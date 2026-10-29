#!/usr/bin/env Rscript
# measure.R — the recompute's access step, timed walk by walk, on one variant
# of link and fresh (link#394, folding in #409).
#
# For each group, runs the recompute's access step the way lnk_access(merge =
# FALSE, build_views = FALSE) does (same species, presence, views and scoped
# segments table), into a scratch table, and records:
#   - the step's wall time and each frs_network_features() walk (table,
#     result mode, direction, seconds, rows, and the other active client
#     backends when it returned): walks.tsv
#   - an md5 of the output over every column, ordered by id_segment, so two
#     variants can be compared for identical output: measure.tsv
# It calls lnk_pipeline_access() itself, with its own scoped segments table
# (`zz394_streams_<aoi>`), because lnk_access() builds and drops
# `<schema>.zz_lnk_streams_<aoi>`, the name a live recompute of the same group
# uses: a run beside one would drop the other's table. Its scratch tables are
# dropped on exit. Each row records the write counters of the tables the walks
# read (`inputs`), so rows taken while something wrote them can be told apart.
#
# Variants are code and installed fresh, not flags: load_all() runs from
# LNK_SRC (a worktree of the commit to measure), and the installed fresh is
# whatever the library holds when it runs.
#
# Usage (from the repo root):
#   LNK_SRC=<path to link tree> Rscript data-raw/logs/recompute_access_394/measure.R \
#     <variant> <WSG> [<WSG> ...] [--allow-busy]

args <- commandArgs(trailingOnly = TRUE)
allow_busy <- "--allow-busy" %in% args
args <- setdiff(args, "--allow-busy")
if (length(args) < 2L) {
  stop("usage: measure.R <variant> <WSG> [<WSG> ...] [--allow-busy]", call. = FALSE)
}
variant <- args[1]
wsgs <- toupper(args[-1])
src <- Sys.getenv("LNK_SRC", ".")
out_dir <- "data-raw/logs/recompute_access_394"
stopifnot(dir.exists(out_dir), dir.exists(src))

suppressPackageStartupMessages({
  pkgload::load_all(src, quiet = TRUE)
  library(DBI)
})

link_sha <- system2("git", c("-C", src, "rev-parse", "--short=8", "HEAD"),
                    stdout = TRUE)
link_dirty <- length(system2("git", c("-C", src, "status", "--porcelain",
                                      "--untracked-files=no"),
                             stdout = TRUE)) > 0L
fresh_ver <- as.character(utils::packageVersion("fresh"))
fresh_sha <- substr(utils::packageDescription("fresh")$RemoteSha %||% "", 1, 8)

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
invisible(DBI::dbExecute(conn, "SET statement_timeout = '1800000'"))
invisible(DBI::dbExecute(conn, "SET lock_timeout = '60s'"))

others <- function() DBI::dbGetQuery(conn,
  "SELECT count(*)::int AS n FROM pg_stat_activity
   WHERE datname = current_database() AND state <> 'idle'
     AND pid <> pg_backend_pid() AND backend_type = 'client backend'")$n
load1 <- function() {
  x <- system2("sysctl", c("-n", "vm.loadavg"), stdout = TRUE)
  as.numeric(strsplit(trimws(gsub("[{}]", "", x)), " +")[[1]][1])
}

sch <- "fresh_default"
cfg <- lnk_config("default")
cfg$pipeline$schema <- sch
loaded <- lnk_load_overrides(cfg)

# Write counters of what the walks read: barriers, overrides, streams.
inputs <- function() {
  x <- DBI::dbGetQuery(conn, sprintf(
    "SELECT relname, n_tup_ins + n_tup_upd + n_tup_del AS n
     FROM pg_stat_user_tables WHERE schemaname = %s
       AND relname IN ('barriers', 'barrier_overrides', 'streams')
     ORDER BY relname", DBI::dbQuoteString(conn, sch)))
  paste(sprintf("%s:%s", x$relname, format(x$n, scientific = FALSE)),
        collapse = ",")
}

orig <- fresh::frs_network_features
walks <- NULL

append_tsv <- function(df, path) {
  utils::write.table(df, path, sep = "\t", quote = FALSE, row.names = FALSE,
                     col.names = !file.exists(path), append = file.exists(path))
}

for (wsg in wsgs) {
  n_others <- others()
  if (n_others > 0L && !allow_busy) {
    stop("REFUSE: ", n_others, " other active client backend(s); ",
         "pass --allow-busy to record a busy run", call. = FALSE)
  }
  active <- lnk_pipeline_species(cfg, loaded, wsg)
  pres <- lnk_presence(loaded$wsg_species_presence, wsg)
  to <- paste0(sch, ".zz394_", tolower(wsg), "_out")
  streams_scoped <- paste0(sch, ".zz394_streams_", tolower(wsg))
  drop_scratch <- function() {
    for (t in c(to, streams_scoped)) {
      try(DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", t)),
          silent = TRUE)
    }
  }
  drop_scratch()
  walks <- NULL
  load_start <- load1()
  inputs_start <- inputs()
  sp_set <- tolower(active)

  t0 <- Sys.time()
  tryCatch({
    # lnk_access()'s scoped segments table (R/lnk_access.R), under our own name.
    for (sql in c(
      sprintf("CREATE TABLE %s AS SELECT * FROM %s.streams
               WHERE watershed_group_code = %s",
              streams_scoped, sch, DBI::dbQuoteLiteral(conn, wsg)),
      sprintf("CREATE INDEX ON %s (id_segment)", streams_scoped),
      sprintf("CREATE INDEX ON %s USING GIST (wscode_ltree)", streams_scoped),
      sprintf("CREATE INDEX ON %s USING GIST (localcode_ltree)", streams_scoped),
      sprintf("CREATE INDEX ON %s (blue_line_key)", streams_scoped),
      sprintf("ANALYZE %s", streams_scoped))) {
      DBI::dbExecute(conn, sql)
    }
    testthat::with_mocked_bindings(
      lnk_pipeline_access(conn,
        segments = streams_scoped, aoi = wsg, to = to,
        barriers_per_sp = stats::setNames(
          as.list(paste0(sch, ".barriers_", sp_set, "_access")), sp_set),
        observations = NULL, presence = pres,
        barrier_sources = list(
          anthropogenic = paste0(sch, ".barriers_anthropogenic_unified"),
          pscis         = paste0(sch, ".barriers_pscis_unified"),
          dams          = paste0(sch, ".barriers_dams_unified")),
        crossings_table = NULL),
      frs_network_features = function(conn, segments, features, ...) {
        dots <- list(...)
        s <- Sys.time()
        res <- orig(conn, segments, features, ...)
        walks <<- rbind(walks, data.frame(
          features = features,
          result = if (is.null(dots$result)) "ids" else dots$result,
          direction = dots$direction,
          seconds = round(as.numeric(difftime(Sys.time(), s, units = "secs")), 3),
          rows = nrow(res),
          other_backends = others(),
          segments_md5 = digest::digest(sort(as.character(res[[1]])), algo = "md5")))
        res
      },
      .package = "fresh"
    )
  }, error = function(e) {
    drop_scratch()
    stop(e)
  })
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  cols <- DBI::dbGetQuery(conn, sprintf(
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = %s AND table_name = %s",
    DBI::dbQuoteString(conn, sch),
    DBI::dbQuoteString(conn, sub("^[^.]+\\.", "", to))))$column_name
  cols <- sort(cols)
  dig <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n,
            md5(string_agg(t::text, '|' ORDER BY t.id_segment)) AS md5
     FROM (SELECT %s FROM %s) t",
    paste(cols, collapse = ", "), to))
  inputs_end <- inputs()
  drop_scratch()

  stamp <- data.frame(
    variant = variant, wsg = wsg, date_utc = format(t0, tz = "UTC", usetz = FALSE),
    link_sha = link_sha, link_dirty = link_dirty,
    fresh_version = fresh_ver, fresh_sha = fresh_sha)
  append_tsv(cbind(stamp,
    species = paste(sort(active), collapse = ","),
    n_walks = nrow(walks), walk_seconds = round(sum(walks$seconds), 3),
    access_seconds = round(secs, 3), n_segments = dig$n,
    n_columns = length(cols), output_md5 = dig$md5,
    other_backends = n_others,
    other_backends_max = max(c(n_others, walks$other_backends)),
    load1_start = load_start, load1_end = load1(),
    inputs_start = inputs_start, inputs_end = inputs_end),
    file.path(out_dir, "measure.tsv"))
  append_tsv(cbind(stamp[rep(1L, nrow(walks)), ], walks),
             file.path(out_dir, "walks.tsv"))
  message(sprintf("[measure] %s %s: %d walks %.1f s, access %.1f s, md5 %s",
                  variant, wsg, nrow(walks), sum(walks$seconds), secs, dig$md5))
}

DBI::dbDisconnect(conn)
