test_that("lnk_barriers_views emits one DROP+CREATE per species + 3 source views", {
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

  # 8 species → DROP+CREATE for _unified AND _access (4 each = 32); plus
  # 3 source views → 3 DROP + 3 CREATE = 6. Total 38.
  expect_equal(length(captured), 38L)

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

  # 2 species → 4 each (_unified + _access DROP+CREATE) = 8; plus 3 source
  # views → 6. Total 14.
  expect_equal(length(captured), 14L)
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
})
