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
#     once per feature, and walks.R found the probe's cost is what differs.
#
# The natural views' province-wide and in-range counts are taken from
# <schema>.barriers by blocks_species, without the override anti-join (it
# removes about 1,800 of 7.24 M rows for CH).
#
# Usage (from the repo root):
#   LNK_MEASURE_HOST=<host> Rscript data-raw/logs/recompute_cost_261/predictors.R
# Output: predictors.tsv

suppressPackageStartupMessages({
  pkgload::load_all(quiet = TRUE)
  library(DBI)
})
out_dir <- "data-raw/logs/recompute_cost_261"
sch <- "fresh_default"
conn <- lnk_db_conn(dbname = "fwapg", host = Sys.getenv("LNK_MEASURE_HOST", "localhost"),
                    port = 5432L, user = "postgres", password = "postgres")
invisible(DBI::dbExecute(conn, "SET statement_timeout = '1800000'"))
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
  rng <- sum(vapply(sp, in_range_nat, numeric(1), lo = lo, hi = hi)) +
    sum(vapply(sources, in_range_src, numeric(1), lo = lo, hi = hi))
  data.frame(wsg = aoi, segments = wsgs$segments[i], lo = lo, hi = hi,
             species_walked = length(sp), walks = length(tabs),
             features_inside = sum(per[1, ]),
             crossings_inside = sum(per[1, grepl("anthropogenic", tabs)]),
             natural_inside = sum(per[1, nat]),
             features_below_outlet = sum(per[2, ]),
             natural_below_outlet = sum(per[2, nat]),
             outer_rows = outer, in_range = rng)
})
p <- do.call(rbind, rows)
utils::write.table(p, file.path(out_dir, "predictors.tsv"), sep = "\t",
                   row.names = FALSE, quote = FALSE)
cat(sprintf("[predictors] %d groups written\n", nrow(p)))
