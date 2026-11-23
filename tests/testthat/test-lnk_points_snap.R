# lnk_points_snap() wraps fresh::frs_point_snap() (link#314). The mocks
# stand in for DBI and fresh; the live tests at the end need a database.

snap_mocks <- function(cols = c("stream_crossing_id", "geom")) {
  list(
    quote_id = mockery::mock(DBI::SQL('"stream_crossing_id"'), cycle = TRUE),
    quote_str = mockery::mock(DBI::SQL("'q'"), cycle = TRUE),
    query = mockery::mock(data.frame(column_name = cols), cycle = TRUE),
    exec = mockery::mock(1L, cycle = TRUE),
    snap = mockery::mock(invisible(NULL), cycle = TRUE)
  )
}

run_snap <- function(m, ...) {
  conn <- structure(list(), class = "DBIConnection")
  with_mocked_bindings(
    dbQuoteIdentifier = m$quote_id,
    dbQuoteString = m$quote_str,
    dbGetQuery = m$query,
    dbExecute = m$exec,
    .package = "DBI",
    with_mocked_bindings(
      frs_point_snap = m$snap,
      .package = "fresh",
      lnk_points_snap(conn, ...)
    )
  )
}

exec_sql <- function(m) {
  paste(vapply(mockery::mock_args(m$exec), function(a) a[[2]], character(1)),
        collapse = "\n")
}

test_that("the mocked frs_point_snap matches fresh's signature", {
  expect_true(all(c("conn", "points", "to", "col_id", "col_geom", "col_blk",
                    "tolerance", "num_features", "stream_order_min",
                    "exclude_edge_types") %in%
                    names(formals(fresh::frs_point_snap))))
})

test_that("lnk_points_snap snaps through fresh and keeps the input columns", {
  m <- snap_mocks()
  result <- run_snap(m, table_in = "whse_fish.pscis_assessment_svw",
                     table_out = "fresh.pscis_assessment_snapped",
                     id_col = "stream_crossing_id")
  expect_equal(result, "fresh.pscis_assessment_snapped")

  mockery::expect_called(m$snap, 1)
  a <- mockery::mock_args(m$snap)[[1]]
  expect_identical(a[[2]], "whse_fish.pscis_assessment_svw")
  expect_identical(a$col_id, "stream_crossing_id")
  expect_identical(a$col_geom, "geom")
  expect_null(a$col_blk)
  expect_identical(a$tolerance, 100)
  expect_identical(a$num_features, 1L)
  expect_identical(a$exclude_edge_types, 1425L)
  # the scratch table sits in table_out's schema
  expect_match(a$to, "^fresh\\.zz_lnk_points_snap_[0-9]+$")

  sql <- exec_sql(m)
  expect_match(sql, "DROP TABLE IF EXISTS fresh\\.pscis_assessment_snapped")
  expect_match(sql, "CREATE TABLE fresh\\.pscis_assessment_snapped")
  expect_match(sql, "pts\\.\\*")
  expect_match(sql, "FROM whse_fish\\.pscis_assessment_svw pts")
  expect_match(sql, "snap\\.blue_line_key AS snapped_blue_line_key")
  expect_match(sql, "snap\\.geom AS geom_snapped")
  expect_match(sql, "snap\\.watershed_group_code")
  expect_match(sql, "snap\\.gnis_name")
  # nearest only: no rank column
  expect_no_match(sql, "candidate_rank")
  # the scratch table is dropped on exit
  expect_match(sql, "DROP TABLE IF EXISTS fresh\\.zz_lnk_points_snap_")
})

test_that("lnk_points_snap passes the candidate rules through to fresh", {
  m <- snap_mocks(c("stream_crossing_id", "blue_line_key", "geom"))
  run_snap(m, "x.in", "y.out", id_col = "stream_crossing_id",
           geom_col = "geom", snap_tolerance = 150,
           exclude_edge_types = c(1410L, 1425L),
           blue_line_key_col = "blue_line_key", stream_order_min = 3,
           num_features = 5L)
  a <- mockery::mock_args(m$snap)[[1]]
  expect_identical(a$tolerance, 150)
  expect_identical(a$exclude_edge_types, c(1410L, 1425L))
  expect_identical(a$col_blk, "blue_line_key")
  expect_identical(a$stream_order_min, 3)
  expect_identical(a$num_features, 5L)
  # several candidates: the rank is carried and orders the output
  expect_match(exec_sql(m), "snap\\.candidate_rank,")
  expect_match(exec_sql(m), "ORDER BY snap\\.\"stream_crossing_id\", snap\\.candidate_rank")
})

test_that("lnk_points_snap passes no excluded edge types for integer(0)", {
  m <- snap_mocks()
  run_snap(m, "x.in", "y.out", id_col = "stream_crossing_id",
           exclude_edge_types = integer(0))
  expect_length(mockery::mock_args(m$snap)[[1]]$exclude_edge_types, 0L)
})

test_that("lnk_points_snap rejects tables not in <schema>.<table> form", {
  m <- snap_mocks()
  expect_error(run_snap(m, "no_dot", "y.out", id_col = "a"),
               "table_in must be '<schema>\\.<table>'")
  expect_error(run_snap(m, "a.b.c", "y.out", id_col = "a"),
               "table_in must be '<schema>\\.<table>'")
  expect_error(run_snap(m, "x.in", "no_dot", id_col = "a"),
               "table_out must be '<schema>\\.<table>'")
  mockery::expect_called(m$snap, 0)
})

test_that("lnk_points_snap fails loud on input/output column collision", {
  for (col in c("linear_feature_id", "watershed_group_code", "gnis_name",
                "candidate_rank", "geom_snapped")) {
    m <- snap_mocks(c("stream_crossing_id", col, "geom"))
    expect_error(run_snap(m, "x.in", "y.out", id_col = "stream_crossing_id"),
                 col, fixed = TRUE)
    # refused before anything is snapped or written
    mockery::expect_called(m$snap, 0)
    expect_length(mockery::mock_args(m$exec), 0L)
  }
})

test_that("lnk_points_snap refuses an id column the table does not have", {
  m <- snap_mocks(c("id", "geom"))
  expect_error(run_snap(m, "x.in", "y.out", id_col = "stream_crossing_id"),
               "id_col 'stream_crossing_id' is not a column of x.in",
               fixed = TRUE)
  mockery::expect_called(m$snap, 0)
})

test_that("lnk_points_snap validates argument shapes", {
  conn <- structure(list(), class = "DBIConnection")
  expect_error(lnk_points_snap("not a conn", "a.b", "c.d", "id"))
  expect_error(lnk_points_snap(conn, "", "c.d", "id"))
  expect_error(lnk_points_snap(conn, "a.b", "", "id"))
  expect_error(lnk_points_snap(conn, "a.b", "c.d"))
  expect_error(lnk_points_snap(conn, "a.b", "c.d", NA_character_))
  expect_error(lnk_points_snap(conn, "a.b", "c.d", "id", snap_tolerance = -1))
  expect_error(lnk_points_snap(conn, "a.b", "c.d", "id",
                               snap_tolerance = c(1, 2)))
  expect_error(lnk_points_snap(conn, "a.b", "c.d", "id", num_features = 0))
})

# --- live: the snap never lands on a placeholder stream (link#313) ---------
# Before link#478 the guard was `wscode_ltree != '999'`, which let every
# 999.999999... segment through; on the provincial PSCIS 11 picks sat on one.

test_that("no PSCIS candidate snaps to a placeholder (999.*) stream", {
  conn <- skip_if_no_db()
  has <- DBI::dbGetQuery(conn, "
    SELECT to_regclass('whse_fish.pscis_assessment_svw') IS NOT NULL AS pscis,
           to_regclass('whse_basemapping.fwa_stream_networks_sp') IS NOT NULL AS fwa")
  skip_if(!isTRUE(has$pscis) || !isTRUE(has$fwa), "no PSCIS or FWA tables")
  # the PSCIS points within 150 m of a placeholder segment
  DBI::dbExecute(conn, "DROP SCHEMA IF EXISTS zz_test_snap313 CASCADE")
  withr::defer(DBI::dbExecute(conn, "DROP SCHEMA IF EXISTS zz_test_snap313 CASCADE"))
  DBI::dbExecute(conn, "CREATE SCHEMA zz_test_snap313")
  DBI::dbExecute(conn, "
    CREATE TABLE zz_test_snap313.pts AS
    SELECT p.stream_crossing_id, p.geom
    FROM whse_fish.pscis_assessment_svw p
    WHERE EXISTS (SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp s
                  -- text, not <@: the ltree index made this run for minutes
                  WHERE (s.wscode_ltree::text = '999'
                         OR left(s.wscode_ltree::text, 4) = '999.')
                    AND ST_DWithin(s.geom, p.geom, 150))")
  n_pts <- DBI::dbGetQuery(conn, "SELECT count(*)::int AS n FROM zz_test_snap313.pts")$n
  skip_if(n_pts == 0L, "no PSCIS point near a placeholder stream")
  lnk_points_snap(conn, "zz_test_snap313.pts", "zz_test_snap313.snapped",
                  id_col = "stream_crossing_id", snap_tolerance = 150,
                  num_features = 5L)
  got <- DBI::dbGetQuery(conn, "
    SELECT count(*)::int AS n,
           count(*) FILTER (WHERE wscode_ltree <@ '999'::ltree)::int AS n999
    FROM zz_test_snap313.snapped")
  expect_gt(got$n, 0L)
  expect_identical(got$n999, 0L)
})
