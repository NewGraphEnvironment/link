#!/usr/bin/env Rscript
# measure.R — the recompute's access step, timed walk by walk, on one variant
# of link and fresh (link#394, folding in #409).
#
# For each group, runs lnk_access(merge = FALSE, build_views = FALSE) the way
# wsg_recompute_one.R does (same species, presence and views), into a scratch
# table, and records:
#   - the step's wall time and each frs_network_features() walk (table,
#     result mode, direction, seconds, rows, and the other active client
#     backends when it returned): walks.tsv
#   - an md5 of the output over every column, ordered by id_segment, so two
#     variants can be compared for identical output: measure.tsv
# The scratch table is dropped afterwards. lnk_access() also builds and drops
# `<schema>.zz_lnk_streams_<aoi>`, the name a live recompute of the same group
# uses, which is one more reason the script refuses beside another session.
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
  walks <- NULL
  load_start <- load1()

  t0 <- Sys.time()
  testthat::with_mocked_bindings(
    lnk_access(conn, cfg, aoi = wsg,
               table_streams  = paste0(sch, ".streams"),
               table_barriers = paste0(sch, ".barriers"),
               table_to       = to,
               merge = FALSE, presence = pres, species = active,
               build_views = FALSE),
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
  invisible(DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", to)))

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
    load1_start = load_start, load1_end = load1()),
    file.path(out_dir, "measure.tsv"))
  append_tsv(cbind(stamp[rep(1L, nrow(walks)), ], walks),
             file.path(out_dir, "walks.tsv"))
  message(sprintf("[measure] %s %s: %d walks %.1f s, access %.1f s, md5 %s",
                  variant, wsg, nrow(walks), sum(walks$seconds), secs, dig$md5))
}

DBI::dbDisconnect(conn)
