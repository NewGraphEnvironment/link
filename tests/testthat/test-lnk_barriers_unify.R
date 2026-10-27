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
  expect_match(sql, "'GRADIENT-' \\|\\|")

  # Falls branch.
  expect_match(sql, "'FALLS'::text\\s+AS barrier_source")
  expect_match(sql, "FROM working_pars\\.falls f")
  expect_match(sql, "'FALLS-' \\|\\|")

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
  expect_match(sql, "'SUBSURFACE-' \\|\\|")
})

test_that("lnk_barriers_unify emits a USER_DEFINITE branch from barriers_definite", {
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

  # User-definite branch: own barrier_source + namespaced id, sourced from
  # <schema>.barriers_definite, ltree resolved via the FWA join (mirrors
  # FALLS + bcfp barriers_user_definite.sql). link#200.
  expect_match(sql, "'USER_DEFINITE'::text\\s+AS barrier_source")
  expect_match(sql, "FROM working_pars\\.barriers_definite d")
  expect_match(sql, "'USER_DEFINITE-' \\|\\|")
  expect_match(sql, "JOIN whse_basemapping\\.fwa_stream_networks_sp s")
  # Blocks all species in the set (the override-exempt user set is universal).
  expect_match(sql,
               "ARRAY\\['BT', 'CH', 'CM', 'CO', 'PK', 'SK', 'ST', 'WCT'\\]::text\\[\\]\\s+AS blocks_species")
  # Only blue_line_key + downstream_route_measure referenced from `d`
  # (empty-fallback shape safety) — no d.wscode_ltree / d.barrier_type.
  expect_no_match(sql, "d\\.wscode_ltree")
  expect_no_match(sql, "d\\.barrier_type")
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

test_that("every barrier id is numbered in a stated order (link#367)", {
  # row_number() OVER () numbers rows in scan order, so two builds from the
  # same inputs could give a barrier different ids (link#277).
  src <- paste(deparse(lnk_barriers_unify), collapse = "\n")
  expect_false(grepl("row_number() OVER ()", src, fixed = TRUE))
  n_numbered <- lengths(regmatches(src, gregexpr("row_number() OVER (", src, fixed = TRUE)))
  expect_identical(n_numbered, 4L)
  # Falls and user-definite rows join FWA segments, and a point in the ~1 mm
  # overlap between two segments joins both, so their order ends on the
  # joined linear_feature_id.
  # deparse() writes a string's newlines as a literal backslash-n.
  flat <- gsub("(\\\\n|\\s)+", " ", src)
  expect_match(flat, "f.downstream_route_measure, s.linear_feature_id", fixed = TRUE)
  expect_match(flat, "d.downstream_route_measure, s.linear_feature_id", fixed = TRUE)
})

test_that("no branch calls FWA_LocateAlong() in its SELECT list (#326)", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  with_mocked_bindings(
    dbGetQuery = mockery::mock(data.frame(x = 1L)),  # subsurface present
    dbQuoteString = mockery::mock(DBI::SQL("'working_pars'"), cycle = TRUE),
    .package = "DBI",
    lnk_barriers_unify(conn = structure(list(), class = "DBIConnection"),
                       aoi = "PARS", cfg = cfg_fixture(),
                       loaded = loaded_fixture(), schema = "working_pars")
  )
  sql <- paste(captured, collapse = "\n")
  # A set-returning call in a SELECT list drops the row when it returns none.
  expect_no_match(sql, "ST_Force2D\\(FWA_LocateAlong")
  # Gradient, falls, user-definite and subsurface each locate through it.
  expect_identical(lengths(regmatches(sql, gregexpr("FROM FWA_LocateAlong\\(", sql))), 4L)
})

test_that("a measure in FWA's segment gap still gets a point (#326)", {
  conn <- skip_if_no_db()
  # MORR blue line 360611439: segment 139051732 starts at 1153.6404 m and the
  # one below ends short of it, so FWA_LocateAlong() gives no point at 1153.64.
  gap <- DBI::dbGetQuery(conn,
    "SELECT count(*)::int AS n FROM FWA_LocateAlong(360611439, 1153.64)")$n
  skip_if(gap != 0L, "FWA here no longer has the gap this test needs")
  pts <- DBI::dbGetQuery(conn, sprintf(
    "SELECT ST_AsText(%s) AS gap_pt, ST_AsText(%s) AS mid_pt,
            ST_AsText(ST_Force2D((SELECT geom FROM FWA_LocateAlong(360611439, 1500)))) AS fwa_pt",
    .lnk_sql_locate("360611439", "1153.64"),
    .lnk_sql_locate("360611439", "1500")))
  expect_match(pts$gap_pt, "^POINT\\(")
  # Where FWA_LocateAlong() answers, the helper returns its point.
  expect_identical(pts$mid_pt, pts$fwa_pt)
})
