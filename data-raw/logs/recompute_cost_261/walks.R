#!/usr/bin/env Rscript
# walks.R — time each downstream walk the post-consolidate recompute runs for a
# group, read-only (link#261).
#
# For each group, mirrors lnk_access(merge = TRUE): the group's segments copied
# into a session TEMP table with the same indexes and ANALYZE, then one
# fresh::frs_network_features(direction = "downstream") call per present species
# (`<schema>.barriers_<sp>_access`) and per source (anthropogenic, pscis, dams).
# The SQL is fresh's own, captured by mocking fresh's frs_db_query(), then run
# under EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON). Nothing in the schema is written:
# the script compares the schema's tuple write counters before and after.
#
# Usage (from the repo root; LNK_MEASURE_HOST names the database host):
#   LNK_MEASURE_HOST=<host> Rscript data-raw/logs/recompute_cost_261/walks.R CHWK SALR ...
# Output: walks.tsv (appended, one row per group x table) and plans/<WSG>_<table>.json

suppressPackageStartupMessages({
  pkgload::load_all(quiet = TRUE)
  library(DBI)
})

wsgs <- toupper(commandArgs(trailingOnly = TRUE))
if (length(wsgs) == 0L) stop("usage: walks.R <WSG> [<WSG> ...]", call. = FALSE)
out_dir <- "data-raw/logs/recompute_cost_261"
stopifnot(dir.exists(out_dir))
sch <- "fresh_default"
host <- Sys.getenv("LNK_MEASURE_HOST", "localhost")

conn <- lnk_db_conn(dbname = "fwapg", host = host, port = 5432L,
                    user = "postgres", password = "postgres")
invisible(DBI::dbExecute(conn, "SET statement_timeout = '1800000'"))  # 30 min / statement

writes <- function() {
  DBI::dbGetQuery(conn, sprintf(
    "SELECT sum(n_tup_ins + n_tup_upd + n_tup_del)::float8 AS n
     FROM pg_stat_user_tables WHERE schemaname = '%s'", sch))$n
}

others <- function() DBI::dbGetQuery(conn,
  "SELECT count(*)::int AS n FROM pg_stat_activity
   WHERE datname = current_database() AND state <> 'idle'
     AND pid <> pg_backend_pid() AND backend_type = 'client backend'")$n
busy <- others()
if (busy > 0L) {
  stop("REFUSE: ", busy, " other active client backend(s) on the database; ",
       "measure on a quiet database", call. = FALSE)
}

cfg <- lnk_config("default")
cfg$pipeline$schema <- sch
loaded <- lnk_load_overrides(cfg)

# The SQL frs_network_features() would send, without sending it.
walk_sql <- function(segments, features) {
  sql <- NULL
  id_col <- paste0(sub("^[^.]+\\.", "", features), "_id")
  testthat::with_mocked_bindings(
    fresh::frs_network_features(conn, segments = segments, features = features,
      segment_id_col = "id_segment", feature_id_col = id_col,
      direction = "downstream", aoi = aoi_now, include_equivalents = TRUE),
    frs_db_query = function(conn, query) {
      sql <<- query
      data.frame(id_segment = integer(), feature_ids = character())
    },
    .package = "fresh")
  sql
}

# Largest actual row count of any join node (rows x loops): the
# (segment, feature) pairs the walk produces before array_agg.
join_rows <- function(node) {
  here <- if (grepl("Join|Nested Loop", node[["Node Type"]])) {
    node[["Actual Rows"]] * node[["Actual Loops"]]
  } else 0
  kids <- vapply(node[["Plans"]] %||% list(), join_rows, numeric(1))
  max(c(here, kids))
}
`%||%` <- function(a, b) if (is.null(a)) b else a

w0 <- writes()
tsv <- file.path(out_dir, "walks.tsv")
cols <- c("wsg", "table", "segments", "features_in_wsg", "pairs",
          "segments_out", "exec_s", "plan_s", "shared_hit", "shared_read",
          "temp_read", "others_active", "measured_utc")
if (!file.exists(tsv)) cat(paste(cols, collapse = "\t"), "\n", sep = "", file = tsv)

for (aoi_now in wsgs) {
  active <- lnk_pipeline_species(cfg, loaded, aoi_now)
  pres <- lnk_presence(loaded$wsg_species_presence, aoi_now)
  walked_sp <- tolower(active[pres$is_present(tolower(active))])
  tables <- c(paste0(sch, ".barriers_", walked_sp, "_access"),
              paste0(sch, ".barriers_", c("anthropogenic", "pscis", "dams"),
                     "_unified"))

  seg <- "pg_temp.zz_walk_streams"
  # Writes are refused between TEMP builds (added after the 2026-10-27 run,
  # whose guard was the tuple write counters printed at the end).
  DBI::dbExecute(conn, "RESET default_transaction_read_only")
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", seg))
  DBI::dbExecute(conn, sprintf(
    "CREATE TEMP TABLE zz_walk_streams AS SELECT * FROM %s.streams
     WHERE watershed_group_code = %s", sch, DBI::dbQuoteLiteral(conn, aoi_now)))
  for (ix in c("(id_segment)", "USING GIST (wscode_ltree)",
               "USING GIST (localcode_ltree)", "(blue_line_key)")) {
    DBI::dbExecute(conn, sprintf("CREATE INDEX ON %s %s", seg, ix))
  }
  DBI::dbExecute(conn, sprintf("ANALYZE %s", seg))
  DBI::dbExecute(conn, "SET default_transaction_read_only = on")
  n_seg <- DBI::dbGetQuery(conn, sprintf("SELECT count(*)::int n FROM %s", seg))$n

  for (tb in tables) {
    n_in <- DBI::dbGetQuery(conn, sprintf(
      "SELECT count(*)::int n FROM %s WHERE watershed_group_code = %s",
      tb, DBI::dbQuoteLiteral(conn, aoi_now)))$n
    sql <- walk_sql(seg, tb)
    js <- DBI::dbGetQuery(conn, paste(
      "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)", sql))[[1]]
    writeLines(js, file.path(out_dir, "plans",
      sprintf("%s_%s.json", aoi_now, sub("^[^.]+\\.", "", tb))))
    p <- jsonlite::fromJSON(js, simplifyVector = FALSE)[[1]]
    top <- p[["Plan"]]
    row <- c(aoi_now, sub("^[^.]+\\.", "", tb), n_seg, n_in,
             format(join_rows(top), scientific = FALSE),
             top[["Actual Rows"]],
             round(p[["Execution Time"]] / 1000, 3),
             round(p[["Planning Time"]] / 1000, 3),
             top[["Shared Hit Blocks"]], top[["Shared Read Blocks"]],
             top[["Temp Read Blocks"]] %||% 0, others(),
             format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
    cat(paste(row, collapse = "\t"), "\n", sep = "", file = tsv, append = TRUE)
    cat(sprintf("[walks] %s %-32s %8.1f s  pairs %s\n", aoi_now,
                sub("^[^.]+\\.", "", tb), p[["Execution Time"]] / 1000,
                format(join_rows(top), big.mark = ",")))
  }
}

w1 <- writes()
cat(sprintf("[walks] %s tuple writes before %.0f after %.0f: %s\n", sch, w0, w1,
            if (identical(w0, w1)) "UNCHANGED" else "CHANGED"))
DBI::dbDisconnect(conn)
