#' Snap a Postgres table of points to the FWA stream network
#'
#' Bulk-snap helper: takes a Postgres table of point geometries and
#' creates a new table with each row enriched with the nearest FWA stream
#' segment's `linear_feature_id`, `blue_line_key`, `downstream_route_measure`,
#' `wscode_ltree`, `localcode_ltree`, plus snap distance.
#'
#' Uses a single SQL `CROSS JOIN LATERAL ... ORDER BY <-> ... LIMIT 1`
#' against `whse_basemapping.fwa_stream_networks_sp` — same lateral-KNN
#' pattern as `bcfishpass`'s `load_dams.sql` and link's existing CABD
#' dams snap in [lnk_pipeline_prepare()]. One round-trip; scales to
#' province-wide point sets.
#'
#' Generic — not specific to any pipeline phase. Likely belongs in a
#' future `pac` package once that's scaffolded; ships in link for now.
#'
#' @param conn A DBI connection.
#' @param table_in Fully-qualified `<schema>.<table>` of input points.
#' @param table_out Fully-qualified `<schema>.<table>` to create. Existing
#'   table is `DROP TABLE IF EXISTS`'d first.
#' @param geom_col Name of the geometry column in `table_in`. Default
#'   `"geom"`.
#' @param snap_tolerance Maximum snap distance in metres. Points farther
#'   than this from the network are dropped. Default `100`.
#' @param exclude_edge_types Integer vector of `edge_type` codes to
#'   exclude from the FWA network when snapping. Default `1425L`
#'   (subsurface flow). Pass `integer(0)` to exclude none.
#' @param blue_line_key_col Optional name of a `blue_line_key` column in
#'   `table_in` to constrain candidate streams to. `NULL` (default) snaps
#'   to any FWA stream within tolerance.
#' @param stream_order_min Optional minimum `stream_order` to include.
#'   `NULL` (default) accepts any order.
#'
#' @return `invisible(table_out)`. Side effect: creates `table_out` in
#'   `conn`'s database.
#'
#' @details
#' Output table columns: every column from `table_in` PLUS
#' `linear_feature_id` (bigint), `blue_line_key` (integer),
#' `downstream_route_measure` (numeric), `wscode_ltree` (ltree),
#' `localcode_ltree` (ltree), `distance_to_stream` (numeric, metres),
#' `geom_snapped` (geometry — point projected onto the segment).
#'
#' Filters applied to candidate streams (from
#' `fresh::frs_point_snap_knn` conventions):
#' - `wscode_ltree != '999'` (placeholder streams excluded)
#' - `localcode_ltree IS NOT NULL` (unmapped tributaries excluded)
#' - `edge_type NOT IN (exclude_edge_types)` (subsurface etc. excluded)
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' lnk_points_snap(
#'   conn,
#'   table_in  = "whse_fish.pscis_assessment_svw",
#'   table_out = "working_adms.pscis_assessment_snapped",
#'   snap_tolerance = 100,
#'   exclude_edge_types = c(1410L, 1425L)
#' )
#' }
#'
#' @family points
#' @export
lnk_points_snap <- function(conn, table_in, table_out,
                            geom_col = "geom",
                            snap_tolerance = 100,
                            exclude_edge_types = 1425L,
                            blue_line_key_col = NULL,
                            stream_order_min = NULL) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(table_in), length(table_in) == 1L, nzchar(table_in),
    is.character(table_out), length(table_out) == 1L, nzchar(table_out),
    is.character(geom_col), length(geom_col) == 1L, nzchar(geom_col),
    is.numeric(snap_tolerance), length(snap_tolerance) == 1L,
    snap_tolerance > 0,
    is.numeric(exclude_edge_types) || is.integer(exclude_edge_types),
    is.null(blue_line_key_col) ||
      (is.character(blue_line_key_col) && length(blue_line_key_col) == 1L),
    is.null(stream_order_min) ||
      (is.numeric(stream_order_min) && length(stream_order_min) == 1L)
  )

  # Constrained candidate-stream WHERE clause built up from optional args.
  where <- c(
    "s.wscode_ltree != '999'::ltree",
    "s.localcode_ltree IS NOT NULL"
  )
  if (length(exclude_edge_types) > 0L) {
    where <- c(where, sprintf("s.edge_type NOT IN (%s)",
                              paste(as.integer(exclude_edge_types),
                                    collapse = ", ")))
  }
  if (!is.null(blue_line_key_col)) {
    where <- c(where, sprintf("s.blue_line_key = pts.%s",
                              DBI::dbQuoteIdentifier(conn,
                                                     blue_line_key_col)))
  }
  if (!is.null(stream_order_min)) {
    where <- c(where, sprintf("s.stream_order >= %d",
                              as.integer(stream_order_min)))
  }
  where_sql <- paste(where, collapse = " AND ")

  geom_q <- DBI::dbQuoteIdentifier(conn, geom_col)

  sql <- sprintf("
    DROP TABLE IF EXISTS %s;
    CREATE TABLE %s AS
    SELECT
      pts.*,
      snap.linear_feature_id,
      snap.blue_line_key   AS snapped_blue_line_key,
      snap.downstream_route_measure,
      snap.wscode_ltree,
      snap.localcode_ltree,
      ST_Distance(pts.%s, snap.geom_snapped) AS distance_to_stream,
      snap.geom_snapped
    FROM %s pts
    CROSS JOIN LATERAL (
      SELECT
        s.linear_feature_id,
        s.blue_line_key,
        s.wscode_ltree,
        s.localcode_ltree,
        ST_LineLocatePoint(s.geom, pts.%s)
          * ST_Length(s.geom) AS downstream_route_measure,
        ST_ClosestPoint(s.geom, pts.%s) AS geom_snapped
      FROM whse_basemapping.fwa_stream_networks_sp s
      WHERE ST_DWithin(s.geom, pts.%s, %f)
        AND %s
      ORDER BY s.geom <-> pts.%s
      LIMIT 1
    ) snap;",
    table_out, table_out,
    geom_q,
    table_in,
    geom_q, geom_q, geom_q,
    snap_tolerance,
    where_sql,
    geom_q
  )

  DBI::dbExecute(conn, sql)
  invisible(table_out)
}
