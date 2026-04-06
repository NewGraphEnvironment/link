# --- lnk_override_load: CSV validation (no DB needed) ---

test_that("override_load errors on non-character csv", {
  expect_error(lnk_override_load(NULL, csv = 42, to = "t"), "character vector")
})

test_that("override_load errors on empty csv vector", {
  expect_error(
    lnk_override_load(NULL, csv = character(0), to = "t"),
    "character vector"
  )
})

test_that("override_load errors on missing file", {
  expect_error(
    lnk_override_load(NULL, csv = "/no/such/file.csv", to = "t"),
    "not found"
  )
})

test_that("override_load errors on multiple missing files", {
  expect_error(
    lnk_override_load(NULL, csv = c("/no/a.csv", "/no/b.csv"), to = "t"),
    "a\\.csv.*b\\.csv"
  )
})

test_that("override_load validates destination table name", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines("modelled_crossing_id,barrier_result_code\n1001,BARRIER", tmp)
  expect_error(
    lnk_override_load(NULL, csv = tmp, to = "bad;table"),
    "disallowed"
  )
})

# --- lnk_override_load: CSV structure validation (DB needed) ---

test_that("override_load rejects CSV missing required columns", {
  conn <- skip_if_no_db()
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines("wrong_id,barrier_result_code\n1001,BARRIER", tmp)

  expect_error(
    lnk_override_load(
      conn, csv = tmp, to = "working.test_overrides",
      cols_id = "modelled_crossing_id"
    ),
    "missing required columns.*modelled_crossing_id"
  )
})

test_that("override_load rejects CSV missing cols_required", {
  conn <- skip_if_no_db()
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines("modelled_crossing_id,other_col\n1001,foo", tmp)

  expect_error(
    lnk_override_load(
      conn, csv = tmp, to = "working.test_overrides",
      cols_required = c("barrier_result_code")
    ),
    "missing required columns.*barrier_result_code"
  )
})

test_that("override_load writes to database and returns table name", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  dest <- "working.test_ol"
  on.exit(DBI::dbExecute(conn, paste("DROP TABLE IF EXISTS", dest)))

  csv_path <- system.file("extdata", "overrides_example.csv", package = "link")
  result <- lnk_override_load(conn, csv = csv_path, to = dest)

  expect_equal(result, dest)
  n <- DBI::dbGetQuery(conn, paste("SELECT count(*) FROM", dest))[[1]]
  expect_equal(n, 5L)
})

test_that("override_load appends multiple CSVs", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  dest <- "working.test_ol_multi"
  on.exit(DBI::dbExecute(conn, paste("DROP TABLE IF EXISTS", dest)))

  tmp1 <- tempfile(fileext = ".csv")
  tmp2 <- tempfile(fileext = ".csv")
  on.exit(unlink(c(tmp1, tmp2)), add = TRUE)

  writeLines(c(
    "modelled_crossing_id,barrier_result_code",
    "1001,PASSABLE",
    "1002,BARRIER"
  ), tmp1)
  writeLines(c(
    "modelled_crossing_id,barrier_result_code",
    "1003,NONE",
    "1004,PASSABLE"
  ), tmp2)

  lnk_override_load(conn, csv = c(tmp1, tmp2), to = dest)
  n <- DBI::dbGetQuery(conn, paste("SELECT count(*) FROM", dest))[[1]]
  expect_equal(n, 4L)
})

test_that("override_load with overwrite=TRUE replaces existing data", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  dest <- "working.test_ol_ow"
  on.exit(DBI::dbExecute(conn, paste("DROP TABLE IF EXISTS", dest)))

  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(c(
    "modelled_crossing_id,barrier_result_code",
    "1001,PASSABLE"
  ), tmp)

  lnk_override_load(conn, csv = tmp, to = dest)
  lnk_override_load(conn, csv = tmp, to = dest, overwrite = TRUE)
  n <- DBI::dbGetQuery(conn, paste("SELECT count(*) FROM", dest))[[1]]
  expect_equal(n, 1L)
})

test_that("override_load errors when all CSVs are empty", {
  conn <- skip_if_no_db()
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines("modelled_crossing_id,barrier_result_code", tmp)

  expect_error(
    suppressWarnings(
      lnk_override_load(conn, csv = tmp, to = "working.test_ol_empty")
    ),
    "empty"
  )
})

test_that("override_load notes missing provenance columns", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  dest <- "working.test_ol_noprov"
  on.exit(DBI::dbExecute(conn, paste("DROP TABLE IF EXISTS", dest)))

  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(c(
    "modelled_crossing_id,barrier_result_code",
    "1001,PASSABLE"
  ), tmp)

  expect_message(
    lnk_override_load(conn, csv = tmp, to = dest),
    "provenance columns not found"
  )
})
