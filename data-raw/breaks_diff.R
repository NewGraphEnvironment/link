#!/usr/bin/env Rscript
# breaks_diff.R — segment break census: a link persist schema against
# fresh.streams_vw_bcfp (bcfishpass's segmentation), per watershed group.
#
# A break is a segment's downstream_route_measure > 0.5 m (0 is the line's own
# start). Two breaks match within 1 m on the same blue_line_key. Only the
# group's own streams are counted on either side.
#
# Each link break is labelled by what put it there:
#   - MINIMAL_<cls>: a position in the group's working
#     <working>.gradient_barriers_minimal (the reduced post-lift per-species
#     sets, #326), classed by the persisted barrier it sits on (gradient by the
#     species it blocks: 25/30 % = BT, 20 % = ST not BT, 15 % = salmon only);
#   - <source>_NON_MINIMAL: a persisted barrier position the reduction did not
#     keep, broken there by something else: an independent break source
#     (falls, barriers_definite, subsurfaceflow; #96), an FWA line start, an
#     observation or a crossing;
#   - FWA_BASE_SEGMENT: the start of a whole fwa_stream_networks_sp line;
#   - none: an observation, crossing or habitat endpoint.
# With no working schema (dropped), the MINIMAL / NON_MINIMAL split is skipped
# and positions are labelled by barrier class alone, as #324's census did.
#
# Usage: Rscript data-raw/breaks_diff.R <WSG> [WSG ...]
#          [--schema=fresh] [--out=data-raw/logs/segmentation_326]
#          [--suffix=]   (appended to <wsg>_breaks<suffix>.csv)
# Writes <out>/<wsg>_breaks<suffix>.csv and prints it.
# Promoted from data-raw/logs/rearing_diff_324/breaks.R (#324, #326).

suppressPackageStartupMessages(library(DBI))
argv <- commandArgs(trailingOnly = TRUE)
opt <- function(name, default) {
  hit <- grep(sprintf("^--%s=", name), argv, value = TRUE)
  if (length(hit)) sub(sprintf("^--%s=", name), "", hit[1]) else default
}
schema <- opt("schema", "fresh")
out_dir <- opt("out", "data-raw/logs/segmentation_326")
suffix <- opt("suffix", "")
wsgs <- toupper(argv[!grepl("^--", argv)])
if (!length(wsgs)) stop("give at least one watershed group code", call. = FALSE)
stopifnot(grepl("^[a-z_][a-z0-9_]*$", schema), grepl("^[A-Za-z0-9_]*$", suffix))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")
x <- function(sql) invisible(DBI::dbExecute(conn, sql))

for (w in wsgs) {
  stopifnot(grepl("^[A-Z]{4}$", w))
  lit <- DBI::dbQuoteLiteral(conn, w)
  working <- paste0("working_", tolower(w))
  has_min <- nrow(DBI::dbGetQuery(conn, sprintf(
    "SELECT 1 FROM information_schema.tables
     WHERE table_schema = %s AND table_name = 'gradient_barriers_minimal'",
    DBI::dbQuoteLiteral(conn, working)))) > 0L
  for (t in c("lb", "bb", "br", "fb", "mn")) x(sprintf("DROP TABLE IF EXISTS pg_temp.%s", t))
  x(sprintf("CREATE TEMP TABLE lb AS SELECT blue_line_key blk, downstream_route_measure m
             FROM %s.streams WHERE watershed_group_code = %s AND downstream_route_measure > 0.5",
            schema, lit))
  x(sprintf("CREATE TEMP TABLE bb AS SELECT blue_line_key blk, downstream_route_measure m
             FROM fresh.streams_vw_bcfp WHERE watershed_group_code = %s AND downstream_route_measure > 0.5", lit))
  x(sprintf("CREATE TEMP TABLE br AS SELECT blue_line_key blk, downstream_route_measure m,
               CASE WHEN barrier_source <> 'GRADIENT' THEN barrier_source
                    WHEN 'BT' = ANY(blocks_species) THEN 'GRADIENT_25_30'
                    WHEN 'ST' = ANY(blocks_species) THEN 'GRADIENT_20'
                    ELSE 'GRADIENT_15' END AS cls
             FROM %s.barriers WHERE watershed_group_code = %s
               AND barrier_source IN ('GRADIENT', 'FALLS', 'SUBSURFACE_FLOW', 'USER_DEFINITE')",
            schema, lit))
  x(sprintf("CREATE TEMP TABLE fb AS SELECT blue_line_key blk, downstream_route_measure m
             FROM whse_basemapping.fwa_stream_networks_sp WHERE watershed_group_code = %s", lit))
  if (has_min) {
    x(sprintf("CREATE TEMP TABLE mn AS SELECT blue_line_key blk, downstream_route_measure m
               FROM %s.gradient_barriers_minimal", working))
  } else {
    x("CREATE TEMP TABLE mn (blk bigint, m double precision)")
  }
  for (t in c("lb", "bb", "br", "fb", "mn")) {
    x(sprintf("CREATE INDEX ON %s (blk, m)", t)); x(sprintf("ANALYZE %s", t))
  }
  near <- function(t, a) sprintf("%1$s.blk = %2$s.blk AND %1$s.m BETWEEN %2$s.m - 1 AND %2$s.m + 1", t, a)
  link <- DBI::dbGetQuery(conn, sprintf("
    SELECT in_bcfp,
           CASE WHEN cls IS NOT NULL AND %1$s AND on_min THEN 'MINIMAL_' || cls
                WHEN cls IS NOT NULL AND %1$s THEN cls || '_NON_MINIMAL'
                WHEN cls IS NOT NULL THEN cls
                WHEN on_min THEN 'MINIMAL_unclassed'
                WHEN fwa THEN 'FWA_BASE_SEGMENT'
                ELSE 'none (observation / crossing / endpoint)' END AS position,
           count(*) AS n
    FROM (SELECT exists(SELECT 1 FROM bb WHERE %2$s) AS in_bcfp,
                 (SELECT min(cls) FROM br WHERE %3$s) AS cls,
                 exists(SELECT 1 FROM mn WHERE %4$s) AS on_min,
                 exists(SELECT 1 FROM fb WHERE %5$s) AS fwa
          FROM lb) z
    GROUP BY 1, 2 ORDER BY 1, 3 DESC, 2",
    if (has_min) "TRUE" else "FALSE",
    near("bb", "lb"), near("br", "lb"), near("mn", "lb"), near("fb", "lb")))
  bcfp <- DBI::dbGetQuery(conn, sprintf("
    SELECT count(*) AS n_bcfp,
           count(*) FILTER (WHERE NOT exists(SELECT 1 FROM lb WHERE %s)) AS n_bcfp_not_in_link
    FROM bb", near("lb", "bb")))
  out <- rbind(data.frame(wsg = w, side = "link", in_other = link$in_bcfp,
                          position = link$position, n = link$n),
               data.frame(wsg = w, side = "bcfp", in_other = c(TRUE, FALSE), position = "all",
                          n = c(bcfp$n_bcfp - bcfp$n_bcfp_not_in_link, bcfp$n_bcfp_not_in_link)))
  utils::write.csv(out, file.path(out_dir, sprintf("%s_breaks%s.csv", tolower(w), suffix)),
                   row.names = FALSE)
  cat(sprintf("\n%s (schema %s, working minimal %s)\n", w, schema,
              if (has_min) "read" else "absent"))
  print(out, row.names = FALSE)
}
DBI::dbDisconnect(conn)
