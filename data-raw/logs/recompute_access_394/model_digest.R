#!/usr/bin/env Rscript
# model_digest.R — model groups into a scratch persist schema and digest every
# persisted table, so two variants of link and fresh can be shown to write the
# same rows (link#394, folding in #409's "outputs should not move").
#
# Each variant gets its own persist schema and working schemas
# (`zz394w_<wsg>_<variant>`), so nothing a live run reads or writes is touched,
# and a second variant cannot see the first's barriers. Groups are modelled in
# the order given, with log = FALSE, LNK_GUARD_DOWNSTREAM=warn (the scratch
# schema holds no downstream group), mapping_code = TRUE and the habitat gate on,
# the way a single-group wsg_run_one.R run does. Each table is digested as the
# md5 of its rows' text in text order; the counts of the paths the access step
# feeds (codes 0/1/2, dam_dnstr_ind) say whether a group exercised them.
#
# Usage (from the repo root):
#   LNK_SRC=<path to link tree> Rscript data-raw/logs/recompute_access_394/model_digest.R \
#     <variant> <WSG> [<WSG> ...]
# Output: model_digest.tsv (appended)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) {
  stop("usage: model_digest.R <variant> <WSG> [<WSG> ...]", call. = FALSE)
}
variant <- args[1]
stopifnot(grepl("^[a-z0-9]+$", variant))
wsgs <- toupper(args[-1])
src <- Sys.getenv("LNK_SRC", ".")
out_dir <- "data-raw/logs/recompute_access_394"
stopifnot(dir.exists(out_dir), dir.exists(src))
Sys.setenv(LNK_GUARD_DOWNSTREAM = "warn")

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

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
invisible(DBI::dbExecute(conn, "SET statement_timeout = '1800000'"))

persist <- paste0("zz394_", variant)
cfg <- lnk_config("default")
cfg$pipeline$schema <- persist
loaded <- lnk_load_overrides(cfg)

for (wsg in wsgs) {
  t0 <- Sys.time()
  lnk_pipeline_run(conn, aoi = wsg, cfg = cfg, loaded = loaded,
                   schema = paste0("zz394w_", tolower(wsg), "_", variant),
                   mapping_code = TRUE, log = FALSE)
  message(sprintf("[model_digest] %s %s modelled in %.1f min", variant, wsg,
                  as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}

tables <- DBI::dbGetQuery(conn, sprintf(
  "SELECT table_name FROM information_schema.tables
   WHERE table_schema = %s AND table_type = 'BASE TABLE'
     AND table_name NOT LIKE 'log%%'
   ORDER BY table_name", DBI::dbQuoteString(conn, persist)))$table_name

rows <- lapply(tables, function(tb) {
  d <- DBI::dbGetQuery(conn, sprintf(
    "SELECT watershed_group_code AS wsg, count(*)::int AS n,
            md5(string_agg(t::text, '|' ORDER BY t::text COLLATE \"C\")) AS md5
     FROM %s.%s t GROUP BY watershed_group_code ORDER BY 1", persist, tb))
  if (nrow(d) == 0L) return(NULL)
  cbind(table = tb, d)
})
dig <- do.call(rbind, rows)

paths <- DBI::dbGetQuery(conn, sprintf(
  "SELECT watershed_group_code AS wsg,
          count(*) FILTER (WHERE dam_dnstr_ind) AS dam_dnstr_true,
          count(*) FILTER (WHERE has_barriers_dams_dnstr) AS dams_dnstr_true,
          count(*) FILTER (WHERE remediated_dnstr_ind) AS remediated_true,
          count(*) FILTER (WHERE has_barriers_remediations_dnstr) AS remediations_dnstr_true
   FROM %s.streams_access GROUP BY 1 ORDER BY 1", persist))
access_cols <- grep("^access_", DBI::dbListFields(
  conn, DBI::Id(schema = persist, table = "streams_access")), value = TRUE)
codes <- DBI::dbGetQuery(conn, sprintf(
  "SELECT watershed_group_code AS wsg, v AS code, count(*)::int AS n
   FROM %s.streams_access, LATERAL unnest(ARRAY[%s]) v
   GROUP BY 1, 2 ORDER BY 1, 2", persist, paste(access_cols, collapse = ", ")))
message("[model_digest] paths:")
print(paths)
print(codes)

stamp <- data.frame(variant = variant, persist = persist,
                    date_utc = format(Sys.time(), tz = "UTC"),
                    link_sha = link_sha, link_dirty = link_dirty,
                    fresh_version = fresh_ver)
out <- cbind(stamp[rep(1L, nrow(dig)), ], dig)
path <- file.path(out_dir, "model_digest.tsv")
utils::write.table(out, path, sep = "\t", quote = FALSE, row.names = FALSE,
                   col.names = !file.exists(path), append = file.exists(path))
utils::write.table(cbind(stamp[rep(1L, nrow(codes)), ], codes),
                   file.path(out_dir, "model_codes.tsv"), sep = "\t",
                   quote = FALSE, row.names = FALSE,
                   col.names = !file.exists(file.path(out_dir, "model_codes.tsv")),
                   append = file.exists(file.path(out_dir, "model_codes.tsv")))
DBI::dbDisconnect(conn)
