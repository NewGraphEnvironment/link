# -- identifier validation ---------------------------------------------------

test_that("lnk_pipeline_setup rejects invalid schema names", {
  expect_error(
    lnk_pipeline_setup("mock-conn", schema = "bad;name"),
    "schema"
  )
  expect_error(
    lnk_pipeline_setup("mock-conn", schema = ""),
    "schema"
  )
})

# -- SQL shape (mocked) ------------------------------------------------------

test_that("lnk_pipeline_setup creates working and fresh schemas", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  lnk_pipeline_setup("mock-conn", schema = "working_bulk")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "CREATE SCHEMA IF NOT EXISTS working_bulk")
  expect_match(joined, "CREATE SCHEMA IF NOT EXISTS fresh")
  expect_false(any(grepl("DROP SCHEMA", captured)))
})

test_that("lnk_pipeline_setup drops schema CASCADE when overwrite is TRUE", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  lnk_pipeline_setup("mock-conn",
    schema = "working_bulk", overwrite = TRUE)

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "DROP SCHEMA IF EXISTS working_bulk CASCADE")
  expect_match(joined, "CREATE SCHEMA IF NOT EXISTS working_bulk")
  # DROP precedes CREATE for the target schema
  drop_idx <- which(grepl("DROP SCHEMA IF EXISTS working_bulk", captured))[1]
  create_idx <- which(grepl("CREATE SCHEMA IF NOT EXISTS working_bulk",
                             captured))[1]
  expect_lt(drop_idx, create_idx)
})

# Live DB verification is redundant: the mocked tests validate SQL shape,
# and Postgres's CREATE SCHEMA / DROP SCHEMA behavior is not under test.
# Schema setup failures will surface immediately in _targets.R if they happen.
