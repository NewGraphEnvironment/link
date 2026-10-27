#!/usr/bin/env Rscript
# walk_prefilter.R — does the walk's cost come from probing the group's segments
# once per province-wide feature? Read-only (link#261).
#
# For each group and walked view, runs fresh::frs_network_features()'s SQL as
# sent (captured as in walks.R) and the same SQL with the feature side
# prefiltered to features that can be downstream of a group segment: those on
# one of the group's blue lines, or whose wscode is an ancestor of, or equal
# to, a group segment's wscode. whse_basemapping.fwa_downstream() admits no
# other feature (criterion 1 needs the same blue line, criterion 2
# `wscode_a <@ wscode_b`), so the two must return the same arrays. Both are
# digested (in their own order, and with each array sorted) and timed.
#
# One view per barrier-set shape the group walks (CH-like, BT-like, ST-like:
# identical before overrides) plus the anthropogenic source.
#
# Usage (from the repo root):
#   LNK_MEASURE_HOST=<host> Rscript data-raw/logs/recompute_cost_261/walk_prefilter.R CHWK SALR ...
# Output: walk_prefilter.tsv (appended) and plans/prefilter_<WSG>_<table>.json

suppressPackageStartupMessages({
  pkgload::load_all(quiet = TRUE)
  library(DBI)
})

wsgs <- toupper(commandArgs(trailingOnly = TRUE))
if (length(wsgs) == 0L) stop("usage: walk_prefilter.R <WSG> [<WSG> ...]", call. = FALSE)
out_dir <- "data-raw/logs/recompute_cost_261"
stopifnot(dir.exists(out_dir))
sch <- "fresh_default"
conn <- lnk_db_conn(dbname = "fwapg", host = Sys.getenv("LNK_MEASURE_HOST", "localhost"),
                    port = 5432L, user = "postgres", password = "postgres")
invisible(DBI::dbExecute(conn, "SET statement_timeout = '1800000'"))

others <- function() DBI::dbGetQuery(conn,
  "SELECT count(*)::int AS n FROM pg_stat_activity
   WHERE datname = current_database() AND state <> 'idle'
     AND pid <> pg_backend_pid() AND backend_type = 'client backend'")$n
# One other backend is tolerated: the two forms run side by side under the same
# load, and walks.R's LSKE CH-shaped walks took 67.6-69.2 s alone and 68.0-70.1 s
# beside one.
if (others() > 1L) stop("REFUSE: more than one other active client backend", call. = FALSE)

cfg <- lnk_config("default")
cfg$pipeline$schema <- sch
loaded <- lnk_load_overrides(cfg)
shapes <- list(c("ch", "cm", "co", "gr", "ko", "pk", "sk"),
               c("bt", "dv", "rb"), c("st", "wct"))

walk_sql <- function(segments, features, aoi) {
  sql <- NULL
  testthat::with_mocked_bindings(
    fresh::frs_network_features(conn, segments = segments, features = features,
      segment_id_col = "id_segment",
      feature_id_col = paste0(sub("^[^.]+\\.", "", features), "_id"),
      direction = "downstream", aoi = aoi, include_equivalents = TRUE),
    frs_db_query = function(conn, query) {
      sql <<- query
      data.frame(id_segment = integer(), feature_ids = character())
    },
    .package = "fresh")
  sql
}

digest_sql <- function(sql) paste0(
  "SELECT count(*)::int AS n,
     md5(string_agg(id_segment::text || ':' || coalesce(feature_ids::text, ''),
                    ',' ORDER BY id_segment)) AS d_order,
     md5(string_agg(id_segment::text || ':' || coalesce((SELECT array_agg(e ORDER BY e)::text
                    FROM unnest(feature_ids) e), ''), ',' ORDER BY id_segment)) AS d_set
   FROM (", sql, ") x")

tsv <- file.path(out_dir, "walk_prefilter.tsv")
if (!file.exists(tsv)) {
  cat(paste(c("wsg", "table", "form", "segments_out", "seconds", "d_order", "d_set",
              "others_active", "measured_utc"), collapse = "\t"), "\n",
      sep = "", file = tsv)
}

for (aoi in wsgs) {
  active <- lnk_pipeline_species(cfg, loaded, aoi)
  pres <- lnk_presence(loaded$wsg_species_presence, aoi)
  sp <- tolower(active[pres$is_present(tolower(active))])
  pick <- unlist(lapply(shapes, function(s) head(intersect(s, sp), 1)))
  tables <- paste0(sch, ".", c(paste0("barriers_", pick, "_access"),
                               "barriers_anthropogenic_unified"))

  invisible(DBI::dbExecute(conn, "RESET default_transaction_read_only"))
  for (t in c("zz_walk_streams", "zz_walk_anc", "zz_walk_blk")) {
    invisible(DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS pg_temp.%s", t)))
  }
  invisible(DBI::dbExecute(conn, sprintf(
    "CREATE TEMP TABLE zz_walk_streams AS SELECT * FROM %s.streams
     WHERE watershed_group_code = %s", sch, DBI::dbQuoteLiteral(conn, aoi))))
  for (ix in c("(id_segment)", "USING GIST (wscode_ltree)",
               "USING GIST (localcode_ltree)", "(blue_line_key)")) {
    invisible(DBI::dbExecute(conn, sprintf("CREATE INDEX ON pg_temp.zz_walk_streams %s", ix)))
  }
  invisible(DBI::dbExecute(conn,
    "CREATE TEMP TABLE zz_walk_anc AS
     SELECT DISTINCT subpath(wscode_ltree, 0, k) AS w
     FROM pg_temp.zz_walk_streams, generate_series(1, nlevel(wscode_ltree)) k"))
  invisible(DBI::dbExecute(conn,
    "CREATE TEMP TABLE zz_walk_blk AS
     SELECT DISTINCT blue_line_key FROM pg_temp.zz_walk_streams"))
  for (t in c("zz_walk_streams", "zz_walk_anc", "zz_walk_blk")) {
    invisible(DBI::dbExecute(conn, sprintf("ANALYZE pg_temp.%s", t)))
  }
  invisible(DBI::dbExecute(conn, "SET default_transaction_read_only = on"))

  for (tb in tables) {
    sent <- walk_sql("pg_temp.zz_walk_streams", tb, aoi)
    join <- sprintf("INNER JOIN %s b ON", tb)
    stopifnot(lengths(regmatches(sent, gregexpr(join, sent, fixed = TRUE))) == 1L)
    pre <- sub(join, sprintf(
      "INNER JOIN (SELECT * FROM %s f
                   WHERE f.wscode_ltree = ANY (ARRAY(SELECT w FROM pg_temp.zz_walk_anc))
                      OR f.blue_line_key = ANY (ARRAY(SELECT blue_line_key
                                                      FROM pg_temp.zz_walk_blk))) b ON",
      tb), sent, fixed = TRUE)
    for (form in c("prefilter", "sent")) {
      sql <- if (form == "sent") sent else pre
      t0 <- Sys.time()
      d <- DBI::dbGetQuery(conn, digest_sql(sql))
      secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
      row <- c(aoi, sub("^[^.]+\\.", "", tb), form, d$n, round(secs, 3), d$d_order,
               d$d_set, others(), format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
      cat(paste(row, collapse = "\t"), "\n", sep = "", file = tsv, append = TRUE)
      cat(sprintf("[prefilter] %s %-32s %-9s %8.1f s  %s\n", aoi,
                  sub("^[^.]+\\.", "", tb), form, secs, d$d_set))
    }
    js <- DBI::dbGetQuery(conn, paste("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)", pre))[[1]]
    writeLines(js, file.path(out_dir, "plans",
      sprintf("prefilter_%s_%s.json", aoi, sub("^[^.]+\\.", "", tb))))
  }
}
