#!/usr/bin/env Rscript
# Phase 3 verification for link#364, on one watershed group (default ADMS).
#
# 1. A test bundle (default, with CH rear_wetland_flow = stream and a CH
#    rear near-river pair: measure model, channel width 15 m / discharge
#    3 m3/s, 1000 m) runs end to end into a scratch persist schema with
#    mapping_code. Checks: <schema>.streams_near_river holds the group's
#    rows, <schema>.log.near_river names the pair, and lnk_habitat_validate()
#    scores CH with 0 post_predicate misses (persisted flags the bundle's own
#    predicates do not reproduce).
# 2. On the same working schema, `default` (no pair) classified on filled and
#    on unfilled discharge gives identical habitat: on a cw group with no
#    discharge-measured pair the fill moves nothing.
#
# Usage (repo root): Rscript data-raw/logs/wetland_door_364/verify_phase3.R [WSG]
# Writes data-raw/logs/wetland_door_364/verify_phase3_<wsg>.txt and drops the
# scratch schemas.

pkgload::load_all(quiet = TRUE)
suppressPackageStartupMessages(library(DBI))

args <- commandArgs(trailingOnly = TRUE)
wsg <- toupper(if (length(args) >= 1) args[1] else "ADMS")
stopifnot(grepl("^[A-Z]{4}$", wsg))
out_dir <- file.path("data-raw", "logs", "wetland_door_364")
out <- file.path(out_dir, sprintf("verify_phase3_%s.txt", tolower(wsg)))
persist <- "zz364_verify"
work <- paste0("working_zz364_", tolower(wsg))
lines <- character(0)
say <- function(...) {
  x <- sprintf(...)
  lines <<- c(lines, x)
  cat(x, "\n")
}

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
for (s in c(persist, work)) {
  dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
}

# -- the test bundle ----------------------------------------------------------
tmp <- tempfile("v364_")
dir.create(tmp)
cfg0 <- lnk_config("default")
cfg0$pipeline$schema <- persist
dims <- utils::read.csv(cfg0$dimensions, stringsAsFactors = FALSE,
                        check.names = FALSE)
dims$rear_wetland_flow[dims$species == "CH"] <- "stream"
dims_f <- file.path(tmp, "dimensions.csv")
utils::write.csv(dims, dims_f, row.names = FALSE)
th <- utils::read.csv(cfg0$files$parameters_habitat_thresholds$path,
                      stringsAsFactors = FALSE, check.names = FALSE)
ch <- th$species_code == "CH"
th$rear_river_measure[ch] <- "model"
th$rear_river_channel_width_min[ch] <- 15
th$rear_river_discharge_min[ch] <- 3
th$rear_river_distance_max[ch] <- 1000
th_f <- file.path(tmp, "parameters_habitat_thresholds.csv")
utils::write.csv(th, th_f, row.names = FALSE)
rules_f <- file.path(tmp, "rules.yaml")
suppressMessages(lnk_rules_build(dims_f, rules_f, thresholds = th_f,
                                 edge_types = "explicit"))
cfg1 <- cfg0
cfg1$dimensions <- dims_f
cfg1$rules <- rules_f
cfg1$files$parameters_habitat_thresholds$path <- th_f

say("link %s, fresh %s, group %s, persist %s", utils::packageVersion("link"),
    utils::packageVersion("fresh"), wsg, persist)
say("test bundle near_river: %s", .lnk_near_river_logged(cfg1, wsg))

# -- 1. end to end ------------------------------------------------------------
loaded1 <- lnk_load_overrides(cfg1)
t0 <- Sys.time()
lnk_pipeline_run(conn, aoi = wsg, cfg = cfg1, loaded = loaded1,
                 schema = work, mapping_code = TRUE, cleanup_working = FALSE)
say("pipeline: %.1f min", as.numeric(difftime(Sys.time(), t0, units = "mins")))
nr <- dbGetQuery(conn, sprintf(
  "SELECT measure, threshold, distance_max, count(*)::int AS n
     FROM %s.streams_near_river WHERE watershed_group_code = '%s'
    GROUP BY 1, 2, 3 ORDER BY 1", persist, wsg))
say("persisted streams_near_river: %s", paste(capture.output(print(nr)),
                                              collapse = " | "))
logged <- dbGetQuery(conn, sprintf(
  "SELECT near_river FROM %s.log WHERE watershed_group_code = '%s'
    ORDER BY date_start DESC LIMIT 1", persist, wsg))$near_river
say("log.near_river: %s", logged)
km <- dbGetQuery(conn, sprintf(
  "SELECT s.edge_type IN (1050, 1150) AS wetland_flow,
          round((sum(s.length_metre) FILTER (WHERE h.rearing) / 1000)::numeric, 1) AS rear_km,
          round((sum(s.length_metre) FILTER (WHERE h.rearing AND n.id_segment
                IS NOT NULL AND NOT coalesce(s.channel_width >= 1.5, false))
                / 1000)::numeric, 1) AS rear_km_by_river_only
     FROM %1$s.streams s
     JOIN %1$s.streams_habitat_ch h USING (id_segment, watershed_group_code)
     LEFT JOIN %1$s.streams_near_river n USING (id_segment, watershed_group_code)
    WHERE s.watershed_group_code = '%2$s'
    GROUP BY 1 ORDER BY 1", persist, wsg))
say("CH rearing km: %s", paste(capture.output(print(km)), collapse = " | "))

v <- lnk_habitat_validate(conn, aoi = wsg, cfg = cfg1, loaded = loaded1,
                          species = "CH", schema = persist)
o <- v$observations
pp <- sum(o$miss_reason_spawn %in% "post_predicate") +
  sum(o$miss_reason_rear %in% "post_predicate")
say("validate CH: %d locations, %d post_predicate misses", nrow(o), pp)

# -- 2. the fill moves nothing without a discharge pair -----------------------
loaded0 <- lnk_load_overrides(cfg0)
digest_habitat <- function() {
  x <- dbGetQuery(conn, sprintf(
    "SELECT id_segment, species_code, accessible, spawning, rearing,
            lake_rearing, wetland_rearing
       FROM %s.streams_habitat ORDER BY species_code, id_segment", work))
  digest::digest(x)
}
.lnk_discharge_join(conn, paste0(work, ".streams"), wsg, fill = TRUE)
lnk_pipeline_classify(conn, aoi = wsg, cfg = cfg0, loaded = loaded0,
                      schema = work)
d_fill <- digest_habitat()
.lnk_discharge_join(conn, paste0(work, ".streams"), wsg, fill = FALSE)
lnk_pipeline_classify(conn, aoi = wsg, cfg = cfg0, loaded = loaded0,
                      schema = work)
d_raw <- digest_habitat()
say("default classify, filled vs unfilled discharge: %s (%s / %s)",
    if (identical(d_fill, d_raw)) "identical" else "DIFFER", d_fill, d_raw)
no_nr <- !DBI::dbExistsTable(conn, DBI::Id(schema = work,
                                           table = "streams_habitat_near_river"))
say("default classify left no working near-river table: %s", no_nr)

writeLines(lines, out)
for (s in c(persist, work)) {
  dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
}
dbDisconnect(conn)
stopifnot(nrow(nr) == 1L, nr$n > 0, identical(logged, "channel_width:15:1000"),
          pp == 0L, identical(d_fill, d_raw), no_nr)
