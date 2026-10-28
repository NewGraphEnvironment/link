#!/usr/bin/env Rscript
# predictors.R — candidate predictors of a group's recompute minutes, per group,
# read-only (link#261).
#
# Per group in <schema>.streams:
#   segments, walks (present species walked, plus three sources);
#   features of the walked tables inside the group;
#   features of the walked tables downstream of the group's outlet
#     (fresh::frs_wsg_outlets() with fwa_downstream(..., true, 1), the form
#     fresh::frs_network_features() walks with: #261's own predictor);
#   outer_rows: features each walk drives from (the walked view, province-wide),
#     summed over the group's walks;
#   in_range: of those, the features whose code can have descendants inside the
#     group's code range [lo, hi] (code in [lo, hi], or an ancestor of lo),
#     summed over the group's walks. The walk probes the group's wscode GiST
#     once per feature. Refuted as the explanation (SETN); kept as a column so
#     the correlation table shows it;
#   probe_us: microseconds per feature for a walk of a fixed 200,000-feature
#     sample of the CH view (deterministic, md5-ordered), run through
#     fresh::frs_network_features()'s own SQL against the group's TEMP segments
#     built as lnk_access() builds them. The sample has no index, so the plan can
#     only drive from it, as the real walk drives from the province-wide view
#     (its plan is not recorded).
#     walks.R found this per-feature probe is what differs between groups.
#   probe_pre_us: the same sample walk with the feature side prefiltered to
#     features on the group's blue lines or on an ancestor-or-equal of a group
#     code (walk_prefilter.R: same features per segment, in every group tried).
#
# The natural views' province-wide and in-range counts are taken from
# <schema>.barriers by blocks_species, without the override anti-join (it
# removes about 1,800 of 7.24 M rows for CH).
#
# Usage (from the repo root):
#   LNK_MEASURE_HOST=<host> Rscript data-raw/logs/recompute_cost_261/predictors.R [WSG ...]
# Output: predictors.tsv (every group), or predictors_subset.tsv when groups are named

suppressPackageStartupMessages({
  pkgload::load_all(quiet = TRUE)
  library(DBI)
})
out_dir <- "data-raw/logs/recompute_cost_261"
sch <- "fresh_default"
conn <- lnk_db_conn(dbname = "fwapg", host = Sys.getenv("LNK_MEASURE_HOST", "localhost"),
                    port = 5432L, user = "postgres", password = "postgres")
invisible(DBI::dbExecute(conn, "SET statement_timeout = '1800000'"))
others <- function() DBI::dbGetQuery(conn,
  "SELECT count(*)::int AS n FROM pg_stat_activity
   WHERE datname = current_database() AND state <> 'idle'
     AND pid <> pg_backend_pid() AND backend_type = 'client backend'")$n
# One other backend is tolerated (walk_prefilter.R gives the measurement).
if (others() > 1L) stop("REFUSE: more than one other active client backend", call. = FALSE)
q <- function(x) DBI::dbQuoteLiteral(conn, x)
n1 <- function(sql) DBI::dbGetQuery(conn, sql)[[1]]

cfg <- lnk_config("default")
cfg$pipeline$schema <- sch
loaded <- lnk_load_overrides(cfg)
outlets <- fresh::frs_wsg_outlets()
natural <- "('GRADIENT','FALLS','SUBSURFACE_FLOW','USER_DEFINITE')"
sources <- c("anthropogenic", "pscis", "dams")

# Natural features per species, keyed by code, with a running total so a
# code range is two index lookups.
invisible(DBI::dbExecute(conn, sprintf(
  "CREATE TEMP TABLE zz261_bc AS
   SELECT sp, w, n, sum(n) OVER (PARTITION BY sp ORDER BY w) AS cum
   FROM (SELECT lower(sp) AS sp, wscode_ltree AS w, count(*)::bigint AS n
         FROM %s.barriers b, unnest(b.blocks_species) sp
         WHERE barrier_source IN %s GROUP BY 1, 2) x", sch, natural)))
invisible(DBI::dbExecute(conn, "CREATE INDEX ON zz261_bc (sp, w)"))
invisible(DBI::dbExecute(conn, "ANALYZE zz261_bc"))
province_nat <- DBI::dbGetQuery(conn,
  "SELECT sp, sum(n)::float8 AS n FROM zz261_bc GROUP BY 1")
invisible(DBI::dbExecute(conn, sprintf(
  "CREATE TEMP TABLE zz261_probe AS
   SELECT row_number() OVER ()::int AS probe_id, blue_line_key,
          downstream_route_measure, wscode_ltree, localcode_ltree
   FROM (SELECT * FROM %s.barriers_ch_access
         ORDER BY md5(barriers_ch_access_id::text) LIMIT 200000) x", sch)))
invisible(DBI::dbExecute(conn, "ANALYZE zz261_probe"))
n_probe <- n1("SELECT count(*)::float8 FROM zz261_probe")

walk_sql <- function(segments, features, id_col, aoi) {
  sql <- NULL
  testthat::with_mocked_bindings(
    fresh::frs_network_features(conn, segments = segments, features = features,
      segment_id_col = "id_segment", feature_id_col = id_col,
      direction = "downstream", aoi = aoi, include_equivalents = TRUE),
    frs_db_query = function(conn, query) {
      sql <<- query
      data.frame(id_segment = integer(), feature_ids = character())
    },
    .package = "fresh")
  sql
}

probe <- function(aoi) {
  invisible(DBI::dbExecute(conn, "DROP TABLE IF EXISTS pg_temp.zz261_seg"))
  invisible(DBI::dbExecute(conn, sprintf(
    "CREATE TEMP TABLE zz261_seg AS SELECT * FROM %s.streams
     WHERE watershed_group_code = %s", sch, q(aoi))))
  for (ix in c("(id_segment)", "USING GIST (wscode_ltree)",
               "USING GIST (localcode_ltree)", "(blue_line_key)")) {
    invisible(DBI::dbExecute(conn, sprintf("CREATE INDEX ON pg_temp.zz261_seg %s", ix)))
  }
  invisible(DBI::dbExecute(conn, "ANALYZE pg_temp.zz261_seg"))
  for (t in c("zz261_anc", "zz261_blk")) {
    invisible(DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS pg_temp.%s", t)))
  }
  invisible(DBI::dbExecute(conn,
    "CREATE TEMP TABLE zz261_anc AS SELECT DISTINCT subpath(wscode_ltree, 0, k) AS w
     FROM pg_temp.zz261_seg, generate_series(1, nlevel(wscode_ltree)) k"))
  invisible(DBI::dbExecute(conn,
    "CREATE TEMP TABLE zz261_blk AS SELECT DISTINCT blue_line_key FROM pg_temp.zz261_seg"))
  sent <- walk_sql("pg_temp.zz261_seg", "pg_temp.zz261_probe", "probe_id", aoi)
  join <- "INNER JOIN pg_temp.zz261_probe b ON"
  stopifnot(lengths(regmatches(sent, gregexpr(join, sent, fixed = TRUE))) == 1L)
  pre <- sub(join, "INNER JOIN (SELECT * FROM pg_temp.zz261_probe f
      WHERE f.wscode_ltree IN (SELECT w FROM pg_temp.zz261_anc)
         OR f.blue_line_key IN (SELECT blue_line_key FROM pg_temp.zz261_blk)) b ON",
    sent, fixed = TRUE)
  vapply(list(sent, pre), function(sql) {
    t0 <- Sys.time()
    n1(paste0("SELECT count(*) FROM (", sql, ") x"))
    as.numeric(difftime(Sys.time(), t0, units = "secs")) / n_probe * 1e6
  }, numeric(1))
}

province_src <- vapply(sources, function(s) n1(sprintf(
  "SELECT count(*)::float8 FROM %s.barriers_%s_unified", sch, s)), numeric(1))

wsgs <- DBI::dbGetQuery(conn, sprintf(
  "SELECT a.wsg, a.lo::text AS lo, b.hi::text AS hi, c.segments FROM
   (SELECT DISTINCT ON (watershed_group_code) watershed_group_code AS wsg,
           wscode_ltree AS lo
    FROM %1$s.streams ORDER BY watershed_group_code, wscode_ltree) a
   JOIN (SELECT DISTINCT ON (watershed_group_code) watershed_group_code AS wsg,
           wscode_ltree AS hi
    FROM %1$s.streams ORDER BY watershed_group_code, wscode_ltree DESC) b USING (wsg)
   JOIN (SELECT watershed_group_code AS wsg, count(*)::int AS segments
    FROM %1$s.streams GROUP BY 1) c USING (wsg)
   ORDER BY 1", sch))
only <- toupper(commandArgs(trailingOnly = TRUE))
if (length(only) > 0L) wsgs <- wsgs[wsgs$wsg %in% only, ]

in_range_nat <- function(sp, lo, hi) n1(sprintf(
  "SELECT coalesce((SELECT cum FROM zz261_bc WHERE sp = %1$s AND w <= %3$s::ltree
                    ORDER BY w DESC LIMIT 1), 0)
        - coalesce((SELECT cum FROM zz261_bc WHERE sp = %1$s AND w < %2$s::ltree
                    ORDER BY w DESC LIMIT 1), 0)
        + coalesce((SELECT sum(n) FROM zz261_bc,
                      generate_series(1, nlevel(%2$s::ltree) - 1) k
                    WHERE sp = %1$s AND w = subpath(%2$s::ltree, 0, k)), 0)",
  q(sp), q(lo), q(hi)))
in_range_src <- function(s, lo, hi) n1(sprintf(
  "SELECT count(*)::float8 FROM %1$s.barriers_%2$s_unified
   WHERE (wscode_ltree >= %3$s::ltree AND wscode_ltree <= %4$s::ltree)
      OR wscode_ltree @> %3$s::ltree",
  sch, s, q(lo), q(hi)))

rows <- lapply(seq_len(nrow(wsgs)), function(i) {
  aoi <- wsgs$wsg[i]; lo <- wsgs$lo[i]; hi <- wsgs$hi[i]
  active <- lnk_pipeline_species(cfg, loaded, aoi)
  pres <- lnk_presence(loaded$wsg_species_presence, aoi)
  sp <- tolower(active[pres$is_present(tolower(active))])
  tabs <- c(paste0("barriers_", sp, "_access"), paste0("barriers_", sources, "_unified"))
  o <- outlets[outlets$watershed_group_code == aoi, ]
  per <- vapply(tabs, function(tb) {
    inside <- n1(sprintf(
      "SELECT count(*)::float8 FROM %s.%s WHERE watershed_group_code = %s",
      sch, tb, q(aoi)))
    below <- if (nrow(o) == 1L) n1(sprintf(
      "SELECT count(*)::float8 FROM %s.%s b
       WHERE b.watershed_group_code <> %s
         AND (b.wscode_ltree @> %s::ltree OR b.blue_line_key = %s)
         AND whse_basemapping.fwa_downstream(
           %s::integer, %s::double precision, %s::ltree, %s::ltree,
           b.blue_line_key, b.downstream_route_measure,
           b.wscode_ltree, b.localcode_ltree, true, 1)",
      sch, tb, q(aoi), q(o$wscode_ltree), o$blue_line_key, o$blue_line_key,
      o$downstream_route_measure, q(o$wscode_ltree), q(o$localcode_ltree))) else NA_real_
    c(inside, below)
  }, numeric(2))
  nat <- grepl("_access$", tabs)
  outer <- sum(province_nat$n[match(sp, province_nat$sp)]) + sum(province_src)
  pus <- probe(aoi)
  rng <- sum(vapply(sp, in_range_nat, numeric(1), lo = lo, hi = hi)) +
    sum(vapply(sources, in_range_src, numeric(1), lo = lo, hi = hi))
  data.frame(wsg = aoi, segments = wsgs$segments[i], lo = lo, hi = hi,
             species_walked = length(sp), walks = length(tabs),
             features_inside = sum(per[1, ]),
             crossings_inside = sum(per[1, grepl("anthropogenic", tabs)]),
             natural_inside = sum(per[1, nat]),
             features_below_outlet = sum(per[2, ]),
             natural_below_outlet = sum(per[2, nat]),
             outer_rows = outer,
             outer_rows_natural = sum(province_nat$n[match(sp, province_nat$sp)]),
             in_range = rng, probe_us = round(pus[1], 4),
             probe_pre_us = round(pus[2], 4), others_active = others())
})
p <- do.call(rbind, rows)
out_file <- if (length(only) > 0L) "predictors_subset.tsv" else "predictors.tsv"
utils::write.table(p, file.path(out_dir, out_file), sep = "\t",
                   row.names = FALSE, quote = FALSE)
cat(sprintf("[predictors] %d groups written\n", nrow(p)))
