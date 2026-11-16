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

test_that("observation counts are distinct, so a repeated barrier position counts each record once", {
  # natural_barriers can hold one position twice (link#367); each copy joins
  # the same observations, and a plain count would credit a record per copy.
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
    conn = "mock", barriers = "working.natural_barriers",
    observations = "bcfishobs.observations", control = NULL,
    params = .stub_params(), to = "working.barrier_overrides", verbose = FALSE
  )
  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "HAVING count(DISTINCT o.observation_key) >=", fixed = TRUE)
  expect_no_match(joined, "HAVING count(o.observation_key)", fixed = TRUE)
})

test_that("habitat override path is NOT gated by control (bcfishpass parity)", {
  # bcfishpass's hab_upstr CTE has no control join. Expert-confirmed
  # habitat is higher-trust than observations; the control table does not
  # block it. Any drift here would silently under-override bcfishpass.
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

  habitat_sql <- captured[grepl("working.user_habitat_classification h",
    captured, fixed = TRUE)]
  expect_true(length(habitat_sql) >= 1)
  habitat_joined <- paste(habitat_sql, collapse = "\n")
  expect_no_match(habitat_joined, "NOT EXISTS")
  expect_no_match(habitat_joined, "barriers_definite_control")
  expect_no_match(habitat_joined, "c\\.barrier_ind::boolean")
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

  # Each species builds its (barrier, record) pairs, then inserts its lifts
  # from them (link#434). BT's pairs should have no NOT EXISTS; CH's should.
  # Each pairs statement is tied to its species by the INSERT that follows.
  pairs_i <- grep("CREATE TEMP TABLE lnk_bo_pairs", captured, fixed = TRUE)
  expect_length(pairs_i, 2L)
  species_of <- vapply(pairs_i, function(i) {
    ins <- captured[(i + 1):length(captured)]
    ins <- ins[grepl("FROM pg_temp.lnk_bo_pairs o", ins, fixed = TRUE)][1]
    sub("^.*downstream_route_measure, '([A-Z]+)'.*$", "\\1", gsub("\n", " ", ins))
  }, character(1))
  expect_identical(species_of, c("BT", "CH"))
  expect_no_match(captured[pairs_i[1]], "NOT EXISTS")
  expect_match(captured[pairs_i[2]], "NOT EXISTS", fixed = TRUE)
})

test_that("each lift's evidence lists the records that met the rule, once each (DB, #434)", {
  skip_if_no_db()
  conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                      user = "postgres", password = "postgres")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  ex <- function(sql) DBI::dbExecute(conn, sql)
  s <- "zz_lnk_bo_evidence_test"
  ex(sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
  ex(sprintf("CREATE SCHEMA %s", s))
  on.exit(ex(sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s)), add = TRUE,
          after = FALSE)
  # Barrier A (line 10 at 100) is held twice, as natural_barriers can hold a
  # position (link#367); barrier B is on line 10 at 900.
  ex(sprintf("CREATE TABLE %s.nb (blue_line_key int,
                downstream_route_measure float8, wscode_ltree ltree,
                localcode_ltree ltree, label text)", s))
  ex(sprintf("INSERT INTO %s.nb VALUES
                (10, 100, '100.200', '100.200', 'x'),
                (10, 100, '100.200', '100.200', 'x'),
                (10, 900, '100.200', '100.200', 'x')", s))
  # k1 sits above A only; k2 above both and is filed as an alias that
  # counts as two species of the list (two rows, one key); k3 is too old.
  ex(sprintf("CREATE TABLE %s.obs (observation_key text,
                watershed_group_code text, species_code text,
                species_code_recorded text, observation_date date,
                blue_line_key int, downstream_route_measure float8,
                wscode ltree, localcode ltree)", s))
  ex(sprintf("INSERT INTO %s.obs VALUES
    ('k1', 'AAAA', 'XX', 'XX', '2001-01-01', 10, 500, '100.200', '100.200'),
    ('k2', 'BBBB', 'XX', 'XA', '2002-01-01', 10, 950, '100.200', '100.200'),
    ('k2', 'BBBB', 'YY', 'XA', '2002-01-01', 10, 950, '100.200', '100.200'),
    ('k3', 'AAAA', 'XX', 'XX', '1980-01-01', 10, 600, '100.200', '100.200')",
    s))
  params <- data.frame(species_code = "XX", observation_threshold = 2L,
                       observation_date_min = "1990-01-01",
                       observation_buffer_m = 20,
                       observation_species = "XX;YY",
                       observation_control_apply = FALSE,
                       stringsAsFactors = FALSE)
  lnk_barrier_overrides(conn, barriers = paste0(s, ".nb"),
                        observations = paste0(s, ".obs"), params = params,
                        to = paste0(s, ".bo"), evidence = paste0(s, ".ev"),
                        verbose = FALSE)
  bo <- DBI::dbGetQuery(conn, sprintf(
    "SELECT blue_line_key, downstream_route_measure, species_code
     FROM %s.bo", s))
  ev <- DBI::dbGetQuery(conn, sprintf(
    "SELECT downstream_route_measure, evidence, evidence_key,
            species_code_recorded, evidence_wsg, observation_threshold,
            observation_date_min, observation_species
     FROM %s.ev ORDER BY evidence_key", s))
  # A is lifted (k1 and k2, two distinct records); B has k2 alone, below 2
  expect_equal(bo$downstream_route_measure, 100)
  expect_equal(ev$downstream_route_measure, c(100, 100))
  expect_equal(ev$evidence_key, c("k1", "k2"))
  expect_equal(ev$species_code_recorded, c("XX", "XA"))
  expect_equal(ev$evidence_wsg, c("AAAA", "BBBB"))
  expect_equal(ev$observation_threshold, c(2L, 2L))
  expect_equal(ev$observation_date_min, as.Date(c("1990-01-01", "1990-01-01")))
  expect_equal(unique(ev$observation_species), "XX;YY")
  # the same lifts without evidence
  lnk_barrier_overrides(conn, barriers = paste0(s, ".nb"),
                        observations = paste0(s, ".obs"), params = params,
                        to = paste0(s, ".bo2"), verbose = FALSE)
  bo2 <- DBI::dbGetQuery(conn, sprintf(
    "SELECT blue_line_key, downstream_route_measure, species_code
     FROM %s.bo2", s))
  expect_equal(bo2, bo)
})
