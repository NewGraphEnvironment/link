# -- ctrl_filter honours barrier_ind (mocked SQL) -----------------------------

# The ctrl_where / ctrl_filter pattern appears inside both the
# observation-based override SQL and the habitat-based override SQL. These
# tests capture the rendered SQL and assert the filter shape.

.stub_params <- function() {
  data.frame(
    species_code = "BT",
    observation_threshold = 1L,
    observation_date_min = "2000-01-01",
    observation_buffer_m = 20,
    observation_species = "BT",
    stringsAsFactors = FALSE
  )
}

test_that("lnk_barrier_overrides honours barrier_ind = true via NOT EXISTS", {
  captured <- character(0)
  local_mocked_bindings(
    dbExecute = function(conn, sql, ...) {
      captured <<- c(captured, sql)
      1L
    },
    dbGetQuery = function(conn, sql, ...) {
      if (grepl("information_schema.columns", sql)) {
        return(data.frame(
          column_name = c("blue_line_key", "wscode_ltree", "localcode_ltree"),
          stringsAsFactors = FALSE))
      }
      if (grepl("SELECT count", sql, ignore.case = TRUE)) {
        return(data.frame(count = 0L))
      }
      data.frame()
    },
    .package = "DBI"
  )

  lnk_barrier_overrides(
    conn = "mock",
    barriers = "working.natural_barriers",
    observations = "bcfishobs.observations",
    control = "working.barriers_definite_control",
    params = .stub_params(),
    to = "working.barrier_overrides",
    verbose = FALSE
  )

  joined <- paste(captured, collapse = "\n")
  # NOT EXISTS subquery in WHERE, not a LEFT JOIN in FROM
  expect_match(joined, "AND NOT EXISTS",           fixed = TRUE)
  expect_match(joined, "FROM working.barriers_definite_control c",
    fixed = TRUE)
  expect_match(joined, "c.barrier_ind::boolean = true",
    fixed = TRUE)
  expect_no_match(joined, "LEFT JOIN.*barriers_definite_control")
})

test_that("lnk_barrier_overrides omits ctrl_filter when control is NULL", {
  captured <- character(0)
  local_mocked_bindings(
    dbExecute = function(conn, sql, ...) {
      captured <<- c(captured, sql)
      1L
    },
    dbGetQuery = function(conn, sql, ...) {
      if (grepl("information_schema.columns", sql)) {
        return(data.frame(
          column_name = c("blue_line_key", "wscode_ltree", "localcode_ltree"),
          stringsAsFactors = FALSE))
      }
      if (grepl("SELECT count", sql, ignore.case = TRUE)) {
        return(data.frame(count = 0L))
      }
      data.frame()
    },
    .package = "DBI"
  )

  lnk_barrier_overrides(
    conn = "mock",
    barriers = "working.natural_barriers",
    observations = "bcfishobs.observations",
    control = NULL,
    params = .stub_params(),
    to = "working.barrier_overrides",
    verbose = FALSE
  )

  joined <- paste(captured, collapse = "\n")
  expect_no_match(joined, "NOT EXISTS.*barriers_definite_control")
  expect_no_match(joined, "LEFT JOIN.*barriers_definite_control")
  expect_no_match(joined, "c\\.barrier_ind::boolean")
})

test_that("lnk_barrier_overrides control filter applies to habitat overrides too", {
  captured <- character(0)
  local_mocked_bindings(
    dbExecute = function(conn, sql, ...) {
      captured <<- c(captured, sql)
      1L
    },
    dbGetQuery = function(conn, sql, ...) {
      if (grepl("information_schema.columns", sql)) {
        return(data.frame(
          column_name = c("blue_line_key", "wscode_ltree", "localcode_ltree"),
          stringsAsFactors = FALSE))
      }
      if (grepl("SELECT count", sql, ignore.case = TRUE)) {
        return(data.frame(count = 0L))
      }
      data.frame()
    },
    .package = "DBI"
  )

  # No observations; habitat path only
  lnk_barrier_overrides(
    conn = "mock",
    barriers = "working.natural_barriers",
    observations = NULL,
    habitat = "working.user_habitat_classification",
    control = "working.barriers_definite_control",
    params = .stub_params(),
    to = "working.barrier_overrides",
    verbose = FALSE
  )

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "AND NOT EXISTS", fixed = TRUE)
  expect_match(joined,
    "FROM working.barriers_definite_control c", fixed = TRUE)
  expect_match(joined, "c.barrier_ind::boolean = true", fixed = TRUE)
  # habitat-only path uses habitat-specific SQL (confirm we're in that
  # branch by checking for the habitat join pattern)
  expect_match(joined,
    "working.user_habitat_classification h", fixed = TRUE)
})
