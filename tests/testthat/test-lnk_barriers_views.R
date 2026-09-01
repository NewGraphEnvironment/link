test_that("lnk_barriers_views emits one CREATE per species view + 3 source views", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  cfg <- lnk_config("bcfishpass")
  lnk_barriers_views(
    structure(list(), class = "DBIConnection"),
    schema = "working_pars",
    cfg = cfg
  )

  sql <- paste(captured, collapse = "\n")

  # 8 species → CREATE for _unified AND _access (2 each = 16); plus 3 source
  # views = 3. Total 19. Was 38 before link#250 removed the redundant
  # DROP VIEW that preceded every statement.
  expect_equal(length(captured), 19L)

  # The DROP is what left a window in which the view did not exist. Assert
  # its ABSENCE, not just the lower count -- a count alone would still pass
  # if a DROP were reintroduced alongside a removed CREATE.
  expect_no_match(sql, "DROP VIEW")

  # Per-species views land under <schema>.barriers_<sp>_unified, with
  # the id alias `barriers_<sp>_unified_id` for fresh's feature_id_col
  # convention.
  expect_match(sql, "CREATE OR REPLACE VIEW working_pars\\.barriers_bt_unified AS")
  expect_match(sql, "id_barrier AS barriers_bt_unified_id")
  expect_match(sql, "WHERE 'BT' = ANY\\(blocks_species\\)")
  expect_match(sql, "CREATE OR REPLACE VIEW working_pars\\.barriers_wct_unified AS")
  expect_match(sql, "WHERE 'WCT' = ANY\\(blocks_species\\)")

  # Per-species ACCESS views (link#200): natural-only filter, definite
  # override-exemption, anti-join the province-wide barrier_overrides,
  # feature id `barriers_<sp>_access_id`.
  expect_match(sql, "CREATE OR REPLACE VIEW working_pars\\.barriers_bt_access AS")
  expect_match(sql, "id_barrier AS barriers_bt_access_id")
  expect_match(sql,
               "barrier_source IN \\('GRADIENT', 'FALLS', 'SUBSURFACE_FLOW', 'USER_DEFINITE'\\)")
  expect_match(sql, "barrier_source = 'USER_DEFINITE'")
  expect_match(sql, "FROM fresh\\.barrier_overrides o")
  expect_match(sql, "o\\.species_code = 'BT'")
  expect_match(sql, "abs\\(o\\.downstream_route_measure - b\\.downstream_route_measure\\) < 1")

  # Underlying table is the persist-schema unified table (fresh.barriers
  # for the bcfishpass bundle).
  expect_match(sql, "FROM fresh\\.barriers")

  # Source-typed views with _unified suffix.
  expect_match(sql, "CREATE OR REPLACE VIEW working_pars\\.barriers_anthropogenic_unified AS")
  expect_match(sql,
               "WHERE barrier_source IN \\('PSCIS', 'CABD', 'MODELLED_CROSSINGS'\\)")
  expect_match(sql, "CREATE OR REPLACE VIEW working_pars\\.barriers_dams_unified AS")
  expect_match(sql, "WHERE barrier_source = 'CABD'")
  expect_match(sql, "CREATE OR REPLACE VIEW working_pars\\.barriers_pscis_unified AS")
  expect_match(sql, "WHERE barrier_source = 'PSCIS'")
})

test_that("lnk_barriers_views honours a custom species set", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  cfg <- lnk_config("bcfishpass")
  lnk_barriers_views(
    structure(list(), class = "DBIConnection"),
    schema = "working_pars",
    cfg = cfg,
    species = c("BT", "SK")
  )

  sql <- paste(captured, collapse = "\n")

  # 2 species → 2 each (_unified + _access) = 4; plus 3 source views. Total 7.
  expect_equal(length(captured), 7L)
  expect_match(sql, "barriers_bt_unified")
  expect_match(sql, "barriers_bt_access")
  expect_match(sql, "barriers_sk_access")
  expect_no_match(sql, "barriers_ch_unified")
  expect_no_match(sql, "barriers_ch_access")
})

test_that("lnk_barriers_views validates argument shapes", {
  cfg <- lnk_config("bcfishpass")
  expect_error(lnk_barriers_views("not a conn", "working_pars", cfg))
  conn <- structure(list(), class = "DBIConnection")
  expect_error(lnk_barriers_views(conn, "", cfg))
  expect_error(lnk_barriers_views(conn, "working_pars", list()))
  expect_error(lnk_barriers_views(conn, "working_pars", cfg, species = character(0)))
  expect_error(lnk_barriers_views(conn, "working_pars", cfg, recreate = NA))
  expect_error(lnk_barriers_views(conn, "working_pars", cfg, recreate = "yes"))
})

test_that("recreate = TRUE restores the DROP+CREATE pair", {
  # The escape hatch for a genuine column-shape change. It must still work,
  # and it must be the ONLY way to get a DROP -- so this test is what stops
  # the default from being quietly reverted.
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  cfg <- lnk_config("bcfishpass")
  lnk_barriers_views(
    structure(list(), class = "DBIConnection"),
    schema = "working_pars",
    cfg = cfg,
    recreate = TRUE
  )

  sql <- paste(captured, collapse = "\n")

  expect_equal(length(captured), 38L)
  expect_match(sql, "DROP VIEW IF EXISTS working_pars\\.barriers_bt_access")
  expect_match(sql, "DROP VIEW IF EXISTS working_pars\\.barriers_dams_unified")
  # Every DROP is still followed by its CREATE.
  expect_equal(sum(grepl("^DROP VIEW", captured)), 19L)
  expect_equal(sum(grepl("^CREATE OR REPLACE VIEW", captured)), 19L)
})

test_that("a column-shape change errors with recreate = TRUE guidance", {
  # Postgres refuses CREATE OR REPLACE when a view's output columns change.
  # The right response is to STOP naming the escape hatch, never to fall back
  # to DROP+CREATE -- that would reintroduce the non-existence window
  # mid-fan-out, which is the whole defect link#250 removed.
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      stop("SQL execution failed:\ncannot change name of view column ",
           "\"barriers_bt_unified_id\" to \"id\"", call. = FALSE)
    }
  )
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_barriers_views(structure(list(), class = "DBIConnection"),
                       schema = "working_pars", cfg = cfg, species = "BT"),
    "recreate = TRUE"
  )
  # It must name the view that failed, not just the remedy.
  expect_error(
    lnk_barriers_views(structure(list(), class = "DBIConnection"),
                       schema = "working_pars", cfg = cfg, species = "BT"),
    "working_pars\\.barriers_bt_unified"
  )
})

test_that("an unrelated SQL error is re-raised unchanged, not relabelled", {
  # The shape-change branch must not swallow ordinary failures -- a missing
  # barriers table reported as "re-run with recreate = TRUE" would send the
  # operator to fix the wrong thing.
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      stop("SQL execution failed:\nrelation \"fresh.barriers\" does not exist",
           call. = FALSE)
    }
  )
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_barriers_views(structure(list(), class = "DBIConnection"),
                       schema = "working_pars", cfg = cfg, species = "BT"),
    "does not exist"
  )
  msg <- tryCatch(
    lnk_barriers_views(structure(list(), class = "DBIConnection"),
                       schema = "working_pars", cfg = cfg, species = "BT"),
    error = conditionMessage)
  expect_false(grepl("recreate = TRUE", msg, fixed = TRUE))
})
