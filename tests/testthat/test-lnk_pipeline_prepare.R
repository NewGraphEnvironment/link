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
  # A point in a segment overlap matches two segments; the lower one is
  # named, not left to the UPDATE's join order (link#367).
  expect_match(joined, "SELECT DISTINCT ON (g2.ctid)", fixed = TRUE)
  expect_match(joined, "ORDER BY g2.ctid, s.downstream_route_measure, s.linear_feature_id",
               fixed = TRUE)
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

test_that(".lnk_resolve_classes round-trips YAML config knob", {
  # End-to-end check: write a config bundle with pipeline.gradient_classes,
  # round-trip through lnk_config(), confirm the named-list-of-scalars
  # shape that yaml::read_yaml() produces resolves to a named numeric.
  bundle <- file.path(tempdir(), "test_grad_classes")
  src <- system.file("extdata/configs/bcfishpass", package = "link")
  if (!nzchar(src)) skip("link package source configs not installed")
  unlink(bundle, recursive = TRUE)
  file.copy(src, dirname(bundle), recursive = TRUE)
  file.rename(file.path(dirname(bundle), "bcfishpass"), bundle)

  cfg_yaml <- file.path(bundle, "config.yaml")
  yml <- readLines(cfg_yaml)
  i <- grep("^  schema: fresh$", yml)[1]
  yml <- append(yml, c(
    "  gradient_classes:",
    "    \"0500\": 0.05",
    "    \"1500\": 0.15"
  ), after = i)
  writeLines(yml, cfg_yaml)

  cfg <- lnk_config(bundle)
  resolved <- .lnk_resolve_classes(NULL, cfg)
  expect_type(resolved, "double")
  expect_identical(names(resolved), c("0500", "1500"))
  expect_equal(unname(resolved), c(0.05, 0.15))

  unlink(bundle, recursive = TRUE)
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
#
# Each present species' post-lift barrier set is reduced to its downstream-
# most position per flow path, and only those positions break the network
# (#326; bcfishpass 01_model_access_natural.sh). The log interleaves SQL and
# frs_barriers_minimal calls so ordering can be asserted.

.pm_presence <- function(aoi = "BULK", ...) {
  row <- data.frame(watershed_group_code = aoi, bt = "", ch = "", cm = "",
                    co = "", pk = "", sk = "", st = "", wct = "", notes = "",
                    stringsAsFactors = FALSE)
  for (nm in names(list(...))) row[[nm]] <- list(...)[[nm]]
  row
}

.run_prep_minimal <- function(species, amax, presence, classes = .lnk_classes_bcfp,
                              break_order = NULL, schema = "w") {
  log <- list()
  testthat::local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      log[[length(log) + 1L]] <<- list(kind = "sql", sql = sql)
      invisible(NULL)
    },
    .env = parent.frame()
  )
  testthat::local_mocked_bindings(
    frs_barriers_minimal = function(conn, from, to, ...) {
      log[[length(log) + 1L]] <<- list(kind = "min", from = from, to = to)
      invisible(NULL)
    },
    .package = "fresh",
    .env = parent.frame()
  )
  cfg <- structure(list(species = species,
                        pipeline = list(break_order = break_order)),
                   class = "lnk_config")
  loaded <- list(
    parameters_fresh = data.frame(species_code = species,
                                  access_gradient_max = amax,
                                  stringsAsFactors = FALSE),
    wsg_species_presence = presence)
  .lnk_pipeline_prep_minimal("mock-conn", aoi = presence$watershed_group_code[1],
    cfg = cfg, loaded = loaded, schema = schema, classes = classes)
  log
}

.pm_sql <- function(log) {
  vapply(Filter(function(e) e$kind == "sql", log), `[[`, "", "sql")
}
.pm_min <- function(log) Filter(function(e) e$kind == "min", log)
.pm_union <- function(log, schema = "w") {
  s <- .pm_sql(log)
  s[grepl(sprintf("CREATE TABLE %s\\.gradient_barriers_minimal", schema), s)]
}

sp5 <- c("BT", "CH", "SK", "ST", "WCT")
amax5 <- c(0.25, 0.15, 0.15, 0.20, 0.20)

test_that(".lnk_pipeline_prep_minimal reduces only the species present in the group", {
  log <- .run_prep_minimal(sp5, amax5, .pm_presence(bt = "t"))

  sql <- .pm_sql(log)
  expect_length(grep("CREATE TABLE w\\.barriers_[a-z]+ AS", sql), 1L)
  expect_length(grep("CREATE TABLE w\\.barriers_bt AS", sql), 1L)

  mins <- .pm_min(log)
  expect_length(mins, 1L)
  expect_identical(mins[[1]]$from, "w.barriers_bt")
  expect_identical(mins[[1]]$to, "w.barriers_bt_min")

  union_sql <- .pm_union(log)
  expect_length(union_sql, 1L)
  expect_match(union_sql, "FROM w\\.barriers_bt_min\\b")
  # The raw post-lift table never breaks the network (#223 dropped the
  # reduction; #326 restores it after the lifts).
  expect_no_match(union_sql, "barriers_bt\\b")
  expect_no_match(union_sql, "barriers_(ch|sk|st|wct)")
})

test_that(".lnk_pipeline_prep_minimal expands a group of present species", {
  # ch present, sk empty: the salmon group puts sk (and cm, co, pk) in too;
  # bt, st and wct stay out.
  log <- .run_prep_minimal(sp5, amax5, .pm_presence(ch = "t"))
  froms <- vapply(.pm_min(log), `[[`, "", "from")
  expect_setequal(froms, c("w.barriers_ch", "w.barriers_sk"))
  union_sql <- .pm_union(log)
  expect_match(union_sql, "FROM w\\.barriers_ch_min\\b")
  expect_match(union_sql, "FROM w\\.barriers_sk_min\\b")
  expect_no_match(union_sql, "barriers_(bt|st|wct)")
})

test_that(".lnk_pipeline_prep_minimal with no species present writes the empty shape", {
  log <- .run_prep_minimal(sp5, amax5, .pm_presence())
  expect_length(.pm_min(log), 0L)
  sql <- .pm_sql(log)
  expect_length(grep("CREATE TABLE w\\.barriers_[a-z]+ AS", sql), 0L)
  empty <- sql[grepl("CREATE TABLE w\\.gradient_barriers_minimal \\(", sql)]
  expect_length(empty, 1L)
  expect_match(empty, "blue_line_key bigint")
})

test_that(".lnk_pipeline_prep_minimal builds each table post-lift, with definite barriers inside", {
  log <- .run_prep_minimal(sp5, amax5,
    .pm_presence(bt = "t", ch = "t", st = "t", wct = "t"))
  sql <- .pm_sql(log)
  bt <- sql[grepl("CREATE TABLE w\\.barriers_bt AS", sql)]
  expect_length(bt, 1L)

  # The lift: the uppercase parameters_fresh code, as barrier_overrides
  # stores it (a lowercase literal matches nothing and reduces the pre-lift
  # set, #223's failure).
  expect_match(bt, "FROM w\\.barrier_overrides o")
  expect_match(bt, "o\\.species_code = 'BT'")
  expect_no_match(bt, "species_code = 'bt'")
  expect_match(bt,
    "abs\\(o\\.downstream_route_measure - n\\.downstream_route_measure\\) < 1")
  expect_match(bt, "o\\.blue_line_key = n\\.blue_line_key")
  # Natural sources: gradient at the species' classes and falls.
  expect_match(bt, "FROM w\\.gradient_barriers_raw")
  expect_match(bt, "gradient_class IN \\(2500, 3000\\)")
  expect_match(bt, "FROM w\\.falls f")
  # Definite barriers are inside the table, after the lift (never lifted).
  expect_match(bt, "FROM w\\.barriers_definite d")
  definite_at <- regexpr("barriers_definite d", bt)
  lift_at <- regexpr("barrier_overrides o", bt)
  expect_gt(definite_at, lift_at)
  # Rows the FWA join could not place neither prune nor are pruned.
  expect_match(bt, "wscode_ltree IS NOT NULL")
  # Raw measures: no rounding before the reduction.
  expect_no_match(bt, "round\\(", ignore.case = TRUE)
  # Subsurface flow only when break_order opts in.
  expect_no_match(bt, "barriers_subsurfaceflow")

  # Each species' own classes.
  ch <- sql[grepl("CREATE TABLE w\\.barriers_ch AS", sql)]
  expect_match(ch, "gradient_class IN \\(1500, 2000, 2500, 3000\\)")
  expect_match(ch, "o\\.species_code = 'CH'")
  st <- sql[grepl("CREATE TABLE w\\.barriers_st AS", sql)]
  expect_match(st, "gradient_class IN \\(2000, 2500, 3000\\)")
})

test_that(".lnk_pipeline_prep_minimal includes subsurface flow when break_order has it", {
  log <- .run_prep_minimal("BT", 0.25, .pm_presence(bt = "t"),
    break_order = c("observations", "gradient_minimal", "subsurfaceflow"))
  bt <- .pm_sql(log)[grepl("CREATE TABLE w\\.barriers_bt AS", .pm_sql(log))]
  expect_match(bt, "FROM w\\.barriers_subsurfaceflow")
  # Inside the lifted part, before the definite barriers.
  expect_lt(regexpr("barriers_subsurfaceflow", bt),
            regexpr("barrier_overrides o", bt))
})

test_that(".lnk_pipeline_prep_minimal reduces each table after building it and before the union", {
  log <- .run_prep_minimal(sp5, amax5, .pm_presence(bt = "t", st = "t"))
  kinds <- vapply(log, function(e) {
    if (e$kind == "min") paste0("min:", e$from)
    else if (grepl("CREATE TABLE w\\.barriers_bt AS", e$sql)) "create:w.barriers_bt"
    else if (grepl("CREATE TABLE w\\.barriers_st AS", e$sql)) "create:w.barriers_st"
    else if (grepl("CREATE TABLE w\\.gradient_barriers_minimal", e$sql)) "union"
    else "other"
  }, "")
  for (sp in c("bt", "st")) {
    expect_lt(match(paste0("create:w.barriers_", sp), kinds),
              match(paste0("min:w.barriers_", sp), kinds))
    expect_lt(match(paste0("min:w.barriers_", sp), kinds), match("union", kinds))
  }
  expect_length(.pm_min(log), 2L)
})

test_that(".lnk_pipeline_prep_minimal skips species with NA / zero access_gradient_max", {
  log <- .run_prep_minimal(c("BT", "LK", "ZR"), c(0.25, NA, 0),
    data.frame(watershed_group_code = "BULK", bt = "t", lk = "t", zr = "t",
               stringsAsFactors = FALSE))
  froms <- vapply(.pm_min(log), `[[`, "", "from")
  expect_identical(froms, "w.barriers_bt")
  union_sql <- .pm_union(log)
  expect_no_match(union_sql, "barriers_lk")
  expect_no_match(union_sql, "barriers_zr")
})

test_that(".lnk_pipeline_prep_minimal adds the orphan classes unreduced", {
  # Orphan: 0.05 < min(0.25, 0.15). Orphans are segmentation positions, not
  # access barriers, so they are never reduced.
  custom <- c("0500" = 0.05, "1500" = 0.15, "2500" = 0.25)
  log <- .run_prep_minimal(c("BT", "CH"), c(0.25, 0.15),
    .pm_presence(bt = "t", ch = "t"), classes = custom)
  sql <- .pm_sql(log)
  orphan <- sql[grepl("CREATE TABLE w\\.barriers_orphan\\b", sql)]
  expect_length(orphan, 1L)
  expect_match(orphan, "gradient_class IN \\(500\\)")
  froms <- vapply(.pm_min(log), `[[`, "", "from")
  expect_false("w.barriers_orphan" %in% froms)
  union_sql <- .pm_union(log)
  expect_match(union_sql, "FROM w\\.barriers_orphan\\b")
  expect_match(union_sql, "FROM w\\.barriers_bt_min\\b")
  expect_match(union_sql, "FROM w\\.barriers_ch_min\\b")
})

test_that(".lnk_pipeline_prep_minimal does NOT add orphan branch when no low classes", {
  log <- .run_prep_minimal(c("BT", "CH"), c(0.25, 0.15),
    .pm_presence(bt = "t", ch = "t"))
  expect_no_match(.pm_union(log), "barriers_orphan")
})

test_that(".lnk_pipeline_prep_minimal honours custom classes vector", {
  # BT @ 0.10 → classes ≥ 0.10 are 1000 + 1500.
  custom <- c("0500" = 0.05, "0800" = 0.08, "1000" = 0.10, "1500" = 0.15)
  log <- .run_prep_minimal("BT", 0.10, .pm_presence(bt = "t"), classes = custom)
  bt <- .pm_sql(log)[grepl("CREATE TABLE w\\.barriers_bt AS", .pm_sql(log))]
  expect_length(bt, 1L)
  expect_match(bt, "gradient_class IN \\(1000, 1500\\)")
})

test_that(".lnk_pipeline_prep_minimal also lifts by the persisted overrides the view reads", {
  # The access view anti-joins <persist>.barrier_overrides (every group's
  # rows); the reduction must lift at least as much, or a position lifted in
  # the view prunes a frontier the view treats as real (#326 review).
  run <- function(exists, schema_cfg = "fresh") {
    log <- list()
    local_mocked_bindings(
      .lnk_db_execute = function(conn, sql) {
        log[[length(log) + 1L]] <<- sql
        invisible(NULL)
      },
      .lnk_table_exists = function(conn, table) {
        expect_identical(table, "fresh.barrier_overrides")
        exists
      }
    )
    local_mocked_bindings(frs_barriers_minimal = function(...) invisible(NULL),
                          .package = "fresh")
    cfg <- structure(list(species = "BT",
                          pipeline = list(schema = schema_cfg)),
                     class = "lnk_config")
    loaded <- list(
      parameters_fresh = data.frame(species_code = "BT",
                                    access_gradient_max = 0.25),
      wsg_species_presence = .pm_presence(bt = "t"))
    .lnk_pipeline_prep_minimal("mock-conn", aoi = "BULK", cfg = cfg,
      loaded = loaded, schema = "w")
    sql <- unlist(log)
    sql[grepl("CREATE TABLE w\\.barriers_bt AS", sql)]
  }
  bt <- run(TRUE)
  expect_match(bt, "FROM w\\.barrier_overrides o")
  expect_match(bt, "FROM fresh\\.barrier_overrides p")
  expect_match(bt, "p\\.species_code = 'BT'")
  expect_match(bt,
    "abs\\(p\\.downstream_route_measure - n\\.downstream_route_measure\\) < 1")
  # Both lifts sit before the definite barriers, which are never lifted.
  expect_lt(regexpr("barrier_overrides p", bt), regexpr("barriers_definite d", bt))
  # No persisted table yet (a first build): the working lift alone.
  bt0 <- run(FALSE)
  expect_no_match(bt0, "barrier_overrides p")
  expect_match(bt0, "FROM w\\.barrier_overrides o")
})

# -- prep_network SQL shape --------------------------------------------------

test_that(".lnk_pipeline_prep_network loads fresh.streams with FWA filters", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    },
    # The discharge join checks its source table first (#331).
    lnk_preflight_discharge = function(...) invisible(list(ok = TRUE))
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

test_that(".lnk_pipeline_prep_network joins mad_m3s onto the working streams (#286, #305)", {
  run <- function(fill) {
    captured <- character(0)
    local_mocked_bindings(
      .lnk_db_execute = function(conn, sql) {
        captured <<- c(captured, sql)
        invisible(NULL)
      },
      # The discharge join checks its source table first (#331).
      lnk_preflight_discharge = function(...) invisible(list(ok = TRUE))
    )
    local_mocked_bindings(
      frs_col_join = function(...) invisible(NULL),
      frs_col_generate = function(...) invisible(NULL),
      .package = "fresh"
    )
    .lnk_pipeline_prep_network("mock-conn", aoi = "BULK", schema = "w_bulk",
                               fill = fill)
    captured
  }
  for (fill in c(FALSE, TRUE)) {
    sql <- run(fill)
    # Typed here: frs_col_join() types a subquery's columns text (#305).
    add <- grep("ADD COLUMN IF NOT EXISTS mad_m3s double precision", sql,
                fixed = TRUE, value = TRUE)
    expect_length(add, 1L)
    expect_match(add, "w_bulk.streams", fixed = TRUE)
    expect_match(add, "mad_m3s_source text", fixed = TRUE)
    upd <- grep("SET mad_m3s = d.mad_m3s", sql, fixed = TRUE, value = TRUE)
    expect_length(upd, 1L)
    expect_match(upd, "whse_basemapping.fwa_stream_networks_discharge",
                 fixed = TRUE)
    expect_match(upd, "d.linear_feature_id = t.linear_feature_id",
                 fixed = TRUE)
    expect_identical(grepl("LATERAL", upd, fixed = TRUE), fill)
  }
})

test_that("mad_m3s stays out of the persisted streams shape (#286)", {
  # Decided in #286: working table only, so existing persist schemas need
  # no migration.
  expect_false("mad_m3s" %in% names(cols_streams))
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
    },
    .lnk_db_execute = function(conn, sql) invisible(NULL)
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
    },
    .lnk_db_execute = function(conn, sql) invisible(NULL)
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
    },
    .lnk_db_execute = function(conn, sql) invisible(NULL)
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
    },
    .lnk_db_execute = function(conn, sql) invisible(NULL)
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


# --- Golden regression net for .lnk_pipeline_prep_dams (link#227 Phase 0) ---
#
# The CABD dam snap is the most delicate SQL in the package, and link#227
# refactors it so the guard can share the exact same filters rather than
# maintain a second copy that drifts. This test pins current behaviour FIRST,
# so the refactor is provably behaviour-preserving.

test_that(".lnk_pipeline_prep_dams output is stable (golden, pre-refactor)", {
  conn <- skip_if_no_db()
  cfg <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)
  schema <- "working_golden_dams"

  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", schema))
  withr::defer(
    try(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema)),
        silent = TRUE))

  # ADMS: smallest WSG that still carries dams.
  .lnk_pipeline_prep_dams(conn, conn_tunnel = conn, aoi = "ADMS",
                          schema = schema, loaded = loaded)

  got <- DBI::dbGetQuery(conn, sprintf(
    "SELECT dam_id, watershed_group_code, passability_status_code,
            blue_line_key, round(downstream_route_measure::numeric, 2) AS drm
       FROM %s.dams ORDER BY dam_id", schema))

  # AOI filter applied: nothing outside ADMS survives step 4.
  expect_true(all(got$watershed_group_code == "ADMS"))
  expect_gt(nrow(got), 0L)

  # The blocking subset is what the link#227 guard must reproduce exactly.
  blocking <- got[got$passability_status_code %in% c(1L, 2L), ]
  expect_gt(nrow(blocking), 0L)

  # Pinned dam ids, re-pinned 2026-10-22 against docker fwapg with cabd.dams
  # at 2,592 rows (load of 2026-10-17; link#345). The 2026-08-28 pin was 8
  # dams at 2,594 rows; the bcfishpass reference's own bcfishpass.dams holds
  # these same 7 for ADMS, so the eighth left CABD upstream. Ids, not a
  # count, so the next CABD change names what moved. Not expect_snapshot():
  # snapshots skip on CRAN, which would make the regression net silently
  # absent in exactly the run that matters. Re-pin deliberately rather than
  # loosening the assertion.
  expect_identical(got$dam_id, c(
    "2e2f177c-3643-40a1-862b-efab63d6d0c8",
    "30931810-86cc-4e9e-96d8-a6d8df138bd4",
    "5e806d7e-6ef9-4db0-b122-40425035d13e",
    "841a71fd-89e0-4d9d-a486-7dcca3b8443a",
    "9b0ee2e6-1e55-4f97-bd9a-a7c950dd7baf",
    "b48ea884-cab3-478d-863d-5033dbcf0bea",
    "fc6931e8-ded6-42a2-bd0b-1a5b4b72d0e4"
  ))
  expect_identical(nrow(blocking), nrow(got))
  expect_true(all(got$passability_status_code == 1L))

  # dam_id uniqueness encodes DISTINCT ON (c.dam_id) — one row per dam even
  # though the lateral snap can match several stream segments.
  expect_identical(anyDuplicated(got$dam_id), 0L)

  # Every dam snapped to a real blue line; the 65 m filter drops the rest.
  expect_false(any(is.na(got$blue_line_key)))
})

# --- Phase 1 (#227): shared SQL builders --------------------------------

test_that(".lnk_dams_matched_sql keeps the snap semantics intact", {
  sql <- .lnk_dams_matched_sql()
  # Each of these encodes a distinct filter the guard must inherit exactly.
  expect_match(sql, "CROSS JOIN LATERAL", fixed = TRUE)
  expect_match(sql, "<= 65", fixed = TRUE)              # snap distance
  expect_match(sql, "DISTINCT ON (c.dam_id)", fixed = TRUE)  # one row per dam
  expect_match(sql, "999'::ltree", fixed = TRUE)        # excluded wscode
  expect_match(sql, "ORDER BY str.geom <-> c.geom", fixed = TRUE)  # KNN
})

test_that(".lnk_dams_cabd_sql applies all three edit CSVs", {
  sql <- .lnk_dams_cabd_sql("SRC", "EXCL", "XREF", "UPD")
  expect_match(sql, "FROM SRC d", fixed = TRUE)
  expect_match(sql, "LEFT OUTER JOIN EXCL x", fixed = TRUE)
  expect_match(sql, "LEFT OUTER JOIN XREF blk", fixed = TRUE)
  expect_match(sql, "LEFT OUTER JOIN UPD u", fixed = TRUE)
  # Exclusions are an anti-join, not a filter on the dam source.
  expect_match(sql, "WHERE x.cabd_id IS NULL", fixed = TRUE)
  # Passability override wins over the raw code.
  expect_match(sql, "COALESCE(u.passability_status_code", fixed = TRUE)
})

test_that("the emitted prep_dams DDL still carries the snap semantics", {
  captured <- character()
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(conn)
    }
  )
  # Only the SQL assembly is under test; stub the round trip and the writes.
  with_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      data.frame(cabd_id = character(0), passability_status_code = integer(0))
    },
    dbWriteTable = function(conn, name, value, ...) invisible(TRUE),
    .package = "DBI",
    {
      cfg <- lnk_config("bcfishpass")
      loaded <- lnk_load_overrides(cfg)
      .lnk_pipeline_prep_dams(structure(list(), class = "DBIConnection"),
                              conn_tunnel = structure(list(),
                                                      class = "DBIConnection"),
                              aoi = "ADMS", schema = "s", loaded = loaded)
    }
  )
  ddl <- paste(captured, collapse = "\n")
  expect_match(ddl, "CROSS JOIN LATERAL", fixed = TRUE)
  expect_match(ddl, "<= 65", fixed = TRUE)
  expect_match(ddl, "DISTINCT ON (c.dam_id)", fixed = TRUE)
  expect_match(ddl, "UNION ALL", fixed = TRUE)   # the cabd_additions `usa` CTE
})

test_that(".lnk_dams_edit_values_sql quotes literals and survives empty CSVs", {
  conn <- structure(list(), class = "DBIConnection")
  with_mocked_bindings(
    dbQuoteLiteral = function(conn, x, ...) {
      paste0("'", gsub("'", "''", as.character(x)), "'")
    },
    .package = "DBI",
    {
      # A cabd_id carrying a quote must not break out of the VALUES list.
      v <- .lnk_dams_edit_values_sql(
        conn, list(cabd_exclusions = data.frame(cabd_id = "o'brien",
                                                stringsAsFactors = FALSE)))
      expect_match(v$excl, "o''brien", fixed = TRUE)
      # Absent CSVs still yield a typed sentinel so the LEFT JOIN shape holds.
      expect_match(v$xref, "NULL::text", fixed = TRUE)
      expect_match(v$upd, "NULL::integer", fixed = TRUE)
    }
  )
})


# -- province-wide observations for barrier lifts (link#349) -----------------

test_that("prep_observations builds observations_province from every group's presence", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  loaded <- list(
    wsg_species_presence = data.frame(
      watershed_group_code = c("UPCE", "PARS", "XXXX"),
      bt = c("t", "t", "f"), ch = "f", cm = "f", co = "f", ct = "f",
      dv = "f", ko = c("f", "t", "f"), pk = "f", rb = c("t", "t", "f"),
      sk = "f", st = "f", wct = "f",
      stringsAsFactors = FALSE),
    observation_exclusions = data.frame(
      observation_key = c("aaa", "bbb"), data_error = c(TRUE, FALSE),
      release_exclude = c(FALSE, FALSE), stringsAsFactors = FALSE))
  .lnk_pipeline_prep_observations("mock", aoi = "UPCE", loaded = loaded,
    schema = "w_upce", observations = "bcfishobs.observations")

  prov <- grep("CREATE TABLE w_upce\\.observations_province AS", captured,
               value = TRUE)
  expect_length(prov, 1L)
  # Each record kept by its OWN group's presence: PARS's KO counts toward a
  # barrier in UPCE, where KO is absent; nothing from XXXX, which has none.
  expect_match(prov, "('UPCE', 'BT')", fixed = TRUE)
  expect_match(prov, "('PARS', 'KO')", fixed = TRUE)
  expect_no_match(prov, "('UPCE', 'KO')", fixed = TRUE)
  expect_no_match(prov, "XXXX", fixed = TRUE)
  expect_match(prov, "p.watershed_group_code = o.watershed_group_code",
               fixed = TRUE)
  expect_match(prov, "p.species_code = o.species_code", fixed = TRUE)
  expect_no_match(prov, "o.watershed_group_code = 'UPCE'", fixed = TRUE)
  expect_match(prov, "observation_key NOT IN ('aaa')", fixed = TRUE)
  expect_true(any(grepl("observations_province USING gist (wscode)", captured,
                        fixed = TRUE)))
  # The AOI table is unchanged: this group's own observations only.
  aoi <- grep("CREATE TABLE w_upce\\.observations AS", captured, value = TRUE)
  expect_match(aoi, "o.watershed_group_code = 'UPCE'", fixed = TRUE)
})

test_that("prep_overrides counts lifts over observations_province, then drops it", {
  captured <- list()
  sent <- character(0)
  local_mocked_bindings(
    lnk_barrier_overrides = function(conn, ...) {
      captured[["args"]] <<- list(...)
      sent <<- c(sent, "overrides")
      invisible(NULL)
    },
    .lnk_db_execute = function(conn, sql) { sent <<- c(sent, sql); invisible(NULL) }
  )
  .lnk_pipeline_prep_overrides("mock-conn",
    loaded = list(parameters_fresh = data.frame(species_code = "BT")),
    schema = "working_bulk")
  expect_equal(captured$args$observations, "working_bulk.observations_province")
  # Dropped after the count, never before it: a kept working schema must not
  # hold a province-wide copy per group.
  expect_equal(sent, c("overrides",
    "DROP TABLE IF EXISTS working_bulk.observations_province"))
})

test_that("study_area_run.sh models with the gate off on both legs (#349)", {
  # The gate is one-way; a dispatch's recompute settles on final access. The
  # cloud leg is an ssh string, so an export on the local leg alone would not
  # reach it (the LNK_GUARD_DOWNSTREAM trap, #227).
  f <- testthat::test_path("..", "..", "data-raw", "study_area_run.sh")
  skip_if_not(file.exists(f), "data-raw is not shipped with the package")
  src <- readLines(f)
  local_leg <- grep("Rscript data-raw/wsg_run_one.R \"\\$w\"", src) - 1L
  expect_length(local_leg, 1L)
  expect_match(src[local_leg], "LNK_HABITAT_GATE=0", fixed = TRUE)
  # The ssh leg's command is built by remote_leg_cmd (study_area_remote.sh,
  # link#376), which the driver's ssh call uses.
  expect_length(grep('"$(remote_leg_cmd "$WS" "$B_SPACE")"', src, fixed = TRUE), 1L)
  remote <- readLines(testthat::test_path("..", "..", "data-raw", "study_area_remote.sh"))
  ssh_leg <- grep("wsg_run_one.R", remote, value = TRUE)
  expect_length(ssh_leg, 1L)
  expect_match(ssh_leg, "export LNK_HABITAT_GATE=0 &&", fixed = TRUE)
})

test_that("the province table lifts a barrier the AOI table cannot (DB)", {
  skip_if_no_db()
  conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                      user = "postgres", password = "postgres")
  withr::defer(DBI::dbDisconnect(conn))
  s <- "zz_lnk_obs_scope_probe"
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", s))
  withr::defer(try(DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", s)),
                   silent = TRUE))

  # One barrier on line 1 at 100 m, held by group AAAA. One RB observation
  # 5 km upstream on the same line, recorded in group BBBB.
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s.natural_barriers AS
     SELECT 1 AS blue_line_key, 100::double precision AS downstream_route_measure,
            'blocked'::text AS label, '100'::ltree AS wscode_ltree,
            '100'::ltree AS localcode_ltree", s))
  obs <- "SELECT 'k1'::text AS observation_key, 'RB'::text AS species_code,
                 %s::text AS watershed_group_code, 1 AS blue_line_key,
                 5000::double precision AS downstream_route_measure,
                 '100'::ltree AS wscode, '100'::ltree AS localcode,
                 '2001-06-01'::date AS observation_date"
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s.obs_province AS %s", s,
                               sprintf(obs, "'BBBB'")))
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s.obs_aoi AS %s WHERE FALSE", s,
                               sprintf(obs, "'BBBB'")))

  params <- lnk_load_overrides(lnk_config("default"))$parameters_fresh
  rb <- params[params$species_code == "RB", , drop = FALSE]
  lift <- function(obs_table) {
    to <- paste0(s, ".ov_", sub(".*\\.", "", obs_table))
    lnk_barrier_overrides(conn, barriers = paste0(s, ".natural_barriers"),
                          observations = obs_table, params = rb, to = to,
                          verbose = FALSE)
    DBI::dbGetQuery(conn, sprintf("SELECT * FROM %s", to))
  }
  # default's RB rule (one RB observation, no date floor) lifts it with the
  # province table, and cannot with the AOI's own observations.
  got <- lift(paste0(s, ".obs_province"))
  expect_equal(nrow(got), 1L)
  expect_equal(got$species_code, "RB")
  expect_equal(nrow(lift(paste0(s, ".obs_aoi"))), 0L)
})


# --- cabd_additions placeholders (link#244, link#367) -----------------------

test_that(".lnk_dams_usa_sql gives the placeholders a code only as barriers", {
  off <- .lnk_dams_usa_sql("A")
  on <- .lnk_dams_usa_sql("A", barrier = TRUE)
  expect_match(off, "NULL::integer AS passability_status_code", fixed = TRUE)
  # Only rows the CSV marks as barriers get a code.
  expect_match(on, "CASE WHEN lower(a.barrier_ind::text) IN ('t', 'true', '1')",
               fixed = TRUE)
  expect_false(grepl("barrier_ind", off, fixed = TRUE))
  # Numbered in CSV order, stated: the ids become barrier ids, and the guard
  # looks them up in the persisted barriers.
  expect_match(off, "row_number() OVER (ORDER BY a.csv_row, s.linear_feature_id)", fixed = TRUE)
  expect_match(on, "row_number() OVER (ORDER BY a.csv_row, s.linear_feature_id)", fixed = TRUE)
  expect_match(off, "FROM A a", fixed = TRUE)
  expect_match(off, "WHERE a.feature_type = 'dams'", fixed = TRUE)
  expect_error(.lnk_dams_usa_sql("A", barrier = NA))
})

test_that("default sets cabd_additions_barriers; bcfishpass leaves it off", {
  expect_true(.lnk_cabd_additions_barriers(lnk_config("default")))
  expect_true(.lnk_cabd_additions_barriers(lnk_config("default_tuned")))
  expect_false(.lnk_cabd_additions_barriers(lnk_config("bcfishpass")))
  expect_false(.lnk_cabd_additions_barriers(NULL))
})

test_that("a non-logical cabd_additions_barriers fails at config load", {
  expect_error(.lnk_config_pipeline_check(list(cabd_additions_barriers = "yes"), "x"),
               "cabd_additions_barriers must be true or false")
  expect_error(.lnk_config_pipeline_check(list(cabd_additions_barriers = NA), "x"),
               "cabd_additions_barriers must be true or false")
  expect_identical(
    .lnk_config_pipeline_check(list(cabd_additions_barriers = TRUE), "x"),
    list(cabd_additions_barriers = TRUE))
})

test_that("prep_dams makes the placeholders barriers under default only", {
  conn <- skip_if_no_db()
  schema <- "working_usa_dams"
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", schema))
  withr::defer(
    try(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema)),
        silent = TRUE))

  got <- lapply(c("bcfishpass", "default"), function(nm) {
    cfg <- lnk_config(nm)
    .lnk_pipeline_prep_dams(conn, conn_tunnel = conn, aoi = "LARL",
                            schema = schema, loaded = lnk_load_overrides(cfg),
                            cfg = cfg)
    DBI::dbGetQuery(conn, sprintf(
      "SELECT dam_id, passability_status_code AS psc FROM %s.dams
        WHERE dam_id LIKE '12000%%' ORDER BY dam_id", schema))
  })
  # LARL holds three of the five placeholders, CSV rows 2-4 (Columbia, Big
  # and Little Sheep creeks); row 1 is the Kettle (KETL), row 5 Ross (SKGT).
  expect_identical(got[[1]]$dam_id, c("1200000002", "1200000003", "1200000004"))
  expect_identical(got[[2]]$dam_id, got[[1]]$dam_id)
  expect_true(all(is.na(got[[1]]$psc)))
  expect_true(all(got[[2]]$psc == 1L))
})

test_that(".lnk_cabd_additions_rows numbers cabd_additions only", {
  df <- data.frame(name = c("a", "b", "c"))
  expect_identical(.lnk_cabd_additions_rows(df)$csv_row, 1:3)
  expect_identical(.lnk_cabd_additions_rows(df, "cabd_exclusions"), df)
  expect_null(.lnk_cabd_additions_rows(NULL))
})

test_that("lnk_pipeline_prepare passes cfg to prep_dams", {
  # prep_dams reads the knob from cfg; with cfg NULL it falls back to
  # bcfishpass's behaviour, so a dropped argument would leave `default`'s
  # placeholders off the barriers with every other test green (link#367).
  seen <- NULL
  noop <- function(...) invisible(NULL)
  local_mocked_bindings(
    .lnk_pipeline_prep_load_aux = noop,
    .lnk_pipeline_prep_observations = noop,
    .lnk_pipeline_prep_gradient = noop,
    .lnk_pipeline_prep_natural = noop,
    .lnk_pipeline_prep_overrides = noop,
    .lnk_pipeline_prep_minimal = noop,
    .lnk_pipeline_prep_network = noop,
    .lnk_discharge_fill_applied = function(...) FALSE,
    .lnk_pipeline_prep_dams = function(conn, conn_tunnel, aoi, schema, loaded,
                                       cfg = NULL) {
      seen <<- .lnk_cabd_additions_barriers(cfg)
      invisible(NULL)
    }
  )
  lnk_pipeline_prepare(fake_conn(), "LARL", lnk_config("default"), list(),
                       schema = "w_larl")
  expect_true(seen)
})
