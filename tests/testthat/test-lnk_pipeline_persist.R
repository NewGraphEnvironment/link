# Tests for lnk_pipeline_persist — SQL emission shape (mocked DB)

# Mock DBI helpers shared across tests — barriers staging-table probe
# returns "absent" by default so legacy tests don't see the new
# barriers DELETE/INSERT branch.
mock_dbi_no_barriers <- function() {
  with(list(), {
    list(
      dbGetQuery    = function(...) data.frame(x = integer(0)),
      dbQuoteString = function(...) DBI::SQL("'x'")
    )
  })
}

test_that("lnk_pipeline_persist emits DELETE+INSERT for streams + each species", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  m <- mock_dbi_no_barriers()
  with_mocked_bindings(
    dbGetQuery = m$dbGetQuery, dbQuoteString = m$dbQuoteString,
    .package = "DBI",
    {
      cfg <- lnk_config("bcfishpass")
      lnk_pipeline_persist(
        structure(list(), class = "DBIConnection"),
        aoi = "LRDO", cfg = cfg, species = c("BT", "SK"))
    }
  )

  joined <- paste(captured, collapse = "\n")

  # streams: DELETE + INSERT pair, scoped to LRDO
  expect_match(joined, "DELETE FROM fresh\\.streams WHERE watershed_group_code = 'LRDO'")
  expect_match(joined, "INSERT INTO fresh\\.streams \\(.*id_segment.*watershed_group_code.*geom.*\\)")
  expect_match(joined, "FROM working_lrdo\\.streams")

  # streams_habitat_<sp>: one DELETE+INSERT pair per species (lowercased)
  expect_match(joined, "DELETE FROM fresh\\.streams_habitat_bt WHERE watershed_group_code = 'LRDO'")
  expect_match(joined, "DELETE FROM fresh\\.streams_habitat_sk WHERE watershed_group_code = 'LRDO'")
  expect_match(joined, "INSERT INTO fresh\\.streams_habitat_bt")
  expect_match(joined, "INSERT INTO fresh\\.streams_habitat_sk")

  # Long->wide pivot: per-species INSERT filters working_<aoi>.streams_habitat
  # by species_code, and projects only cols_habitat (no species_code in SELECT)
  expect_match(joined,
    "INSERT INTO fresh\\.streams_habitat_bt \\(id_segment, watershed_group_code, accessible, spawning, rearing, lake_rearing, wetland_rearing\\)\\s+SELECT id_segment, watershed_group_code, accessible, spawning, rearing, lake_rearing, wetland_rearing FROM working_lrdo\\.streams_habitat WHERE species_code = 'BT'")
})

test_that("lnk_pipeline_persist counts: 2 streams ops + 2 ops per species", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  m <- mock_dbi_no_barriers()
  with_mocked_bindings(
    dbGetQuery = m$dbGetQuery, dbQuoteString = m$dbQuoteString,
    .package = "DBI",
    {
      cfg <- lnk_config("bcfishpass")
      lnk_pipeline_persist(
        structure(list(), class = "DBIConnection"),
        aoi = "ADMS", cfg = cfg, species = c("BT", "CH", "SK"))
    }
  )

  # 2 (streams DELETE+INSERT) + 2 * 3 (per-species DELETE+INSERT) = 8
  # (barriers branch skipped — probe returned absent)
  expect_equal(length(captured), 8L)
})

test_that("lnk_pipeline_persist input validation", {
  cfg <- lnk_config("bcfishpass")
  expect_error(lnk_pipeline_persist("c", aoi = "", cfg = cfg, species = "BT"),
               "aoi must be a single non-empty WSG code")
  expect_error(lnk_pipeline_persist("c", aoi = "LRDO", cfg = list(), species = "BT"),
               "cfg must be an lnk_config object")
  expect_error(lnk_pipeline_persist("c", aoi = "LRDO", cfg = cfg, species = character(0)),
               "species must be a non-empty character vector")
})

test_that("lnk_pipeline_persist accepts non-default schema", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  m <- mock_dbi_no_barriers()
  with_mocked_bindings(
    dbGetQuery = m$dbGetQuery, dbQuoteString = m$dbQuoteString,
    .package = "DBI",
    {
      cfg <- lnk_config("bcfishpass")
      lnk_pipeline_persist(
        structure(list(), class = "DBIConnection"),
        aoi = "LRDO", cfg = cfg, species = "BT", schema = "working_custom")
    }
  )

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "FROM working_custom\\.streams")
  expect_match(joined, "FROM working_custom\\.streams_habitat WHERE species_code = 'BT'")
})

test_that("lnk_pipeline_persist persists barriers when staging table present", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  # Probe returns one row → <schema>.barriers exists.
  with_mocked_bindings(
    dbGetQuery    = function(...) data.frame(x = 1L),
    dbQuoteString = function(...) DBI::SQL("'working_pars'"),
    .package = "DBI",
    {
      cfg <- lnk_config("bcfishpass")
      lnk_pipeline_persist(
        structure(list(), class = "DBIConnection"),
        aoi = "PARS", cfg = cfg, species = "BT")
    }
  )

  joined <- paste(captured, collapse = "\n")
  expect_match(joined,
               "DELETE FROM fresh\\.barriers WHERE watershed_group_code = 'PARS'")
  expect_match(joined,
               "INSERT INTO fresh\\.barriers \\(id_barrier, watershed_group_code,.*blocks_species.*geom\\)\\s+SELECT id_barrier, watershed_group_code,.*\\s+FROM working_pars\\.barriers")
})

test_that("lnk_pipeline_persist persists barrier_overrides when staging table present", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  # Probe returns one row → <schema>.barrier_overrides exists.
  with_mocked_bindings(
    dbGetQuery    = function(...) data.frame(x = 1L),
    dbQuoteString = function(...) DBI::SQL("'working_pars'"),
    .package = "DBI",
    {
      cfg <- lnk_config("bcfishpass")
      lnk_pipeline_persist(
        structure(list(), class = "DBIConnection"),
        aoi = "PARS", cfg = cfg, species = "BT")
    }
  )

  joined <- paste(captured, collapse = "\n")
  # DELETE-WHERE-WSG + INSERT; working table lacks watershed_group_code so
  # the AOI is injected as a literal in the SELECT projection (link#200).
  expect_match(joined,
               "DELETE FROM fresh\\.barrier_overrides WHERE watershed_group_code = 'PARS'")
  expect_match(joined,
               "INSERT INTO fresh\\.barrier_overrides \\(blue_line_key, downstream_route_measure, species_code, watershed_group_code\\)\\s+SELECT blue_line_key, downstream_route_measure, species_code, 'PARS'::varchar\\(4\\) FROM working_pars\\.barrier_overrides")
})

test_that("lnk_pipeline_persist skips barrier_overrides branch when staging table absent", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  m <- mock_dbi_no_barriers()
  with_mocked_bindings(
    dbGetQuery = m$dbGetQuery, dbQuoteString = m$dbQuoteString,
    .package = "DBI",
    {
      cfg <- lnk_config("bcfishpass")
      lnk_pipeline_persist(
        structure(list(), class = "DBIConnection"),
        aoi = "PARS", cfg = cfg, species = "BT")
    }
  )
  joined <- paste(captured, collapse = "\n")
  expect_no_match(joined, "fresh\\.barrier_overrides")
})

test_that("lnk_pipeline_persist skips barriers branch when staging table absent", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  m <- mock_dbi_no_barriers()
  with_mocked_bindings(
    dbGetQuery = m$dbGetQuery, dbQuoteString = m$dbQuoteString,
    .package = "DBI",
    {
      cfg <- lnk_config("bcfishpass")
      lnk_pipeline_persist(
        structure(list(), class = "DBIConnection"),
        aoi = "PARS", cfg = cfg, species = "BT")
    }
  )
  joined <- paste(captured, collapse = "\n")
  expect_no_match(joined, "DELETE FROM fresh\\.barriers")
  expect_no_match(joined, "INSERT INTO fresh\\.barriers")
})
