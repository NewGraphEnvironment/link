#!/usr/bin/env Rscript
# measure.R — the lifts a candidate further rule adds, without a build
# (link#236). The candidate: BT also lifts where two or more salmon or
# steelhead records since 1990 sit upstream ("passable by salmon, passable by
# BT", bcfishpass's BT rule at default's salmon count).
#
# On each group's kept working schema from a build (natural_barriers, the
# control and habitat tables), rebuilds observations_province (the run dropped
# it), calls lnk_barrier_overrides() with each species' own rule alone and
# with the candidate added, each to its own table, and counts the lifts the
# candidate adds: every working lift, and those beside a natural barrier the
# group holds (what persists).
#
# Usage: Rscript measure.R <config> <working prefix> <out dir> <WSG,...>
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 4L)
config <- args[[1]]; prefix <- args[[2]]; out <- args[[3]]
wsgs <- strsplit(args[[4]], ",")[[1]]
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
q <- function(sql) DBI::dbGetQuery(conn, sql)
x <- function(sql) invisible(DBI::dbExecute(conn, sql))
cfg <- lnk_config(config)
loaded <- suppressWarnings(lnk_load_overrides(cfg))
own <- .lnk_lift_rules(cfg, loaded)
cand_row <- data.frame(
  species_code = "BT", rule = "salmon", barrier_kinds = "natural",
  observation_species = "CH;CM;CO;PK;SK;ST", observation_threshold = 2,
  observation_date_min = "1990-01-01", observation_buffer_m = 20,
  observation_control_apply = TRUE, date = "2026-11-24", source = "candidate",
  notes = "")
cand <- .lnk_lift_rules(cfg, c(loaded["parameters_fresh"],
                               list(parameters_barrier_lifts = cand_row)))
rows <- list()
for (w in wsgs) {
  s <- paste0(prefix, tolower(w))
  .lnk_pipeline_prep_observations(conn, w, loaded, s, cfg = cfg)
  args_common <- list(conn = conn, barriers = paste0(s, ".natural_barriers"),
    observations = paste0(s, ".observations_province"),
    habitat = if (!is.null(loaded$user_habitat_classification))
      paste0(s, ".user_habitat_classification"),
    control = if (!is.null(loaded$user_barriers_definite_control))
      paste0(s, ".barriers_definite_control"),
    verbose = FALSE)
  t0 <- Sys.time()
  do.call(lnk_barrier_overrides, c(args_common, list(params = own,
          to = paste0(s, ".zz236_own"))))
  do.call(lnk_barrier_overrides, c(args_common, list(params = cand,
          to = paste0(s, ".zz236_cand"))))
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  r <- q(sprintf(
    "WITH added AS (
       SELECT blue_line_key, downstream_route_measure, species_code FROM %1$s.zz236_cand
       EXCEPT
       SELECT blue_line_key, downstream_route_measure, species_code FROM %1$s.zz236_own)
     SELECT species_code, count(*)::int AS lifts_added,
            count(*) FILTER (WHERE EXISTS (
              SELECT 1 FROM %1$s.barriers b
               WHERE b.blue_line_key = a.blue_line_key
                 AND abs(b.downstream_route_measure - a.downstream_route_measure) < 1
                 AND b.barrier_source IN ('GRADIENT', 'FALLS', 'SUBSURFACE_FLOW')))::int
              AS lifts_added_held,
            (SELECT count(*)::int FROM %1$s.zz236_own o
              WHERE o.species_code = a.species_code) AS lifts_own
       FROM added a GROUP BY species_code", s))
  if (nrow(r) == 0L) {
    r <- data.frame(species_code = "BT", lifts_added = 0L, lifts_added_held = 0L,
                    lifts_own = q(sprintf("SELECT count(*)::int AS n FROM %s.zz236_own
                                            WHERE species_code = 'BT'", s))$n)
  }
  r$wsg <- w; r$seconds <- round(secs, 1)
  rows[[length(rows) + 1L]] <- r
  x(sprintf("DROP TABLE IF EXISTS %1$s.zz236_own, %1$s.zz236_cand, %1$s.observations_province", s))
  cat(sprintf("[measure] %s done\n", w))
}
res <- do.call(rbind, rows)
res <- res[, c("wsg", "species_code", "lifts_own", "lifts_added", "lifts_added_held", "seconds")]
dir.create(out, showWarnings = FALSE, recursive = TRUE)
write.csv(res, file.path(out, paste0("candidate_", config, ".csv")), row.names = FALSE)
print(res)
