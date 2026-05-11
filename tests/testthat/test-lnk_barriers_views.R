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

  # 8 species → 8 DROP + 8 CREATE; plus 3 source views → 3 DROP + 3 CREATE = 22.
  expect_equal(length(captured), 22L)

  # Per-species views land under <schema>.barriers_<sp>_unified, with
  # the id alias `barriers_<sp>_unified_id` for fresh's feature_id_col
  # convention.
  expect_match(sql, "CREATE OR REPLACE VIEW working_pars\\.barriers_bt_unified AS")
  expect_match(sql, "id_barrier AS barriers_bt_unified_id")
  expect_match(sql, "WHERE 'BT' = ANY\\(blocks_species\\)")
  expect_match(sql, "CREATE OR REPLACE VIEW working_pars\\.barriers_wct_unified AS")
  expect_match(sql, "WHERE 'WCT' = ANY\\(blocks_species\\)")

  # Underlying table is the persist-schema unified table (fresh.barriers
  # for the bcfishpass bundle).
  expect_match(sql, "FROM fresh\\.barriers")

  # Source-typed views with _unified suffix.
  expect_match(sql, "CREATE OR REPLACE VIEW working_pars\\.barriers_anthropogenic_unified AS")
  expect_match(sql,
               "WHERE barrier_source IN \\('PSCIS', 'CABD', 'MODELLED'\\)")
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

  # 2 species → 2 DROP + 2 CREATE; plus 3 source views → 6 + 3 + 3 = 10.
  expect_equal(length(captured), 10L)
  expect_match(sql, "barriers_bt_unified")
  expect_match(sql, "barriers_sk_unified")
  expect_no_match(sql, "barriers_ch_unified")
})

test_that("lnk_barriers_views validates argument shapes", {
  cfg <- lnk_config("bcfishpass")
  expect_error(lnk_barriers_views("not a conn", "working_pars", cfg))
  conn <- structure(list(), class = "DBIConnection")
  expect_error(lnk_barriers_views(conn, "", cfg))
  expect_error(lnk_barriers_views(conn, "working_pars", list()))
  expect_error(lnk_barriers_views(conn, "working_pars", cfg, species = character(0)))
})
