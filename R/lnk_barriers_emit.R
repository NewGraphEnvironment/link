#' Emit slim crossings_lookup + per-source barriers_* tables
#'
#' Given a `<schema>.crossings` table (bcfp-shaped — produced upstream by
#' [lnk_pipeline_crossings()] or by loading a bcfp-format external dump)
#' plus optional `<schema>.dams`, emits five derived tables via filtered
#' SELECTs:
#'
#' - `<schema>.crossings_lookup` (slim id + status projection)
#' - `<schema>.barriers_anthropogenic` (all barrier-status crossings)
#' - `<schema>.barriers_pscis` (PSCIS-sourced barrier-status crossings)
#' - `<schema>.barriers_dams` (dam-sourced barrier-status crossings)
#' - `<schema>.barriers_remediations` (anthropogenic UNION REMEDIATED-PASSABLE)
#'
#' Output column shapes match what `lnk_pipeline_access(barrier_sources = list(...))`
#' consumes — `aggregated_crossings_id` plus the network-position columns
#' (`linear_feature_id`, `blue_line_key`, `downstream_route_measure`,
#' `wscode_ltree`, `localcode_ltree`).
#'
#' Mostly bcfp-shape-specific — it relies on column names/values from
#' bcfp's `crossings` shape (`barrier_status`, `crossing_source`,
#' `pscis_status`). Lives in link as the emit step of the new
#' `lnk_pipeline_crossings()` phase; may move to a future `pac` package
#' once that's scaffolded.
#'
#' @param conn A DBI connection.
#' @param schema Working schema name (already-existing). Must contain
#'   `<schema>.crossings`. Optionally contains `<schema>.dams`; if absent,
#'   `barriers_dams` is created empty.
#'
#' @return `invisible(NULL)`. Side effect: drops + recreates the five
#'   tables in `schema`.
#'
#' @details
#' Filters mirror bcfp's `model/01_access/sql/barriers_*.sql` and
#' `remediations_barriers.sql`:
#' - `barrier_status IN ('BARRIER', 'POTENTIAL')` for anthropogenic-style tables.
#' - `blue_line_key = watershed_key` (excludes side-channel features).
#' - `barriers_remediations` = `barriers_anthropogenic` UNION
#'   crossings WHERE `pscis_status = 'REMEDIATED' AND barrier_status = 'PASSABLE'`
#'   (bcfp-intended logic per the v0.30.2 fix; see `smnorris/bcfishpass#891`).
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' lnk_pipeline_setup(conn, schema = "working_adms")
#' # ... lnk_pipeline_crossings(...) populates working_adms.crossings ...
#' lnk_barriers_emit(conn, schema = "working_adms")
#' DBI::dbReadTable(conn, c("working_adms", "crossings_lookup"))
#' }
#'
#' @family barriers
#' @export
lnk_barriers_emit <- function(conn, schema) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(schema), length(schema) == 1L, nzchar(schema)
  )

  s <- DBI::dbQuoteIdentifier(conn, schema)

  # Five tables, all DROP + CREATE TABLE AS in one transaction.
  sql <- sprintf("
    -- crossings_lookup (slim id + status projection)
    DROP TABLE IF EXISTS %s.crossings_lookup;
    CREATE TABLE %s.crossings_lookup AS
    SELECT
      aggregated_crossings_id,
      pscis_status,
      barrier_status
    FROM %s.crossings;

    -- barriers_anthropogenic
    DROP TABLE IF EXISTS %s.barriers_anthropogenic;
    CREATE TABLE %s.barriers_anthropogenic AS
    SELECT
      aggregated_crossings_id AS barriers_anthropogenic_id,
      crossing_feature_type   AS barrier_type,
      NULL::text              AS barrier_name,
      linear_feature_id,
      blue_line_key,
      watershed_key,
      downstream_route_measure,
      wscode_ltree,
      localcode_ltree,
      watershed_group_code,
      ST_Force2D(geom)        AS geom
    FROM %s.crossings
    WHERE barrier_status IN ('BARRIER', 'POTENTIAL')
      AND blue_line_key = watershed_key;

    -- barriers_pscis
    DROP TABLE IF EXISTS %s.barriers_pscis;
    CREATE TABLE %s.barriers_pscis AS
    SELECT
      aggregated_crossings_id AS barriers_pscis_id,
      crossing_feature_type   AS barrier_type,
      crossing_source         AS barrier_name,
      linear_feature_id,
      blue_line_key,
      watershed_key,
      downstream_route_measure,
      wscode_ltree,
      localcode_ltree,
      watershed_group_code,
      ST_Force2D(geom)        AS geom
    FROM %s.crossings
    WHERE crossing_source = 'PSCIS'
      AND barrier_status IN ('BARRIER', 'POTENTIAL')
      AND blue_line_key = watershed_key;

    -- barriers_dams (FROM crossings filtered to dam source -- empty if no dam rows)
    DROP TABLE IF EXISTS %s.barriers_dams;
    CREATE TABLE %s.barriers_dams AS
    SELECT
      aggregated_crossings_id AS barriers_dams_id,
      crossing_feature_type   AS barrier_type,
      dam_name                AS barrier_name,
      linear_feature_id,
      blue_line_key,
      watershed_key,
      downstream_route_measure,
      wscode_ltree,
      localcode_ltree,
      watershed_group_code,
      ST_Force2D(geom)        AS geom
    FROM %s.crossings
    WHERE crossing_source = 'CABD'
      AND barrier_status IN ('BARRIER', 'POTENTIAL')
      AND blue_line_key = watershed_key;

    -- barriers_remediations (anthropogenic UNION REMEDIATED-PASSABLE crossings)
    DROP TABLE IF EXISTS %s.barriers_remediations;
    CREATE TABLE %s.barriers_remediations AS
    SELECT
      barriers_anthropogenic_id  AS barriers_remediations_id,
      'barriers_anthropogenic'   AS barrier_type,
      NULL::text                 AS barrier_name,
      linear_feature_id,
      blue_line_key,
      watershed_key,
      downstream_route_measure,
      wscode_ltree,
      localcode_ltree,
      watershed_group_code
    FROM %s.barriers_anthropogenic
    UNION ALL
    SELECT
      aggregated_crossings_id    AS barriers_remediations_id,
      'remediation'              AS barrier_type,
      NULL::text                 AS barrier_name,
      linear_feature_id,
      blue_line_key,
      watershed_key,
      downstream_route_measure,
      wscode_ltree,
      localcode_ltree,
      watershed_group_code
    FROM %s.crossings
    WHERE pscis_status = 'REMEDIATED'
      AND barrier_status = 'PASSABLE';
    ",
    s, s, s,                # crossings_lookup
    s, s, s,                # barriers_anthropogenic
    s, s, s,                # barriers_pscis
    s, s, s,                # barriers_dams
    s, s, s, s              # barriers_remediations (UNION ALL needs 4 schema refs)
  )

  DBI::dbExecute(conn, sql)
  invisible(NULL)
}
