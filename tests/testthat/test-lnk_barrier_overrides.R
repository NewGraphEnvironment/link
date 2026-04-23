# -- ctrl_filter honours barrier_ind (mocked SQL) -----------------------------

# The ctrl_where / ctrl_filter pattern appears inside both the
# observation-based override SQL and the habitat-based override SQL. These
# tests capture the rendered SQL and assert the filter shape.

.stub_params <- function(control_apply = TRUE) {
  data.frame(
    species_code = "BT",
    observation_threshold = 1L,
    observation_date_min = "2000-01-01",
    observation_buffer_m = 20,
    observation_species = "BT",
    observation_control_apply = control_apply,
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

# -- per-species control gate (observation_control_apply) --------------------

test_that("ctrl_filter omitted when observation_control_apply = FALSE", {
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
    habitat = "working.user_habitat_classification",
    control = "working.barriers_definite_control",
    params = .stub_params(control_apply = FALSE),
    to = "working.barrier_overrides",
    verbose = FALSE
  )

  joined <- paste(captured, collapse = "\n")
  # Control is declared at call site, but this species opts out.
  expect_no_match(joined, "NOT EXISTS.*barriers_definite_control")
  expect_no_match(joined, "c\\.barrier_ind::boolean")
})

test_that("ctrl_filter omitted when observation_control_apply = NA", {
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
    params = .stub_params(control_apply = NA),
    to = "working.barrier_overrides",
    verbose = FALSE
  )

  joined <- paste(captured, collapse = "\n")
  expect_no_match(joined, "NOT EXISTS.*barriers_definite_control")
  expect_no_match(joined, "c\\.barrier_ind::boolean")
})

test_that("ctrl_filter gated per-species across mixed params", {
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

  mixed_params <- data.frame(
    species_code = c("BT", "CH"),
    observation_threshold = c(1L, 5L),
    observation_date_min = c("1990-01-01", "1990-01-01"),
    observation_buffer_m = c(20, 20),
    observation_species = c("BT;CH", "CH;CM;CO;PK;SK"),
    observation_control_apply = c(FALSE, TRUE),
    stringsAsFactors = FALSE
  )

  lnk_barrier_overrides(
    conn = "mock",
    barriers = "working.natural_barriers",
    observations = "bcfishobs.observations",
    control = "working.barriers_definite_control",
    params = mixed_params,
    to = "working.barrier_overrides",
    verbose = FALSE
  )

  # Two per-species INSERTs were emitted. BT's should have no NOT EXISTS;
  # CH's should. Identify by the species-code literal in SELECT.
  bt_sql <- captured[grepl("SELECT b.blue_line_key, b.downstream_route_measure, 'BT'",
    captured, fixed = TRUE)]
  ch_sql <- captured[grepl("SELECT b.blue_line_key, b.downstream_route_measure, 'CH'",
    captured, fixed = TRUE)]
  expect_true(length(bt_sql) >= 1)
  expect_true(length(ch_sql) >= 1)
  expect_no_match(paste(bt_sql, collapse = "\n"), "NOT EXISTS")
  expect_match(paste(ch_sql, collapse = "\n"), "NOT EXISTS", fixed = TRUE)
})
