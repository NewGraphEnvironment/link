#!/usr/bin/env Rscript
# prove.R — a further lift rule runs where no shipped bundle declares one
# (link#236). Copies `default` to a scratch bundle, declares
# parameters_barrier_lifts.csv with the candidate BT rule (two salmon or
# steelhead records since 1990), loads it by path, and runs one group through
# load, prepare, crossings, unify and persist into a scratch persist schema.
# Those phases resolve no vocabulary (only lnk_pipeline_run() does), so the
# bundle needs no token. Prints the evidence rows by rule, working and
# persisted.
#
# Usage: Rscript prove.R <WSG> <out dir>
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
w <- args[[1]]; out <- args[[2]]
dir.create(out, recursive = TRUE, showWarnings = FALSE)
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
x <- function(sql) invisible(DBI::dbExecute(conn, sql))
q <- function(sql) DBI::dbGetQuery(conn, sql)

bdir <- file.path(tempdir(), "default_236")
dir.create(bdir)
file.copy(list.files(system.file("extdata", "configs", "default", package = "link"),
                     full.names = TRUE), bdir, recursive = TRUE)
lifts <- data.frame(
  species_code = "BT", rule = "salmon", barrier_kinds = "natural",
  observation_species = "CH;CM;CO;PK;SK;ST", observation_threshold = 2,
  observation_date_min = "1990-01-01", observation_buffer_m = 20,
  observation_control_apply = TRUE, date = "2026-11-24",
  source = "link#236 candidate: passable by salmon, passable by BT",
  notes = "bcfishpass's BT access rule at default's salmon count")
write.csv(lifts, file.path(bdir, "parameters_barrier_lifts.csv"), row.names = FALSE)
y <- readLines(file.path(bdir, "config.yaml"))
i <- grep("^  parameters_fresh:$", y)
y <- append(y, c("  parameters_barrier_lifts:",
                 "    path: parameters_barrier_lifts.csv"), after = i + 1L)
writeLines(y, file.path(bdir, "config.yaml"))

cfg <- lnk_config(bdir)
loaded <- suppressWarnings(lnk_load_overrides(cfg))
stopifnot(!is.null(loaded$parameters_barrier_lifts))
print(.lnk_lift_rules(cfg, loaded)[, c("species_code", "rule",
                                       "observation_species",
                                       "observation_threshold")])

ws <- paste0("w236_", tolower(w)); ps <- "zz236_proof"
cfg$pipeline$schema <- ps
x(sprintf("DROP SCHEMA IF EXISTS %s CASCADE", ps))
lnk_pipeline_setup(conn, ws, overwrite = TRUE)
lnk_pipeline_load(conn, aoi = w, cfg = cfg, loaded = loaded, schema = ws)
lnk_pipeline_prepare(conn, aoi = w, cfg = cfg, loaded = loaded, schema = ws,
                     conn_tunnel = conn)
lnk_pipeline_crossings(conn, aoi = w, cfg = cfg, loaded = loaded, schema = ws)
lnk_barriers_unify(conn, aoi = w, cfg = cfg, loaded = loaded, schema = ws)
lnk_persist_init(conn, cfg, species = cfg$species)
lnk_pipeline_persist(conn, aoi = w, cfg = cfg, species = character(0), schema = ws)

by_rule <- function(t) q(sprintf(
  "SELECT species_code, lift_rule, evidence,
          count(DISTINCT (blue_line_key, downstream_route_measure))::int AS lifts,
          count(*)::int AS rows
     FROM %s GROUP BY 1, 2, 3 ORDER BY 1, 2, 3", t))
wk <- by_rule(paste0(ws, ".barrier_override_evidence"))
pe <- by_rule(paste0(ps, ".barrier_override_evidence"))
# BT positions lifted only by the further rule
only <- q(sprintf(
  "SELECT count(*)::int AS n FROM (
     SELECT blue_line_key, downstream_route_measure FROM %1$s
      WHERE species_code = 'BT' AND lift_rule = 'salmon'
     EXCEPT
     SELECT blue_line_key, downstream_route_measure FROM %1$s
      WHERE species_code = 'BT' AND lift_rule IN ('own', 'habitat')) t",
  paste0(ws, ".barrier_override_evidence")))
cat("\n== working evidence by rule\n"); print(wk)
cat("\n== persisted evidence by rule\n"); print(pe)
cat("\nBT positions lifted by the salmon rule alone:", only$n, "\n")
write.csv(wk, file.path(out, paste0("prove_", w, "_working.csv")), row.names = FALSE)
write.csv(pe, file.path(out, paste0("prove_", w, "_persisted.csv")), row.names = FALSE)
x(sprintf("DROP SCHEMA IF EXISTS %s CASCADE", ps))
x(sprintf("DROP SCHEMA IF EXISTS %s CASCADE", ws))
