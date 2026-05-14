# --- .lnk_parse_table ---

test_that("parse_table splits schema.table", {
  result <- link:::.lnk_parse_table("working.crossings")
  expect_equal(result$schema, "working")
  expect_equal(result$table, "crossings")
})

test_that("parse_table defaults to public schema", {
  result <- link:::.lnk_parse_table("crossings")
  expect_equal(result$schema, "public")
  expect_equal(result$table, "crossings")
})

test_that("parse_table errors on triple-dotted name", {
  expect_error(
    link:::.lnk_parse_table("a.b.c"),
    "Invalid table name"
  )
})

test_that("parse_table errors on empty string", {
  expect_error(
    link:::.lnk_parse_table(""),
    "Invalid table name"
  )
})

# --- .lnk_validate_identifier ---

test_that("validate_identifier accepts clean names", {
  expect_invisible(link:::.lnk_validate_identifier("crossings"))
  expect_invisible(link:::.lnk_validate_identifier("working.crossings"))
  expect_invisible(link:::.lnk_validate_identifier("col_name_123"))
})

test_that("validate_identifier rejects SQL injection attempts", {
  expect_error(
    link:::.lnk_validate_identifier("table; DROP TABLE users"),
    "disallowed"
  )
  expect_error(
    link:::.lnk_validate_identifier("table' OR '1'='1"),
    "disallowed"
  )
  expect_error(
    link:::.lnk_validate_identifier("table--comment"),
    "disallowed"
  )
  expect_error(
    link:::.lnk_validate_identifier("table/*comment*/"),
    "disallowed"
  )
  expect_error(
    link:::.lnk_validate_identifier("table(drop)"),
    "disallowed"
  )
  expect_error(
    link:::.lnk_validate_identifier("1starts_with_number"),
    "disallowed"
  )
})

test_that("validate_identifier rejects non-string input", {
  expect_error(link:::.lnk_validate_identifier(42), "non-empty string")
  expect_error(link:::.lnk_validate_identifier(NULL), "non-empty string")
  expect_error(link:::.lnk_validate_identifier(""), "non-empty string")
  expect_error(link:::.lnk_validate_identifier(c("a", "b")), "non-empty string")
})

# --- .lnk_build_where ---
# Requires DB connection for proper SQL quoting

test_that("build_where handles NULL and empty filters", {
  conn <- skip_if_no_db()
  expect_equal(link:::.lnk_build_where(conn, NULL), "")
  expect_equal(link:::.lnk_build_where(conn, list()), "")
})

test_that("build_where builds single character filter", {
  conn <- skip_if_no_db()
  result <- link:::.lnk_build_where(conn, list(status = "BARRIER"))
  expect_match(result, "WHERE")
  expect_match(result, "status")
  expect_match(result, "BARRIER")
})

test_that("build_where builds numeric filter", {
  conn <- skip_if_no_db()
  result <- link:::.lnk_build_where(conn, list(threshold = 0.6))
  expect_match(result, "WHERE")
  expect_match(result, "threshold")
  expect_match(result, "0.6")
})

test_that("build_where builds logical filter", {
  conn <- skip_if_no_db()
  result <- link:::.lnk_build_where(conn, list(active = TRUE))
  expect_match(result, "WHERE")
  expect_match(result, "active")
  expect_match(result, "TRUE")
})

test_that("build_where combines multiple filters with AND", {
  conn <- skip_if_no_db()
  result <- link:::.lnk_build_where(
    conn, list(status = "BARRIER", severity = "high")
  )
  expect_match(result, "WHERE")
  expect_match(result, "AND")
  expect_match(result, "BARRIER")
  expect_match(result, "high")
})

test_that("build_where rejects NaN and Inf", {
  conn <- skip_if_no_db()
  expect_error(
    link:::.lnk_build_where(conn, list(val = NaN)),
    "non-finite"
  )
  expect_error(
    link:::.lnk_build_where(conn, list(val = Inf)),
    "non-finite"
  )
})

test_that("build_where errors on unsupported type", {
  conn <- skip_if_no_db()
  expect_error(
    link:::.lnk_build_where(conn, list(data = as.Date("2025-01-01"))),
    "Unsupported filter type"
  )
})

test_that("build_where rejects injection in column names", {
  conn <- skip_if_no_db()
  expect_error(
    link:::.lnk_build_where(conn, list("col; DROP TABLE x" = "val")),
    "disallowed"
  )
})

# --- .lnk_merge_lists ---

test_that("merge_lists combines two named lists", {
  a <- list(x = 1, y = 2)
  b <- list(y = 3, z = 4)
  result <- link:::.lnk_merge_lists(a, b)
  expect_equal(result, list(x = 1, y = 3, z = 4))
})

test_that("merge_lists handles empty inputs", {
  expect_equal(link:::.lnk_merge_lists(list(), list(x = 1)), list(x = 1))
  expect_equal(link:::.lnk_merge_lists(list(x = 1), list()), list(x = 1))
})

# --- .lnk_wsg_persisted ---

test_that(".lnk_wsg_persisted rejects non-DBI conn", {
  expect_error(
    link:::.lnk_wsg_persisted(conn = "not-a-conn",
                              cfg = lnk_config("bcfishpass"),
                              aoi = "ADMS"),
    "DBI"
  )
})

test_that(".lnk_wsg_persisted rejects non-lnk_config cfg", {
  conn <- structure(list(), class = "DBIConnection")
  expect_error(
    link:::.lnk_wsg_persisted(conn = conn,
                              cfg = list(name = "x"),
                              aoi = "ADMS"),
    "cfg"
  )
})

test_that(".lnk_wsg_persisted rejects invalid aoi", {
  conn <- structure(list(), class = "DBIConnection")
  cfg <- lnk_config("bcfishpass")
  expect_error(
    link:::.lnk_wsg_persisted(conn, cfg, aoi = ""),
    "aoi"
  )
  expect_error(
    link:::.lnk_wsg_persisted(conn, cfg, aoi = c("ADMS", "BULK")),
    "aoi"
  )
})

test_that(".lnk_wsg_persisted returns FALSE when streams table is absent", {
  conn <- structure(list(), class = "DBIConnection")
  cfg <- lnk_config("bcfishpass")

  # Mock: information_schema returns no rows (table doesn't exist)
  m_query <- function(conn, sql) {
    if (grepl("information_schema", sql)) {
      data.frame()
    } else {
      stop("Should not reach streams query when table is absent")
    }
  }

  with_mocked_bindings(
    dbGetQuery = m_query,
    .package = "DBI",
    {
      expect_false(link:::.lnk_wsg_persisted(conn, cfg, "ADMS"))
    }
  )
})

test_that(".lnk_wsg_persisted returns TRUE when WSG has rows", {
  conn <- structure(list(), class = "DBIConnection")
  cfg <- lnk_config("bcfishpass")

  m_query <- function(conn, sql) {
    if (grepl("information_schema", sql)) {
      data.frame(x = 1L)               # table exists
    } else if (grepl("watershed_group_code", sql)) {
      data.frame(x = 1L)               # WSG has rows
    } else {
      stop("Unexpected query")
    }
  }

  with_mocked_bindings(
    dbGetQuery = m_query,
    .package = "DBI",
    {
      expect_true(link:::.lnk_wsg_persisted(conn, cfg, "ADMS"))
    }
  )
})

test_that(".lnk_wsg_persisted returns FALSE when table exists but WSG has no rows", {
  conn <- structure(list(), class = "DBIConnection")
  cfg <- lnk_config("bcfishpass")

  m_query <- function(conn, sql) {
    if (grepl("information_schema", sql)) {
      data.frame(x = 1L)               # table exists
    } else if (grepl("watershed_group_code", sql)) {
      data.frame()                      # no rows for this WSG
    } else {
      stop("Unexpected query")
    }
  }

  with_mocked_bindings(
    dbGetQuery = m_query,
    .package = "DBI",
    {
      expect_false(link:::.lnk_wsg_persisted(conn, cfg, "ADMS"))
    }
  )
})
