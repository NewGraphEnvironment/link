# -- input validation --------------------------------------------------------

test_that("lnk_pipeline_prepare rejects invalid aoi", {
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = NULL, cfg = cfg,
                          loaded = list(), schema = "w"),
    "aoi must be a single non-empty string"
  )
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = "", cfg = cfg,
                          loaded = list(), schema = "w"),
    "aoi must be a single non-empty string"
  )
})

test_that("lnk_pipeline_prepare rejects non-lnk_config cfg", {
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = "BULK",
                          cfg = list(), loaded = list(), schema = "w"),
    "cfg must be an lnk_config object"
  )
})

test_that("lnk_pipeline_prepare rejects non-list loaded", {
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = "BULK", cfg = cfg,
                          loaded = "not-a-list", schema = "w"),
    "loaded must be a named list"
  )
})

test_that("lnk_pipeline_prepare rejects invalid schema and observations", {
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = "BULK", cfg = cfg,
                          loaded = list(), schema = "bad;name"),
    "schema"
  )
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = "BULK", cfg = cfg,
                          loaded = list(), schema = "working",
                          observations = "bad;name"),
    "observations"
  )
})

# -- quote_literal helper ---------------------------------------------------

test_that(".lnk_quote_literal doubles single-quotes", {
  expect_equal(.lnk_quote_literal("BULK"), "'BULK'")
  expect_equal(.lnk_quote_literal("O'Brien"), "'O''Brien'")
  expect_error(.lnk_quote_literal(c("a", "b")), "single string")
  expect_error(.lnk_quote_literal(123), "single string")
})

# -- prep_gradient SQL shape (mocked) ---------------------------------------

.loaded_no_control <- list()
.loaded_with_control <- list(
  user_barriers_definite_control = data.frame(
    blue_line_key = 1L,
    downstream_route_measure = 1,
    barrier_ind = "t",
    watershed_group_code = "ADMS",
    stringsAsFactors = FALSE
  )
)

test_that(".lnk_pipeline_prep_gradient quotes aoi safely in the streams_blk query", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  local_mocked_bindings(
    frs_break_find = function(...) invisible(NULL),
    .package = "fresh"
  )

  .lnk_pipeline_prep_gradient("mock-conn", aoi = "BULK",
    loaded = .loaded_no_control, schema = "w")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "CREATE TABLE w.streams_blk")
  expect_match(joined, "watershed_group_code = 'BULK'")
  expect_match(joined, "edge_type != 6010")
  expect_match(joined, "ADD COLUMN IF NOT EXISTS wscode_ltree ltree")
  expect_no_match(joined, "DELETE FROM w.gradient_barriers_raw")
})

test_that(".lnk_pipeline_prep_gradient threads classes through to frs_break_find", {
  captured_classes <- NULL
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) invisible(NULL)
  )
  local_mocked_bindings(
    frs_break_find = function(conn, table, attribute, classes, to, ...) {
      captured_classes <<- classes
      invisible(NULL)
    },
    .package = "fresh"
  )

  custom <- c("0500" = 0.05, "0800" = 0.08, "1500" = 0.15)
  .lnk_pipeline_prep_gradient("mock-conn", aoi = "BULK",
    loaded = .loaded_no_control, schema = "w", classes = custom)

  expect_identical(captured_classes, custom)
})

test_that(".lnk_resolve_classes prefers caller arg over cfg over bcfp default", {
  cfg_default <- structure(list(pipeline = list()), class = "lnk_config")
  cfg_with_classes <- structure(
    list(pipeline = list(gradient_classes = list(
      "0500" = 0.05, "1000" = 0.10))),
    class = "lnk_config"
  )

  caller <- c("0100" = 0.01)
  expect_identical(.lnk_resolve_classes(caller, cfg_with_classes), caller)

  resolved <- .lnk_resolve_classes(NULL, cfg_with_classes)
  expect_equal(unname(resolved), c(0.05, 0.10))
  expect_identical(names(resolved), c("0500", "1000"))

  expect_identical(.lnk_resolve_classes(NULL, cfg_default),
                   .lnk_classes_bcfp)
})

test_that(".lnk_pipeline_prep_gradient prunes when manifest declares control", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  local_mocked_bindings(
    frs_break_find = function(...) invisible(NULL),
    .package = "fresh"
  )

  .lnk_pipeline_prep_gradient("mock-conn", aoi = "ADMS",
    loaded = .loaded_with_control, schema = "w_adms")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "DELETE FROM w_adms.gradient_barriers_raw g")
  expect_match(joined, "USING w_adms.barriers_definite_control c")
  expect_match(joined, "c.barrier_ind::boolean = false")
})

# -- prep_natural SQL shape -------------------------------------------------

# Helper: minimal cfg-like object for mocking. The real cfg is built by
# lnk_config(), which reads YAML — too heavy for these unit tests.
.fake_cfg <- function(break_order = NULL) {
  structure(list(pipeline = list(break_order = break_order)),
            class = "lnk_config")
}

test_that(".lnk_pipeline_prep_natural unions gradient + falls when subsurfaceflow opted out", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )

  cfg <- .fake_cfg(break_order = c("observations", "gradient_minimal",
    "barriers_definite", "habitat_endpoints", "crossings"))
  .lnk_pipeline_prep_natural("mock-conn", aoi = "BULK", cfg = cfg,
    loaded = list(), schema = "w_bulk")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "CREATE TABLE w_bulk.natural_barriers")
  expect_match(joined, "FROM w_bulk.gradient_barriers_raw g")
  expect_match(joined, "FROM w_bulk.falls f")
  expect_no_match(joined, "FROM w_bulk\\.barriers_definite\\b")
  expect_match(joined, "'blocked'")
  # Subsurfaceflow code path must not fire when not opted in
  expect_no_match(joined, "barriers_subsurfaceflow")
  expect_no_match(joined, "edge_type IN \\(1410, 1425\\)")
})

test_that(".lnk_pipeline_prep_natural unions subsurfaceflow into natural_barriers when opted in", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )

  cfg <- .fake_cfg(break_order = c("observations", "gradient_minimal",
    "barriers_definite", "subsurfaceflow", "habitat_endpoints", "crossings"))
  .lnk_pipeline_prep_natural("mock-conn", aoi = "HARR", cfg = cfg,
    loaded = list(), schema = "w_harr")

  joined <- paste(captured, collapse = "\n")
  # Builds the subsurfaceflow table from FWA
  expect_match(joined, "CREATE TABLE w_harr.barriers_subsurfaceflow")
  expect_match(joined, "edge_type IN \\(1410, 1425\\)")
  # AND appends those positions to natural_barriers so lnk_barrier_overrides
  # sees them — this is the link#88 fix. Match per-statement (not on the
  # newline-joined blob): a single emitted SQL string must contain both the
  # INSERT target and the SELECT source. A cross-statement regex on the
  # joined blob would false-positive on the falls INSERT plus a downstream
  # CREATE TABLE that names barriers_subsurfaceflow.
  has_fix_insert <- any(
    grepl("INSERT INTO w_harr\\.natural_barriers", captured) &
    grepl("FROM w_harr\\.barriers_subsurfaceflow", captured))
  expect_true(has_fix_insert,
    info = "expected one captured SQL with INSERT INTO natural_barriers ... FROM barriers_subsurfaceflow")
})

test_that(".lnk_pipeline_prep_natural honours barriers_definite_control on subsurfaceflow", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )

  cfg <- .fake_cfg(break_order = c("subsurfaceflow"))
  loaded <- list(user_barriers_definite_control = data.frame(
    blue_line_key = 1L, downstream_route_measure = 0,
    barrier_ind = "true"))
  .lnk_pipeline_prep_natural("mock-conn", aoi = "HARR", cfg = cfg,
    loaded = loaded, schema = "w_harr")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "LEFT OUTER JOIN w_harr.barriers_definite_control c")
  expect_match(joined,
    "c.barrier_ind IS NULL OR c.barrier_ind::boolean IS TRUE")
})

# -- prep_minimal structure --------------------------------------------------

test_that(".lnk_pipeline_prep_minimal builds per-species tables from access_gradient_max", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  minimal_calls <- list()
  local_mocked_bindings(
    frs_barriers_minimal = function(conn, from, to, ...) {
      minimal_calls[[length(minimal_calls) + 1]] <<-
        list(from = from, to = to)
      invisible(NULL)
    },
    .package = "fresh"
  )

  cfg <- structure(
    list(species = c("BT", "CH", "SK", "ST", "WCT")),
    class = "lnk_config"
  )
  loaded <- list(
    parameters_fresh = data.frame(
      species_code = c("BT", "CH", "SK", "ST", "WCT"),
      access_gradient_max = c(0.25, 0.15, 0.15, 0.20, 0.20),
      stringsAsFactors = FALSE
    )
  )

  .lnk_pipeline_prep_minimal("mock-conn", aoi = "BULK", cfg = cfg,
    loaded = loaded, schema = "w_bulk")

  # One barrier table per species (BT/CH/SK/ST/WCT)
  expect_length(minimal_calls, 5L)
  from_tables <- vapply(minimal_calls, `[[`, character(1), "from")
  table_names <- sub("^[^.]+\\.", "", from_tables)
  expect_setequal(table_names,
    c("barriers_bt", "barriers_ch", "barriers_sk",
      "barriers_st", "barriers_wct"))

  # BT @ 0.25 → classes 2500, 3000 (only those ≥ 0.25)
  bt_create <- captured[grepl("CREATE TABLE w_bulk\\.barriers_bt\\b", captured)]
  expect_length(bt_create, 1L)
  expect_match(bt_create, "gradient_class IN \\(2500, 3000\\)")

  # CH @ 0.15 → 1500, 2000, 2500, 3000
  ch_create <- captured[grepl("CREATE TABLE w_bulk\\.barriers_ch\\b", captured)]
  expect_length(ch_create, 1L)
  expect_match(ch_create, "gradient_class IN \\(1500, 2000, 2500, 3000\\)")

  # ST @ 0.20 → 2000, 2500, 3000
  st_create <- captured[grepl("CREATE TABLE w_bulk\\.barriers_st\\b", captured)]
  expect_length(st_create, 1L)
  expect_match(st_create, "gradient_class IN \\(2000, 2500, 3000\\)")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined,
    "CREATE TABLE w_bulk.gradient_barriers_minimal AS")
  expect_match(joined, "UNION")
})

test_that(".lnk_pipeline_prep_minimal skips species with NA / zero access_gradient_max", {
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) invisible(NULL)
  )
  minimal_calls <- list()
  local_mocked_bindings(
    frs_barriers_minimal = function(conn, from, to, ...) {
      minimal_calls[[length(minimal_calls) + 1]] <<-
        list(from = from, to = to)
      invisible(NULL)
    },
    .package = "fresh"
  )

  cfg <- structure(list(species = c("BT", "LK", "ZR")), class = "lnk_config")
  loaded <- list(
    parameters_fresh = data.frame(
      species_code = c("BT", "LK", "ZR"),
      # LK is lake-only (NA access threshold); ZR has zero.
      access_gradient_max = c(0.25, NA, 0),
      stringsAsFactors = FALSE
    )
  )

  .lnk_pipeline_prep_minimal("mock-conn", aoi = "BULK", cfg = cfg,
    loaded = loaded, schema = "w")

  # Only BT yields a barrier table — LK + ZR skipped.
  expect_length(minimal_calls, 1L)
  expect_match(minimal_calls[[1]]$from, "barriers_bt$")
})

test_that(".lnk_pipeline_prep_minimal honours custom classes vector", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  local_mocked_bindings(
    frs_barriers_minimal = function(...) invisible(NULL),
    .package = "fresh"
  )

  cfg <- structure(list(species = "BT"), class = "lnk_config")
  loaded <- list(
    parameters_fresh = data.frame(
      species_code = "BT",
      access_gradient_max = 0.10,
      stringsAsFactors = FALSE
    )
  )

  # Custom break vector at 0.05 / 0.08 / 0.10 / 0.15.
  # BT @ 0.10 → classes ≥ 0.10 are 1000 + 1500.
  custom <- c("0500" = 0.05, "0800" = 0.08, "1000" = 0.10, "1500" = 0.15)
  .lnk_pipeline_prep_minimal("mock-conn", aoi = "BULK", cfg = cfg,
    loaded = loaded, schema = "w", classes = custom)

  bt_create <- captured[grepl("CREATE TABLE w\\.barriers_bt\\b", captured)]
  expect_length(bt_create, 1L)
  expect_match(bt_create, "gradient_class IN \\(1000, 1500\\)")
})

# -- prep_network SQL shape --------------------------------------------------

test_that(".lnk_pipeline_prep_network loads fresh.streams with FWA filters", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  local_mocked_bindings(
    frs_col_join = function(...) invisible(NULL),
    frs_col_generate = function(...) invisible(NULL),
    .package = "fresh"
  )

  .lnk_pipeline_prep_network("mock-conn", aoi = "BULK", schema = "w_bulk")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "CREATE TABLE w_bulk.streams")
  expect_match(joined, "watershed_group_code = 'BULK'")
  expect_match(joined, "localcode_ltree IS NOT NULL")
  expect_match(joined, "edge_type != 6010")
  expect_match(joined, "wscode_ltree <@ '999'::ltree IS FALSE")
  expect_match(joined, "ADD COLUMN id_segment integer")
})

# -- prep_overrides control pass-through (manifest-driven) -------------------

test_that(".lnk_pipeline_prep_overrides passes control when manifest declares it", {
  loaded_stub <- list(
    parameters_fresh = data.frame(
      species_code = "BT",
      observation_threshold = 1L,
      observation_date_min = "2000-01-01",
      observation_buffer_m = 20,
      observation_species = "BT",
      stringsAsFactors = FALSE
    ),
    user_barriers_definite_control = data.frame(
      blue_line_key = 360873822L,
      downstream_route_measure = 1000,
      barrier_ind = "t",
      stringsAsFactors = FALSE
    )
  )

  captured <- list()
  local_mocked_bindings(
    lnk_barrier_overrides = function(conn, ...) {
      captured[["args"]] <<- list(...)
      invisible(NULL)
    }
  )

  .lnk_pipeline_prep_overrides("mock-conn", loaded = loaded_stub,
    schema = "working_bulk")

  expect_equal(captured$args$control, "working_bulk.barriers_definite_control")
})

test_that(".lnk_pipeline_prep_overrides passes control = NULL when manifest omits it", {
  loaded_stub <- list(
    parameters_fresh = data.frame(
      species_code = "BT",
      observation_threshold = 1L,
      observation_date_min = "2000-01-01",
      observation_buffer_m = 20,
      observation_species = "BT",
      stringsAsFactors = FALSE
    )
  )

  captured <- list()
  local_mocked_bindings(
    lnk_barrier_overrides = function(conn, ...) {
      captured[["args"]] <<- list(...)
      invisible(NULL)
    }
  )

  .lnk_pipeline_prep_overrides("mock-conn", loaded = loaded_stub,
    schema = "working_bulk")

  expect_null(captured$args$control)
})

# -- prep_overrides habitat pass-through (manifest-driven) -------------------

test_that(".lnk_pipeline_prep_overrides passes habitat when manifest declares it", {
  loaded_stub <- list(
    parameters_fresh = data.frame(
      species_code = "BT",
      observation_threshold = 1L,
      observation_date_min = "2000-01-01",
      observation_buffer_m = 20,
      observation_species = "BT",
      stringsAsFactors = FALSE
    ),
    user_habitat_classification = data.frame(
      blue_line_key = 1L,
      species_code = "BT",
      stringsAsFactors = FALSE
    )
  )

  captured <- list()
  local_mocked_bindings(
    lnk_barrier_overrides = function(conn, ...) {
      captured[["args"]] <<- list(...)
      invisible(NULL)
    }
  )

  .lnk_pipeline_prep_overrides("mock-conn", loaded = loaded_stub,
    schema = "working_bulk")

  expect_equal(captured$args$habitat,
    "working_bulk.user_habitat_classification")
})

test_that(".lnk_pipeline_prep_overrides passes habitat = NULL when manifest omits it", {
  loaded_stub <- list(
    parameters_fresh = data.frame(
      species_code = "BT",
      observation_threshold = 1L,
      observation_date_min = "2000-01-01",
      observation_buffer_m = 20,
      observation_species = "BT",
      stringsAsFactors = FALSE
    )
  )

  captured <- list()
  local_mocked_bindings(
    lnk_barrier_overrides = function(conn, ...) {
      captured[["args"]] <<- list(...)
      invisible(NULL)
    }
  )

  .lnk_pipeline_prep_overrides("mock-conn", loaded = loaded_stub,
    schema = "working_bulk")

  expect_null(captured$args$habitat)
})


# =====================================================================
# .lnk_pipeline_prep_observations — link#92 per-AOI filtered observations
# =====================================================================
#
# Mirrors bcfp's `model/01_access/sql/load_observations.sql`:
#   - INNER filter to WSG's species set (loaded$wsg_species_presence)
#   - LEFT JOIN observation_exclusions, drop data_error/release_exclude rows
#     (keyed on observation_key)
# Result: <schema>.observations, consumed by prep_overrides + break_obs.

test_that(".lnk_pipeline_prep_observations builds species-filtered table", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )

  loaded <- list(
    wsg_species_presence = data.frame(
      watershed_group_code = "BULK",
      bt = "t", ch = "t", cm = "f", co = "f", ct = "f", dv = "f",
      pk = "f", rb = "f", sk = "f", st = "f", wct = "f",
      stringsAsFactors = FALSE
    ),
    observation_exclusions = NULL
  )
  .lnk_pipeline_prep_observations("mock", aoi = "BULK", loaded = loaded,
    schema = "w_bulk", observations = "bcfishobs.observations")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "DROP TABLE IF EXISTS w_bulk\\.observations\\b")
  expect_match(joined, "CREATE TABLE w_bulk\\.observations AS")
  expect_match(joined, "FROM bcfishobs\\.observations o")
  expect_match(joined, "o\\.watershed_group_code = 'BULK'")
  expect_match(joined, "o\\.species_code IN \\('BT', 'CH'\\)")
  # No exclusions clause when the loaded list has none
  expect_no_match(joined, "observation_key NOT IN")
})

test_that(".lnk_pipeline_prep_observations applies QA exclusions on observation_key", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )

  loaded <- list(
    wsg_species_presence = data.frame(
      watershed_group_code = "BULK",
      bt = "t", ch = "f", cm = "f", co = "f", ct = "f", dv = "f",
      pk = "f", rb = "f", sk = "f", st = "f", wct = "f",
      stringsAsFactors = FALSE
    ),
    observation_exclusions = data.frame(
      observation_key  = c("aaa", "bbb", "ccc", "ddd"),
      data_error       = c(TRUE,  FALSE, FALSE, FALSE),
      release_exclude  = c(FALSE, TRUE,  FALSE, FALSE),
      release_include  = c(FALSE, FALSE, FALSE, FALSE),
      stringsAsFactors = FALSE
    )
  )
  .lnk_pipeline_prep_observations("mock", aoi = "BULK", loaded = loaded,
    schema = "w_bulk", observations = "bcfishobs.observations")

  joined <- paste(captured, collapse = "\n")
  # Filter clause keyed on observation_key (NOT fish_observation_point_id) —
  # this is the link#92 fix. CSV column matches bcfishpass schema exactly.
  expect_match(joined, "AND o\\.observation_key NOT IN")
  # Only the 2 truly-excluded keys (data_error TRUE or release_exclude TRUE)
  # appear; the 2 kept keys do NOT
  expect_match(joined, "'aaa'")
  expect_match(joined, "'bbb'")
  expect_no_match(joined, "'ccc'")
  expect_no_match(joined, "'ddd'")
})

test_that(".lnk_pipeline_prep_observations expands CT to CT/CCT/ACT/CT/RB", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )

  loaded <- list(
    wsg_species_presence = data.frame(
      watershed_group_code = "ELKR",
      bt = "f", ch = "f", cm = "f", co = "f", ct = "t", dv = "f",
      pk = "f", rb = "f", sk = "f", st = "f", wct = "t",
      stringsAsFactors = FALSE
    ),
    observation_exclusions = NULL
  )
  .lnk_pipeline_prep_observations("mock", aoi = "ELKR", loaded = loaded,
    schema = "w_elkr", observations = "bcfishobs.observations")

  joined <- paste(captured, collapse = "\n")
  # CT alias remap mirrors bcfishpass species_code_remap (CCT/ACT/CT/RB → CT)
  for (sp in c("CT", "CCT", "ACT", "CT/RB", "WCT")) {
    expect_match(joined, sprintf("'%s'", sp))
  }
})

test_that(".lnk_pipeline_prep_observations builds empty table when no species present", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )

  loaded <- list(
    wsg_species_presence = data.frame(
      watershed_group_code = "XXXX",
      bt = "f", ch = "f", cm = "f", co = "f", ct = "f", dv = "f",
      pk = "f", rb = "f", sk = "f", st = "f", wct = "f",
      stringsAsFactors = FALSE
    ),
    observation_exclusions = NULL
  )
  .lnk_pipeline_prep_observations("mock", aoi = "XXXX", loaded = loaded,
    schema = "w_x", observations = "bcfishobs.observations")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "WHERE FALSE")
  expect_no_match(joined, "watershed_group_code = 'XXXX'")
})

test_that(".lnk_pipeline_prep_observations errors when wsg_species_presence missing", {
  expect_error(
    .lnk_pipeline_prep_observations("mock", aoi = "BULK",
      loaded = list(wsg_species_presence = NULL),
      schema = "w_bulk", observations = "bcfishobs.observations"),
    "wsg_species_presence not present"
  )
})

# -- prep_dams (link#103) ---------------------------------------------------

test_that(".lnk_pipeline_prep_dams short-circuits when conn_tunnel is NULL", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  .lnk_pipeline_prep_dams("mock", conn_tunnel = NULL, aoi = "HARR",
    schema = "w_harr", loaded = list())
  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "DROP TABLE IF EXISTS w_harr.dams")
  # No CREATE / cabd staging when opted out
  expect_no_match(joined, "CREATE TABLE w_harr\\.dams")
  expect_no_match(joined, "cabd_dams_raw")
})

test_that(".lnk_pipeline_prep_dams errors clearly when a CABD edit CSV is missing", {
  expect_error(
    .lnk_pipeline_prep_dams("mock-conn", conn_tunnel = "mock-tunnel",
      aoi = "HARR", schema = "w_harr",
      loaded = list(cabd_exclusions = data.frame(cabd_id = integer(0)))),
    "missing required CABD edit CSV"
  )
})

test_that(".lnk_pipeline_prep_dams emits load_dams.sql shape when conn_tunnel set", {
  captured_sql <- character(0)
  captured_writes <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured_sql <<- c(captured_sql, sql); invisible(NULL)
    }
  )
  with_mocked_bindings(
    {
      .lnk_pipeline_prep_dams("mock-conn",
        conn_tunnel = "mock-tunnel", aoi = "HARR", schema = "w_harr",
        loaded = list(
          cabd_exclusions = data.frame(cabd_id = integer(0)),
          cabd_blkey_xref = data.frame(cabd_id = integer(0)),
          cabd_passability_status_updates = data.frame(cabd_id = integer(0)),
          cabd_additions = data.frame(cabd_id = integer(0))))
    },
    dbGetQuery = function(conn, statement, ...) {
      data.frame(cabd_id = integer(0), dam_name_en = character(0),
                 height_m = double(0), owner = character(0),
                 dam_use = character(0), operating_status = character(0),
                 passability_status_code = integer(0),
                 geom_ewkb = list(), stringsAsFactors = FALSE)
    },
    dbWriteTable = function(conn, name, value, ...) {
      captured_writes <<- c(captured_writes, paste0(name@name[["schema"]], ".",
                                                     name@name[["table"]]))
      invisible(TRUE)
    },
    .package = "DBI"
  )

  joined <- paste(captured_sql, collapse = "\n")
  # Stages 4 edit CSVs into the working schema
  expect_true("w_harr.cabd_exclusions" %in% captured_writes)
  expect_true("w_harr.cabd_blkey_xref" %in% captured_writes)
  expect_true("w_harr.cabd_passability_status_updates" %in% captured_writes)
  expect_true("w_harr.cabd_additions" %in% captured_writes)
  expect_true("w_harr.cabd_dams_raw" %in% captured_writes)
  # Replicates load_dams.sql: lateral snap, COALESCE on passability,
  # exclusions filter, blkey override, US additions UNION
  expect_match(joined, "CREATE TABLE w_harr\\.dams")
  expect_match(joined, "LEFT OUTER JOIN w_harr.cabd_exclusions")
  expect_match(joined, "LEFT OUTER JOIN w_harr.cabd_blkey_xref")
  expect_match(joined, "LEFT OUTER JOIN w_harr.cabd_passability_status_updates")
  expect_match(joined, "ST_Distance\\(str.geom, c.geom\\) <= 65")
  expect_match(joined, "UNION ALL")
  expect_match(joined, "feature_type = 'dams'")
})
