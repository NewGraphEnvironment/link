#!/usr/bin/env Rscript
# query_habitat_thresholds_mad.R — mean annual discharge (mad_m3s) at fish
# observation locations, against accessible availability, for the species
# that had no MAD range in `default` (link#302; #307 since gave `default`
# width-converted ranges, so a re-run's `current` column reads them).
#
# Under the `mad` habitat model (#286) a species with no `*_mad_min/max` in
# parameters_habitat_thresholds.csv loses every stream rule that inherits
# thresholds. This script measures the discharge the fish actually use, the
# evidence for the ranges `default_tuned` is given.
#
# The instrument is lnk_habitat_validate() itself, run over the calibration
# WSGs with a method table that puts every one of them on `mad`, so each
# observation location carries its segment's mad_m3s (joined from
# whse_basemapping.fwa_stream_networks_discharge on linear_feature_id, which
# is unique there). The attachment, pooling (default's species_pooling.csv),
# exclusions, stage and access are then exactly the validator's: no second
# copy of that logic. The persisted habitat flags are the cw run's and are not
# used here; only the segment attributes, `access` and the stage are.
#
# Calibration WSGs: every WSG persisted in `fresh_default` that has discharge
# for at least one line. They are in-sample for any later score; held-out
# WSGs must come from outside this set.
#
# Decision rule, fixed before the first run (2026-10-02):
#   - Locations: accessible (`access` 1 or 2) on a segment whose stage rule
#     tests the size under `mad` (fresh drops the river rule's rule-level
#     channel_width there, so river polygons inherit the range too):
#       spawn: a river polygon (waterbody_type R), or a stream edge
#              (1000/1100/2000/2300) outside any waterbody (the spawn stream
#              rule carries `in_waterbody: false`);
#       rear:  a river polygon, or a stream edge anywhere (the rear stream
#              rule has no `in_waterbody`), except a segment that the
#              species' own lake or wetland rear rule already admits (as
#              fresh compiles it, .frs_rule_to_sql()); those are reported
#              as subset `waterbody_rule` and never decide.
#     NULL mad_m3s is reported as coverage and left out of the quantiles.
#   - spawn_mad_min <- P05 of spawn-staged locations. Where those are fewer
#     than 30, P05 of locations at any stage on spawn-tested segments,
#     labelled `fallback: any stage` (operator, 2026-10-02: BT and GR cluster
#     rearing on spawning, so an empty spawn range would also empty their
#     stream rearing under `mad`).
#   - rear_mad_min  <- P05 of locations at any stage (these four are
#     residents or carry no stage, as #284 read BT rearing); rear-staged is
#     reported beside it as a comparison.
#   - The value is floored to two significant figures (so the P05 location
#     itself stays inside the range).
#   - `*_mad_max` is 9999 (open), the operator's call at the #302 plan gate.
#   - Fewer than 30 locations (after the spawn fallback): no value
#     ("insufficient"); the cell stays NA. `decides` marks the row whose value
#     is the candidate.
#   - Only stages a stream rule inherits thresholds for (rules.yaml): KO
#     rearing is lake-only, so KO gets a spawn range only.
#
#   Rscript data-raw/query_habitat_thresholds_mad.R \
#     [--species=BT,GR,KO,RB] [--schema=fresh_default] [--wsgs=ADMS,...]
#     [--out=data-raw/logs/habitat_thresholds_302]
#
# Writes to --out:
#   obs_mad.csv      one row per retained location (no project names)
#   coverage.csv     locations per species x stage, and the share with no discharge
#   quantiles.csv    mad_m3s quantiles by species x stage x subset x region
#   selection.csv    use vs accessible length by mad_m3s bin
#   candidates.csv   the decision rule above, applied mechanically
#   stamp.txt        environment stamp
#
# Limits, stated rather than coded around (code-check round 3, none of them
# reached by the `default` rules): the waterbody admission takes fresh's
# compiled L/W rules but not an `area_only` rule's removal or model_rules();
# inherits_size() reads rules.yaml for which stages inherit a size range. The
# classification was checked against fresh's own compiled `mad` predicates on
# every fresh_default segment (BT, GR; spawn, rear): they agree on all of them.
#
# Read-only against docker fwapg (:5432). Temp tables only.

suppressPackageStartupMessages({
  pkgload::load_all(quiet = TRUE)
  library(DBI)
  library(dplyr)
})

opt <- function(name, default = NULL) {
  a <- grep(paste0("^--", name, "="), commandArgs(trailingOnly = TRUE),
            value = TRUE)
  if (length(a) == 0L) return(default)
  sub(paste0("^--", name, "="), "", a[length(a)])
}
split_csv <- function(x) {
  if (is.null(x)) return(character(0))
  v <- toupper(trimws(strsplit(x, ",")[[1]]))
  v[nzchar(v)]
}

species <- split_csv(opt("species", "BT,GR,KO,RB"))
schema <- opt("schema", "fresh_default")
dir_out <- opt("out", file.path("data-raw", "logs", "habitat_thresholds_302"))
wsgs_arg <- split_csv(opt("wsgs"))
fs::dir_create(dir_out)

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")

cfg <- lnk_config("default")
loaded <- suppressWarnings(lnk_load_overrides(cfg))
th <- utils::read.csv(cfg$files$parameters_habitat_thresholds$path)

# -- calibration WSGs: persisted in `schema` and carrying discharge -----------
wsg_cal <- dbGetQuery(conn, sprintf("
  SELECT DISTINCT s.watershed_group_code
    FROM %s.streams s
   WHERE EXISTS (SELECT 1 FROM whse_basemapping.fwa_stream_networks_discharge d
                  WHERE d.linear_feature_id = s.linear_feature_id
                    AND d.mad_m3s IS NOT NULL)
   ORDER BY 1", schema))$watershed_group_code
if (length(wsgs_arg) > 0L) {
  if (!all(wsgs_arg %in% wsg_cal)) {
    stop("--wsgs not persisted in ", schema, " with discharge: ",
         paste(setdiff(wsgs_arg, wsg_cal), collapse = ", "), call. = FALSE)
  }
  wsg_cal <- wsgs_arg
}
message(length(wsg_cal), " calibration WSGs: ", paste(wsg_cal, collapse = " "))

# -- every calibration WSG on `mad`, on a copy of default's method table ------
meth <- utils::read.csv(cfg$files$parameters_habitat_method$path,
                        colClasses = "character")
meth <- rbind(meth[!meth$watershed_group_code %in% wsg_cal, ],
              data.frame(watershed_group_code = wsg_cal, model = "mad"))
path_meth <- tempfile(fileext = ".csv")
utils::write.csv(meth, path_meth, row.names = FALSE, quote = FALSE)
cfg$files$parameters_habitat_method$path <- path_meth

pool <- lnk_species_pooling(loaded, aoi = wsg_cal, species = species)
v <- lnk_habitat_validate(conn, aoi = wsg_cal, cfg = cfg, loaded = loaded,
                          species = species, schema = schema,
                          species_obs = pool)
if (!all(v$observations$model == "mad")) {
  stop("a calibration WSG did not resolve to `mad`", call. = FALSE)
}

regions <- utils::read.csv(system.file("extdata", "wsg_regions.csv",
                                       package = "link"))
rules <- yaml::read_yaml(cfg$rules)
edges_stream <- c(1000L, 1100L, 2000L, 2300L)

# Segments a species' own lake / wetland rear rule admits with no size test.
# The SQL is fresh's own (.frs_rule_to_sql() over the L/W rear rules), so the
# polygon tables, the area floors and the edges are whatever fresh compiles,
# never a transcription of rules.yaml (which declares a wetland_ha_min that
# fresh's rear predicate does not apply, and whose L rules reach reservoirs).
wb_admit_sql <- function(sp) {
  r <- Filter(function(x) isTRUE(x$waterbody_type %in% c("L", "W")),
              rules[[sp]][["rear"]])
  if (length(r) == 0L) return("FALSE")
  paste(vapply(r, function(x) fresh:::.frs_rule_to_sql(x), character(1)),
        collapse = " OR ")
}
# One classification, in SQL, used for both the use side (the observations'
# segments) and the availability side (every accessible segment).
seg_class_sql <- function(sp) {
  # River polygons as fresh resolves `waterbody_type: R` (fwa_rivers_poly
  # membership, .frs_waterbody_tables()), not fwa_waterbodies' type column,
  # which lacks some river-polygon keys.
  sprintf("CASE WHEN s.waterbody_key IN (SELECT waterbody_key
                                           FROM whse_basemapping.fwa_rivers_poly)
                THEN 'river_poly'
                WHEN s.edge_type NOT IN (%1$s) THEN 'other'
                WHEN s.waterbody_key IS NULL THEN 'stream'
                WHEN %2$s THEN 'waterbody_rule'
                ELSE 'stream_in_waterbody' END",
          paste(edges_stream, collapse = ", "), wb_admit_sql(sp))
}
seg_classes <- bind_rows(lapply(species, function(sp) {
  o <- v$observations[v$observations$species_code == sp &
                        !is.na(v$observations$id_segment),
                      c("watershed_group_code", "id_segment")]
  o <- unique(o)
  if (nrow(o) == 0L) return(NULL)
  dbWriteTable(conn, "t_mad_seg", o, temporary = TRUE, overwrite = TRUE)
  dbGetQuery(conn, sprintf("
    SELECT '%1$s' AS species_code, s.watershed_group_code, s.id_segment,
           %3$s AS pred_set
      FROM %2$s.streams s
      JOIN t_mad_seg t USING (watershed_group_code, id_segment)", sp, schema, seg_class_sql(sp)))
}))
tested_classes <- list(spawn = c("river_poly", "stream"),
                       rear = c("river_poly", "stream", "stream_in_waterbody"))

obs <- v$observations |>
  mutate(is_spawn = as.vector(is_spawn), is_rear = as.vector(is_rear),
         obs_species = as.vector(obs_species),
         accessible_pt = access %in% c(1L, 2L)) |>
  left_join(seg_classes,
            by = c("species_code", "watershed_group_code", "id_segment")) |>
  left_join(regions[c("watershed_group_code", "region")],
            by = "watershed_group_code")

readr::write_csv(
  obs |> select(species_code, obs_species, watershed_group_code, region,
                blue_line_key, m, is_spawn, is_rear, n_records, id_segment,
                waterbody_type, pred_set, access, gradient, channel_width,
                mad_m3s),
  file.path(dir_out, "obs_mad.csv"), na = "")

# -- stage sets ------------------------------------------------------------------
# A set of locations is a stage filter AND the segments that stage's rule
# tests: spawn-staged on spawn-tested segments; `any` and rear-staged on
# rear-tested segments (they calibrate rearing).
stage_sets <- list(
  any = function(d) d[d$pred_set %in% tested_classes$rear, ],
  spawn = function(d) {
    d[d$is_spawn %in% TRUE & d$pred_set %in% tested_classes$spawn, ]
  },
  any_spawn = function(d) d[d$pred_set %in% tested_classes$spawn, ],
  rear = function(d) {
    d[d$is_rear %in% TRUE & d$pred_set %in% tested_classes$rear, ]
  })
tested <- obs |> filter(accessible_pt)

coverage <- bind_rows(lapply(species, function(sp) {
  bind_rows(lapply(names(stage_sets), function(st) {
    d <- obs[obs$species_code == sp, ]
    d <- switch(st, any = , any_spawn = d, spawn = d[d$is_spawn %in% TRUE, ],
                rear = d[d$is_rear %in% TRUE, ])
    t <- stage_sets[[st]](tested[tested$species_code == sp, ])
    tibble(species_code = sp, stage = st, n_locations = nrow(d),
           n_accessible_tested = nrow(t),
           n_mad_null = sum(is.na(t$mad_m3s)),
           share_mad_null = if (nrow(t) == 0L) NA_real_ else
             mean(is.na(t$mad_m3s)),
           n_wsg = length(unique(t$watershed_group_code)))
  }))
}))
readr::write_csv(coverage, file.path(dir_out, "coverage.csv"), na = "")

# -- quantiles -------------------------------------------------------------------
probs <- c(0.01, 0.02, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99)
qtab <- function(x, ...) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) return(NULL)
  q <- stats::quantile(x, probs, names = FALSE, type = 7)
  tibble(..., n = length(x),
         !!!stats::setNames(as.list(q), sprintf("p%02d", probs * 100)))
}
quant <- bind_rows(lapply(species, function(sp) {
  bind_rows(lapply(names(stage_sets), function(st) {
    d <- stage_sets[[st]](tested[tested$species_code == sp, ])
    regs <- c("all", sort(unique(d$region)))
    bind_rows(lapply(regs, function(r) {
      dr <- if (r == "all") d else d[d$region %in% r, ]
      bind_rows(
        qtab(dr$mad_m3s, species_code = sp, stage = st, region = r,
             subset = "tested"),
        qtab(dr$mad_m3s[dr$pred_set == "stream"], species_code = sp,
             stage = st, region = r, subset = "stream"))
    }))
  }))
}))
# Rearing a lake or wetland rule admits: no size test today, but the rear
# range also gates fresh's lake / wetland rearing predicates once it exists
# (build_wb_pred), so how much of it sits below a candidate is reported.
quant <- bind_rows(quant, bind_rows(lapply(species, function(sp) {
  d <- tested[tested$species_code == sp & tested$pred_set == "waterbody_rule", ]
  bind_rows(qtab(d$mad_m3s, species_code = sp, stage = "any", region = "all",
                 subset = "waterbody_rule"),
            qtab(d$mad_m3s[d$is_rear %in% TRUE], species_code = sp,
                 stage = "rear", region = "all", subset = "waterbody_rule"))
})))
readr::write_csv(quant, file.path(dir_out, "quantiles.csv"), na = "")

# -- availability: accessible length by mad bin, same WSGs ------------------------
breaks_mad <- c(0, 0.01, 0.02, 0.05, 0.1, 0.2, 0.3, 0.5, 1, 2, 5, 10, 20, 50,
                100, Inf)
avail <- bind_rows(lapply(species, function(sp) {
  present <- toupper(loaded$wsg_species_presence$watershed_group_code[
    as.character(loaded$wsg_species_presence[[tolower(sp)]]) %in% "t"])
  w <- intersect(wsg_cal, present)
  if (length(w) == 0L) return(NULL)
  dbGetQuery(conn, sprintf("
    SELECT '%1$s' AS species_code, %4$s AS pred_set,
           d.mad_m3s, sum(s.length_metre) / 1000 AS km
      FROM %2$s.streams s
      JOIN %2$s.streams_access a USING (id_segment, watershed_group_code)
      LEFT JOIN whse_basemapping.fwa_stream_networks_discharge d
        ON d.linear_feature_id = s.linear_feature_id
     WHERE a.access_%3$s IN (1, 2)
       AND s.watershed_group_code = ANY($1)
     GROUP BY 1, 2, 3", sp, schema, tolower(sp), seg_class_sql(sp)),
    params = list(paste0("{", paste(w, collapse = ","), "}")))
}))

bin_label <- function(x) {
  b <- as.character(cut(x, breaks_mad, right = FALSE, include.lowest = TRUE))
  ifelse(is.na(b), "NULL", b)
}
lv <- c(levels(cut(0, breaks_mad, right = FALSE, include.lowest = TRUE)),
        "NULL")
sel <- bind_rows(lapply(species, function(sp) {
  bind_rows(lapply(names(stage_sets), function(st) {
    cl <- if (st %in% c("spawn", "any_spawn")) tested_classes$spawn else
      tested_classes$rear
    a <- avail[avail$species_code == sp & avail$pred_set %in% cl, ] |>
      mutate(bin = bin_label(mad_m3s)) |>
      group_by(bin) |>
      summarise(avail_km = sum(km), .groups = "drop")
    d <- stage_sets[[st]](tested[tested$species_code == sp, ])
    u <- tibble(bin = bin_label(d$mad_m3s)) |> count(bin, name = "use_n")
    full_join(u, a, by = "bin") |>
      mutate(use_n = coalesce(use_n, 0L), avail_km = coalesce(avail_km, 0),
             use_share = use_n / sum(use_n),
             avail_share = avail_km / sum(avail_km),
             ratio = use_share / avail_share,
             bin = factor(bin, levels = lv)) |>
      arrange(bin) |>
      mutate(bin = as.character(bin), species_code = sp, stage = st,
             .before = 1)
  }))
}))
readr::write_csv(sel, file.path(dir_out, "selection.csv"), na = "")

# -- decision rule ---------------------------------------------------------------
floor_signif2 <- function(x) {
  if (is.na(x) || x <= 0) return(if (is.na(x)) NA_real_ else 0)
  e <- 10^(floor(log10(x)) - 1)
  # round() first: x / e is an exact integer in decimal more often than in binary.
  # signif() last: the product carries binary noise (2.4000000000000004)
  # that would otherwise be written into a thresholds CSV.
  signif(floor(round(x / e, 9)) * e, 2)
}
inherits_size <- function(sp, stage) {
  r <- rules[[sp]][[stage]]
  any(vapply(r, function(x) {
    !identical(x$thresholds, FALSE) && is.null(x$waterbody_type) &&
      any(c(1000L, 1100L) %in% as.integer(unlist(x$edge_types_explicit)))
  }, logical(1)))
}
cands <- bind_rows(lapply(species, function(sp) {
  bind_rows(lapply(c("spawn", "rear"), function(stage) {
    if (!inherits_size(sp, stage)) return(NULL)
    set <- if (stage == "spawn") "spawn" else "any"
    one <- function(st, role, decides) {
      r <- quant[quant$species_code == sp & quant$stage == st &
                   quant$region == "all" & quant$subset == "tested", ]
      n <- if (nrow(r) == 0L) 0L else r$n
      p05 <- if (nrow(r) == 0L) NA_real_ else r$p05
      enough <- n >= 30L
      tibble(species_code = sp, parameter = paste0(stage, "_mad_min"),
             evidence_set = st, evidence_role = role,
             current = th[th$species_code == sp, paste0(stage, "_mad_min")],
             n = n, p05 = p05,
             rule_value = if (enough) floor_signif2(p05) else NA_real_,
             rule_max = if (enough) 9999 else NA_real_,
             rule_says = if (enough) "set" else "insufficient",
             decides = decides)
    }
    prim <- one(set, "primary", TRUE)
    fb <- NULL
    if (stage == "spawn" && prim$rule_says == "insufficient") {
      prim$decides <- FALSE
      fb <- one("any_spawn", "fallback: any stage", TRUE)
    }
    bind_rows(prim, fb,
              if (stage == "rear") one("rear", "comparison: rear-staged", FALSE))
  }))
}))
readr::write_csv(cands, file.path(dir_out, "candidates.csv"), na = "")
print(as.data.frame(cands))

# -- stamp -----------------------------------------------------------------------
fresh_sha <- .lnk_pkg_git_sha("fresh")
link_dirty <- length(system(paste(
  "git status --porcelain -- R inst/extdata/configs/default",
  "data-raw/query_habitat_thresholds_mad.R"), intern = TRUE)) > 0L
pooled <- pool[pool$scope_level != "self", ]
writeLines(c(
  sprintf("date: %s", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
  sprintf("link: %s @ %s%s", utils::packageVersion("link"),
          system("git rev-parse --short HEAD", intern = TRUE),
          if (link_dirty) " (dirty)" else ""),
  sprintf("fresh installed: %s @ %s", utils::packageVersion("fresh"),
          if (is.na(fresh_sha)) "no recorded sha" else fresh_sha),
  "db: docker fwapg localhost:5432",
  sprintf("schema: %s; %d calibration WSGs (persisted, with discharge): %s",
          schema, length(wsg_cal), paste(wsg_cal, collapse = " ")),
  sprintf("bcfishobs.observations rows: %s",
          dbGetQuery(conn, "SELECT count(*) FROM bcfishobs.observations")[[1]]),
  sprintf("discharge rows: %s (%s with mad_m3s)",
          dbGetQuery(conn, "SELECT count(*) FROM whse_basemapping.fwa_stream_networks_discharge")[[1]],
          dbGetQuery(conn, "SELECT count(mad_m3s) FROM whse_basemapping.fwa_stream_networks_discharge")[[1]]),
  sprintf("pooling: default species_pooling.csv; %s",
          if (nrow(pooled) == 0L) "none" else
            paste(unique(paste0(pooled$species_code, "<-", pooled$obs_species)),
                  collapse = ", "))),
  file.path(dir_out, "stamp.txt"))

dbDisconnect(conn)
message("wrote ", dir_out)
