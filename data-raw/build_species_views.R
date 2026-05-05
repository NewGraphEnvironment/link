#!/usr/bin/env Rscript
# data-raw/build_species_views.R
#
# Build one `<schema>.streams_<sp>_vw` view per species — joins
# segment geometry + attributes (streams) with per-species habitat
# booleans (streams_habitat_<sp>) and a `mapping_code` column for
# QGIS symbology (mirrors bcfishpass's streams_<sp>_vw shape).
#
# Run after a provincial trifecta + consolidation has populated
# <schema>.streams + <schema>.streams_habitat_<sp> on M4. Re-run
# after every consolidation — `CREATE OR REPLACE VIEW` is idempotent
# so re-runs just refresh the view definitions (the underlying tables
# don't change unless re-persisted).
#
# Usage:
#   Rscript data-raw/build_species_views.R <schema> [species_csv]
#
# Examples:
#   Rscript data-raw/build_species_views.R fresh_default
#   Rscript data-raw/build_species_views.R fresh_default_extrabreaks BT,CH,CO,SK
#
# Default species set: every `streams_habitat_<sp>` table found in the
# schema (auto-discovered via pg_tables).

suppressPackageStartupMessages({library(DBI); library(RPostgres)})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) {
  stop("Usage: Rscript build_species_views.R <schema> [species_csv]")
}
SCHEMA <- args[1]
SP_FILTER <- if (length(args) >= 2L) toupper(strsplit(args[2], ",")[[1]]) else NULL

conn <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 5432, dbname = "fwapg",
  user = "postgres", password = "postgres")
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

# Discover species by listing streams_habitat_<sp> tables.
hab_tbls <- DBI::dbGetQuery(conn, sprintf(
  "SELECT tablename FROM pg_tables
   WHERE schemaname = %s
     AND tablename LIKE 'streams_habitat\\_%%' ESCAPE '\\'",
  DBI::dbQuoteLiteral(conn, SCHEMA)))$tablename
species <- toupper(sub("^streams_habitat_", "", hab_tbls))
if (!is.null(SP_FILTER)) species <- intersect(species, SP_FILTER)
if (length(species) == 0L) {
  stop("No streams_habitat_<sp> tables found in schema '", SCHEMA, "'")
}
cat(sprintf("Building views in %s for: %s\n",
            SCHEMA, paste(species, collapse = ", ")))

build_view <- function(conn, schema, sp) {
  sp_lower <- tolower(sp)
  view_name <- sprintf("%s.streams_%s_vw", schema, sp_lower)
  hab_tbl   <- sprintf("%s.streams_habitat_%s", schema, sp_lower)
  streams_tbl <- sprintf("%s.streams", schema)
  sql <- sprintf("
    CREATE OR REPLACE VIEW %s AS
    SELECT s.*,
           h.accessible,
           h.spawning,
           h.rearing,
           h.lake_rearing,
           h.wetland_rearing,
           %s AS species_code,
           CASE
             WHEN h.accessible = false             THEN 'INACCESSIBLE'
             WHEN h.spawning AND h.rearing         THEN 'BOTH'
             WHEN h.spawning                       THEN 'SPAWN'
             WHEN h.rearing                        THEN 'REAR'
             ELSE                                       'NONE'
           END AS mapping_code
    FROM %s s
    LEFT JOIN %s h
      ON s.id_segment = h.id_segment
     AND s.watershed_group_code = h.watershed_group_code",
    view_name,
    DBI::dbQuoteLiteral(conn, sp),
    streams_tbl, hab_tbl)
  DBI::dbExecute(conn, sql)
  view_name
}

for (sp in species) {
  vn <- build_view(conn, SCHEMA, sp)
  n <- DBI::dbGetQuery(conn, sprintf("SELECT count(*)::int AS n FROM %s", vn))$n
  cat(sprintf("  %s — %s rows\n", vn, format(n, big.mark = ",")))
}

cat("\nDone. In QGIS, add via Browser → PostgreSQL → fwapg → ",
    SCHEMA, " — drag any streams_<sp>_vw onto the canvas.\n", sep = "")
cat("Symbology suggestion: categorize by `mapping_code` (5 categories: ",
    "INACCESSIBLE / BOTH / SPAWN / REAR / NONE).\n", sep = "")
