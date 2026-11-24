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
  # (barriers branch skipped — probe returned absent; so is
  # streams_near_river, whose rows are replaced pair by pair only when the
  # working table exists, #364)
  expect_equal(length(captured), 8L)
  expect_false(any(grepl("streams_near_river", captured, fixed = TRUE)))
})

test_that("lnk_pipeline_persist input validation", {
  cfg <- lnk_config("bcfishpass")
  expect_error(lnk_pipeline_persist("c", aoi = "", cfg = cfg, species = "BT"),
               "aoi must be a single non-empty WSG code")
  expect_error(lnk_pipeline_persist("c", aoi = "LRDO", cfg = list(), species = "BT"),
               "cfg must be an lnk_config object")
  expect_error(lnk_pipeline_persist("c", aoi = "LRDO", cfg = cfg, species = 1L),
               "species must be a character vector")
})

test_that("persist with no species writes no habitat table (#432)", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  m <- mock_dbi_no_barriers()
  with_mocked_bindings(
    dbGetQuery = m$dbGetQuery, dbQuoteString = m$dbQuoteString,
    .package = "DBI",
    lnk_pipeline_persist("c", aoi = "MURT", cfg = lnk_config("default"),
                         species = character(0))
  )
  expect_true(any(grepl("INSERT INTO fresh\\.streams ", captured)))
  expect_false(any(grepl("streams_habitat_", captured)))
})

test_that(".lnk_persist_clear_unmodelled deletes only species not classified (#432)", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    },
    .lnk_table_exists = function(conn, table) FALSE
  )
  with_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) {
      data.frame(table_name = c("streams_habitat_bt", "streams_habitat_ko",
                                "streams_habitat_rb", "streams_habitat_near_river"),
                 stringsAsFactors = FALSE)
    },
    dbQuoteString = function(conn, x, ...) paste0("'", x, "'"),
    .package = "DBI",
    stale <- .lnk_persist_clear_unmodelled("c", lnk_config("default"),
                                           aoi = "KOTL", species = "BT")
  )
  expect_setequal(stale, c("ko", "rb"))
  # streams_habitat_near_river is not a species table; no near-river table
  # in this mock, so only the two habitat deletes run.
  expect_length(captured, 2L)
  expect_true(all(grepl("^DELETE FROM fresh\\.streams_habitat_(ko|rb) WHERE watershed_group_code = 'KOTL'$",
                        captured)))
})

test_that(".lnk_persist_clear_unmodelled keeps only the near-river pairs the build owns (#432)", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    },
    .lnk_table_exists = function(conn, table) table == "fresh.streams_near_river"
  )
  cfg <- lnk_config("default")
  run <- function(species) {
    captured <<- character(0)
    with_mocked_bindings(
      dbGetQuery = function(conn, sql, ...) data.frame(table_name = character(0)),
      dbQuoteString = function(conn, x, ...) paste0("'", x, "'"),
      .package = "DBI",
      .lnk_persist_clear_unmodelled("c", cfg, aoi = "MURT", species = species,
                                    schema = "w")
    )
    captured
  }
  # No species: every near-river row of the group goes.
  expect_identical(run(character(0)),
    "DELETE FROM fresh.streams_near_river WHERE watershed_group_code = 'MURT'")
  # CH reads a pair: rows outside the pairs CH's rules read go.
  sql <- run("CH")
  expect_length(sql, 1L)
  expect_match(sql, "NOT IN \\(SELECT \\* FROM \\(VALUES")
})

test_that("lnk_pipeline_persist accepts non-default schema", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
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
      captured <<- c(captured, sql)
      invisible(NULL)
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
      captured <<- c(captured, sql)
      invisible(NULL)
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
      captured <<- c(captured, sql)
      invisible(NULL)
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
      captured <<- c(captured, sql)
      invisible(NULL)
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

test_that("lnk_pipeline_persist never deletes from a log table (link#354)", {
  # The log tables are history: a group's earlier builds must survive its next
  # build. Every staging table reported present, so every DELETE branch runs.
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  with_mocked_bindings(
    dbGetQuery = function(...) data.frame(x = 1L),
    dbQuoteString = function(...) DBI::SQL("'x'"),
    .package = "DBI",
    {
      cfg <- lnk_config("bcfishpass")
      lnk_pipeline_persist(
        structure(list(), class = "DBIConnection"),
        aoi = "PARS", cfg = cfg, species = c("BT", "SK"))
    }
  )
  deletes <- grep("^\\s*DELETE FROM", captured, value = TRUE)
  # streams, one per species (2), barriers, barrier_overrides,
  # barrier_override_evidence (#434), streams_access, streams_mapping_code,
  # streams_near_river (#364).
  expect_length(deletes, 9L)
  ev_cols <- paste("blue_line_key, downstream_route_measure, species_code,",
                   "evidence, evidence_key")
  expect_true(any(grepl(
    paste0("INSERT INTO fresh.barrier_override_evidence (", ev_cols),
    captured, fixed = TRUE)))
  # every probe answered present, so the near-river rows are replaced, pair
  # by pair: a species-subset build keeps the other species' distances
  expect_true(any(grepl("INSERT INTO fresh.streams_near_river", captured,
                        fixed = TRUE)))
  del <- grep("DELETE FROM fresh.streams_near_river", captured, value = TRUE,
              fixed = TRUE)
  expect_length(del, 1L)
  expect_match(del, "(p.measure, p.threshold, p.distance_max) IN (",
               fixed = TRUE)
  targets <- sub("^\\s*DELETE FROM (\\S+).*", "\\1", deletes)
  expect_false(any(sub("^[^.]+\\.", "", targets) %in%
                     names(.lnk_log_specs())))
})

test_that("a pair that found no river still clears the group's earlier rows (#364 review)", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  # The working near-river table is absent (as when the walk found nothing
  # and classify kept none), but default's CH rules read a pair.
  m <- mock_dbi_no_barriers()
  with_mocked_bindings(
    dbGetQuery = m$dbGetQuery, dbQuoteString = m$dbQuoteString,
    .package = "DBI",
    {
      lnk_pipeline_persist(structure(list(), class = "DBIConnection"),
                           aoi = "ADMS", cfg = lnk_config("default"),
                           species = c("CH", "BT"))
    }
  )
  del <- grep("DELETE FROM fresh.streams_near_river", captured,
              value = TRUE, fixed = TRUE)
  expect_length(del, 1L)
  expect_match(del, "('channel_width', 15::double precision, 1000::double precision)",
               fixed = TRUE)
  expect_false(any(grepl("INSERT INTO fresh.streams_near_river",
                         captured, fixed = TRUE)))
  # A species with no pair clears nothing.
  captured <- character(0)
  with_mocked_bindings(
    dbGetQuery = m$dbGetQuery, dbQuoteString = m$dbQuoteString,
    .package = "DBI",
    {
      lnk_pipeline_persist(structure(list(), class = "DBIConnection"),
                           aoi = "ADMS", cfg = lnk_config("default"),
                           species = "BT")
    }
  )
  expect_false(any(grepl("streams_near_river", captured, fixed = TRUE)))
})

test_that("the delete writes a pair's numbers as fresh stores them (round 3)", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  cfg <- lnk_config("default")
  th <- utils::read.csv(cfg$files$parameters_habitat_thresholds$path,
                        check.names = FALSE, stringsAsFactors = FALSE)
  th$rear_river_channel_width_min[th$species_code == "CH"] <- 15.0412345678912
  f <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(th, f, row.names = FALSE)
  cfg$files$parameters_habitat_thresholds$path <- f
  m <- mock_dbi_no_barriers()
  with_mocked_bindings(
    dbGetQuery = m$dbGetQuery, dbQuoteString = m$dbQuoteString,
    .package = "DBI",
    lnk_pipeline_persist(structure(list(), class = "DBIConnection"),
                         aoi = "ADMS", cfg = cfg, species = "CH"))
  del <- grep("DELETE FROM fresh.streams_near_river", captured, value = TRUE,
              fixed = TRUE)
  sql_num <- utils::getFromNamespace(".frs_sql_num", "fresh")
  expect_match(del, sprintf("('channel_width', %s::double precision",
                            sql_num(15.0412345678912)), fixed = TRUE)
  # both models' pairs: width under cw, discharge under mad
  expect_match(del, "('discharge', 3::double precision", fixed = TRUE)
})


# -- one holder per position (link#386) -------------------------------------

test_that("an override or evidence row persists only beside a natural barrier the group holds (#386, DB)", {
  conn <- skip_if_no_db()
  w <- paste0("zz_lnk_t386_pw_", Sys.getpid())
  p <- paste0("zz_lnk_t386_pp_", Sys.getpid())
  for (x in c(w, p)) {
    DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", x))
  }
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", w))
  withr::defer(for (x in c(w, p)) {
    DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", x))
  })
  cfg <- lnk_config("bcfishpass")
  cfg$pipeline$schema <- p
  lnk_persist_init(conn, cfg, species = "BT")
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s.streams (LIKE %s.streams)", w, p))
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s.barriers (LIKE %s.barriers)", w, p))
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s.barrier_override_evidence (LIKE %s.barrier_override_evidence)", w, p))
  DBI::dbExecute(conn, sprintf(
    "ALTER TABLE %s.barrier_override_evidence DROP COLUMN watershed_group_code", w))
  # LSAL holds a gradient barrier at 124906.6, just below SALR's first segment
  # (124906.77), and a falls row at 50000; the user-definite row at 60000
  # cannot be lifted. Its working overrides cover the whole line: the lift at
  # 124907 (the barrier's rounded measure, on SALR's side of the boundary) is
  # kept; the lifts at 200000 (a position SALR owns) and 60000 are not.
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.barriers (id_barrier, watershed_group_code, barrier_source,
                              blue_line_key, downstream_route_measure)
     VALUES ('GRADIENT-1', 'LSAL', 'GRADIENT', 356364485, 124906.6),
            ('FALLS-1', 'LSAL', 'FALLS', 356364485, 50000),
            ('USER_DEFINITE-1', 'LSAL', 'USER_DEFINITE', 356364485, 60000)", w))
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s.barrier_overrides AS
     SELECT * FROM (VALUES (356364485, 124907::double precision, 'BT'),
                           (356364485, 50000::double precision, 'BT'),
                           (356364485, 200000::double precision, 'BT'),
                           (356364485, 60000::double precision, 'BT'))
       v(blue_line_key, downstream_route_measure, species_code)", w))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.barrier_override_evidence
       (blue_line_key, downstream_route_measure, species_code, evidence, evidence_key,
        lift_rule)
     SELECT blue_line_key, downstream_route_measure, species_code, 'observation', 'k1',
            'own'
       FROM %s.barrier_overrides", w, w))
  lnk_pipeline_persist(conn, aoi = "LSAL", cfg = cfg, species = character(0),
                       schema = w)
  got <- function(t) DBI::dbGetQuery(conn, sprintf(
    "SELECT downstream_route_measure AS m, watershed_group_code AS g
       FROM %s.%s ORDER BY 1", p, t))
  expect_equal(got("barrier_overrides")$m, c(50000, 124907))
  expect_equal(got("barrier_overrides")$g, c("LSAL", "LSAL"))
  expect_equal(got("barrier_override_evidence")$m, c(50000, 124907))
})
