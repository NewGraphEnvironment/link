#!/usr/bin/env Rscript
# breaks.R — segment break census, link `fresh` against fresh.streams_vw_bcfp (#324).
# A break is a segment's downstream_route_measure > 0.5 m (0 is the line's own
# start). Matched within 1 m on the same blue_line_key. Each link break is labelled
# by the `fresh.barriers` position it sits on (gradient positions by the species
# they block: BT = 25/30 % class, ST but not BT = 20 %, salmon only = 15 %).
# Writes <wsg>_breaks.csv beside this script.
#
# Usage: Rscript data-raw/logs/rearing_diff_324/breaks.R [WSG ...]   (default PCEA)

suppressPackageStartupMessages(library(DBI))
args <- toupper(commandArgs(trailingOnly = TRUE))
wsgs <- if (length(args)) args else "PCEA"
dir  <- "data-raw/logs/rearing_diff_324"

conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")
x <- function(sql) invisible(DBI::dbExecute(conn, sql))

for (w in wsgs) {
  stopifnot(grepl("^[A-Z]{4}$", w))
  lit <- DBI::dbQuoteLiteral(conn, w)
  x("DROP TABLE IF EXISTS pg_temp.lb"); x("DROP TABLE IF EXISTS pg_temp.bb")
  x("DROP TABLE IF EXISTS pg_temp.br")
  x(sprintf("CREATE TEMP TABLE lb AS SELECT blue_line_key blk, downstream_route_measure m
             FROM fresh.streams WHERE watershed_group_code = %s AND downstream_route_measure > 0.5", lit))
  x(sprintf("CREATE TEMP TABLE bb AS SELECT blue_line_key blk, downstream_route_measure m
             FROM fresh.streams_vw_bcfp WHERE watershed_group_code = %s AND downstream_route_measure > 0.5", lit))
  x(sprintf("CREATE TEMP TABLE br AS SELECT blue_line_key blk, downstream_route_measure m,
               CASE WHEN barrier_source <> 'GRADIENT' THEN barrier_source
                    WHEN 'BT' = ANY(blocks_species) THEN 'GRADIENT_25_30'
                    WHEN 'ST' = ANY(blocks_species) THEN 'GRADIENT_20'
                    ELSE 'GRADIENT_15' END AS cls
             FROM fresh.barriers WHERE watershed_group_code = %s", lit))
  for (t in c("lb", "bb", "br")) { x(sprintf("CREATE INDEX ON %s (blk, m)", t)); x(sprintf("ANALYZE %s", t)) }
  link <- DBI::dbGetQuery(conn, "
    SELECT in_bcfp, coalesce(cls, 'none (observation / crossing / endpoint)') AS position, count(*) AS n
    FROM (SELECT exists(SELECT 1 FROM bb WHERE bb.blk = lb.blk AND bb.m BETWEEN lb.m - 1 AND lb.m + 1) AS in_bcfp,
                 (SELECT min(cls) FROM br WHERE br.blk = lb.blk AND br.m BETWEEN lb.m - 1 AND lb.m + 1) AS cls
          FROM lb) z
    GROUP BY 1, 2 ORDER BY 1, 3 DESC")
  bcfp <- DBI::dbGetQuery(conn, "
    SELECT count(*) AS n_bcfp,
           count(*) FILTER (WHERE NOT exists(SELECT 1 FROM lb WHERE lb.blk = bb.blk
                                             AND lb.m BETWEEN bb.m - 1 AND bb.m + 1)) AS n_bcfp_not_in_link
    FROM bb")
  out <- rbind(data.frame(wsg = w, side = "link", in_other = link$in_bcfp,
                          position = link$position, n = link$n),
               data.frame(wsg = w, side = "bcfp", in_other = c(TRUE, FALSE), position = "all",
                          n = c(bcfp$n_bcfp - bcfp$n_bcfp_not_in_link, bcfp$n_bcfp_not_in_link)))
  utils::write.csv(out, file.path(dir, sprintf("%s_breaks.csv", tolower(w))), row.names = FALSE)
  print(out, row.names = FALSE)
}
DBI::dbDisconnect(conn)
