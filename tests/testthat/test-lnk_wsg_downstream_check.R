# Tests for the downstream-state guard (link#227).

fake_conn <- function() structure(list(), class = "DBIConnection")

stub_outlets <- function() {
  data.frame(watershed_group_code = "PARS", blue_line_key = 359572348L,
             downstream_route_measure = 0, wscode_ltree = "200.948755",
             localcode_ltree = "200.948755", stringsAsFactors = FALSE)
}

# --- argument validation ----------------------------------------------------

test_that("lnk_wsg_downstream_check validates its arguments", {
  cfg <- lnk_config("bcfishpass")
  expect_error(lnk_wsg_downstream_check("nope", "PARS", cfg, list()), "DBI")
  expect_error(lnk_wsg_downstream_check(fake_conn(), "", cfg, list()), "aoi")
  expect_error(lnk_wsg_downstream_check(fake_conn(), c("A", "B"), cfg, list()), "aoi")
  expect_error(lnk_wsg_downstream_check(fake_conn(), "PARS", list(name = "x"), list()),
               "lnk_config")
  expect_error(lnk_wsg_downstream_check(fake_conn(), "PARS", cfg, "nope"), "loaded")
  expect_error(lnk_wsg_downstream_check(fake_conn(), "PARS", cfg, list(),
                                        on_fail = "nonsense"))
})

test_that("a bare TRUE override is rejected — the justification IS the mechanism", {
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_wsg_downstream_check(fake_conn(), "PARS", cfg, list(), override = TRUE),
    "justification")
  expect_error(
    lnk_wsg_downstream_check(fake_conn(), "PARS", cfg, list(), override = "  "),
    "non-empty")
})

test_that("on_fail = 'ignore' short-circuits before touching the database", {
  cfg <- lnk_config("bcfishpass")
  # No DBI mocks at all: if it queried, this would error.
  r <- lnk_wsg_downstream_check(fake_conn(), "PARS", cfg, list(),
                                on_fail = "ignore")
  expect_identical(r$status, "pass")
})

# --- probe SQL --------------------------------------------------------------

test_that(".lnk_dams_blocking_downstream applies all three blocking filters", {
  seen <- character()
  with_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      seen <<- c(seen, statement)
      data.frame(dam_id = character(0), dam_name_en = character(0),
                 watershed_group_code = character(0),
                 passability_status_code = integer(0))
    },
    dbQuoteLiteral = function(conn, x, ...) paste0("'", x, "'"),
    .package = "DBI",
    .lnk_dams_blocking_downstream(fake_conn(), "PARS", list(), stub_outlets())
  )
  sql <- paste(seen, collapse = "\n")
  # 1. psc IN (1,2) — NULL (cabd_additions) is deliberately not blocking.
  expect_match(sql, "passability_status_code IN (1, 2)", fixed = TRUE)
  # 2. real linear_feature_id join.
  expect_match(sql, "s.linear_feature_id = m.linear_feature_id", fixed = TRUE)
  # 3. mainstem only.
  expect_match(sql, "m.blue_line_key = s.watershed_key", fixed = TRUE)
  # Path, not membership: the measure-aware downstream test.
  expect_match(sql, "fwa_downstream", fixed = TRUE)
  # And it must exclude the focal WSG's own dams.
  expect_match(sql, "m.watershed_group_code <> 'PARS'", fixed = TRUE)
})

test_that(".lnk_dams_blocking_downstream errors on an unknown watershed group", {
  expect_error(
    .lnk_dams_blocking_downstream(fake_conn(), "NOPE", list(), stub_outlets()),
    "no outlet")
})

test_that(".lnk_barriers_cabd_persisted returns empty when barriers is absent", {
  cfg <- lnk_config("bcfishpass")
  with_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) data.frame(),
    dbQuoteLiteral = function(conn, x, ...) paste0("'", x, "'"),
    .package = "DBI",
    expect_identical(
      .lnk_barriers_cabd_persisted(fake_conn(), cfg, c("a", "b")),
      character(0))
  )
})

test_that(".lnk_barriers_cabd_persisted short-circuits on an empty id set", {
  cfg <- lnk_config("bcfishpass")
  expect_identical(.lnk_barriers_cabd_persisted(fake_conn(), cfg, character(0)),
                   character(0))
})

test_that("missing fwa_downstream fails loud rather than auto-passing", {
  # A silent pass here would be the exact bug the guard exists to prevent.
  with_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) data.frame(n = 0L),
    .package = "DBI",
    expect_error(.lnk_require_fwa_downstream(fake_conn()), "fwa_downstream")
  )
})

# --- live behaviour ---------------------------------------------------------

test_that("guard passes for a WSG with no blocking dams downstream", {
  conn <- skip_if_no_db()
  cfg <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)
  # BULK is the anti-cry-wolf regression: its downstream CLOSURE holds 18
  # blocking dams across LSKE/KISP/KLUM, but none sit on its flow path. A
  # membership-based guard fires here; a path-based one must not.
  r <- lnk_wsg_downstream_check(conn, "BULK", cfg, loaded)
  expect_identical(r$status, "pass")
  expect_lt(r$elapsed_s, 5)
})

test_that("guard fails loud and names the dams when they are unpersisted", {
  conn <- skip_if_no_db()
  cfg <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)
  cfg$pipeline$schema <- "fresh_guard_test_absent"   # nothing persisted here

  expect_error(lnk_wsg_downstream_check(conn, "PARS", cfg, loaded), "Site C")
  expect_error(lnk_wsg_downstream_check(conn, "PARS", cfg, loaded),
               "W.A.C. Bennett")
  # Names the WSGs to model first, not just "closure not persisted".
  expect_error(lnk_wsg_downstream_check(conn, "PARS", cfg, loaded), "UPCE")
})

test_that("warn mode returns a note instead of erroring", {
  conn <- skip_if_no_db()
  cfg <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)
  cfg$pipeline$schema <- "fresh_guard_test_absent"

  suppressMessages(
    r <- lnk_wsg_downstream_check(conn, "PARS", cfg, loaded, on_fail = "warn"))
  expect_identical(r$status, "warn")
  expect_match(r$note, "guard(warn)", fixed = TRUE)
  expect_match(r$note, "link#227", fixed = TRUE)
  expect_setequal(r$wsgs_missing, c("PCEA", "UPCE"))
})

test_that("override proceeds and carries the justification into the note", {
  conn <- skip_if_no_db()
  cfg <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)
  cfg$pipeline$schema <- "fresh_guard_test_absent"

  suppressMessages(
    r <- lnk_wsg_downstream_check(conn, "PARS", cfg, loaded,
                                  override = "fishway operational, ref doc-123"))
  expect_identical(r$status, "override")
  expect_match(r$note, "guard(override)", fixed = TRUE)
  expect_match(r$note, "doc-123", fixed = TRUE)
})

test_that("guard passes when the downstream dams ARE persisted", {
  conn <- skip_if_no_db()
  cfg <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)
  tn <- .lnk_table_names(cfg)
  have <- tryCatch(DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*) n FROM %s.barriers WHERE barrier_source = 'CABD'
      AND watershed_group_code IN ('PCEA','UPCE')", tn$schema))$n,
    error = function(e) 0)
  skip_if(as.integer(have) == 0L, "PCEA/UPCE dams not persisted here")
  # Same WSG, same dams — the only thing that changed is that they're modelled.
  r <- lnk_wsg_downstream_check(conn, "PARS", cfg, loaded)
  expect_identical(r$status, "pass")
})

test_that("guard probe agrees with prep_dams on what blocks (anti-drift)", {
  # The whole point of sharing the SQL: if these ever disagree, the guard is
  # flagging dams the pipeline does not model, or missing ones it does.
  conn <- skip_if_no_db()
  cfg <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)
  schema <- "working_guard_drift"
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", schema))
  withr::defer(
    try(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema)),
        silent = TRUE))

  .lnk_pipeline_prep_dams(conn, conn_tunnel = conn, aoi = "KOTL",
                          schema = schema, loaded = loaded)
  from_pipeline <- DBI::dbGetQuery(conn, sprintf(
    "SELECT d.dam_id FROM %s.dams d
       JOIN whse_basemapping.fwa_stream_networks_sp s
         ON s.linear_feature_id = d.linear_feature_id
      WHERE d.passability_status_code IN (1,2)
        AND d.blue_line_key = s.watershed_key
      ORDER BY d.dam_id", schema))$dam_id

  # SLOC drains through KOTL, so its downstream probe covers KOTL's dams.
  probe <- .lnk_dams_blocking_downstream(conn, "SLOC", loaded,
                                         fresh::frs_wsg_outlets())
  from_guard <- sort(probe$dam_id[probe$watershed_group_code == "KOTL"])

  # Every dam the guard flags in KOTL must be one prep_dams would model.
  expect_true(all(from_guard %in% from_pipeline))
})
