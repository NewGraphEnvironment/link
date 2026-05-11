cfg_fixture <- function() {
  lnk_config("bcfishpass")
}

loaded_fixture <- function() {
  list(
    parameters_fresh = data.frame(
      species_code        = c("BT", "CH", "CM", "CO", "PK", "SK", "ST", "WCT"),
      access_gradient_max = c(0.25, 0.15, 0.15, 0.15, 0.15, 0.15, 0.20, 0.20),
      stringsAsFactors = FALSE
    )
  )
}

test_that("lnk_barriers_unify emits a UNION of anthropogenic + gradient + falls", {
  captured <- character(0)
  m_query <- mockery::mock(data.frame(x = integer(0)))  # subsurface absent
  m_quote_str <- mockery::mock(DBI::SQL("'working_pars'"), cycle = TRUE)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  with_mocked_bindings(
    dbGetQuery = m_query,
    dbQuoteString = m_quote_str,
    .package = "DBI",
    {
      lnk_barriers_unify(
        conn = structure(list(), class = "DBIConnection"),
        aoi = "PARS",
        cfg = cfg_fixture(),
        loaded = loaded_fixture(),
        schema = "working_pars"
      )
    }
  )

  sql <- paste(captured, collapse = "\n")

  # Top-level: DROP + CREATE TABLE working_pars.barriers AS <UNION>.
  expect_match(sql, "DROP TABLE IF EXISTS working_pars\\.barriers")
  expect_match(sql, "CREATE TABLE working_pars\\.barriers AS")
  expect_match(sql, "UNION ALL")

  # Anthropogenic branch — from <schema>.crossings.
  expect_match(sql, "FROM working_pars\\.crossings")
  expect_match(sql, "WHERE barrier_status IN \\('BARRIER', 'POTENTIAL'\\)")
  expect_match(sql, "crossing_source\\s+AS barrier_source")

  # Gradient branch.
  expect_match(sql, "'GRADIENT'::text\\s+AS barrier_source")
  expect_match(sql, "FROM working_pars\\.gradient_barriers_raw")
  expect_match(sql, "3000000000::bigint")

  # Falls branch.
  expect_match(sql, "'FALLS'::text\\s+AS barrier_source")
  expect_match(sql, "FROM working_pars\\.falls f")
  expect_match(sql, "4000000000::bigint")

  # Subsurface absent → no subsurface branch.
  expect_no_match(sql, "'SUBSURFACE_FLOW'")
  expect_no_match(sql, "FROM working_pars\\.barriers_subsurfaceflow")
})

test_that("lnk_barriers_unify includes subsurface_flow when staging table present", {
  captured <- character(0)
  m_query <- mockery::mock(data.frame(x = 1L))  # subsurface present
  m_quote_str <- mockery::mock(DBI::SQL("'working_pars'"), cycle = TRUE)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  with_mocked_bindings(
    dbGetQuery = m_query,
    dbQuoteString = m_quote_str,
    .package = "DBI",
    {
      lnk_barriers_unify(
        conn = structure(list(), class = "DBIConnection"),
        aoi = "PARS",
        cfg = cfg_fixture(),
        loaded = loaded_fixture(),
        schema = "working_pars"
      )
    }
  )

  sql <- paste(captured, collapse = "\n")
  expect_match(sql, "'SUBSURFACE_FLOW'::text\\s+AS barrier_source")
  expect_match(sql, "FROM working_pars\\.barriers_subsurfaceflow")
  expect_match(sql, "5000000000::bigint")
})

test_that("lnk_barriers_unify derives gradient blocks_species per class from parameters_fresh", {
  captured <- character(0)
  m_query <- mockery::mock(data.frame(x = integer(0)))
  m_quote_str <- mockery::mock(DBI::SQL("'working_pars'"), cycle = TRUE)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  with_mocked_bindings(
    dbGetQuery = m_query,
    dbQuoteString = m_quote_str,
    .package = "DBI",
    {
      lnk_barriers_unify(
        conn = structure(list(), class = "DBIConnection"),
        aoi = "PARS",
        cfg = cfg_fixture(),
        loaded = loaded_fixture(),
        schema = "working_pars"
      )
    }
  )

  sql <- paste(captured, collapse = "\n")

  # Per parameters_fresh fixture and .lnk_classes_bcfp (class 1500 ↔
  # threshold 0.15): blockers at this class are species whose
  # access_gradient_max <= 0.15 -> CH/CM/CO/PK/SK. BT (0.25),
  # ST/WCT (0.20) are NOT blockers at this class.
  expect_match(sql,
               "WHEN gradient_class = 1500 THEN ARRAY\\['CH', 'CM', 'CO', 'PK', 'SK'\\]")

  # At class 2500 (threshold 0.25), all species with access_gradient_max
  # <= 0.25 block — that's everything in our fixture (BT, ST, WCT join
  # the salmon set).
  expect_match(sql,
               "WHEN gradient_class = 2500 THEN ARRAY\\['BT', 'CH', 'CM', 'CO', 'PK', 'SK', 'ST', 'WCT'\\]")
})

test_that("lnk_barriers_unify validates argument shapes", {
  cfg <- cfg_fixture()
  loaded <- loaded_fixture()
  expect_error(lnk_barriers_unify("not a conn", "PARS", cfg, loaded))
  conn <- structure(list(), class = "DBIConnection")
  expect_error(lnk_barriers_unify(conn, "", cfg, loaded))
  expect_error(lnk_barriers_unify(conn, "PARS", list(), loaded),
               "cfg")
  expect_error(lnk_barriers_unify(conn, "PARS", cfg, list()),
               "loaded\\$parameters_fresh")
})
