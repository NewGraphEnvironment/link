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
# A model-only variant (link#300) is not a ladder step: it is compared with the
# base in both flags, its bands read against the core within stream-order
# classes ("cw against mad" in the research doc; model_*.csv below).
#
#   Rscript data-raw/habitat_variants_score.R \
#     [--variants=data-raw/habitat_score/variants.csv] \
#     [--roles=data-raw/habitat_score/wsg_roles.csv] \
#     [--wsgs=...] [--buffers=0,100] [--prefix=score284_] \
#     [--floor=found|expected] [--out=data-raw/logs/habitat_score_284]
#     [--base=default]   the base bundle, as habitat_variants_build.R took it
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
#   model_bands.csv, model_bands_pooled.csv  per model-only variant x flag x
#                     stage: cw-only (`removed`) and mad-only (`added`) bands
#                     against the core both models keep (link#300)
#   model_size.csv    the same, per stream-order class, with the rate group
#                     each class is priced at
#   model_reason.csv  why the other model leaves each band out (no discharge or
#                     width, outside its size range, or inside it)
#   model_fill.csv    model_reason split by mad_m3s_source: the discharge
#                     table's own value, a fill tier, or none (link#305). A
#                     variant's fill is the one built.csv records for it.
#   model_verdict.csv the #300 rule: size-adjusted (of record), beside the
#                     unadjusted ratio and the found count
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
base_bundle <- opt("base", "default")
# The defaults are #284's committed run; another variants file must not
# score into (and first clear) #284's outputs.
if (!identical(path_variants, file.path("data-raw", "habitat_score", "variants.csv")) &&
    !all(c("prefix", "out") %in% sub("^--([^=]+)=.*", "\\1",
                                       commandArgs(trailingOnly = TRUE)))) {
  stop("--variants other than #284's needs an explicit --prefix and --out",
       call. = FALSE)
}
buffers <- as.numeric(split_csv(opt("buffers", "0,100")))
if (anyNA(buffers) || !0 %in% buffers) {
  stop("--buffers must be numbers and include 0 (bands are buffer 0)",
       call. = FALSE)
}
n_min <- 10L
ratio_min <- 0.5
# Which n-floor is the verdict of record (both are always written): `found`
# (locations found in the band, #284's) or `expected` (locations the band
# would hold at the core's rate, link#302's: a walk that only loosens from a
# tight anchor is where the found-count floor cannot refuse).
floor_of_record <- opt("floor", "found")
if (!floor_of_record %in% c("found", "expected")) {
  stop("--floor must be found or expected", call. = FALSE)
}

variants <- utils::read.csv(path_variants, colClasses = "character",
                            na.strings = "")
roles <- utils::read.csv(path_roles, colClasses = "character")
# `model` and `set` are optional (link#302), as habitat_variants_build.R reads
# them: an empty model is `cw`, an empty set changes nothing.
for (k in c("model", "set")) {
  if (!k %in% names(variants)) variants[[k]] <- NA_character_
}
variants$model[is.na(variants$model)] <- "cw"
# The base is the row that steps from nothing, as habitat_variants_build.R
# reads it; it must be the --base bundle.
base_variant <- variants$variant[is.na(variants$step_from)]
stopifnot(length(base_variant) == 1L,
          all(variants$model %in% c("cw", "mad")),
          identical(variants$model[variants$variant == base_variant], "cw"),
          is.na(variants$column[variants$variant == base_variant]))
if (!identical(variants$equals_bundle[variants$variant == base_variant],
               base_bundle)) {
  stop("the base variant ", base_variant, " declares equals_bundle ",
       variants$equals_bundle[variants$variant == base_variant],
       ", not --base ", base_bundle, call. = FALSE)
}
# Model-only variants (link#300): no column, on mad, from the base.
model_only <- variants$variant[is.na(variants$column) &
                                 variants$variant != base_variant]
local({
  r <- variants[variants$variant %in% model_only, ]
  bad <- r$variant[r$model != "mad" | r$step_from != base_variant |
                     is.na(r$species_code) | !is.na(r$value) |
                     !is.na(r$flag) | !is.na(r$set) | !is.na(r$obs_stage) |
                     !is.na(r$equals_bundle)]
  if (length(bad) > 0L) {
    stop("a variant with no column must be model-only (on mad, stepping from ",
         base_variant, ", with a species and no value, flag, obs_stage, ",
         "equals_bundle or set): ", paste(bad, collapse = ", "), call. = FALSE)
  }
  # Nothing steps from a model-only variant: it is not a ladder rung.
  off <- variants$variant[variants$step_from %in% model_only]
  if (length(off) > 0L) {
    stop("no variant may step from a model-only variant: ",
         paste(off, collapse = ", "), call. = FALSE)
  }
})
n_set <- function(x) {
  if (is.na(x) || !nzchar(trimws(x))) 0L else
    length(strsplit(trimws(x), ";", fixed = TRUE)[[1]])
}
model_of <- function(v) variants$model[match(v, variants$variant)]
# The same parse as habitat_variants_build.R: "col=value;col=value".
parse_set <- function(x) {
  if (is.na(x) || !nzchar(trimws(x))) return(stats::setNames(character(0), character(0)))
  kv <- strsplit(trimws(strsplit(x, ";", fixed = TRUE)[[1]]), "=", fixed = TRUE)
  stats::setNames(trimws(vapply(kv, `[`, "", 2L)), trimws(vapply(kv, `[`, "", 1L)))
}
# A ladder holds its `set` cells fixed, so a band is the step's own cell
# only: every step but an anchor carries exactly its step_from's set.
local({
  for (v in variants$variant[!is.na(variants$column)]) {
    f <- variants$step_from[variants$variant == v]
    if (identical(f, base_variant) || model_of(v) != model_of(f)) next
    a <- parse_set(variants$set[variants$variant == v])
    b <- parse_set(variants$set[variants$variant == f])
    if (!identical(a[order(names(a))], b[order(names(b))])) {
      stop("step ", v, " changes its set cells from ", f,
           ": a ladder holds them fixed", call. = FALSE)
    }
  }
})
# The ladders must be well formed before anything runs: every step_from names
# a listed variant, and each variant is stepped from by at most one other, so
# every ladder is one chain out from the base (no cycle, no branch below it).
local({
  steps_from <- variants$step_from[variants$variant != base_variant]
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
# paste0() with a zero-length argument returns the bare prefix, not nothing.
schema_of <- function(v) if (length(v) == 0L) character(0) else paste0(prefix, v)
outputs <- c("summary.csv", "totals.csv", "bands.csv", "bands_pooled.csv",
             "verdict.csv", "bridge_band.csv", "taper.csv", "elevation.csv",
             "elevation_adjusted.csv", "habitat_change.csv",
             "model_bands.csv", "model_bands_pooled.csv", "model_size.csv",
             "model_reason.csv", "model_fill.csv", "model_verdict.csv",
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

# -- bundles: the base, and the thin variant bundles the build wrote --------------
cfg_of <- function(v) {
  if (identical(v, base_variant)) return(lnk_config(base_bundle))
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
# that one, differ from the current base in exactly its own cells (none for a
# model-only variant), and carry the value --variants gives it.
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
  # The habitat model a schema was classified on is the bundle's method
  # table; a built.csv from before link#302 carries no method sha, and its
  # rows can only be cw.
  sha_meth <- digest::digest(file = cfgs[[v]]$files$parameters_habitat_method$path,
                             algo = "sha256")
  meth_built <- if ("method_sha256" %in% names(b)) b$method_sha256 else
    rep(NA_character_, nrow(b))
  # The model --variants names must be the one the bundle's method table puts
  # these WSGs on (unlisted is cw), whatever built.csv recorded: a pre-#302
  # row carries no method sha, and a default that later moved a WSG to mad
  # would otherwise score an old cw schema under mad.
  meth <- utils::read.csv(cfgs[[v]]$files$parameters_habitat_method$path,
                          colClasses = "character")
  m_w <- meth$model[match(w_v, meth$watershed_group_code)]
  m_w[is.na(m_w)] <- "cw"
  if (!all(m_w == model_of(v))) {
    stop(v, " is a ", model_of(v), " variant but its method table puts ",
         paste(w_v[m_w != model_of(v)], collapse = ", "), " on another model",
         call. = FALSE)
  }
  if (!all(meth_built %in% sha_meth |
             (is.na(meth_built) & model_of(v) == "cw"))) {
    stop("the method table for ", v, " is not the one every scored WSG of ",
         schema_of(v), " was built from", call. = FALSE)
  }
  # The discharge a variant was classified on (#305): built.csv records the
  # fill per variant x WSG, and a row from before the fill was recorded was
  # built on the raw table. The bundle's own knob is not what classify read:
  # #300's bundles extend default_tuned, which fills now, but their schemas
  # were built raw. So the score (validator and model_reason) takes the
  # recorded state, which must be one per variant.
  fill_built <- if ("discharge_fill" %in% names(b)) {
    b$discharge_fill %in% "TRUE"
  } else {
    rep(FALSE, nrow(b))
  }
  if (length(unique(fill_built)) != 1L) {
    stop(path_built, " records ", v, " with discharge filled in some WSGs ",
         "and not others", call. = FALSE)
  }
  cfgs[[v]]$pipeline$discharge_fill <- fill_built[1]
  if (identical(v, base_variant)) next
  r <- variants[variants$variant == v, ]
  thr <- utils::read.csv(path_thr, colClasses = "character")
  n_diff <- sum(mapply(function(a, b) {
    sum(!((a == b) %in% TRUE) & !(is.na(a) & is.na(b)))
  }, thr, thr_now))
  if (v %in% model_only) {
    if (n_diff != 0L) {
      stop("model-only bundle ", v, " differs from ", base_bundle, " in ",
           n_diff, " threshold cells, not 0", call. = FALSE)
    }
    next
  }
  got <- as.numeric(thr[[r$column]][thr$species_code == r$species_code])
  # Every set cell must hold the value --variants gives it, not just count.
  set_ok <- all(vapply(names(parse_set(r$set)), function(k) {
    got_k <- thr[[k]][thr$species_code == r$species_code]
    want_k <- parse_set(r$set)[[k]]
    # Numbers compared as numbers; anything else (edge types) as text.
    if (is.na(suppressWarnings(as.numeric(want_k)))) {
      identical(got_k, want_k)
    } else {
      isTRUE(all.equal(as.numeric(got_k), as.numeric(want_k)))
    }
  }, logical(1)))
  if (n_diff != 1L + n_set(r$set) || !set_ok ||
      !isTRUE(all.equal(got, as.numeric(r$value)))) {
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
pool <- hv_pooling(data.frame(config = base_bundle, stringsAsFactors = FALSE),
                   list(focal), species, pooling_cfg = base_bundle)

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
  # A --wsgs subset can leave a variant's species with no focal WSG.
  if (length(aoi_of(species_of(v))) == 0L) {
    say("validating %s: no focal WSG for its species, skipped", v)
    next
  }
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

# -- stamp -------------------------------------------------------------------------------------
# A function, so a model-only run (link#300), which has no ladder, writes it too.
write_stamp <- function() {
  fresh_sha <- .lnk_pkg_git_sha("fresh")
  writeLines(c(
    sprintf("date: %s", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
    sprintf("link: %s @ %s%s (at launch)", utils::packageVersion("link"),
            head_sha, if (dirty) " (dirty)" else ""),
    sprintf("fresh: %s @ %s", utils::packageVersion("fresh"),
            if (is.na(fresh_sha)) "no recorded sha" else fresh_sha),
    "db: docker fwapg localhost:5432",
    sprintf("base: %s", base_bundle),
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
    sprintf("rule: n_band >= %d and density_ratio >= %s on held-out WSGs; floor of record: %s",
            n_min, ratio_min, floor_of_record),
    if (length(model_only) > 0L) {
      sprintf(paste("model-only rule (link#300): expected >= %d and found /",
                    "expected >= %s, expected per stream-order class (1, 2, 3,",
                    "4+; merged upward until the core holds %d); held-out",
                    "WSGs, stage any"), n_min, ratio_min, n_min)
    },
    sprintf("pooling: %s", pool$note),
    sprintf("bcfishobs.observations rows: %s",
            dbGetQuery(conn, "SELECT count(*) FROM bcfishobs.observations")[[1]]),
    if (!is.null(abs_note)) sprintf("absences: none (%s)", abs_note) else
    if (is.null(absences)) "absences: none (LNK_KNOWLEDGE_DIR unset)" else
      sprintf("absences: FISS snapshots %s; knowledge @ %s",
              paste(attr(absences, "covered"), collapse = ","),
              attr(absences, "knowledge_sha"))),
    file.path(dir_out, "stamp_score.txt"))
}

# -- cw against mad: model-only variants (link#300) --------------------------------------
# A model-only variant changes the habitat model and no threshold. Per flag, its
# `removed` band is the habitat only cw keeps, its `added` band the habitat only
# mad keeps, and the core the habitat both keep. Each band is then read against
# the core within stream-order classes (neither model tests order), so a band
# of smaller water is not held to the rate of bigger water.
stages <- c("any", "spawn", "rear")
order_levels <- c("1", "2", "3", "4+")
# Order 0 and NULL are not a size: they go to `unknown`.
order_class <- function(o) {
  ifelse(is.na(o) | o < 1, "unknown", ifelse(o >= 4, "4+", as.character(o)))
}
# Rate groups: walking up from order 1, a class joins the next until the group's
# core holds n_min locations; a short last group joins the one before. One group
# is every ordered class together. Returns a group label per class.
order_groups <- function(n_core) {
  grp <- integer(length(n_core))
  g <- 1L
  acc <- 0
  for (i in seq_along(n_core)) {
    grp[i] <- g
    acc <- acc + n_core[i]
    if (acc >= n_min && i < length(n_core)) {
      g <- g + 1L
      acc <- 0
    }
  }
  if (acc < n_min && g > 1L) grp[grp == g] <- g - 1L
  vapply(grp, function(k) {
    m <- order_levels[grp == k]
    if (length(m) == 1L) m else paste0(m[1], "-", m[length(m)])
  }, character(1))
}
mb_dir <- c(cw_only = "removed", mad_only = "added")
if (length(model_only) > 0L) {
  uhc <- loaded$user_habitat_classification
  thr_base <- utils::read.csv(cfgs[[base_variant]]$files$parameters_habitat_thresholds$path)
  mb <- list()
  mseg <- list()
  for (v in model_only) {
    sp <- variants$species_code[variants$variant == v]
    w_sp <- roles$watershed_group_code[roles$species_code == sp]
    if (length(w_sp) == 0L) {
      say("%s: no focal WSG for %s, not compared", v, sp)
      next
    }
    # A user_habitat_classification reach is habitat under both models, so it
    # would sit in the core; stop rather than score a biased core.
    if (!is.null(uhc) && any(uhc$species_code == sp &
                             (uhc$spawning %in% 1 | uhc$rearing %in% 1))) {
      stop("user_habitat_classification reaches for ", sp, " would sit in the ",
           "core of ", v, call. = FALSE)
    }
    sch_pair <- schema_of(c(base_variant, v))
    for (fl in c("spawning", "rearing")) {
      for (st in stages) {
        b <- lnk_habitat_validate_band(
          conn, aoi = w_sp, species = sp, flag = fl,
          schema = schema_of(v), schema_ref = schema_of(base_variant),
          observations = obs_base, stage = st, schema_core = sch_pair)
        b$n_absence_band <- NA_integer_
        if (!is.null(abs_obs) && identical(st, "any")) {
          ab <- lnk_habitat_validate_band(
            conn, aoi = w_sp, species = sp, flag = fl,
            schema = schema_of(v), schema_ref = schema_of(base_variant),
            observations = abs_obs, stage = "any", schema_core = sch_pair)
          b$n_absence_band <- ifelse(
            b$watershed_group_code %in% attr(absences, "covered"),
            ab$n_band, NA_integer_)
        }
        mb[[length(mb) + 1L]] <- cbind(data.frame(variant = v), b)
      }
      # Per segment of the base network: core, cw-only or mad-only, its
      # stream-order class, and why the other model leaves it out (reported
      # only): no discharge or no width, outside that model's size range, or
      # inside it (so connectivity or clustering dropped it). The band
      # function above counts the same rows; that is checked below.
      pre <- if (identical(fl, "spawning")) "spawn" else "rear"
      t_sp <- thr_base[thr_base$species_code == sp, ]
      d <- dbGetQuery(conn, sprintf(
        "SELECT s.watershed_group_code, s.id_segment, s.length_metre,
                s.stream_order, q.mad_m3s_source,
                CASE WHEN coalesce(b.%4$s, false) AND coalesce(m.%4$s, false)
                       THEN 'core'
                     WHEN coalesce(b.%4$s, false) THEN 'cw_only'
                     WHEN coalesce(m.%4$s, false) THEN 'mad_only' END AS class,
                CASE WHEN coalesce(b.%4$s, false) AND NOT coalesce(m.%4$s, false)
                       THEN CASE WHEN q.mad_m3s IS NULL THEN 'mad_null'
                                 WHEN q.mad_m3s < $2 OR q.mad_m3s > $3
                                   THEN 'outside_mad_range'
                                 ELSE 'in_mad_range' END
                     WHEN coalesce(m.%4$s, false) AND NOT coalesce(b.%4$s, false)
                       THEN CASE WHEN s.channel_width IS NULL THEN 'width_null'
                                 WHEN s.channel_width < $4 OR s.channel_width > $5
                                   THEN 'outside_width_range'
                                 ELSE 'in_width_range' END END AS reason
           FROM %1$s.streams s
           LEFT JOIN %1$s.streams_habitat_%3$s b
             ON b.id_segment = s.id_segment
            AND b.watershed_group_code = s.watershed_group_code
           LEFT JOIN %2$s.streams_habitat_%3$s m
             ON m.id_segment = s.id_segment
            AND m.watershed_group_code = s.watershed_group_code
           LEFT JOIN %5$s q ON q.linear_feature_id = s.linear_feature_id
          WHERE s.watershed_group_code = ANY($1)",
        schema_of(base_variant), schema_of(v), tolower(sp), fl,
        # The discharge the variant classified on (built.csv, #305).
        .lnk_discharge_sql(w_sp, fill = .lnk_discharge_fill_applied(cfgs[[v]],
                                                                    w_sp))),
        params = list(paste0("{", paste(w_sp, collapse = ","), "}"),
                      t_sp[[paste0(pre, "_mad_min")]],
                      t_sp[[paste0(pre, "_mad_max")]],
                      t_sp[[paste0(pre, "_channel_width_min")]],
                      t_sp[[paste0(pre, "_channel_width_max")]]))
      d <- d[!is.na(d$class), ]
      if (nrow(d) == 0L) next
      o <- obs_base[obs_base$species_code == sp & !is.na(obs_base$id_segment) &
                      obs_base$watershed_group_code %in% w_sp, ]
      for (st in stages) {
        os <- switch(st, any = o, spawn = o[o$is_spawn %in% TRUE, ],
                     rear = o[o$is_rear %in% TRUE, ])
        n_seg <- table(paste(os$watershed_group_code, os$id_segment))
        n <- as.integer(n_seg[paste(d$watershed_group_code, d$id_segment)])
        n[is.na(n)] <- 0L
        mseg[[length(mseg) + 1L]] <- data.frame(
          variant = v, species_code = sp, flag = fl, stage = st,
          watershed_group_code = d$watershed_group_code, class = d$class,
          order_class = order_class(d$stream_order),
          reason = ifelse(is.na(d$reason), "", d$reason),
          mad_m3s_source = ifelse(is.na(d$mad_m3s_source), "",
                                  d$mad_m3s_source),
          km = d$length_metre / 1000, n = n)
      }
    }
  }
  mb <- do.call(rbind, mb)
  mb$role <- roles$role[match(paste(mb$watershed_group_code, mb$species_code),
                              paste(roles$watershed_group_code,
                                    roles$species_code))]
  utils::write.csv(mb, file.path(dir_out, "model_bands.csv"), row.names = FALSE,
                   na = "")
  key_s <- c("variant", "species_code", "flag", "stage", "role")
  key_m <- c(key_s, "direction")
  mp <- stats::aggregate(mb[c("band_km", "n_band", "core_km", "n_core")],
                         mb[key_m], sum)
  mp <- cbind(mp, .lnk_hvb_density(mp$n_band, mp$band_km, mp$n_core,
                                   mp$core_km))
  mp <- mp[do.call(order, mp[key_m]), ]
  utils::write.csv(mp, file.path(dir_out, "model_bands_pooled.csv"),
                   row.names = FALSE, na = "")

  mseg <- do.call(rbind, mseg)
  mseg$role <- roles$role[match(paste(mseg$watershed_group_code,
                                      mseg$species_code),
                                paste(roles$watershed_group_code,
                                      roles$species_code))]
  ks <- function(d) do.call(paste, d[key_s])
  # One fact derived twice: the per-segment split must reproduce the band
  # function's pooled band and core km and counts, both ways, or the size
  # adjustment reads other rows than the bands.
  tot <- stats::aggregate(mseg[c("km", "n")], mseg[c(key_s, "class")], sum)
  for (k in seq_len(nrow(mp))) {
    r <- mp[k, ]
    cls <- names(mb_dir)[mb_dir == r$direction]
    t_b <- tot[ks(tot) == ks(r) & tot$class == cls, ]
    t_c <- tot[ks(tot) == ks(r) & tot$class == "core", ]
    km_b <- sum(t_b$km); n_b <- sum(t_b$n)
    km_c <- sum(t_c$km); n_c <- sum(t_c$n)
    if (abs(km_b - r$band_km) > 1e-6 || n_b != r$n_band ||
        abs(km_c - r$core_km) > 1e-6 || n_c != r$n_core) {
      stop("the per-segment split does not reproduce model_bands_pooled.csv ",
           "for ", ks(r), " ", r$direction, call. = FALSE)
    }
  }

  # Rates per stream-order class, pooled per role (sums, never averages of
  # segment rates), and the rate each class is priced at: its rate group's
  # (order_groups()), or the core's pooled rate for `unknown` short of n_min.
  ms <- stats::aggregate(mseg[c("km", "n")],
                         mseg[c(key_s, "class", "order_class")], sum)
  ms$per_100km <- ifelse(ms$km > 0, 100 * ms$n / ms$km, NA_real_)
  ms$rate_group <- NA_character_
  ms$core_per_100km_used <- NA_real_
  for (k in unique(ks(ms))) {
    core <- ms[ks(ms) == k & ms$class == "core", ]
    pooled_rate <- if (sum(core$km) > 0) 100 * sum(core$n) / sum(core$km) else NA_real_
    km_o <- core$km[match(order_levels, core$order_class)]
    n_o <- core$n[match(order_levels, core$order_class)]
    km_o[is.na(km_o)] <- 0
    n_o[is.na(n_o)] <- 0
    grp <- order_groups(n_o)
    rate_o <- vapply(grp, function(g) {
      km_g <- sum(km_o[grp == g])
      if (km_g > 0) 100 * sum(n_o[grp == g]) / km_g else pooled_rate
    }, numeric(1))
    i <- which(ks(ms) == k)
    j <- match(ms$order_class[i], order_levels)
    ms$rate_group[i] <- ifelse(is.na(j), "pooled", grp[j])
    ms$core_per_100km_used[i] <- ifelse(is.na(j), pooled_rate, rate_o[j])
    unk <- core[core$order_class == "unknown", ]
    if (nrow(unk) == 1L && unk$n >= n_min && unk$km > 0) {
      u <- i[ms$order_class[i] == "unknown"]
      ms$rate_group[u] <- "unknown"
      ms$core_per_100km_used[u] <- 100 * unk$n / unk$km
    }
  }
  ms$ratio_to_core <- ifelse(!is.na(ms$core_per_100km_used) &
                               ms$core_per_100km_used > 0,
                             ms$per_100km / ms$core_per_100km_used, NA_real_)
  ms <- ms[do.call(order, ms[c(key_s, "class", "order_class")]), ]
  utils::write.csv(ms, file.path(dir_out, "model_size.csv"), row.names = FALSE,
                   na = "")
  # Why the other model leaves each band segment out (reported only).
  mr <- stats::aggregate(mseg[mseg$class != "core", c("km", "n")],
                         mseg[mseg$class != "core", c(key_s, "class", "reason")],
                         sum)
  mr <- mr[do.call(order, mr[c(key_s, "class", "reason")]), ]
  utils::write.csv(mr, file.path(dir_out, "model_reason.csv"), row.names = FALSE,
                   na = "")
  # The same, split by where the discharge came from (#305): the table's own
  # value, a fill tier, or none.
  mf <- stats::aggregate(
    mseg[mseg$class != "core", c("km", "n")],
    mseg[mseg$class != "core", c(key_s, "class", "reason", "mad_m3s_source")],
    sum)
  mf <- mf[do.call(order, mf[c(key_s, "class", "reason", "mad_m3s_source")]), ]
  utils::write.csv(mf, file.path(dir_out, "model_fill.csv"), row.names = FALSE,
                   na = "")

  # The rule: per band, expected = sum over order classes of band km x the
  # rate its class is priced at; habitat when expected >= n_min and found /
  # expected >= ratio_min (of record). Beside it, the #302 reading (expected
  # at the pooled core rate) and the found count.
  eb <- ms[ms$class != "core", ]
  eb$expected <- eb$km * eb$core_per_100km_used / 100
  eb$km_merged_rate <- ifelse(grepl("-", eb$rate_group), eb$km, 0)
  eb$km_pooled_rate <- ifelse(eb$rate_group == "pooled", eb$km, 0)
  mv <- stats::aggregate(eb[c("expected", "km_merged_rate", "km_pooled_rate")],
                         eb[c(key_s, "class")], sum)
  mv$direction <- unname(mb_dir[mv$class])
  mv <- merge(mp, mv[c(key_s, "direction", "class", "expected",
                       "km_merged_rate", "km_pooled_rate")],
              by = key_m, all.x = TRUE)
  miss <- is.na(mv$class)
  mv$class[miss] <- names(mb_dir)[match(mv$direction[miss], mb_dir)]
  for (k in c("expected", "km_merged_rate", "km_pooled_rate")) {
    mv[[k]][miss] <- 0
  }
  decide <- function(expected, ratio) {
    ifelse(is.na(expected) | expected < n_min, "underpowered",
           ifelse(!is.na(ratio) & ratio >= ratio_min, "habitat", "not habitat"))
  }
  mv$ratio_size_adjusted <- ifelse(mv$expected > 0, mv$n_band / mv$expected,
                                   NA_real_)
  mv$decision_size_adjusted <- decide(mv$expected, mv$ratio_size_adjusted)
  mv$n_expected_pooled <- mv$density_core * mv$band_km
  mv$decision_pooled <- decide(mv$n_expected_pooled, mv$density_ratio)
  mv$decision_found_floor <- ifelse(
    mv$n_band < n_min, "underpowered",
    ifelse(!is.na(mv$density_ratio) & mv$density_ratio >= ratio_min, "habitat",
           "not habitat"))
  mv$of_record <- mv$role %in% "held_out" & mv$stage == "any"
  # The two bands of a variant x flag read together (the research doc's
  # table); an underpowered band leaves only its own half open.
  reading_of <- function(cw, mad) {
    if (cw == "underpowered" && mad == "underpowered") return("open")
    if (cw == "underpowered") return(paste0("mad-only ", mad, "; cw-only open"))
    if (mad == "underpowered") return(paste0("cw-only ", cw, "; mad-only open"))
    if (cw == "habitat" && mad != "habitat") return("cw closer")
    if (cw != "habitat" && mad == "habitat") return("mad closer")
    if (cw == "habitat") return("each misses habitat the other finds")
    "the models differ only on little-used water"
  }
  mv$reading <- NA_character_
  rd <- mv[mv$of_record, ]
  for (k in unique(paste(rd$variant, rd$flag))) {
    r <- rd[paste(rd$variant, rd$flag) == k, ]
    cw <- r$decision_size_adjusted[r$class == "cw_only"]
    mad <- r$decision_size_adjusted[r$class == "mad_only"]
    if (length(cw) != 1L || length(mad) != 1L) next
    mv$reading[mv$of_record & paste(mv$variant, mv$flag) == k] <-
      reading_of(cw, mad)
  }
  mv <- mv[do.call(order, mv[c(key_s, "class")]), ]
  utils::write.csv(mv, file.path(dir_out, "model_verdict.csv"),
                   row.names = FALSE, na = "")
}

if (sum(!is.na(variants$column)) == 0L) {
  # Model-only variants and no ladder: nothing below applies.
  write_stamp()
  dbDisconnect(conn)
  say("wrote %s", dir_out)
  quit(save = "no")
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
# A step that changes the habitat model as well (the cw base to the first
# `mad` rung of a MAD ladder, link#302) is the ladder's anchor, not a
# threshold step: it is taken by construction, its bands are reported both
# ways, and the walk starts beyond it.
steps$model_step <- model_of(steps$variant) != model_of(steps$step_from)
# A model change is a ladder's first step or nothing: mid-ladder it would be
# force-taken and would put a rung of another model in the core.
if (any(steps$model_step & steps$step_from != base_variant)) {
  stop("a model change must step from ", base_variant, ": ",
       paste(steps$variant[steps$model_step & steps$step_from != base_variant],
             collapse = ", "), call. = FALSE)
}
# Raising a maximum adds habitat; lowering a minimum does (link#302's MAD
# rungs are the first ladders on a `_min` column).
loosens <- ifelse(grepl("_min$", steps$column),
                  num(steps$value) < steps$value_from,
                  num(steps$value) > steps$value_from)
steps$direction <- ifelse(steps$model_step | loosens, "added", "removed")
ladder_of <- function(sp, column) {
  c(base_variant, variants$variant[variants$species_code %in% sp &
                                     variants$column %in% column])
}
# The core: the habitat every schema of the ladder keeps. A MAD ladder's core
# leaves out the cw base, which tests axes the `mad` rungs do not (a width
# floor, and NULL widths fail), so the core and the bands are cut alike.
core_of <- function(sp, column) {
  l <- ladder_of(sp, column)
  rungs <- l[-1L]
  if (any(model_of(rungs) != "cw")) rungs else l
}
# Every step past an anchor reads the same species, column, flag and stage as
# its step_from, or value_from is NA and the step drops out of the walk.
local({
  for (k in seq_len(nrow(steps))) {
    f <- steps$step_from[k]
    if (identical(f, base_variant)) next
    a <- variants[variants$variant == steps$variant[k],
                  c("species_code", "column", "flag", "obs_stage")]
    b <- variants[variants$variant == f,
                  c("species_code", "column", "flag", "obs_stage")]
    if (!identical(unname(unlist(a)), unname(unlist(b)))) {
      stop("step ", steps$variant[k], " reads a different species, column, ",
           "flag or stage than its step_from ", f, call. = FALSE)
    }
  }
})
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
bands <- list()
for (k in seq_len(nrow(steps))) {
  s <- steps[k, ]
  w_sp <- roles$watershed_group_code[roles$species_code == s$species_code]
  core <- schema_of(core_of(s$species_code, s$column))
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
b_any <- bands[bands$stage == "any" &
                 !bands$variant %in% steps$variant[steps$model_step], ]
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

# value_from is NA for a ladder's anchor (default has no value), and
# aggregate() drops a group whose key is NA, so it is joined back after.
key_b <- c("variant", "step_from", "column", "value", "step_direction",
           "obs_stage", "species_code", "flag", "role", "direction", "stage")
pooled <- stats::aggregate(bands[c("band_km", "n_band", "core_km", "n_core")],
                           bands[key_b], sum)
pooled <- cbind(pooled[1:3],
                value_from = steps$value_from[match(pooled$variant,
                                                    steps$variant)],
                pooled[-(1:3)])
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
is_anchor <- rule$variant %in% steps$variant[steps$model_step]
rule$decision[is_anchor] <- "take (anchor: model change)"
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
rule$decision_expected_floor[is_anchor] <- "take (anchor: model change)"
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
    dec[startsWith(dec, "take")] <- "take"
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
    } else if (any(chain %in% steps$variant[steps$model_step])) {
      # A MAD ladder has no prior verdict to stand (default has no range).
      # Pre-registered (research/habitat_thresholds.md, #302): an
      # underpowered first step past the anchor lands its own value, the
      # calibrated candidate, unscored; a later one stops at the last value
      # taken.
      first <- stop_at >= 2L &&
        chain[stop_at - 1L] %in% steps$variant[steps$model_step]
      if (first) {
        status <- paste("underpowered at", chain[stop_at],
                        "- its value lands unscored")
        value <- num(variants$value[variants$variant == chain[stop_at]])
      } else {
        status <- paste("underpowered at", chain[stop_at], "- stops at",
                        chain[stop_at - 1L])
        value <- num(variants$value[variants$variant == chain[stop_at - 1L]])
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
rule$floor_of_record <- rep(floor_of_record, nrow(rule))
rule$decision_of_record <- if (floor_of_record == "found") rule$decision else
  rule$decision_expected_floor
rule$walked_value_of_record <- if (floor_of_record == "found") {
  rule$walked_value
} else {
  rule$walked_value_expected_floor
}
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
  # A segment goes to the first band whose flags differ, which is the
  # verdict's band only on a nested ladder. A MAD ladder's anchor moves
  # habitat both ways, so the threshold steps are labelled first and the
  # anchor last, split by direction, as bands.csv counts them.
  thr_steps <- lad[!lad$model_step, ]
  anc <- lad[lad$model_step, ]
  band_case <- paste(c(
    sprintf("WHEN %s <> %s THEN %s", flag_of(schema_of(thr_steps$variant)),
            flag_of(schema_of(thr_steps$step_from)),
            DBI::dbQuoteString(conn, thr_steps$variant)),
    if (nrow(anc) > 0L) {
      sprintf("WHEN %1$s AND NOT %2$s THEN %3$s WHEN %2$s AND NOT %1$s THEN %4$s",
              flag_of(schema_of(anc$variant)), flag_of(schema_of(anc$step_from)),
              DBI::dbQuoteString(conn, paste(anc$variant, "added")),
              DBI::dbQuoteString(conn, paste(anc$variant, "removed")))
    }),
    collapse = " ")
  d <- dbGetQuery(conn, sprintf(
    "SELECT s.watershed_group_code, s.id_segment, s.length_metre, s.gradient,
            (st_zmin(s.geom) + st_zmax(s.geom)) / 2 AS elevation,
            CASE WHEN %3$s THEN 'core' %4$s ELSE NULL END AS class
       FROM %1$s.streams s
       %2$s
      WHERE s.watershed_group_code = ANY($1)",
    schema_of(base_variant), joins,
    paste(vapply(schema_of(core_of(L$species_code, L$column)), flag_of,
                 character(1)), collapse = " AND "),
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
            -- connectivity (a cluster the step newly connects); NULL for a
            -- step that is not a gradient step (a MAD rung, link#302)
            CASE WHEN $4 THEN b.gradient > $2 AND b.gradient <= $3
            END AS in_window,
            sum(b.length_metre) / 1000 AS km
       FROM band b
      GROUP BY 1, 2, 3", sv, sr, spl),
    params = list(paste0("{", paste(w_sp, collapse = ","), "}"),
                  s$value_from, num(s$value),
                  grepl("_gradient_", s$column) && !s$model_step))
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

write_stamp()
dbDisconnect(conn)
say("wrote %s", dir_out)
