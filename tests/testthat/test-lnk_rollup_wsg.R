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
  expect_equal(lengths(regmatches(sql, gregexpr("UNION ALL", sql))), 1L)
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
