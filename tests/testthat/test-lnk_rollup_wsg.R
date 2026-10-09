# Tests for lnk_rollup_wsg — argument validation + SQL construction

mock_conn <- function() structure(list(), class = "DBIConnection")

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

test_that("lnk_rollup_wsg rejects invalid aoi", {
  expect_error(lnk_rollup_wsg(mock_conn(), aoi = "", species = "CO"), "aoi")
  expect_error(lnk_rollup_wsg(mock_conn(), aoi = "ab", species = "CO"), "aoi")
  expect_error(
    lnk_rollup_wsg(mock_conn(), aoi = c("MORR", "BULK"), species = "CO"),
    "aoi")
})

test_that("lnk_rollup_wsg rejects non-DBI conn", {
  expect_error(lnk_rollup_wsg("not-a-conn", aoi = "MORR", species = "CO"),
               "DBI")
})

test_that("lnk_rollup_wsg rejects empty or non-alpha species", {
  expect_error(
    lnk_rollup_wsg(mock_conn(), aoi = "MORR", species = character(0)),
    "species")
  expect_error(
    lnk_rollup_wsg(mock_conn(), aoi = "MORR", species = ""),
    "species")
  # Injection-shaped species suffix must be rejected before it reaches SQL.
  expect_error(
    lnk_rollup_wsg(mock_conn(), aoi = "MORR", species = "co; DROP TABLE x"),
    "species")
  expect_error(
    lnk_rollup_wsg(mock_conn(), aoi = "MORR", species = "co_1"),
    "species")
})

test_that("lnk_rollup_wsg rejects schema outside the SQL identifier whitelist", {
  expect_error(
    lnk_rollup_wsg(mock_conn(), aoi = "MORR", species = "CO",
                   schema = "Fresh"),                       # mixed case
    "schema")
  expect_error(
    lnk_rollup_wsg(mock_conn(), aoi = "MORR", species = "CO",
                   schema = "x; DROP SCHEMA public CASCADE"),
    "schema")
  expect_error(
    lnk_rollup_wsg(mock_conn(), aoi = "MORR", species = "CO",
                   schema = "1bad"),                        # leading digit
    "schema")
})

test_that("lnk_rollup_wsg rejects unnamed metrics", {
  expect_error(
    lnk_rollup_wsg(mock_conn(), aoi = "MORR", species = "CO",
                   metrics = c("COUNT(*)")),
    "metrics")
})

# ---------------------------------------------------------------------------
# SQL construction (offline, via DBI::ANSI() for standard-SQL quoting)
# ---------------------------------------------------------------------------

test_that(".lnk_rollup_wsg_sql builds one UNION ALL branch per species", {
  metrics <- c(
    accessible_km =
      "round(sum(length_metre) FILTER (WHERE access IN (1, 2))::numeric / 1000, 2)", # nolint: line_length_linter
    spawning_km = "round(sum(length_metre) FILTER (WHERE spawning)::numeric / 1000, 2)") # nolint: line_length_linter

  sql <- link:::.lnk_rollup_wsg_sql(
    conn = DBI::ANSI(), aoi = "MORR", species = c("CO", "BT"),
    schema = "fresh", metrics = metrics, where = NULL)

  # Per-species table + access column, correctly lower-cased.
  expect_match(sql, "fresh\\.streams_habitat_co", fixed = FALSE)
  expect_match(sql, "fresh\\.streams_habitat_bt", fixed = FALSE)
  expect_match(sql, "a\\.access_co AS access")
  expect_match(sql, "a\\.access_bt AS access")
  # species_code literal upper-cased.
  expect_match(sql, "'CO' AS species_code")
  expect_match(sql, "'BT' AS species_code")
  # One UNION ALL joining the two branches.
  # Species branches join on a line of their own; the waterbody join's
  # UNION ALLs are inline.
  expect_equal(lengths(regmatches(sql, gregexpr("\n\\s*UNION ALL\n", sql))), 1L)
  # Full-PK join (#203) on both access and habitat.
  expect_match(sql, "s\\.watershed_group_code = a\\.watershed_group_code")
  expect_match(sql, "s\\.watershed_group_code = h\\.watershed_group_code")
  # streams_access is LEFT-joined (optional) so habitat length is never
  # dropped when access is unbuilt; habitat is an inner join.
  expect_match(sql, "LEFT JOIN fresh\\.streams_access")
  expect_match(sql, "JOIN fresh\\.streams_habitat_co")
  # Metric aliases + grouping.
  expect_match(sql, "AS accessible_km")
  expect_match(sql, "AS spawning_km")
  expect_match(sql, "GROUP BY watershed_group_code, species_code")
  # aoi literal bound.
  expect_match(sql, "'MORR'")
})

test_that(".lnk_rollup_wsg_sql appends an optional where predicate", {
  metrics <- c(n = "COUNT(*)")

  sql_no_where <- link:::.lnk_rollup_wsg_sql(
    conn = DBI::ANSI(), aoi = "MORR", species = "CO",
    schema = "fresh", metrics = metrics, where = NULL)
  expect_false(grepl("access IN \\(1, 2\\)", sql_no_where))

  sql_where <- link:::.lnk_rollup_wsg_sql(
    conn = DBI::ANSI(), aoi = "MORR", species = "CO",
    schema = "fresh", metrics = metrics, where = "access IN (1, 2)")
  # Outer WHERE on the aggregated subquery, before GROUP BY.
  expect_match(sql_where, "per_species\\s*\\n\\s*WHERE access IN \\(1, 2\\)")
})

# ---------------------------------------------------------------------------
# Waterbody class: stream / lake / wetland by polygon (#310)
# ---------------------------------------------------------------------------

test_that(".lnk_rollup_wsg_sql exposes each line's waterbody class", {
  sql <- link:::.lnk_rollup_wsg_sql(
    conn = DBI::ANSI(), aoi = "MORR", species = c("CO", "BT"),
    schema = "fresh",
    metrics = c(n = "count(*) FILTER (WHERE waterbody = 'lake')"),
    where = NULL)
  # One join per species branch, on the polygon tables fresh reads.
  n_join <- gregexpr("\\) wb ON wb\\.waterbody_key = s\\.waterbody_key", sql)
  expect_equal(lengths(regmatches(sql, n_join)), 2L)
  expect_false(grepl("fwa_waterbodies", sql))
  expect_equal(lengths(regmatches(sql, gregexpr("AS waterbody,", sql))), 2L)
})

test_that("waterbody class: lakes and reservoirs are lake, river polygons stream", {
  j <- link:::.lnk_sql_waterbody_join()
  expect_match(j, "'lake' AS waterbody\\s+FROM whse_basemapping\\.fwa_lakes_poly")
  expect_match(j, "'lake'\\s+FROM whse_basemapping\\.fwa_manmade_waterbodies_poly")
  expect_match(j, "'wetland'\\s+FROM whse_basemapping\\.fwa_wetlands_poly")
  expect_false(grepl("rivers_poly", j))
  expect_identical(link:::.lnk_sql_waterbody_class(),
                   "COALESCE(wb.waterbody, 'stream')")
})

# ---------------------------------------------------------------------------
# Lake connection lines: in `rearing`, out of the km (#317)
# ---------------------------------------------------------------------------

test_that("a lake connection line is a lake-polygon line on edge 1450", {
  p <- link:::.lnk_sql_lake_connection()
  expect_identical(
    p, paste0("COALESCE(COALESCE(wb.waterbody, 'stream') = 'lake' ",
              "AND s.edge_type = 1450, FALSE)"))
  # Connectors only, in lakes: construction flow lines (1200, and 1400
  # "other flow / inferred connection") and wetland lines are not it.
  expect_false(grepl("1200", p))
  expect_false(grepl("1400", p))
  expect_false(grepl("wetland", p))
})

test_that(".lnk_rollup_wsg_sql exposes each line's lake-connection flag", {
  sql <- link:::.lnk_rollup_wsg_sql(
    conn = DBI::ANSI(), aoi = "MORR", species = c("CO", "BT"),
    schema = "fresh",
    metrics = c(n = "count(*) FILTER (WHERE connection)"),
    where = NULL)
  expect_equal(lengths(regmatches(sql, gregexpr("AS connection,", sql))), 2L)
  expect_match(sql, link:::.lnk_sql_lake_connection(), fixed = TRUE)
})

test_that("default rearing_km leaves connection lines out, reported apart", {
  # One meaning of rearing_km in every output (#319): the compare family,
  # the validator's cost and the parity scripts all leave lake connection
  # lines out and carry them as rearing_lake_connection_km.
  m <- eval(formals(lnk_rollup_wsg)$metrics)
  expect_identical(names(m), c("accessible_km", "spawning_km", "rearing_km",
                               "rearing_lake_connection_km"))
  expect_match(m[["rearing_km"]],
               "FILTER (WHERE rearing AND NOT connection)::", fixed = TRUE)
  expect_match(m[["rearing_lake_connection_km"]],
               "FILTER (WHERE rearing AND connection)", fixed = TRUE)
  # 0, not NULL, where a group has no connection lines, so the two always
  # sum to the flag total.
  expect_match(m[["rearing_lake_connection_km"]], "COALESCE(", fixed = TRUE)
  # Access and spawning are unchanged.
  acc <- "round(sum(length_metre) FILTER (WHERE access IN (1, 2))::numeric / 1000, 2)"
  spawn <- "round(sum(length_metre) FILTER (WHERE spawning)::numeric / 1000, 2)"
  expect_identical(m[["accessible_km"]], acc)
  expect_identical(m[["spawning_km"]], spawn)
})

test_that("lake hectares read lake and reservoir polygons", {
  polys <- link:::.lnk_sql_lake_polys()
  expect_match(polys, "fwa_lakes_poly")
  expect_match(polys, "fwa_manmade_waterbodies_poly")
})

test_that("stream + lake + wetland rearing km equal rearing km (live)", {
  conn <- skip_if_no_db()
  has <- DBI::dbGetQuery(conn, "
    SELECT count(*) AS n FROM information_schema.tables
     WHERE table_schema = 'fresh_default'
       AND table_name IN ('streams', 'streams_habitat_bt', 'streams_access')")
  skip_if_not(has$n == 3L, "fresh_default not persisted here")
  # A group with BT rearing inside a polygon, so a fan-out would show.
  aoi <- DBI::dbGetQuery(conn, "
    SELECT s.watershed_group_code
      FROM fresh_default.streams s
      JOIN fresh_default.streams_habitat_bt h
        ON s.id_segment = h.id_segment
       AND s.watershed_group_code = h.watershed_group_code
     WHERE h.rearing AND s.waterbody_key IN (
       SELECT waterbody_key FROM whse_basemapping.fwa_wetlands_poly)
     LIMIT 1")$watershed_group_code
  skip_if(length(aoi) == 0L, "no BT rearing inside a polygon persisted")
  m <- function(w) {
    sprintf("sum(length_metre) FILTER (WHERE rearing%s)", w)
  }
  r <- lnk_rollup_wsg(conn, aoi = aoi, species = "BT",
                      schema = "fresh_default",
                      metrics = c(total = m(""),
                                  rearing = m(" AND NOT connection"),
                                  stream = m(" AND waterbody = 'stream'"),
                                  lake = m(" AND waterbody = 'lake' AND NOT connection"), # nolint: line_length_linter
                                  wetland = m(" AND waterbody = 'wetland'"),
                                  connection = m(" AND connection")))
  # The three classes partition rearing km, which leaves connection lines
  # out (#317); adding them back gives every line flagged `rearing`.
  parts <- sum(r$stream, r$lake, r$wetland, na.rm = TRUE)
  expect_equal(parts, r$rearing, tolerance = 1e-9)
  expect_equal(sum(r$rearing, r$connection, na.rm = TRUE), r$total,
               tolerance = 1e-9)
  # The join must not fan out: the total equals the sum with no polygon join.
  direct <- DBI::dbGetQuery(conn, sprintf("
    SELECT sum(s.length_metre) AS m
      FROM fresh_default.streams s
      JOIN fresh_default.streams_habitat_bt h
        ON s.id_segment = h.id_segment
       AND s.watershed_group_code = h.watershed_group_code
     WHERE s.watershed_group_code = '%s' AND h.rearing", aoi))$m
  expect_equal(r$total, as.numeric(direct), tolerance = 1e-9)
  # The default metrics split the same flag total in two (#319).
  d <- lnk_rollup_wsg(conn, aoi = aoi, species = "BT",
                      schema = "fresh_default")
  # Each column is rounded to 0.01 km, so the sum is within 0.01 km.
  expect_lt(abs(sum(d$rearing_km, d$rearing_lake_connection_km,
                    na.rm = TRUE) - r$total / 1000), 0.0101)
})
