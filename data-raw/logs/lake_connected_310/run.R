# Usage: Rscript run.R <repo> <config> <aoi> <schema> <run_label> <out_dir>
# Re-classifies an existing scratch working schema (classify + connect only,
# segmentation held fixed; the #311 builds zz311_<wsg>), snapshots the
# habitat table to zz310_snap.<aoi>_<run_label>, and records the run (link
# and fresh SHAs, config hash) in <out_dir>/runs.csv. measure.R measures
# the snapshots. Never persists to fresh / fresh_default.
args <- commandArgs(trailingOnly = TRUE)
repo <- args[1]; cfg_arg <- args[2]; aoi <- args[3]
schema <- args[4]; run_label <- args[5]; out_dir <- args[6]
suppressMessages(devtools::load_all(repo, quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config(cfg_arg)
loaded <- suppressWarnings(lnk_load_overrides(cfg))
t0 <- Sys.time()
lnk_pipeline_classify(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
lnk_pipeline_connect(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)

DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS zz310_snap")
snap <- sprintf("zz310_snap.%s_%s", tolower(aoi), run_label)
DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", snap))
DBI::dbExecute(conn, sprintf(
  "CREATE TABLE %s AS SELECT * FROM %s.streams_habitat", snap, schema))

stamp_file <- file.path(out_dir, sprintf("stamp_%s.txt", run_label))
if (!file.exists(stamp_file)) {
  writeLines(utils::capture.output(print(lnk_stamp(cfg, conn = conn, aoi = aoi))),
             stamp_file)
}

seg <- as.numeric(DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*) AS n FROM %s.streams", schema))$n)
fresh_sha <- packageDescription("fresh")$RemoteSha
link_sha <- system2("git", c("-C", repo, "rev-parse", "--short", "HEAD"),
                    stdout = TRUE)
r <- data.frame(run = run_label, aoi = aoi, schema = schema, snapshot = snap,
                n_segments = seg, link_sha = link_sha,
                link_dirty = length(system2("git", c("-C", repo, "status",
                  "--porcelain", "--", "R", "inst"), stdout = TRUE)) > 0,
                fresh = as.character(utils::packageVersion("fresh")),
                fresh_sha = if (is.null(fresh_sha)) NA else substr(fresh_sha, 1, 7),
                cfg_hash = .lnk_config_hash(cfg),
                minutes = round(as.numeric(difftime(Sys.time(), t0,
                                                    units = "mins")), 1))
runs_csv <- file.path(out_dir, "runs.csv")
utils::write.table(r, runs_csv, sep = ",", row.names = FALSE,
                   col.names = !file.exists(runs_csv),
                   append = file.exists(runs_csv))
print(r, row.names = FALSE)
DBI::dbDisconnect(conn)
