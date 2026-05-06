#!/usr/bin/env Rscript
# data-raw/build_species_views.R
#
# Build one `<schema>.streams_<sp>_vw` view per species — joins
# segment geometry + attributes (streams) with per-species habitat
# booleans (streams_habitat_<sp>) and a `mapping_code` column for
# QGIS symbology (mirrors bcfishpass's streams_<sp>_vw shape).
#
# When `--bcfp` is passed AND `<schema>.streams_mapping_code` exists,
# also emits `streams_<sp>_bcfp_vw` siblings carrying bcfp-shape
# mapping_code_<sp> strings (from `lnk_pipeline_mapping_code` output).
# Both views co-exist for QGIS A/B comparison.
#
# Run after a provincial trifecta + consolidation has populated
# <schema>.streams + <schema>.streams_habitat_<sp> on M4. Re-run
# after every consolidation — `CREATE OR REPLACE VIEW` is idempotent
# so re-runs just refresh the view definitions (the underlying tables
# don't change unless re-persisted).
#
# Usage:
#   Rscript data-raw/build_species_views.R <schema> [species_csv] [--bcfp]
#
# Examples:
#   Rscript data-raw/build_species_views.R fresh_default
#   Rscript data-raw/build_species_views.R fresh_default_extrabreaks BT,CH,CO,SK
#   Rscript data-raw/build_species_views.R fresh_default_extrabreaks --bcfp
#
# Default species set: every `streams_habitat_<sp>` table found in the
# schema (auto-discovered via pg_tables).

suppressPackageStartupMessages({library(DBI); library(RPostgres)})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) {
  stop("Usage: Rscript build_species_views.R <schema> [species_csv] [--bcfp]")
}
flags <- args[grepl("^--", args)]
positional <- args[!grepl("^--", args)]
SCHEMA <- positional[1]
SP_FILTER <- if (length(positional) >= 2L) toupper(strsplit(positional[2], ",")[[1]]) else NULL
BCFP_VIEWS <- "--bcfp" %in% flags

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
  # Synthetic single-column fid for QGIS — views don't have PKs, and
  # QGIS needs one column to identify features. id_segment alone isn't
  # globally unique across WSGs, so use a deterministic row_number over
  # (watershed_group_code, id_segment) which IS jointly unique. Recomputed
  # at query time; stable as long as underlying tables don't change between
  # QGIS render passes.
  # CREATE OR REPLACE is column-shape-locked (can't reorder columns or
  # rename column 1). DROP first so we can change the schema cleanly
  # across re-runs that evolve the view definition.
  DBI::dbExecute(conn, sprintf("DROP VIEW IF EXISTS %s", view_name))
  sql <- sprintf("
    CREATE VIEW %s AS
    SELECT
      ROW_NUMBER() OVER (
        ORDER BY s.watershed_group_code, s.id_segment
      )::integer AS fid,
      s.*,
      h.accessible,
      h.spawning,
      h.rearing,
      h.lake_rearing,
      h.wetland_rearing,
      %s AS species_code,
      CASE
        WHEN h.accessible = false             THEN 'INACCESSIBLE'
        WHEN h.spawning AND h.rearing         THEN 'SPAWN'
        WHEN h.spawning                       THEN 'SPAWN_NO_REAR'
        WHEN h.rearing                        THEN 'REAR'
        ELSE                                       'ACCESSIBLE'
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

# bcfp parity sibling views (mapping_code_<sp> from
# lnk_pipeline_mapping_code output table). Skipped silently when the
# table doesn't exist or `--bcfp` was not passed.
build_bcfp_view <- function(conn, schema, sp) {
  sp_lower <- tolower(sp)
  view_name <- sprintf("%s.streams_%s_bcfp_vw", schema, sp_lower)
  mc_tbl <- sprintf("%s.streams_mapping_code", schema)
  streams_tbl <- sprintf("%s.streams", schema)
  mc_col <- sprintf("mapping_code_%s", sp_lower)
  DBI::dbExecute(conn, sprintf("DROP VIEW IF EXISTS %s", view_name))
  sql <- sprintf("
    CREATE VIEW %s AS
    SELECT
      ROW_NUMBER() OVER (
        ORDER BY s.watershed_group_code, s.id_segment
      )::integer AS fid,
      s.*,
      mc.%s AS mapping_code_bcfp,
      %s AS species_code
    FROM %s s
    LEFT JOIN %s mc
      ON s.id_segment = mc.id_segment",
    view_name, mc_col,
    DBI::dbQuoteLiteral(conn, sp),
    streams_tbl, mc_tbl)
  DBI::dbExecute(conn, sql)
  view_name
}

mc_exists <- DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*)::int AS n FROM pg_tables
   WHERE schemaname = %s AND tablename = 'streams_mapping_code'",
  DBI::dbQuoteLiteral(conn, SCHEMA)))$n > 0L

if (BCFP_VIEWS && mc_exists) {
  cat("\nBuilding bcfp-parity sibling views (streams_<sp>_bcfp_vw):\n")
  for (sp in species) {
    vn <- build_bcfp_view(conn, SCHEMA, sp)
    n <- DBI::dbGetQuery(conn, sprintf("SELECT count(*)::int AS n FROM %s", vn))$n
    cat(sprintf("  %s — %s rows\n", vn, format(n, big.mark = ",")))
  }
} else if (BCFP_VIEWS && !mc_exists) {
  cat("\n--bcfp passed but ", SCHEMA,
      ".streams_mapping_code does not exist; skipping sibling views.\n",
      "  Populate via lnk_pipeline_mapping_code(..., to = '",
      SCHEMA, ".streams_mapping_code', conn = conn) first.\n", sep = "")
}

cat("\nDone. In QGIS, add via Browser → PostgreSQL → fwapg → ",
    SCHEMA, " — drag any streams_<sp>_vw or streams_<sp>_bcfp_vw onto the canvas.\n",
    sep = "")
cat("Symbology suggestions:\n",
    "  - streams_<sp>_vw      : categorize by `mapping_code` (5 link categories: ",
    "INACCESSIBLE / SPAWN / SPAWN_NO_REAR / REAR / ACCESSIBLE)\n",
    "  - streams_<sp>_bcfp_vw : categorize by `mapping_code_bcfp` (bcfp tokens: ",
    "ACCESS;DAM, SPAWN;ASSESSED, REAR;MODELLED;INTERMITTENT, ...)\n", sep = "")
