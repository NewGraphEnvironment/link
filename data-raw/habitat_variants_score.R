#!/usr/bin/env Rscript
# habitat_variants_score.R — score the threshold variants built by
# habitat_variants_build.R against fish observations, and apply the #284
# step 5 rule (research/habitat_thresholds.md, "Scoring design").
#
# Per variant schema: lnk_habitat_validate() capture and cost, at each buffer.
# Per ladder step (a variant and its --variants `step_from`):
# lnk_habitat_validate_band(), the observations per km on the segments the
# step moves against the core every step of that ladder agrees on.
#
# The rule, applied mechanically to the held-out WSGs of the step's species,
# pooled (in-sample rows are written beside it and never decide):
#   - a band is habitat when n_band >= 10 and density_ratio >= 0.5;
#   - a loosening step is taken when its band is habitat, a tightening step
#     when its band is not; n_band < 10 keeps the value;
#   - walking out from `default`, the first step not taken stops the ladder;
#     an underpowered step decides nothing, so a walk that reaches one has no
#     value and the step 1-4 verdict in the bundle stands.
# The literature veto is applied by hand in the research doc, not here.
#
#   Rscript data-raw/habitat_variants_score.R \
#     [--variants=data-raw/habitat_score/variants.csv] \
#     [--roles=data-raw/habitat_score/wsg_roles.csv] \
#     [--wsgs=...] [--buffers=0,100] [--prefix=score284_] \
#     [--out=data-raw/logs/habitat_score_284]
#
# Absences come from LNK_KNOWLEDGE_DIR (the private `knowledge` repo) through
# data-raw/habitat_validate_inputs.R, as habitat_validate.R reads them; only
# counts are written. Read-only against docker fwapg: session temp tables.
#
# Writes to --out:
#   summary.csv       lnk_habitat_validate()$summary, every variant x buffer
#   totals.csv        summed per variant x species x role x stage x buffer
#   bands.csv         per step x WSG x direction x stage (observations and
#                     absence sites)
#   bands_pooled.csv  the same summed per step x role x direction x stage
#   verdict.csv       the rule per step, and the walked-out value per ladder
#   bridge_band.csv   rearing km each added band holds with and without
#                     spawning upstream
#   taper.csv         observations per km along each ladder: the core cut into
#                     gradient bins, then each band, against the core's rate
#   elevation.csv     each band against the core within the same elevation
#                     class (terciles of the WSG's own core rearing), so a
#                     band's low rate can be told apart from "it is higher up"
#   elevation_adjusted.csv  per band: found / expected at the core's rate in
#                     the band's own elevation mix
#   habitat_change.csv  per variant x WSG: stream-rearing and spawning km
#                     against the base, and the change (km and %)
#   stamp_score.txt   environment stamp

suppressPackageStartupMessages({
  pkgload::load_all(quiet = TRUE)
  library(DBI)
})

opt <- function(name, default = NULL) {
  a <- grep(paste0("^--", name, "="), commandArgs(trailingOnly = TRUE),
            value = TRUE)
  if (length(a) == 0L) return(default)
  sub(paste0("^--", name, "="), "", a[length(a)])
}
split_csv <- function(x) {
  if (is.null(x)) return(character(0))
  v <- trimws(strsplit(x, ",")[[1]])
  v[nzchar(v)]
}
say <- function(...) message(format(Sys.time(), "%H:%M:%S "), sprintf(...))

path_variants <- opt("variants", file.path("data-raw", "habitat_score",
                                           "variants.csv"))
path_roles <- opt("roles", file.path("data-raw", "habitat_score",
                                     "wsg_roles.csv"))
prefix <- opt("prefix", "score284_")
dir_out <- opt("out", file.path("data-raw", "logs", "habitat_score_284"))
buffers <- as.numeric(split_csv(opt("buffers", "0,100")))
if (anyNA(buffers) || !0 %in% buffers) {
  stop("--buffers must be numbers and include 0 (bands are buffer 0)",
       call. = FALSE)
}
n_min <- 10L
ratio_min <- 0.5

variants <- utils::read.csv(path_variants, colClasses = "character",
                            na.strings = "")
roles <- utils::read.csv(path_roles, colClasses = "character")
base_variant <- variants$variant[is.na(variants$column)]
stopifnot(length(base_variant) == 1L)
# The ladders must be well formed before anything runs: every step_from names
# a listed variant, and each variant is stepped from by at most one other, so
# every ladder is one chain out from the base (no cycle, no branch below it).
local({
  steps_from <- variants$step_from[!is.na(variants$column)]
  if (!all(steps_from %in% variants$variant)) {
    stop("step_from names no listed variant: ",
         paste(setdiff(steps_from, variants$variant), collapse = ", "),
         call. = FALSE)
  }
  below <- steps_from[steps_from != base_variant]
  if (anyDuplicated(below)) {
    stop("a ladder branches below the base at: ",
         paste(unique(below[duplicated(below)]), collapse = ", "),
         call. = FALSE)
  }
  for (v in variants$variant) {
    seen <- character(0)
    while (!identical(v, base_variant)) {
      if (v %in% seen) stop("step_from cycle through ", v, call. = FALSE)
      seen <- c(seen, v)
      v <- variants$step_from[variants$variant == v]
    }
  }
})

focal <- toupper(split_csv(opt("wsgs")))
if (length(focal) == 0L) focal <- unique(roles$watershed_group_code)
roles <- roles[roles$watershed_group_code %in% focal, ]
species <- sort(unique(roles$species_code))
schema_of <- function(v) paste0(prefix, v)
outputs <- c("summary.csv", "totals.csv", "bands.csv", "bands_pooled.csv",
             "verdict.csv", "bridge_band.csv", "taper.csv", "elevation.csv",
             "elevation_adjusted.csv", "habitat_change.csv",
             "stamp_score.txt")
unlink(file.path(dir_out, outputs))

# Taken at launch: the code that runs is the code at the start.
head_sha <- system("git rev-parse --short HEAD", intern = TRUE)
dirty <- length(system(paste(
  "git status --porcelain -- R inst/extdata data-raw/habitat_score",
  "data-raw/habitat_variants_score.R data-raw/habitat_validate_inputs.R",
  "data-raw/fiss_absence_taxa.csv"), intern = TRUE)) > 0L

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")

# -- bundles: default, and the thin variant bundles the build wrote --------------
cfg_of <- function(v) {
  if (identical(v, base_variant)) return(lnk_config("default"))
  d <- file.path(dir_out, "bundles", v)
  if (!dir.exists(d)) {
    stop("no bundle for ", v, " under ", dir_out,
         ": run habitat_variants_build.R first", call. = FALSE)
  }
  lnk_config(normalizePath(d))
}
cfgs <- stats::setNames(lapply(variants$variant, cfg_of), variants$variant)
# The values below label every band, so they must be the ones each schema was
# built from. built.csv (written by the build once a schema's checks pass)
# names the bundle sha each schema came from; the bundle on disk must still be
# that one, differ from the current default in exactly its own cell, and
# carry the value --variants gives it.
path_built <- file.path(dir_out, "built.csv")
if (!file.exists(path_built)) {
  stop("no ", path_built, ": run habitat_variants_build.R first", call. = FALSE)
}
built <- utils::read.csv(path_built, colClasses = "character")
thr_now <- utils::read.csv(
  cfgs[[base_variant]]$files$parameters_habitat_thresholds$path,
  colClasses = "character")
for (v in variants$variant) {
  path_thr <- cfgs[[v]]$files$parameters_habitat_thresholds$path
  sp_v <- if (identical(v, base_variant)) species else
    variants$species_code[variants$variant == v]
  w_v <- intersect(focal, roles$watershed_group_code[roles$species_code %in% sp_v])
  b <- built[built$variant == v & built$watershed_group_code %in% w_v, ]
  if (!setequal(b$watershed_group_code, w_v) || nrow(b) != length(w_v)) {
    stop(v, " was not built for: ",
         paste(setdiff(w_v, b$watershed_group_code), collapse = ", "),
         " (", path_built, ")", call. = FALSE)
  }
  if (!all(b$schema == schema_of(v))) {
    stop(path_built, " records ", v, " in another schema than ", schema_of(v),
         call. = FALSE)
  }
  if (!all(b$thresholds_sha256 ==
             digest::digest(file = path_thr, algo = "sha256"))) {
    stop("the thresholds bundle for ", v, " is not the one every scored WSG ",
         "of ", schema_of(v), " was built from", call. = FALSE)
  }
  if (identical(v, base_variant)) next
  r <- variants[variants$variant == v, ]
  thr <- utils::read.csv(path_thr, colClasses = "character")
  n_diff <- sum(mapply(function(a, b) {
    sum(!((a == b) %in% TRUE) & !(is.na(a) & is.na(b)))
  }, thr, thr_now))
  got <- as.numeric(thr[[r$column]][thr$species_code == r$species_code])
  if (n_diff != 1L || !isTRUE(all.equal(got, as.numeric(r$value)))) {
    stop("bundle ", v, " is not default with ", r$column, " = ", r$value,
         " for ", r$species_code, " (", n_diff, " cells differ; it holds ",
         got, ")", call. = FALSE)
  }
}
loaded <- suppressWarnings(lnk_load_overrides(cfgs[[base_variant]]))

# Access was copied from the base at build time; a later base pass can move
# the base's. Each variant must still carry the base's access, per WSG.
digest_access <- function(sch, w) {
  dbGetQuery(conn, sprintf(
    "SELECT md5(string_agg(t::text, '|' ORDER BY t.id_segment))
       FROM (SELECT * FROM %s.streams_access
              WHERE watershed_group_code = $1) t", sch),
    params = list(w))[[1]]
}
for (v in setdiff(variants$variant, base_variant)) {
  for (w in intersect(focal, roles$watershed_group_code[
    roles$species_code == variants$species_code[variants$variant == v]])) {
    if (!identical(digest_access(schema_of(v), w),
                   digest_access(schema_of(base_variant), w))) {
      stop(schema_of(v), ".streams_access differs from ",
           schema_of(base_variant), " in ", w, ": rebuild the variants",
           call. = FALSE)
    }
  }
}

# -- absences and pooling: the same code path as habitat_validate.R ------------------
source(file.path("data-raw", "habitat_validate_inputs.R"))
absences <- hv_fiss_absences(conn, species)
abs_note <- attr(absences, "reason")
if (!is.null(abs_note)) absences <- NULL
pool <- hv_pooling(data.frame(config = "default", stringsAsFactors = FALSE),
                   list(focal), species, pooling_cfg = "default")

# -- validate every variant schema -------------------------------------------------------
# A variant schema holds habitat only for its own species (the build
# re-classifies just that one), so it is validated for that species only;
# another species' empty table would read as zero capture at zero cost.
species_of <- function(v) {
  if (identical(v, base_variant)) species else
    intersect(species, variants$species_code[variants$variant == v])
}
aoi_of <- function(sp) {
  intersect(focal, roles$watershed_group_code[roles$species_code %in% sp])
}
runs <- list()
for (v in variants$variant) {
  for (b in buffers) {
    say("validating %s (%s), buffer %s m", v, schema_of(v), b)
    r <- do.call(lnk_habitat_validate, c(list(
      conn, aoi = aoi_of(species_of(v)), cfg = cfgs[[v]], loaded = loaded,
      species = species_of(v), schema = schema_of(v), buffer_m = b,
      absences = absences), pool$args))
    r$summary <- cbind(data.frame(variant = v), r$summary)
    runs[[paste(v, b)]] <- r
  }
}
summary <- do.call(rbind, lapply(runs, `[[`, "summary"))
rownames(summary) <- NULL
utils::write.csv(summary, file.path(dir_out, "summary.csv"),
                 row.names = FALSE, na = "")

# Every variant must retain the same observations on the same segments, or a
# capture difference mixes an attachment difference into a threshold one.
obs_key <- function(o) {
  sort(paste(o$species_code, o$watershed_group_code, o$observation_key,
             o$id_segment))
}
obs_base <- runs[[paste(base_variant, 0)]]$observations
for (v in setdiff(variants$variant, base_variant)) {
  o_v <- runs[[paste(v, 0)]]$observations
  o_b <- obs_base[obs_base$species_code %in% species_of(v) &
                    obs_base$watershed_group_code %in% aoi_of(species_of(v)), ]
  if (!identical(obs_key(o_v), obs_key(o_b))) {
    stop(v, " retained or attached different observations than ",
         base_variant, call. = FALSE)
  }
}

summary$role <- roles$role[match(
  paste(summary$watershed_group_code, summary$species_code),
  paste(roles$watershed_group_code, roles$species_code))]
summary <- summary[!is.na(summary$role), ]
cols_n <- c("n_obs", "n_accessible", "n_spawning", "n_rearing",
            "n_rearing_any", "n_obs_outside_uhc_spawn",
            "n_spawning_outside_uhc", "n_obs_outside_uhc_rear",
            "n_rearing_any_outside_uhc", "accessible_km", "spawning_km",
            "rearing_km")
key_t <- c("variant", "buffer_m", "species_code", "role", "stage")
totals <- stats::aggregate(summary[cols_n], summary[key_t], sum)
for (k in c("accessible", "spawning", "rearing", "rearing_any")) {
  totals[[paste0("share_", k)]] <- ifelse(
    totals$n_obs > 0, totals[[paste0("n_", k)]] / totals$n_obs, NA_real_)
}
totals <- totals[do.call(order, totals[rev(key_t)]), ]
utils::write.csv(totals, file.path(dir_out, "totals.csv"), row.names = FALSE,
                 na = "")

# What each variant does to the amount of habitat, WSG by WSG: the cost side
# of the score, in the units people quote (km), from the rollup the
# validator already carries. One row per variant x WSG x species.
hc <- summary[summary$buffer_m == 0 & summary$stage == "any",
              c("variant", "watershed_group_code", "species_code", "role",
                "rearing_km", "spawning_km")]
hc_base <- hc[hc$variant == base_variant, ]
key_hc <- function(d) paste(d$watershed_group_code, d$species_code)
hc <- hc[hc$variant != base_variant, ]
i <- match(key_hc(hc), key_hc(hc_base))
hc$rearing_km_base <- hc_base$rearing_km[i]
hc$spawning_km_base <- hc_base$spawning_km[i]
hc$rearing_km_added <- hc$rearing_km - hc$rearing_km_base
hc$rearing_pct_added <- ifelse(hc$rearing_km_base > 0,
                               100 * hc$rearing_km_added / hc$rearing_km_base,
                               NA_real_)
hc$spawning_km_added <- hc$spawning_km - hc$spawning_km_base
hc <- hc[order(hc$variant, -hc$rearing_pct_added), ]
utils::write.csv(hc, file.path(dir_out, "habitat_change.csv"),
                 row.names = FALSE, na = "")

# -- absence sites attached to segments ---------------------------------------------------
# The validator's absence output is counts; to count absence sites in a band
# they are attached the way observations are, by running them through the
# validator as an observation source (model species codes, no pooling).
abs_obs <- NULL
if (!is.null(absences) && nrow(absences) > 0L) {
  a <- absences[absences$watershed_group_code %in% focal, , drop = FALSE]
  if (nrow(a) > 0L) {
    loaded_abs <- loaded
    loaded_abs$observation_exclusions <- NULL
    abs_obs <- lnk_habitat_validate(
      conn, aoi = focal, cfg = cfgs[[base_variant]], loaded = loaded_abs,
      species = species, schema = schema_of(base_variant), observations = a,
      species_obs = list(), match_types = NULL,
      source_exclude = NULL)$observations
  }
}

# -- bands, per ladder step ------------------------------------------------------------------
num <- function(x) as.numeric(x)
thr_default <- utils::read.csv(
  cfgs[[base_variant]]$files$parameters_habitat_thresholds$path)
value_of <- function(v, sp, column) {
  r <- variants[variants$variant == v, ]
  if (identical(v, base_variant) || !identical(r$column, column)) {
    return(thr_default[[column]][thr_default$species_code == sp])
  }
  num(r$value)
}
steps <- variants[!is.na(variants$column), ]
steps$value_from <- mapply(value_of, steps$step_from, steps$species_code,
                           steps$column)
steps$direction <- ifelse(num(steps$value) > steps$value_from, "added",
                          "removed")
ladder_of <- function(sp, column) {
  c(base_variant, variants$variant[variants$species_code %in% sp &
                                     variants$column %in% column])
}
# A user_habitat_classification reach is forced to habitat under every
# variant, so it would sit in the core and pull its density toward wherever
# the confirmed reaches are. The band function does not exclude them; stop
# rather than score a biased core.
uhc <- loaded$user_habitat_classification
if (!is.null(uhc)) {
  for (k in seq_len(nrow(steps))) {
    hit <- uhc$species_code == steps$species_code[k] &
      uhc[[steps$flag[k]]] %in% 1
    if (any(hit)) {
      stop(sum(hit), " user_habitat_classification ", steps$flag[k],
           " reaches for ", steps$species_code[k], " would sit in the core ",
           "of step ", steps$variant[k], call. = FALSE)
    }
  }
}
stages <- c("any", "spawn", "rear")
bands <- list()
for (k in seq_len(nrow(steps))) {
  s <- steps[k, ]
  w_sp <- roles$watershed_group_code[roles$species_code == s$species_code]
  core <- schema_of(ladder_of(s$species_code, s$column))
  for (st in stages) {
    b <- lnk_habitat_validate_band(
      conn, aoi = w_sp, species = s$species_code, flag = s$flag,
      schema = schema_of(s$variant), schema_ref = schema_of(s$step_from),
      observations = obs_base, stage = st, schema_core = core)
    b$n_absence_band <- NA_integer_
    if (!is.null(abs_obs) && identical(st, "any")) {
      ab <- lnk_habitat_validate_band(
        conn, aoi = w_sp, species = s$species_code, flag = s$flag,
        schema = schema_of(s$variant), schema_ref = schema_of(s$step_from),
        observations = abs_obs, stage = "any", schema_core = core)
      # Surveyed WSGs, not those with an absence row: a surveyed WSG with no
      # absence site in the band reports 0, not "not assessed".
      covered <- attr(absences, "covered")
      b$n_absence_band <- ifelse(b$watershed_group_code %in% covered,
                                 ab$n_band, NA_integer_)
    }
    bands[[length(bands) + 1L]] <- cbind(
      data.frame(variant = s$variant, step_from = s$step_from,
                 column = s$column, value_from = s$value_from,
                 value = num(s$value), step_direction = s$direction,
                 obs_stage = s$obs_stage),
      b)
  }
}
bands <- do.call(rbind, bands)
bands$role <- roles$role[match(
  paste(bands$watershed_group_code, bands$species_code),
  paste(roles$watershed_group_code, roles$species_code))]
utils::write.csv(bands, file.path(dir_out, "bands.csv"), row.names = FALSE,
                 na = "")
# A ladder step moves habitat one way, except that clustering can drop a
# segment when a newly admitted one merges it into a different cluster
# (measured: 1.1 km against 1,365 km added across the BT steps). The
# against-direction length stays in bands.csv; the run stops only when it is
# more than 1 % of what the step moves the right way, which would mean the
# ladder is not nested and the core is not "default outside every band".
b_any <- bands[bands$stage == "any", ]
with_km <- tapply(b_any$band_km[b_any$direction == b_any$step_direction],
                  b_any$variant[b_any$direction == b_any$step_direction], sum)
against_km <- tapply(b_any$band_km[b_any$direction != b_any$step_direction],
                     b_any$variant[b_any$direction != b_any$step_direction], sum)
share <- against_km / with_km[names(against_km)]
if (any(share > 0.01, na.rm = TRUE)) {
  stop("steps moved more than 1 % of their habitat against their direction ",
       "(see bands.csv): ", paste(names(share)[share > 0.01], collapse = ", "),
       call. = FALSE)
}
message("habitat moved against the step direction (km): ",
        paste(names(against_km), round(against_km, 3), collapse = ", "))

key_b <- c("variant", "step_from", "column", "value_from", "value",
           "step_direction", "obs_stage", "species_code", "flag", "role",
           "direction", "stage")
pooled <- stats::aggregate(bands[c("band_km", "n_band", "core_km", "n_core")],
                           bands[key_b], sum)
pooled <- cbind(pooled, .lnk_hvb_density(pooled$n_band, pooled$band_km,
                                         pooled$n_core, pooled$core_km))
pooled <- pooled[do.call(order, pooled[c("species_code", "column", "value",
                                         "role", "direction", "stage")]), ]
utils::write.csv(pooled, file.path(dir_out, "bands_pooled.csv"),
                 row.names = FALSE, na = "")

# -- the rule ----------------------------------------------------------------------------------
rule <- pooled[pooled$role == "held_out" &
                 pooled$direction == pooled$step_direction &
                 pooled$stage == pooled$obs_stage, ]
if (nrow(rule) == 0L) {
  message("no held-out WSG in scope: verdict.csv carries no rows")
}
rule$band_is_habitat <- rule$n_band >= n_min &
  !is.na(rule$density_ratio) & rule$density_ratio >= ratio_min
rule$decision <- ifelse(
  rule$n_band < n_min, "keep (n < 10)",
  ifelse((rule$step_direction == "added") == rule$band_is_habitat,
         "take", "refuse"))
# Beside the rule, not in it: the same floor on the locations the band would
# hold at the core's rate (core density x band km), which is set by the band's
# length before any fish are counted. The rule's floor on the locations
# FOUND cannot refuse a band fish avoid (few found reads as "underpowered");
# this reading can. Under discussion with the operator, 2026-09-29; the
# verdict of record is `decision`.
rule$n_expected <- rule$density_core * rule$band_km
band_is_dense <- !is.na(rule$density_ratio) & rule$density_ratio >= ratio_min
rule$decision_expected_floor <- ifelse(
  is.na(rule$n_expected) | rule$n_expected < n_min, "keep (expected < 10)",
  ifelse((rule$step_direction == "added") == band_is_dense, "take", "refuse"))
# Walk each ladder out from default once, to its last step, and write that
# one outcome on every row of the ladder. A ladder is the chain from default
# to a tip (a variant no other variant steps from); a ladder that branches at
# default (one step looser, one tighter) is two ladders. The walk stops at the
# first step not decided "take". A "refuse" ends it at the value before that
# step. An underpowered step decides nothing: the ladder has no value
# (walked_value NA) and the step 1-4 verdict in the bundle stands.
chain_to <- function(v) {
  chain <- character(0)
  # Bounded, though the ladder check at the top already rules out a cycle.
  while (!identical(v, base_variant) && length(chain) <= nrow(variants)) {
    chain <- c(v, chain)
    v <- variants$step_from[variants$variant == v]
  }
  chain
}
tips <- setdiff(rule$variant, variants$step_from)
walk <- function(decision) {
  out <- data.frame(tip = rep(NA_character_, nrow(rule)),
                    status = rep(NA_character_, nrow(rule)),
                    value = rep(NA_real_, nrow(rule)))
  for (tip in tips) {
    chain <- chain_to(tip)
    dec <- decision[match(chain, rule$variant)]
    stop_at <- which(dec != "take" | is.na(dec))[1]
    r <- rule[rule$variant == tip, ]
    if (is.na(stop_at)) {
      status <- paste("taken through", tip)
      value <- num(variants$value[variants$variant == tip])
    } else if (identical(dec[stop_at], "refuse")) {
      status <- paste("refused at", chain[stop_at])
      value <- if (stop_at == 1L) {
        value_of(base_variant, r$species_code, r$column)
      } else {
        num(variants$value[variants$variant == chain[stop_at - 1L]])
      }
    } else {
      status <- paste("underpowered at", chain[stop_at],
                      "- the step 1-4 verdict stands")
      value <- NA_real_
    }
    on <- rule$variant %in% chain
    out$tip[on] <- tip
    out$status[on] <- status
    out$value[on] <- value
  }
  out
}
w_rule <- walk(rule$decision)
rule$ladder_tip <- w_rule$tip
rule$walk_status <- w_rule$status
rule$walked_value <- w_rule$value
w_exp <- walk(rule$decision_expected_floor)
rule$walk_status_expected_floor <- w_exp$status
rule$walked_value_expected_floor <- w_exp$value
utils::write.csv(rule, file.path(dir_out, "verdict.csv"), row.names = FALSE,
                 na = "")

# -- diagnostics: the taper, and the band against the core by elevation -----------------
# Per segment of the base network, for each ladder (species x column x flag):
# which step's band it is in (or the core, or neither), its gradient, its
# elevation (mean of the geometry's Z range) and the locations on it. Rates
# are pooled sums (locations / km) per role, never averages of segment rates.
ladders <- unique(steps[c("species_code", "column", "flag")])
seg_rows <- list()
for (k in seq_len(nrow(ladders))) {
  L <- ladders[k, ]
  lad <- steps[steps$species_code == L$species_code & steps$column == L$column, ]
  sch_all <- schema_of(ladder_of(L$species_code, L$column))
  w_sp <- roles$watershed_group_code[roles$species_code == L$species_code]
  spl <- tolower(L$species_code)
  joins <- paste(sprintf(
    "LEFT JOIN %1$s.streams_habitat_%2$s h%3$d
       ON h%3$d.id_segment = s.id_segment
      AND h%3$d.watershed_group_code = s.watershed_group_code",
    sch_all, spl, seq_along(sch_all)), collapse = "\n ")
  flag_of <- function(sch) {
    sprintf("coalesce(h%d.%s, false)", match(sch, sch_all), L$flag)
  }
  band_case <- paste(sprintf("WHEN %s <> %s THEN %s",
                             flag_of(schema_of(lad$variant)),
                             flag_of(schema_of(lad$step_from)),
                             DBI::dbQuoteString(conn, lad$variant)),
                     collapse = " ")
  d <- dbGetQuery(conn, sprintf(
    "SELECT s.watershed_group_code, s.id_segment, s.length_metre, s.gradient,
            (st_zmin(s.geom) + st_zmax(s.geom)) / 2 AS elevation,
            CASE WHEN %3$s THEN 'core' %4$s ELSE NULL END AS class
       FROM %1$s.streams s
       %2$s
      WHERE s.watershed_group_code = ANY($1)",
    schema_of(base_variant), joins,
    paste(vapply(sch_all, flag_of, character(1)), collapse = " AND "),
    band_case), params = list(paste0("{", paste(w_sp, collapse = ","), "}")))
  d <- d[!is.na(d$class), ]
  o <- obs_base[obs_base$species_code == L$species_code &
                  !is.na(obs_base$id_segment), ]
  st <- unique(lad$obs_stage)
  if (identical(st, "spawn")) o <- o[o$is_spawn %in% TRUE, ]
  if (identical(st, "rear")) o <- o[o$is_rear %in% TRUE, ]
  n_seg <- table(paste(o$watershed_group_code, o$id_segment))
  d$n <- as.integer(n_seg[paste(d$watershed_group_code, d$id_segment)])
  d$n[is.na(d$n)] <- 0L
  d$species_code <- L$species_code
  d$column <- L$column
  d$role <- roles$role[match(paste(d$watershed_group_code, d$species_code),
                             paste(roles$watershed_group_code,
                                   roles$species_code))]
  seg_rows[[k]] <- d
}
seg <- do.call(rbind, seg_rows)
pool_rate <- function(d, by) {
  a <- stats::aggregate(cbind(km = d$length_metre / 1000, n = d$n), d[by], sum)
  a$per_100km <- ifelse(a$km > 0, 100 * a$n / a$km, NA_real_)
  a
}
# Taper: the core split into gradient bins, then each band as its own row.
grad_bins <- c(-Inf, 0.02, 0.05, 0.08, Inf)
seg$taper_class <- ifelse(
  seg$class == "core",
  paste0("core ", as.character(cut(seg$gradient, grad_bins, right = TRUE))),
  paste0("band ", seg$class))
taper <- pool_rate(seg, c("species_code", "column", "role", "taper_class"))
core_rate <- pool_rate(seg[seg$class == "core", ],
                       c("species_code", "column", "role"))
taper$ratio_to_core <- taper$per_100km /
  core_rate$per_100km[match(paste(taper$species_code, taper$column, taper$role),
                            paste(core_rate$species_code, core_rate$column,
                                  core_rate$role))]
utils::write.csv(taper[do.call(order, taper[c("species_code", "column", "role",
                                              "taper_class")]), ],
                 file.path(dir_out, "taper.csv"), row.names = FALSE, na = "")
# Elevation: terciles of each WSG's own core elevation, length-weighted, so a
# band sits in the same low / mid / high classes as the rearing it joins.
seg$elev_class <- NA_character_
for (w in unique(seg$watershed_group_code)) {
  for (lad_key in unique(paste(seg$species_code, seg$column))) {
    i <- seg$watershed_group_code == w & paste(seg$species_code, seg$column) == lad_key
    core <- seg[i & seg$class == "core" & !is.na(seg$elevation), ]
    if (nrow(core) == 0L) next
    o <- order(core$elevation)
    cw <- cumsum(core$length_metre[o]) / sum(core$length_metre)
    cuts <- c(core$elevation[o][which(cw >= 1 / 3)[1]],
              core$elevation[o][which(cw >= 2 / 3)[1]])
    seg$elev_class[i] <- as.character(cut(seg$elevation[i],
                                          c(-Inf, cuts, Inf),
                                          labels = c("low", "mid", "high")))
  }
}
elev <- pool_rate(seg[!is.na(seg$elev_class), ],
                  c("species_code", "column", "role", "class", "elev_class"))
elev_core <- elev[elev$class == "core", ]
elev$core_per_100km <- elev_core$per_100km[match(
  paste(elev$species_code, elev$column, elev$role, elev$elev_class),
  paste(elev_core$species_code, elev_core$column, elev_core$role,
        elev_core$elev_class))]
elev$ratio_to_core <- elev$per_100km / elev$core_per_100km
elev$elev_class <- factor(elev$elev_class, c("low", "mid", "high"))
utils::write.csv(elev[do.call(order, elev[c("species_code", "column", "role",
                                            "class", "elev_class")]), ],
                 file.path(dir_out, "elevation.csv"), row.names = FALSE,
                 na = "")
# One number per band: locations found against those expected if the band
# held the core's rate in each of its own elevation classes (sum of band km x
# core rate, class by class). It removes "the band is higher up" from the
# pooled ratio; it does not remove temperature or size within a class.
eb <- elev[elev$class != "core", ]
eb$expected <- eb$km * eb$core_per_100km / 100
adj <- stats::aggregate(cbind(km, n, expected) ~ species_code + column + role +
                          class, eb, sum)
adj$ratio_elevation_adjusted <- ifelse(adj$expected > 0, adj$n / adj$expected,
                                       NA_real_)
utils::write.csv(adj, file.path(dir_out, "elevation_adjusted.csv"),
                 row.names = FALSE, na = "")

# -- question 2: added rearing with and without spawning upstream -------------------------
# .frs_cluster_both() keeps a rearing cluster with spawning anywhere upstream,
# and otherwise only through the downstream bridge; this splits each added
# rearing band the same way, per segment, against the variant's own spawning.
bridge <- list()
for (k in which(steps$flag == "rearing" & steps$direction == "added")) {
  s <- steps[k, ]
  spl <- tolower(s$species_code)
  w_sp <- roles$watershed_group_code[roles$species_code == s$species_code]
  sv <- schema_of(s$variant)
  sr <- schema_of(s$step_from)
  d <- dbGetQuery(conn, sprintf(
    "WITH band AS (
       SELECT s.* FROM %1$s.streams s
         JOIN %1$s.streams_habitat_%3$s h
           ON h.id_segment = s.id_segment
          AND h.watershed_group_code = s.watershed_group_code
         LEFT JOIN %2$s.streams_habitat_%3$s r
           ON r.id_segment = s.id_segment
          AND r.watershed_group_code = s.watershed_group_code
        WHERE s.watershed_group_code = ANY($1)
          AND h.rearing AND NOT coalesce(r.rearing, false)),
     spawn AS (
       SELECT s.* FROM %1$s.streams s
         JOIN %1$s.streams_habitat_%3$s h
           ON h.id_segment = s.id_segment
          AND h.watershed_group_code = s.watershed_group_code
        WHERE s.watershed_group_code = ANY($1) AND h.spawning)
     SELECT b.watershed_group_code,
            EXISTS (
              SELECT 1 FROM spawn p
               WHERE p.watershed_group_code = b.watershed_group_code
                 AND whse_basemapping.fwa_upstream(
                       b.blue_line_key, b.downstream_route_measure,
                       b.wscode_ltree, b.localcode_ltree,
                       p.blue_line_key, p.downstream_route_measure,
                       p.wscode_ltree, p.localcode_ltree)) AS spawning_upstream,
            -- in the gradient window the step opens, or admitted through
            -- connectivity (a cluster the step newly connects)
            (b.gradient > $2 AND b.gradient <= $3) AS in_window,
            sum(b.length_metre) / 1000 AS km
       FROM band b
      GROUP BY 1, 2, 3", sv, sr, spl),
    params = list(paste0("{", paste(w_sp, collapse = ","), "}"),
                  s$value_from, num(s$value)))
  if (nrow(d) > 0L) {
    bridge[[length(bridge) + 1L]] <- cbind(
      data.frame(variant = s$variant, step_from = s$step_from,
                 species_code = s$species_code), d)
  }
}
if (length(bridge) > 0L) {
  bridge <- do.call(rbind, bridge)
  bridge$role <- roles$role[match(
    paste(bridge$watershed_group_code, bridge$species_code),
    paste(roles$watershed_group_code, roles$species_code))]
  utils::write.csv(bridge, file.path(dir_out, "bridge_band.csv"),
                   row.names = FALSE, na = "")
}

# -- stamp -------------------------------------------------------------------------------------
fresh_sha <- .lnk_pkg_git_sha("fresh")
writeLines(c(
  sprintf("date: %s", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
  sprintf("link: %s @ %s%s (at launch)", utils::packageVersion("link"),
          head_sha, if (dirty) " (dirty)" else ""),
  sprintf("fresh: %s @ %s", utils::packageVersion("fresh"),
          if (is.na(fresh_sha)) "no recorded sha" else fresh_sha),
  "db: docker fwapg localhost:5432",
  sprintf("variants: %s (md5 %s): %s", path_variants,
          unname(tools::md5sum(path_variants)),
          paste(variants$variant, collapse = ",")),
  sprintf("roles: %s (md5 %s)", path_roles, unname(tools::md5sum(path_roles))),
  # The build this score verified (built.csv rows for the scored WSGs).
  vapply(variants$variant, function(v) {
    b <- built[built$variant == v & built$watershed_group_code %in% focal, ]
    sprintf("built %s: thresholds sha256 %s; link %s%s; %d WSGs, %s to %s", v,
            substr(b$thresholds_sha256[1], 1, 12),
            paste(unique(b$link_head), collapse = ","),
            if (any(b$dirty %in% "TRUE")) " (dirty)" else "", nrow(b),
            min(b$built_at), max(b$built_at))
  }, character(1)),
  sprintf("focal: %s; species: %s; buffers: %s m",
          paste(focal, collapse = ","), paste(species, collapse = ","),
          paste(buffers, collapse = ",")),
  sprintf("rule: n_band >= %d and density_ratio >= %s on held-out WSGs",
          n_min, ratio_min),
  sprintf("pooling: %s", pool$note),
  sprintf("bcfishobs.observations rows: %s",
          dbGetQuery(conn, "SELECT count(*) FROM bcfishobs.observations")[[1]]),
  if (!is.null(abs_note)) sprintf("absences: none (%s)", abs_note) else
  if (is.null(absences)) "absences: none (LNK_KNOWLEDGE_DIR unset)" else
    sprintf("absences: FISS snapshots %s; knowledge @ %s",
            paste(attr(absences, "covered"), collapse = ","),
            attr(absences, "knowledge_sha"))),
  file.path(dir_out, "stamp_score.txt"))
dbDisconnect(conn)
say("wrote %s", dir_out)
