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


test_that("the guard sees the cabd_additions dams only when they are barriers", {
  # Shared SQL, so the guard and prep_dams agree on the placeholders too
  # (link#367). KOTL drains down the Columbia past LARL's border placeholder.
  conn <- skip_if_no_db()
  cfg <- lnk_config("default")
  loaded <- lnk_load_overrides(cfg)
  schema <- "working_guard_usa"
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", schema))
  withr::defer(
    try(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema)),
        silent = TRUE))

  outlets <- fresh::frs_wsg_outlets()
  on <- .lnk_dams_blocking_downstream(conn, "KOTL", loaded, outlets,
                                      additions = TRUE)
  off <- .lnk_dams_blocking_downstream(conn, "KOTL", loaded, outlets)
  usa_on <- on$dam_id[grepl("^12000", on$dam_id)]
  expect_identical(usa_on, "1200000002")  # CSV row 2, the Columbia at the border
  expect_false(any(grepl("^12000", off$dam_id)))
  # Everything else is the same probe.
  expect_identical(sort(setdiff(on$dam_id, usa_on)), sort(off$dam_id))

  # And the id the guard reports is the one prep_dams persists.
  .lnk_pipeline_prep_dams(conn, conn_tunnel = conn, aoi = "LARL",
                          schema = schema, loaded = loaded, cfg = cfg)
  from_pipeline <- DBI::dbGetQuery(conn, sprintf(
    "SELECT dam_id FROM %s.dams WHERE passability_status_code IN (1, 2)",
    schema))$dam_id
  expect_true(usa_on %in% from_pipeline)
})

test_that("lnk_wsg_downstream_check passes the bundle's knob to the probe", {
  # The probe's default (additions = FALSE) is bcfishpass's behaviour, so a
  # caller that dropped the argument would pass every group upstream of a
  # placeholder under `default` (link#367 review).
  seen <- logical()
  local_mocked_bindings(
    .lnk_require_fwa_downstream = function(conn) invisible(TRUE),
    .lnk_wsg_fwa_unloaded = function(conn, wsgs) character(0),
    .lnk_dams_near_groups = function(conn, wsgs) NULL,
    .lnk_wsg_line_deps = function(conn, aoi) character(0),
    .lnk_dams_blocking_downstream = function(conn, aoi, loaded, outlets,
                                             additions = FALSE,
                                             near_groups = NULL) {
      seen <<- c(seen, additions)
      data.frame(dam_id = character(0), dam_name_en = character(0),
                 watershed_group_code = character(0),
                 passability_status_code = integer(0))
    },
    lnk_wsg_resolve = function(...) "KOTL"
  )
  local_mocked_bindings(frs_wsg_drainage = function(conn, wsg, outlets) "KOTL",
                        .package = "fresh")
  for (nm in c("default", "bcfishpass")) {
    r <- lnk_wsg_downstream_check(fake_conn(), "KOTL", lnk_config(nm), list(),
                                  outlets = stub_outlets())
    expect_identical(r$status, "pass")
  }
  expect_identical(seen, c(TRUE, FALSE))
})


# --- downstream groups not loaded (link#464) ---------------------------------

# The test database holds every group, so an unloaded downstream group is a
# code no FWA row carries. The closure is mocked both ways the check has ever
# asked for it, so the test fails on the code before link#464 (it passed).
unloaded_mocks <- function(env = parent.frame()) {
  no_dams <- function(...) {
    data.frame(dam_id = character(0), dam_name_en = character(0),
               watershed_group_code = character(0),
               passability_status_code = integer(0))
  }
  testthat::local_mocked_bindings(
    .lnk_dams_blocking_downstream = no_dams,
    lnk_wsg_resolve = function(cfg, loaded, wsgs, ...) wsgs,
    .env = env)
  testthat::local_mocked_bindings(
    frs_wsg_drainage = function(conn, wsg, outlets) c("ZZZZ", "PARS"),
    .package = "fresh", .env = env)
}

test_that("a downstream group with no FWA streams refuses, named", {
  conn <- skip_if_no_db()
  cfg <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)
  unloaded_mocks()
  expect_error(lnk_wsg_downstream_check(conn, "PARS", cfg, loaded),
               "link#464")
  expect_error(lnk_wsg_downstream_check(conn, "PARS", cfg, loaded), "ZZZZ")
})

test_that("an unloaded downstream group warns and overrides as dams do", {
  conn <- skip_if_no_db()
  cfg <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)
  unloaded_mocks()
  suppressMessages(
    r <- lnk_wsg_downstream_check(conn, "PARS", cfg, loaded, on_fail = "warn"))
  expect_identical(r$status, "warn")
  expect_identical(r$wsgs_unloaded, "ZZZZ")
  expect_identical(r$wsgs_missing, character(0))
  expect_match(r$note, "link#464 guard(warn)", fixed = TRUE)
  expect_match(r$note, "no FWA streams loaded at open — ZZZZ", fixed = TRUE)

  suppressMessages(
    r <- lnk_wsg_downstream_check(conn, "PARS", cfg, loaded,
                                  override = "loading ZZZZ later, ref doc-9"))
  expect_identical(r$status, "override")
  expect_match(r$note, "doc-9", fixed = TRUE)
})

test_that("a closure that errors refuses rather than passing", {
  conn <- skip_if_no_db()
  cfg <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)
  local_mocked_bindings(
    frs_wsg_drainage = function(conn, wsg, outlets) stop("outlet table broken"),
    .package = "fresh")
  expect_error(lnk_wsg_downstream_check(conn, "PARS", cfg, loaded),
               "outlet table broken")
})

test_that("the check times its steps and names them", {
  conn <- skip_if_no_db()
  cfg <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)
  r <- lnk_wsg_downstream_check(conn, "PARS", cfg, loaded, on_fail = "warn")
  expect_true(all(c("outlets", "closure", "loaded", "near", "probe") %in%
                    names(r$steps_s)))
  expect_true(all(r$steps_s >= 0))
})

test_that(".lnk_wsg_fwa_unloaded names only the groups with no streams", {
  conn <- skip_if_no_db()
  expect_identical(.lnk_wsg_fwa_unloaded(conn, c("PARS", "ZZZZ")), "ZZZZ")
  expect_identical(.lnk_wsg_fwa_unloaded(conn, character(0)), character(0))
})

test_that(".lnk_dams_near_groups gives up the narrowing on a missing polygon", {
  conn <- skip_if_no_db()
  expect_identical(.lnk_dams_near_groups(conn, c("PCEA", "UPCE")),
                   c("PCEA", "UPCE"))
  expect_null(.lnk_dams_near_groups(conn, c("PCEA", "ZZZZ")))
  expect_identical(.lnk_dams_near_groups(conn, character(0)), character(0))
})

test_that("the narrowed probe finds the dams the full probe finds", {
  # The narrowing is only sound if no dam the probe reports lies more than
  # 65 m from its group's polygon; PARS has three, in PCEA and UPCE.
  conn <- skip_if_no_db()
  cfg <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)
  o <- fresh::frs_wsg_outlets()
  full <- .lnk_dams_blocking_downstream(conn, "PARS", loaded, o)
  narrow <- .lnk_dams_blocking_downstream(conn, "PARS", loaded, o,
                                          near_groups = c("PCEA", "UPCE",
                                                          "LPCE", "PARA"))
  expect_gt(nrow(full), 0)
  expect_identical(narrow, full)
  expect_identical(nrow(.lnk_dams_blocking_downstream(
    conn, "PARS", loaded, o, near_groups = character(0))), 0L)
})

test_that(".lnk_dams_near_groups snaps every dam where the polygon table is absent", {
  conn <- skip_if_no_db()
  local_mocked_bindings(.lnk_table_exists = function(conn, tbl) FALSE)
  expect_null(.lnk_dams_near_groups(conn, c("PCEA", "UPCE")))
})

test_that("the dam snap gives a tie at a shared vertex to the segment starting there (link#478)", {
  sql <- link:::.lnk_dams_matched_sql()
  expect_match(sql, paste0(
    "ORDER BY str.geom <-> c.geom,\\s+ST_LineLocatePoint\\(str.geom, c.geom\\) = 1,",
    "\\s+str.downstream_route_measure DESC,\\s+str.linear_feature_id"))

  conn <- skip_if_no_db()
  # A dam 10 m off the vertex where a tributary (start 0) meets the top end
  # of another line, both segments equidistant: the tributary wins, where
  # "higher measure" would take the other line's top.
  got <- DBI::dbGetQuery(conn, sprintf("
    WITH str_in AS (
      SELECT * FROM (VALUES
        (1::bigint, 11::integer, 0::double precision,
         'LINESTRING(0 0, 0 100)'::text),
        (2::bigint, 22::integer, 900::double precision,
         'LINESTRING(-100 0, 0 0)'::text)) v(lfid, blk, ds, wkt)),
    c AS (SELECT 'd1'::text AS dam_id, ST_SetSRID(ST_MakePoint(7.0710678, -7.0710678), 3005) AS geom)
    SELECT str.lfid
    FROM c CROSS JOIN LATERAL (
      SELECT s.lfid, ST_SetSRID(ST_GeomFromText(s.wkt), 3005) AS geom, s.ds
      FROM str_in s
      ORDER BY ST_SetSRID(ST_GeomFromText(s.wkt), 3005) <-> c.geom,
               ST_LineLocatePoint(ST_SetSRID(ST_GeomFromText(s.wkt), 3005), c.geom) = 1,
               s.ds DESC, s.lfid
      LIMIT 1) str"))
  expect_identical(as.numeric(got$lfid), 1)
})


# --- groups on the line holding no barrier rows (link#386) -----------------

test_that("a group on the downstream lines holding no barrier rows refuses, named (DB)", {
  conn <- skip_if_no_db()
  cfg <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)
  s <- paste0("zz_lnk_t386_guard_", Sys.getpid())
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", s))
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s)))
  cfg$pipeline$schema <- s
  # BULK's lines are touched by KISP, KLUM, LKEL, LSKE, MORR, MSKE, USKE and
  # ZYMO (no dam on BULK's path, so only this condition can refuse).
  deps <- intersect(.lnk_wsg_line_deps(conn, "BULK"),
                    lnk_wsg_resolve(cfg, loaded, wsgs = NULL))
  skip_if(length(deps) < 2L, "FWA here no longer gives BULK two line dependencies")
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s.barriers (watershed_group_code varchar(4))", s))
  DBI::dbExecute(conn, sprintf("INSERT INTO %s.barriers VALUES ('%s')", s, deps[1]))
  expect_error(lnk_wsg_downstream_check(conn, "BULK", cfg, loaded), "link#386")
  r <- suppressMessages(lnk_wsg_downstream_check(conn, "BULK", cfg, loaded,
                                                 on_fail = "warn"))
  expect_identical(r$status, "warn")
  expect_identical(r$wsgs_unheld, sort(deps[-1]))
  expect_match(r$note, "^link#386 guard\\(warn\\)")
  DBI::dbExecute(conn, sprintf("INSERT INTO %s.barriers SELECT unnest(%s::text[])", s,
    DBI::dbQuoteLiteral(conn, paste0("{", paste(deps[-1], collapse = ","), "}"))))
  expect_identical(lnk_wsg_downstream_check(conn, "BULK", cfg, loaded)$status, "pass")
})

test_that("a modelled group with no FWA streams here is named: its lines cannot be read (round 3)", {
  local_mocked_bindings(
    .lnk_require_fwa_downstream = function(conn) invisible(TRUE),
    .lnk_wsg_fwa_unloaded = function(conn, wsgs) intersect(wsgs, "INGR"),
    .lnk_dams_near_groups = function(conn, wsgs) NULL,
    .lnk_wsg_line_deps = function(conn, aoi) character(0),
    .lnk_wsg_unheld = function(conn, cfg, wsgs) character(0),
    .lnk_dams_blocking_downstream = function(...) {
      data.frame(dam_id = character(0), dam_name_en = character(0),
                 watershed_group_code = character(0),
                 passability_status_code = integer(0))
    },
    lnk_wsg_resolve = function(cfg, loaded, wsgs = NULL, ...) {
      if (is.null(wsgs)) c("FINA", "INGR", "UPCE") else wsgs
    })
  local_mocked_bindings(frs_wsg_drainage = function(conn, wsg, outlets) c("FINA", "UPCE"),
                        .package = "fresh")
  r <- suppressMessages(lnk_wsg_downstream_check(fake_conn(), "FINA",
    lnk_config("default"), list(), on_fail = "warn", outlets = stub_outlets()))
  expect_identical(r$status, "warn")
  expect_identical(r$wsgs_unheld, "INGR")
  expect_error(lnk_wsg_downstream_check(fake_conn(), "FINA", lnk_config("default"),
                                        list(), outlets = stub_outlets()),
               "no FWA streams in this database")
})

test_that("the recompute's post-condition takes the written-reason override (round 3)", {
  f <- testthat::test_path("..", "..", "data-raw", "wsg_recompute_one.R")
  skip_if_not(file.exists(f), "data-raw not in this tree")
  txt <- paste(readLines(f), collapse = "\n")
  expect_match(txt, 'Sys.getenv("LNK_GUARD_DOWNSTREAM_NOTE", "")', fixed = TRUE)
  expect_match(txt, "override = if \\(nzchar\\(trimws\\(note\\)\\)\\) note")
})
