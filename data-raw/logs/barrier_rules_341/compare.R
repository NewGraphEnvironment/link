#!/usr/bin/env Rscript
# compare.R — two barrier-rule sets on #321's parity groups (link#341), and
# whether a rule change needs a re-model.
#
# Reads one build: its persist schema (streams, habitat, barriers) and the
# kept working `crossings` of each group (`crossings` is not persisted). For
# each rule set it copies a group's crossings into a scratch schema, writes
# barrier_rule_id with the rules (`.lnk_barrier_rules_apply()`), emits the
# barrier sets (`lnk_barriers_emit()`), and computes:
#   - per-crossing totals (`lnk_aggregate(barriers = )`), and their seconds;
#   - the barrier-below marks (`lnk_access()` over the build's barriers with
#     the group's human-made rows replaced), and their seconds.
# Rule sets:
#   province  the built-in rule: the source's own status
#   added     province OR outlet drop above 0.6 m OR slope x length above 120
#             (PSCIS assessments)
#   in_place  for a PSCIS crossing, the measured rules, keeping the province's
#             result only where both measurements are null; every other
#             crossing keeps the province's result
# The measured numbers are the ones lnk_thresholds() shipped as `high`.
#
# Usage: Rscript compare.R <persist schema> <working prefix> <config> <out dir> <WSG,...>
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 5L)
persist <- args[[1]]; prefix <- args[[2]]; config <- args[[3]]; out <- args[[4]]
wsgs <- strsplit(args[[5]], ",")[[1]]
dir.create(out, recursive = TRUE, showWarnings = FALSE)
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
q <- function(sql) DBI::dbGetQuery(conn, sql)
x <- function(sql) invisible(DBI::dbExecute(conn, sql))
cfg <- lnk_config(config)
cfg$pipeline$schema <- persist
loaded <- suppressWarnings(lnk_load_overrides(cfg))

row <- function(rule_id, applies_to, source_table, column, operator, value) {
  data.frame(rule_id = rule_id, applies_to = applies_to,
             source_table = source_table, column_name = column, operator = operator,
             value = value, species = "*", outcome = "barrier",
             date = "2026-11-24", source = "link#341 compare", notes = "",
             stringsAsFactors = FALSE)
}
drop <- row("drop", "PSCIS", "pscis_assessment", "outlet_drop", ">", "0.6")
slope <- row("slope", "PSCIS", "pscis_assessment", "slope_length", ">", "120")
status <- .lnk_barrier_rules_builtin
sets <- list(
  province = status,
  added = rbind(status, drop, slope),
  in_place = rbind(
    row("status", "MODELLED_CROSSINGS;CABD", "crossings", "barrier_status",
        "in", "BARRIER;POTENTIAL"),
    drop, slope,
    row("unmeasured", "PSCIS", "pscis_assessment", "outlet_drop", "is_null", NA),
    row("unmeasured", "PSCIS", "pscis_assessment", "slope_length", "is_null", NA),
    row("unmeasured", "PSCIS", "crossings", "barrier_status", "in",
        "BARRIER;POTENTIAL")))
for (nm in names(sets)) {
  write.csv(sets[[nm]][, 1:8], file.path(out, paste0("rules_", nm, ".csv")),
            row.names = FALSE)
}

timing <- list(); classes <- list(); km <- list(); marks <- list()
cols_b <- paste(names(cols_barriers), collapse = ", ")
for (w in wsgs) {
  src <- paste0(prefix, tolower(w), ".crossings")
  for (nm in names(sets)) {
    s <- paste0("zz341_", nm, "_", tolower(w))
    x(sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
    x(sprintf("CREATE SCHEMA %s", s))
    x(sprintf("CREATE TABLE %s.crossings AS SELECT * FROM %s", s, src))
    x(sprintf("ALTER TABLE %s.crossings DROP COLUMN IF EXISTS barrier_rule_id", s))
    .lnk_barrier_rules_apply(conn, s, sets[[nm]])
    lnk_barriers_emit(conn, s)
    t0 <- Sys.time()
    lnk_aggregate(conn, crossings = paste0(s, ".crossings"), schema = persist,
                  to = paste0(s, ".agg"), config = config,
                  barriers = paste0(s, ".barriers_anthropogenic"),
                  verbose = FALSE)
    t_agg <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    # The build's barriers with this group's human-made rows replaced by the
    # rule set's, as lnk_barriers_unify() writes them.
    x(sprintf("CREATE TABLE %1$s.barriers AS SELECT * FROM %2$s.barriers
                WHERE NOT (watershed_group_code = '%3$s'
                           AND barrier_source IN ('PSCIS', 'CABD', 'MODELLED_CROSSINGS'))",
              s, persist, w))
    x(sprintf("INSERT INTO %1$s.barriers (%2$s)
      SELECT aggregated_crossings_id, watershed_group_code, crossing_source,
             crossing_feature_type, barrier_status, NULL::text[], linear_feature_id,
             blue_line_key, watershed_key, downstream_route_measure, wscode_ltree,
             localcode_ltree, ST_Force2D(geom)
        FROM %1$s.crossings
       WHERE barrier_rule_id IS NOT NULL AND blue_line_key = watershed_key",
      s, cols_b))
    x(sprintf("CREATE TABLE %1$s.barrier_overrides AS SELECT * FROM %2$s.barrier_overrides", s, persist))
    # The persisted tables' indexes: the downstream walk probes them by line
    # and code, and unindexed copies make it scan.
    for (ix in c("barriers USING gist (wscode_ltree)", "barriers USING gist (localcode_ltree)",
                 "barriers (blue_line_key, downstream_route_measure)",
                 "barriers (barrier_source)", "barriers (watershed_group_code)",
                 "barrier_overrides (blue_line_key, downstream_route_measure)")) {
      x(sprintf("CREATE INDEX ON %s.%s", s, ix))
    }
    x(sprintf("ANALYZE %1$s.barriers", s)); x(sprintf("ANALYZE %1$s.barrier_overrides", s))
    t0 <- Sys.time()
    pres <- lnk_presence(loaded$wsg_species_presence, w,
                         groups = .lnk_presence_groups(loaded))
    lnk_access(conn, cfg = cfg, aoi = w,
               table_streams = paste0(persist, ".streams"),
               table_barriers = paste0(s, ".barriers"),
               table_to = paste0(s, ".access"), presence = pres,
               species = lnk_pipeline_species(cfg, loaded, w))
    t_acc <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    timing[[length(timing) + 1L]] <- data.frame(
      wsg = w, set = nm, aggregate_s = round(t_agg, 1), access_s = round(t_acc, 1))
  }
  # Class changes and unmeasured assessments, against the province.
  base <- paste0("zz341_province_", tolower(w))
  for (nm in setdiff(names(sets), "province")) {
    s <- paste0("zz341_", nm, "_", tolower(w))
    cl <- q(sprintf(
      "SELECT b.crossing_source,
              count(*) FILTER (WHERE b.barrier_rule_id IS NULL AND a.barrier_rule_id IS NOT NULL)::int AS to_barrier,
              count(*) FILTER (WHERE b.barrier_rule_id IS NOT NULL AND a.barrier_rule_id IS NULL)::int AS to_not_barrier,
              count(*)::int AS n
         FROM %1$s.crossings b JOIN %2$s.crossings a USING (aggregated_crossings_id)
        GROUP BY 1 ORDER BY 1", base, s))
    cl$wsg <- w; cl$set <- nm
    classes[[length(classes) + 1L]] <- cl
    k <- q(sprintf(
      "SELECT b.species_code,
              count(*) FILTER (WHERE abs(coalesce(b.spawning_belowupstrbarriers_km, 0)
                                       - coalesce(a.spawning_belowupstrbarriers_km, 0)) > 0.001
                                OR abs(coalesce(b.rearing_belowupstrbarriers_km, 0)
                                       - coalesce(a.rearing_belowupstrbarriers_km, 0)) > 0.001)::int
                AS crossings_moved,
              round(sum(abs(coalesce(b.spawning_belowupstrbarriers_km, 0)
                            - coalesce(a.spawning_belowupstrbarriers_km, 0)))::numeric, 2) AS spawning_km_moved,
              round(sum(abs(coalesce(b.rearing_belowupstrbarriers_km, 0)
                            - coalesce(a.rearing_belowupstrbarriers_km, 0)))::numeric, 2) AS rearing_km_moved
         FROM %1$s.agg b JOIN %2$s.agg a
           ON a.aggregated_crossings_id = b.aggregated_crossings_id
          AND a.species_code = b.species_code
        GROUP BY 1 ORDER BY 1", base, s))
    k$wsg <- w; k$set <- nm
    km[[length(km) + 1L]] <- k
    mk <- q(sprintf(
      "SELECT count(*) FILTER (WHERE b.has_barriers_anthropogenic_dnstr
                                 IS DISTINCT FROM a.has_barriers_anthropogenic_dnstr)::int
                AS anthropogenic_mark_moved,
              count(*) FILTER (WHERE b.has_barriers_pscis_dnstr
                                 IS DISTINCT FROM a.has_barriers_pscis_dnstr)::int AS pscis_mark_moved,
              count(*)::int AS segments
         FROM %1$s.access b JOIN %2$s.access a USING (id_segment)", base, s))
    mk$wsg <- w; mk$set <- nm
    marks[[length(marks) + 1L]] <- mk
  }
  um <- q(sprintf(
    "SELECT count(*)::int AS pscis_crossings,
            count(*) FILTER (WHERE pa.outlet_drop IS NULL AND
                                   (pa.culvert_slope IS NULL OR pa.length_or_width IS NULL))::int
              AS no_measurement
       FROM %s c LEFT JOIN whse_fish.pscis_assessment_svw pa
         ON pa.stream_crossing_id::text = c.aggregated_crossings_id
      WHERE c.crossing_source = 'PSCIS'", src))
  um$wsg <- w
  # A widened set selects crossings the persisted barriers do not hold.
  wid <- q(sprintf(
    "SELECT count(*)::int AS n FROM zz341_added_%s.crossings c
      WHERE c.barrier_rule_id IS NOT NULL AND c.blue_line_key = c.watershed_key
        AND NOT EXISTS (SELECT 1 FROM %s.barriers b
                         WHERE b.watershed_group_code = '%s'
                           AND b.id_barrier = c.aggregated_crossings_id)",
    tolower(w), persist, w))
  um$added_not_in_persisted_barriers <- wid$n
  write.csv(um, file.path(out, paste0("unmeasured_", w, ".csv")), row.names = FALSE)
}
bind <- function(l) do.call(rbind, l)
write.csv(bind(timing), file.path(out, "timing.csv"), row.names = FALSE)
write.csv(bind(classes), file.path(out, "classes.csv"), row.names = FALSE)
write.csv(bind(km), file.path(out, "km_below_barriers.csv"), row.names = FALSE)
write.csv(bind(marks), file.path(out, "marks.csv"), row.names = FALSE)
print(bind(timing)); print(bind(classes)); print(bind(km)); print(bind(marks))
for (w in wsgs) print(read.csv(file.path(out, paste0("unmeasured_", w, ".csv"))))
for (w in wsgs) for (nm in names(sets)) {
  x(sprintf("DROP SCHEMA IF EXISTS zz341_%s_%s CASCADE", nm, tolower(w)))
}
