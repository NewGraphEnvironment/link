#' Snap a Postgres table of points to the FWA stream network
#'
#' Bulk-snap helper: takes a Postgres table of point geometries and
#' creates a new table with each row enriched with the nearest FWA stream
#' segment's `linear_feature_id`, `blue_line_key`, `downstream_route_measure`,
#' `wscode_ltree`, `localcode_ltree`, `watershed_group_code`, `gnis_name`,
#' plus snap distance.
#'
#' The snap itself is [fresh::frs_point_snap()]: one lateral nearest-neighbour
#' query for the whole table. This function keeps every column of `table_in`
#' beside the snap, under link's column names, so a pipeline can carry the
#' points' own attributes through. The candidate rules are fresh's:
#'
#' - placeholder streams (`wscode_ltree <@ '999'`) and unmapped tributaries
#'   (`localcode_ltree IS NULL`) are never candidates;
#' - `edge_type NOT IN (exclude_edge_types)` drops more;
#' - an exact distance tie, a point nearest to the vertex two segments
#'   share, goes to the segment with the higher `downstream_route_measure`
#'   (the one starting at that vertex), then the lower `linear_feature_id`.
#'   This is fwapg's rule for `fwa_indexpoint()`.
#'
#' The measure is a whole metre, as in bcfishpass's `04_pscis.sql`.
#'
#' @param conn A DBI connection.
#' @param table_in Fully-qualified `<schema>.<table>` of input points.
#' @param table_out Fully-qualified `<schema>.<table>` to create. Existing
#'   table is `DROP TABLE IF EXISTS`'d first.
#' @param id_col Name of a column in `table_in` that identifies each point.
#'   Its values must be unique and non-missing; the function stops
#'   otherwise.
#' @param geom_col Name of the geometry column in `table_in`. Default
#'   `"geom"`. A MultiPoint is snapped by its first point.
#' @param snap_tolerance Maximum snap distance in metres. Points farther
#'   than this from the network are dropped. Default `100`.
#' @param exclude_edge_types Integer vector of `edge_type` codes to
#'   exclude from the FWA network when snapping. Default `1425L`
#'   (subsurface flow). Pass `integer(0)` to exclude none.
#' @param blue_line_key_col Optional name of a `blue_line_key` column in
#'   `table_in` to constrain candidate streams to. `NULL` (default) snaps
#'   to any FWA stream within tolerance. A point whose hint is missing
#'   snaps to any stream.
#' @param stream_order_min Optional minimum `stream_order` to include.
#'   `NULL` (default) accepts any order.
#' @param num_features Integer scalar. Maximum number of stream candidates
#'   per input point. Default `1L` (nearest only). Set higher (e.g. `5L`)
#'   to score and pick among nearby streams. Output then has one row per
#'   (input row, candidate stream) pair and a `candidate_rank` column
#'   (1 = nearest).
#'
#' @return `invisible(table_out)`. Side effect: creates `table_out` in
#'   `conn`'s database.
#'
#' @details
#' Output table columns: every column from `table_in` PLUS
#' `linear_feature_id`, `snapped_blue_line_key`,
#' `downstream_route_measure`, `wscode_ltree`, `localcode_ltree`,
#' `watershed_group_code`, `gnis_name`, `distance_to_stream` (metres),
#' `candidate_rank` (when `num_features > 1`) and `geom_snapped` (the
#' point projected onto the segment, EPSG:3005). An input table holding
#' any of those names is refused. The snap is written first to a scratch
#' table beside `table_out`, which is dropped on exit.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' lnk_points_snap(
#'   conn,
#'   table_in  = "whse_fish.pscis_assessment_svw",
#'   table_out = "working_adms.pscis_assessment_snapped",
#'   id_col = "stream_crossing_id",
#'   snap_tolerance = 150,
#'   num_features = 5L
#' )
#' }
#'
#' @family points
#' @export
lnk_points_snap <- function(conn, table_in, table_out, id_col,
                            geom_col = "geom",
                            snap_tolerance = 100,
                            exclude_edge_types = 1425L,
                            blue_line_key_col = NULL,
                            stream_order_min = NULL,
                            num_features = 1L) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(table_in), length(table_in) == 1L, nzchar(table_in),
    is.character(table_out), length(table_out) == 1L, nzchar(table_out),
    is.character(id_col), length(id_col) == 1L, !is.na(id_col),
    nzchar(id_col),
    is.character(geom_col), length(geom_col) == 1L, nzchar(geom_col),
    is.numeric(snap_tolerance), length(snap_tolerance) == 1L,
    snap_tolerance > 0,
    is.numeric(exclude_edge_types) || is.integer(exclude_edge_types),
    is.null(blue_line_key_col) ||
      (is.character(blue_line_key_col) && length(blue_line_key_col) == 1L),
    is.null(stream_order_min) ||
      (is.numeric(stream_order_min) && length(stream_order_min) == 1L),
    is.numeric(num_features), length(num_features) == 1L,
    !is.na(num_features), num_features >= 1
  )

  # <schema>.<table> for both, so the column lookup can run and the
  # scratch table can sit in table_out's schema.
  parts <- strsplit(table_in, ".", fixed = TRUE)[[1]]
  if (length(parts) != 2L) {
    stop(
      sprintf("table_in must be '<schema>.<table>'; got '%s'.", table_in),
      call. = FALSE
    )
  }
  # table_out is dropped before it is built from table_in
  if (identical(tolower(table_in), tolower(table_out))) {
    stop("table_out must differ from table_in.", call. = FALSE)
  }
  parts_out <- strsplit(table_out, ".", fixed = TRUE)[[1]]
  if (length(parts_out) != 2L) {
    stop(
      sprintf("table_out must be '<schema>.<table>'; got '%s'.", table_out),
      call. = FALSE
    )
  }

  # Fail loud if the input table has columns that collide with the snap
  # output projection: `pts.*` would otherwise produce a duplicate-name
  # error from CREATE TABLE AS.
  # Resolved as the snap's own FROM resolves it (case folding, pg_temp), not
  # by the literal name, which information_schema would need spelled exactly.
  in_cols <- DBI::dbGetQuery(conn, sprintf(
    "SELECT attname AS column_name
       FROM pg_attribute
      WHERE attrelid = to_regclass(%s) AND attnum > 0 AND NOT attisdropped;",
    DBI::dbQuoteString(conn, table_in)
  ))$column_name
  if (length(in_cols) == 0L) {
    stop(sprintf("table_in %s was not found (or has no columns).", table_in),
         call. = FALSE)
  }
  snap_cols <- c("linear_feature_id", "snapped_blue_line_key",
                 "downstream_route_measure", "wscode_ltree",
                 "localcode_ltree", "watershed_group_code", "gnis_name",
                 "distance_to_stream", "candidate_rank", "geom_snapped")
  collisions <- intersect(in_cols, snap_cols)
  if (length(collisions) > 0L) {
    stop(
      sprintf("Input table %s has columns that collide with snap output: %s. ",
              table_in, paste(collisions, collapse = ", ")),
      "Rename or drop them before snapping.",
      call. = FALSE
    )
  }
  if (!id_col %in% in_cols) {
    stop(sprintf("id_col '%s' is not a column of %s.", id_col, table_in),
         call. = FALSE)
  }

  tmp <- sprintf("%s.zz_lnk_points_snap_%d", parts_out[1], Sys.getpid())
  on.exit(
    tryCatch(DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s;", tmp)),
             error = function(e) NULL),
    add = TRUE
  )
  fresh::frs_point_snap(
    conn, table_in,
    to = tmp,
    col_id = id_col,
    col_geom = geom_col,
    col_blk = blue_line_key_col,
    tolerance = snap_tolerance,
    num_features = as.integer(num_features),
    stream_order_min = stream_order_min,
    exclude_edge_types = as.integer(exclude_edge_types)
  )

  id_q <- DBI::dbQuoteIdentifier(conn, id_col)
  has_rank <- num_features > 1
  create_sql <- sprintf("
    CREATE TABLE %s AS
    SELECT
      pts.*,
      snap.linear_feature_id,
      snap.blue_line_key AS snapped_blue_line_key,
      snap.downstream_route_measure,
      snap.wscode_ltree,
      snap.localcode_ltree,
      snap.watershed_group_code,
      snap.gnis_name,
      snap.distance_to_stream,%s
      snap.geom AS geom_snapped
    FROM %s pts
    JOIN %s snap ON snap.%s = pts.%s
    ORDER BY snap.%s%s;",
    table_out,
    if (has_rank) "\n      snap.candidate_rank," else "",
    table_in, tmp, id_q, id_q, id_q,
    if (has_rank) ", snap.candidate_rank" else ""
  )

  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s;", table_out))
  DBI::dbExecute(conn, create_sql)
  invisible(table_out)
}
