# Tests for the run-provenance log primitives (link#127).

# --- .lnk_host --------------------------------------------------------------

test_that(".lnk_host honours LNK_HOST_ALIAS", {
  withr::local_envvar(LNK_HOST_ALIAS = "m4")
  expect_identical(.lnk_host(), "m4")
})

test_that(".lnk_host falls back to nodename when the alias is unset", {
  withr::local_envvar(LNK_HOST_ALIAS = "")
  expect_identical(.lnk_host(), unname(Sys.info()[["nodename"]]))
})


# --- .lnk_run_id ------------------------------------------------------------

test_that(".lnk_run_id has the documented shape", {
  withr::local_envvar(LNK_HOST_ALIAS = "m4")
  id <- .lnk_run_id()
  expect_match(id, "^m4-[0-9]{8}T[0-9]{6}\\.[0-9]{3}-[0-9a-f]{6}$")
})

test_that(".lnk_run_id is unique across many draws", {
  ids <- vapply(seq_len(500), function(i) .lnk_run_id(), character(1))
  expect_identical(length(unique(ids)), 500L)
})

test_that(".lnk_run_id strips punctuation from the host", {
  withr::local_envvar(LNK_HOST_ALIAS = "my.host-01")
  expect_match(.lnk_run_id(), "^myhost01-")
})


# --- .lnk_config_hash -------------------------------------------------------

test_that(".lnk_config_hash is stable across calls and prefixed sha256:", {
  cfg <- lnk_config("default")
  h1 <- .lnk_config_hash(cfg)
  h2 <- .lnk_config_hash(cfg)
  expect_identical(h1, h2)
  expect_match(h1, "^sha256:[0-9a-f]{64}$")
})

test_that(".lnk_config_hash differs between bundles", {
  expect_false(identical(
    .lnk_config_hash(lnk_config("default")),
    .lnk_config_hash(lnk_config("bcfishpass"))
  ))
})

test_that(".lnk_config_hash rejects non-config input", {
  expect_error(.lnk_config_hash(list(name = "x")), "lnk_config")
})

# A bundle copied to a temp dir, so we can mutate it. This is the acceptance
# criterion "changing one value yields a new config_hash", provable without a
# database.
local_bundle_copy <- function(name = "default", env = parent.frame()) {
  src <- system.file("extdata", "configs", name, package = "link")
  if (!nzchar(src)) skip("bundle not found in installed package")
  dest_root <- withr::local_tempdir(.local_envir = env)
  dest <- file.path(dest_root, name)
  dir.create(dest, recursive = TRUE)
  file.copy(list.files(src, full.names = TRUE), dest, recursive = TRUE)
  dest
}

test_that(".lnk_config_hash changes when one byte of parameters_fresh.csv changes", {
  dir <- local_bundle_copy("default")
  before <- .lnk_config_hash(lnk_config(dir))

  pf <- file.path(dir, "parameters_fresh.csv")
  txt <- readLines(pf, warn = FALSE)
  txt[2] <- sub("^([^,]*,)", "\\1", txt[2])          # no-op guard
  writeLines(c(txt, ""), pf)                          # append a byte

  after <- .lnk_config_hash(lnk_config(dir))
  expect_false(identical(before, after))
})

test_that(".lnk_config_hash changes when config.yaml pipeline$schema changes", {
  # The gap a verify-derived hash would have missed: config.yaml is absent
  # from its own provenance: block.
  dir <- local_bundle_copy("default")
  before <- .lnk_config_hash(lnk_config(dir))

  yml <- file.path(dir, "config.yaml")
  txt <- readLines(yml, warn = FALSE)
  txt <- sub("^(\\s*schema:\\s*).*$", "\\1fresh_scenario_b", txt)
  writeLines(txt, yml)

  after <- .lnk_config_hash(lnk_config(dir))
  expect_false(identical(before, after))
})

test_that(".lnk_config_hash tolerates a missing declared file", {
  dir <- local_bundle_copy("default")
  cfg <- lnk_config(dir)
  # Removing a provenanced-but-not-required file must not error; the hash
  # simply changes (MISSING sentinel).
  victim <- file.path(dir, "overrides", "cabd_additions.csv")
  skip_if_not(file.exists(victim))
  before <- .lnk_config_hash(cfg)
  file.remove(victim)
  expect_silent(after <- .lnk_config_hash(cfg))
  expect_false(identical(before, after))
})


# --- .lnk_fwapg_sha ---------------------------------------------------------

test_that(".lnk_fwapg_sha prefers the env var", {
  withr::local_envvar(FWAPG_GIT_SHA = "deadbeef")
  expect_identical(.lnk_fwapg_sha(), "deadbeef")
})

test_that(".lnk_fwapg_sha returns NA when nothing resolves", {
  withr::local_envvar(FWAPG_GIT_SHA = "", FWAPG_DIR = withr::local_tempdir())
  # HOME-based fallback may still find a real checkout on a dev machine, so
  # only assert the type contract.
  out <- .lnk_fwapg_sha()
  expect_true(is.character(out) && length(out) == 1L)
})


# --- .lnk_bcfishobs_sha (link#264) ------------------------------------------

test_that(".lnk_bcfishobs_sha prefers the env var", {
  # The tier every cypher takes: no bcfishobs checkout exists there, so
  # study_area_run.sh resolves it once on the dispatcher and exports it.
  withr::local_envvar(BCFISHOBS_GIT_SHA = "08630cf4ac14")
  expect_identical(.lnk_bcfishobs_sha(), "08630cf4ac14")
})

test_that(".lnk_bcfishobs_sha reads a real checkout via BCFISHOBS_DIR", {
  # Both known answers for the directory tier, against a real git repo rather
  # than a mock: the value must come from HEAD, not from the env.
  skip_if(!nzchar(Sys.which("git")), "git not installed")
  d <- withr::local_tempdir()
  run <- function(...) {
    out <- suppressWarnings(system2("git", c("-C", shQuote(d), ...),
                                    stdout = TRUE, stderr = FALSE))
    st <- attr(out, "status")
    if (!is.null(st) && !identical(as.integer(st), 0L)) stop("git setup failed")
    invisible(out)
  }
  writeLines("x", file.path(d, "README.md"))
  run("init", "-q", ".")
  run("add", "-A")
  run("-c", "user.email=t@example.com", "-c", "user.name=t",
      "commit", "-qm", "init")
  head <- suppressWarnings(system2("git", c("-C", shQuote(d), "rev-parse", "HEAD"),
                                   stdout = TRUE, stderr = FALSE))[1]

  withr::local_envvar(BCFISHOBS_GIT_SHA = "", BCFISHOBS_DIR = d)
  expect_identical(.lnk_bcfishobs_sha(), head)
})

test_that(".lnk_bcfishobs_sha returns NA when nothing resolves", {
  # HOME-based fallback may find a real checkout on a dev machine, so assert
  # the type contract, exactly as the fwapg test above does.
  withr::local_envvar(BCFISHOBS_GIT_SHA = "",
                      BCFISHOBS_DIR = withr::local_tempdir())
  out <- .lnk_bcfishobs_sha()
  expect_true(is.character(out) && length(out) == 1L)
})

test_that("fwapg and bcfishobs resolvers do not read each other's env", {
  # They share .lnk_checkout_sha(), so a copy-paste of the wrong variable name
  # is the failure this closes -- and it would be invisible on a machine where
  # both checkouts sit at the conventional path.
  withr::local_envvar(FWAPG_GIT_SHA = "fwapg000000",
                      BCFISHOBS_GIT_SHA = "bcfishobs00")
  expect_identical(.lnk_fwapg_sha(), "fwapg000000")
  expect_identical(.lnk_bcfishobs_sha(), "bcfishobs00")
})


# --- .lnk_pkg_git_dirty -----------------------------------------------------

test_that(".lnk_pkg_git_dirty honours the env override", {
  withr::local_envvar(LINK_GIT_DIRTY = "true")
  expect_true(.lnk_pkg_git_dirty("link"))
  withr::local_envvar(LINK_GIT_DIRTY = "0")
  expect_false(.lnk_pkg_git_dirty("link"))
})

test_that(".lnk_pkg_git_dirty returns NA for an unknown package", {
  withr::local_envvar(NOSUCHPKG_GIT_DIRTY = "")
  expect_true(is.na(.lnk_pkg_git_dirty("nosuchpkg")))
})


# --- lnk_stamp additive slots ----------------------------------------------

test_that("lnk_stamp gains host/config_hash/config_drift without losing old slots", {
  cfg <- lnk_config("default")
  st <- lnk_stamp(cfg, conn = NULL, aoi = "PINE")

  # new
  expect_match(st$config_hash, "^sha256:")
  expect_true(is.character(st$host) && nzchar(st$host))
  expect_true(is.logical(st$config_drift) || is.na(st$config_drift))
  expect_true("dirty" %in% names(st$software$link))

  # pre-existing contract intact
  expect_identical(st$config_name, cfg$name)
  expect_true(all(c("config_dir", "provenance", "software", "db", "run",
                    "result") %in% names(st)))
  expect_null(st$db)
  expect_identical(st$run$aoi, "PINE")
  expect_s3_class(st, "lnk_stamp")
})


# --- Phase 2: DDL -----------------------------------------------------------

# Capture SQL without a database, mirroring test-lnk_persist_init.R.
capture_ddl <- function(expr) {
  captured <- character()
  testthat::local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(conn)
    }
  )
  force(expr)
  captured
}

test_that(".lnk_log_create_tables emits a CREATE TABLE for every spec", {
  # Enumerated, not a remembered count: the name used to say "all four" and
  # kept passing at five, because it asserts presence rather than coverage.
  sql <- capture_ddl(.lnk_log_create_tables(NULL, "fresh_test"))
  joined <- paste(sql, collapse = "\n")
  for (tbl in c("log", "log_recompute", "log_input", "log_parameters_fresh",
                "log_dimensions")) {
    expect_match(joined,
      sprintf("CREATE TABLE IF NOT EXISTS fresh_test\\.%s \\(", tbl))
  }
})

test_that("log uses a TEXT run_id primary key, not a serial", {
  # A serial would collide across hosts when schema_consolidate COPYs
  # literal values between schemas whose sequences both start at 1.
  sql <- paste(capture_ddl(.lnk_log_create_tables(NULL, "s")), collapse = "\n")
  expect_match(sql, "run_id text NOT NULL")
  expect_match(sql, "PRIMARY KEY \\(run_id\\)")
  expect_no_match(sql, "serial")
})

test_that("log carries array columns and a watershed_group_code", {
  sql <- paste(capture_ddl(.lnk_log_create_tables(NULL, "s")), collapse = "\n")
  expect_match(sql, "species text\\[\\]")
  expect_match(sql, "wsg_upstream text\\[\\]")
  # Required for schema_consolidate.R auto-discovery.
  expect_match(sql, "watershed_group_code varchar\\(4\\) NOT NULL")
})

test_that("config snapshot tables key on config_hash", {
  sql <- paste(capture_ddl(.lnk_log_create_tables(NULL, "s")), collapse = "\n")
  expect_match(sql, "PRIMARY KEY \\(config_hash, species_code\\)")
  expect_match(sql, "PRIMARY KEY \\(config_hash, species\\)")
})

test_that("ADD COLUMN IF NOT EXISTS is emitted for every expected column", {
  # CREATE TABLE IF NOT EXISTS cannot ship a new config column; this is what
  # makes the wide design safe against dictionary growth.
  sql <- paste(capture_ddl(.lnk_log_create_tables(NULL, "s")), collapse = "\n")
  for (nm in names(cols_log)) {
    expect_match(sql,
      sprintf("ALTER TABLE s\\.log ADD COLUMN IF NOT EXISTS %s ", nm))
  }
  # NOT NULL must be stripped when back-filling an existing populated table.
  expect_no_match(sql, "ADD COLUMN IF NOT EXISTS [a-z_]+ [a-z()0-9\\[\\]]+ NOT NULL")
})

test_that("indexes are created IF NOT EXISTS", {
  sql <- paste(capture_ddl(.lnk_log_create_tables(NULL, "s")), collapse = "\n")
  expect_match(sql, "CREATE INDEX IF NOT EXISTS log_wsg_date_idx")
  expect_match(sql, "CREATE INDEX IF NOT EXISTS log_config_idx")
  expect_match(sql, "CREATE INDEX IF NOT EXISTS log_input_rn_idx")
})


# --- dictionary-driven columns must cover EVERY bundle ----------------------

bundle_union <- function(file) {
  dirs <- list.dirs(system.file("extdata", "configs", package = "link"),
                    recursive = FALSE)
  out <- character()
  for (d in dirs) {
    f <- file.path(d, file)
    if (file.exists(f)) {
      out <- union(out, names(utils::read.csv(f, check.names = FALSE, nrows = 1)))
    }
  }
  out
}

test_that("log_parameters_fresh covers the union of every bundle's header", {
  # Bundles carry different column subsets, so coverage must be asserted
  # against the union, never a single bundle.
  cols <- setdiff(names(.lnk_cols_log_parameters_fresh()), "config_hash")
  expect_setequal(cols, bundle_union("parameters_fresh.csv"))
})

test_that("log_dimensions covers the union of every bundle's header", {
  cols <- setdiff(names(.lnk_cols_log_dimensions()), "config_hash")
  expect_setequal(cols, bundle_union("dimensions.csv"))
})

test_that("snapshot value columns are text, only keys are constrained", {
  cols <- .lnk_cols_log_parameters_fresh()
  expect_identical(unname(cols[["species_code"]]), "text NOT NULL")
  expect_identical(unname(cols[["access_gradient_max"]]), "text")
})

test_that(".lnk_input_primitives lists the pipeline's inputs with a source", {
  p <- .lnk_input_primitives()
  expect_true(all(c("table_name", "source") %in% names(p)))
  expect_true("whse_basemapping.fwa_stream_networks_sp" %in% p$table_name)
  expect_true("bcfishobs.observations" %in% p$table_name)
  expect_false(any(is.na(p$source) | !nzchar(p$source)))
})


# --- Phase 3: write path ----------------------------------------------------

fake_conn <- function() structure(list(), class = "DBIConnection")

# Capture SQL AND stub the DBI probes the write path makes.
capture_write <- function(expr, probe_rows = 0L, query_result = NULL) {
  captured <- character()
  testthat::local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(conn)
    }
  )
  testthat::with_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (!is.null(query_result)) return(query_result)
      if (probe_rows > 0L) data.frame(x = seq_len(probe_rows)) else
        data.frame()
    },
    dbQuoteLiteral = function(conn, x, ...) {
      if (is.logical(x)) return(if (isTRUE(x)) "TRUE" else "FALSE")
      paste0("'", gsub("'", "''", as.character(x)), "'")
    },
    .package = "DBI",
    force(expr)
  )
  captured
}

test_that(".lnk_log_run_start opens a row with date_start and NULL date_end", {
  cfg <- lnk_config("default")
  sql <- capture_write(
    .lnk_log_run_start(fake_conn(), cfg, "PINE", "working_pine"))
  ins <- grep("INSERT INTO .*\\.log \\(", sql, value = TRUE)
  expect_length(ins, 1L)
  expect_match(ins, "date_start")
  expect_match(ins, "now\\(\\)")
  # date_end must not be set at open time.
  expect_no_match(ins, "date_end")
})

test_that(".lnk_log_run_start records wsg_upstream as a text array", {
  cfg <- lnk_config("default")
  sql <- capture_write(
    .lnk_log_run_start(fake_conn(), cfg, "PINE", "working_pine"))
  ins <- grep("INSERT INTO .*\\.log \\(", sql, value = TRUE)
  expect_match(ins, "wsg_upstream")
  expect_match(ins, "ARRAY\\[\\]::text\\[\\]|ARRAY\\[.*\\]::text\\[\\]")
})

test_that(".lnk_log_run_start creates the tables before inserting", {
  cfg <- lnk_config("default")
  sql <- capture_write(
    .lnk_log_run_start(fake_conn(), cfg, "PINE", "working_pine"))
  first_create <- min(grep("CREATE TABLE IF NOT EXISTS", sql))
  first_insert <- min(grep("INSERT INTO", sql))
  expect_lt(first_create, first_insert)
})

test_that(".lnk_log_run_start returns run_id and config_hash", {
  cfg <- lnk_config("default")
  box <- new.env(parent = emptyenv())
  capture_write(
    assign("out", .lnk_log_run_start(fake_conn(), cfg, "PINE", "working_pine"),
           envir = box))
  expect_match(box$out$run_id, "-[0-9a-f]{6}$")
  expect_match(box$out$config_hash, "^sha256:")
  expect_identical(box$out$schema, cfg$pipeline$schema)
})

test_that(".lnk_log_run_finish sets date_end and species", {
  cfg <- lnk_config("default")
  sql <- capture_write(
    .lnk_log_run_finish(fake_conn(), cfg, "rid-1", species = c("BT", "GR")))
  expect_length(sql, 1L)
  expect_match(sql, "SET date_end = now\\(\\)")
  expect_match(sql, "species = ARRAY\\['BT', 'GR'\\]::text\\[\\]")
  expect_match(sql, "WHERE run_id = 'rid-1'")
})

test_that(".lnk_log_run_fail sets notes and never touches date_end", {
  cfg <- lnk_config("default")
  sql <- capture_write(.lnk_log_run_fail(fake_conn(), cfg, "rid-1"))
  expect_match(sql, "SET notes = ")
  expect_no_match(sql, "date_end")
})

test_that("run_finish soft-fails to a warning rather than erroring", {
  cfg <- lnk_config("default")
  testthat::local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) stop("connection dropped")
  )
  expect_warning(out <- .lnk_log_run_finish(fake_conn(), cfg, "rid-1"),
                 "not finalized")
  expect_false(out)
})

test_that("log_input soft-fails to a warning rather than erroring", {
  testthat::local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) stop("boom")
  )
  testthat::with_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) data.frame(),
    dbQuoteLiteral = function(conn, x, ...) paste0("'", x, "'"),
    .package = "DBI",
    expect_warning(out <- .lnk_log_inputs(fake_conn(), "s", "rid", "PINE"),
                   "log_input not recorded")
  )
  expect_false(out)
})

test_that(".lnk_log_inputs never issues a count(*)", {
  sql <- capture_write(.lnk_log_inputs(fake_conn(), "s", "rid-1", "PINE"))
  joined <- paste(sql, collapse = " ")
  expect_no_match(joined, "count\\(\\*\\)")
  expect_match(joined, "reltuples")
  expect_match(joined, "row_count_estimated")
})

test_that(".lnk_log_inputs covers every declared primitive", {
  sql <- paste(capture_write(
    .lnk_log_inputs(fake_conn(), "s", "rid-1", "PINE")), collapse = " ")
  for (tbl in .lnk_input_primitives()$table_name) {
    expect_match(sql, tbl, fixed = TRUE)
  }
})

test_that("config snapshot skips entirely when the hash is already present", {
  cfg <- lnk_config("default")
  loaded <- list(parameters_fresh = utils::read.csv(
    file.path(cfg$dir, "parameters_fresh.csv"), check.names = FALSE))
  sql <- capture_write(
    .lnk_log_config_snapshot(fake_conn(), "s", cfg, loaded, "sha256:abc"),
    probe_rows = 1L)
  expect_length(sql, 0L)
})

test_that("config snapshot inserts full rows with ON CONFLICT DO NOTHING", {
  cfg <- lnk_config("default")
  loaded <- list(parameters_fresh = utils::read.csv(
    file.path(cfg$dir, "parameters_fresh.csv"), check.names = FALSE))
  sql <- capture_write(
    .lnk_log_config_snapshot(fake_conn(), "s", cfg, loaded, "sha256:abc"),
    probe_rows = 0L)
  joined <- paste(sql, collapse = "\n")
  expect_match(joined, "INSERT INTO s\\.log_parameters_fresh")
  expect_match(joined, "INSERT INTO s\\.log_dimensions")
  expect_match(joined, "ON CONFLICT DO NOTHING")
  # The values actually land, not just the column names.
  expect_match(joined, "'BT'")
})

test_that("config snapshot warns and inserts the intersection on shape drift", {
  cfg <- lnk_config("default")
  df <- utils::read.csv(file.path(cfg$dir, "parameters_fresh.csv"),
                        check.names = FALSE)
  df$not_in_dictionary <- "x"
  expect_warning(
    sql <- capture_write(
      .lnk_log_config_snapshot(fake_conn(), "s", cfg,
                               list(parameters_fresh = df), "sha256:abc"),
      probe_rows = 0L),
    "absent from the dictionary")
  expect_no_match(paste(sql, collapse = " "), "not_in_dictionary")
})


# --- Phase 5: read helper ---------------------------------------------------

test_that("lnk_log_read validates its arguments", {
  cfg <- lnk_config("default")
  expect_error(lnk_log_read("nope", cfg), "DBIConnection")
  expect_error(lnk_log_read(fake_conn(), list(name = "x")), "lnk_config")
  expect_error(lnk_log_read(fake_conn(), cfg, aoi = c("A", "B")), "aoi")
  expect_error(lnk_log_read(fake_conn(), cfg, latest = "yes"))
})

test_that("lnk_log_read builds DISTINCT ON for latest, plain select otherwise", {
  cfg <- lnk_config("default")
  seen <- character()
  testthat::with_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      seen <<- c(seen, statement)
      data.frame()
    },
    dbQuoteLiteral = function(conn, x, ...) paste0("'", x, "'"),
    .package = "DBI",
    {
      lnk_log_read(fake_conn(), cfg)
      lnk_log_read(fake_conn(), cfg, latest = FALSE)
      lnk_log_read(fake_conn(), cfg, aoi = "PINE")
    }
  )
  expect_match(seen[1], "DISTINCT ON \\(watershed_group_code\\)")
  expect_match(seen[1], "ORDER BY watershed_group_code, date_start DESC")
  expect_no_match(seen[2], "DISTINCT ON")
  expect_match(seen[3], "WHERE watershed_group_code = 'PINE'")
})

test_that("lnk_log_read returns a tibble", {
  cfg <- lnk_config("default")
  testthat::with_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      data.frame(run_id = "r1", watershed_group_code = "PINE")
    },
    dbQuoteLiteral = function(conn, x, ...) paste0("'", x, "'"),
    .package = "DBI",
    out <- lnk_log_read(fake_conn(), cfg)
  )
  expect_s3_class(out, "tbl_df")
  expect_identical(out$run_id, "r1")
})


# --- link#262: run identity, recompute log, bcfp pin ------------------------

# --- .lnk_blank_to_na -------------------------------------------------------

test_that(".lnk_blank_to_na treats a set-but-empty value as absent", {
  # Sys.getenv(x, NA) returns NA only when x is UNSET. `export LNK_RUN_UID=""`
  # yields "", which would be quoted into SQL as '' — and an empty-string
  # run_uid joins to every other empty-string row, merging two unlabelled
  # dispatches into one "run". Worse than NULL, not equivalent to it.
  expect_true(is.na(.lnk_blank_to_na("")))
  expect_true(is.na(.lnk_blank_to_na("   ")))
  expect_true(is.na(.lnk_blank_to_na(NA_character_)))
  expect_true(is.na(.lnk_blank_to_na(character(0))))
  expect_identical(.lnk_blank_to_na("field-scope-2026"), "field-scope-2026")
})


# --- DDL --------------------------------------------------------------------

test_that("log_recompute is created alongside the other log tables", {
  sql <- capture_ddl(.lnk_log_create_tables(NULL, "fresh_test"))
  joined <- paste(sql, collapse = "\n")
  for (tbl in c("log", "log_recompute", "log_input",
                "log_parameters_fresh", "log_dimensions")) {
    expect_match(joined,
      sprintf("CREATE TABLE IF NOT EXISTS fresh_test\\.%s \\(", tbl))
  }
})

test_that("log_recompute keys on a TEXT recompute_id, not a serial", {
  # Same reason as `log`: schema_consolidate COPYs literal values between
  # hosts whose sequences would both start at 1.
  sql <- paste(capture_ddl(.lnk_log_create_tables(NULL, "s")), collapse = "\n")
  expect_match(sql, "recompute_id text NOT NULL")
  expect_match(sql, "PRIMARY KEY \\(recompute_id\\)")
})

test_that("log_recompute carries watershed_group_code for consolidate pickup", {
  # schema_consolidate.R discovers tables by "is a BASE TABLE with a
  # watershed_group_code column". Without it a cypher's recompute rows would
  # never travel home, and nothing would say so.
  expect_true("watershed_group_code" %in% names(cols_log_recompute))
})

test_that("log gains run_uid and an index on it", {
  sql <- paste(capture_ddl(.lnk_log_create_tables(NULL, "s")), collapse = "\n")
  expect_match(sql, "run_uid text")
  expect_match(sql, "CREATE INDEX IF NOT EXISTS log_run_uid_idx ON s\\.log \\(run_uid\\)")
  expect_match(sql,
    "CREATE INDEX IF NOT EXISTS log_rc_run_uid_idx ON s\\.log_recompute \\(run_uid\\)")
})

test_that("ADD COLUMN IF NOT EXISTS covers every log_recompute column", {
  # CREATE TABLE IF NOT EXISTS is a no-op against a drifted table, so this is
  # what actually ships a new column to a live schema.
  sql <- paste(capture_ddl(.lnk_log_create_tables(NULL, "s")), collapse = "\n")
  for (nm in names(cols_log_recompute)) {
    expect_match(sql, sprintf(
      "ALTER TABLE s\\.log_recompute ADD COLUMN IF NOT EXISTS %s ", nm))
  }
})

test_that("log_recompute does not claim primitive inputs it never read", {
  # The recompute reads the already-persisted streams / habitat / barriers,
  # not the DB primitives. A fingerprint here would describe inputs it never
  # touched, and log_input is keyed on run_id, not recompute_id.
  expect_false(any(grepl("^(row_count|last_analyze|table_name)$",
                         names(cols_log_recompute))))
})


# --- run_uid on the modelling write path ------------------------------------

test_that(".lnk_log_run_start writes run_uid into the INSERT", {
  cfg <- lnk_config("default")
  sql <- capture_write(
    .lnk_log_run_start(fake_conn(), cfg, "PINE", "working_pine",
                       run_uid = "20260901T120000-abcd1234",
                       run_label = "field-scope"))
  ins <- grep("INSERT INTO .*\\.log \\(", sql, value = TRUE)
  expect_length(ins, 1L)
  expect_match(ins, "run_uid")
  expect_match(ins, "20260901T120000-abcd1234")
  expect_match(ins, "field-scope")
})

test_that(".lnk_log_run_start records a blank run_uid as NULL, not ''", {
  cfg <- lnk_config("default")
  sql <- capture_write(
    .lnk_log_run_start(fake_conn(), cfg, "PINE", "working_pine",
                       run_uid = "", run_label = ""))
  ins <- grep("INSERT INTO .*\\.log \\(", sql, value = TRUE)
  # The VALUES list must carry NULL for both, and no empty string literal.
  expect_no_match(ins, "''\\s*,\\s*''")
})

test_that(".lnk_log_run_start still opens with run_uid absent", {
  # An ad-hoc single-WSG call belongs to no dispatch. NA is the honest answer.
  cfg <- lnk_config("default")
  sql <- capture_write(
    .lnk_log_run_start(fake_conn(), cfg, "PINE", "working_pine"))
  ins <- grep("INSERT INTO .*\\.log \\(", sql, value = TRUE)
  expect_match(ins, "run_uid")
  expect_match(ins, "NULL")
})


# --- .lnk_log_recompute_* ---------------------------------------------------

test_that(".lnk_log_recompute_start refuses when the table is absent", {
  # And says how to fix it. The pool runs up to 16 wide, so this path must
  # never respond by running DDL.
  cfg <- lnk_config("default")
  expect_error(
    capture_write(
      .lnk_log_recompute_start(fake_conn(), cfg, "PINE"),
      probe_rows = 0L),
    "log_recompute is missing")
  expect_error(
    capture_write(
      .lnk_log_recompute_start(fake_conn(), cfg, "PINE"),
      probe_rows = 0L),
    "lnk_persist_init")
})

test_that(".lnk_log_recompute_start runs NO DDL when the table is present", {
  # The whole point: CREATE TABLE IF NOT EXISTS and ALTER TABLE take an
  # AccessExclusiveLock, and a queued exclusive request blocks every sibling's
  # AccessShareLock behind it. That is the convoy link#250 hoisted the barrier
  # views out of the pool to remove; re-introducing it here would be the same
  # bug one layer down.
  cfg <- lnk_config("default")
  sql <- capture_write(
    .lnk_log_recompute_start(fake_conn(), cfg, "PINE"),
    probe_rows = 1L)
  expect_length(grep("CREATE TABLE|ALTER TABLE|CREATE INDEX|CREATE SCHEMA", sql), 0L)
})

test_that(".lnk_log_recompute_start opens a row with date_start, no date_end", {
  cfg <- lnk_config("default")
  sql <- capture_write(
    .lnk_log_recompute_start(fake_conn(), cfg, "PINE",
                             run_uid = "20260901T120000-abcd1234",
                             run_label = "field-scope",
                             views_prebuilt = TRUE),
    probe_rows = 1L)
  ins <- grep("INSERT INTO .*\\.log_recompute \\(", sql, value = TRUE)
  expect_length(ins, 1L)
  expect_match(ins, "date_start")
  expect_match(ins, "now\\(\\)")
  expect_no_match(ins, "date_end")
  expect_match(ins, "20260901T120000-abcd1234")
  expect_match(ins, "views_prebuilt")
})

test_that(".lnk_log_recompute_start returns a recompute_id and the schema", {
  cfg <- lnk_config("default")
  box <- new.env(parent = emptyenv())
  capture_write(
    assign("out", .lnk_log_recompute_start(fake_conn(), cfg, "PINE"),
           envir = box),
    probe_rows = 1L)
  expect_match(box$out$recompute_id, "-[0-9a-f]{6}$")
  expect_identical(box$out$schema, cfg$pipeline$schema)
})

test_that(".lnk_log_recompute_finish sets date_end and species", {
  cfg <- lnk_config("default")
  sql <- capture_write(
    .lnk_log_recompute_finish(fake_conn(), cfg, "rid-1", c("BT", "CO")))
  upd <- grep("UPDATE .*\\.log_recompute SET date_end", sql, value = TRUE)
  expect_length(upd, 1L)
  expect_match(upd, "species = ARRAY\\['BT', 'CO'\\]::text\\[\\]")
  expect_match(upd, "WHERE recompute_id = 'rid-1'")
})

test_that(".lnk_log_recompute_fail appends notes and never sets date_end", {
  # Three-state signal, same as the modelling log: date_end set -> success;
  # NULL + notes -> it ran and errored; NULL + no notes -> the process died.
  cfg <- lnk_config("default")
  sql <- capture_write(
    .lnk_log_recompute_fail(fake_conn(), cfg, "rid-1", "post-condition failed"))
  upd <- grep("UPDATE .*\\.log_recompute SET notes", sql, value = TRUE)
  expect_length(upd, 1L)
  expect_match(upd, "concat_ws")
  expect_no_match(upd, "date_end")
})


# --- .lnk_bcfp_log_current: the tunnel-free pin -----------------------------

# A ledger in the shape lnk_baseline_append() writes.
local_ledger <- function(rows, env = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".csv", .local_envir = env)
  writeLines(c(paste(names(cols_baseline), collapse = ","), rows), path)
  withr::local_envvar(LNK_BCFP_BASELINE = path, .local_envir = env)
  path
}

test_that(".lnk_bcfp_log_ledger reads this host's latest model_version", {
  withr::local_envvar(LNK_HOST_ALIAS = "m1")
  local_ledger(c(
    "2026-08-01 10:00,m1,snapshot-old,n/a,,v0.7.15-40-gaaaaaaa,2026-08-01T00:00:00Z,x",
    "2026-08-31 14:50,m1,snapshot-new,n/a,,v0.7.15-47-ga702229,2026-08-19T04:31:37Z,y"))
  out <- .lnk_bcfp_log_ledger()
  expect_identical(out$model_version, "v0.7.15-47-ga702229")
})

test_that(".lnk_bcfp_log_ledger leaves model_run_id NA rather than inventing one", {
  # log.json carries no model_run_id — lnk_bucket_log() requires only
  # model_version, date_completed, head_sha — so lnk_baseline_append() writes
  # "". Honest absence beats a fabricated id.
  withr::local_envvar(LNK_HOST_ALIAS = "m1")
  local_ledger(
    "2026-08-31 14:50,m1,snapshot,n/a,,v0.7.15-47-ga702229,2026-08-19T04:31:37Z,y")
  out <- .lnk_bcfp_log_ledger()
  expect_true(is.na(out$model_run_id))
})

test_that(".lnk_bcfp_log_ledger carries a model_run_id when the ledger has one", {
  withr::local_envvar(LNK_HOST_ALIAS = "m4")
  local_ledger(
    "2026-05-03 14:23,m4,provincial,fresh_default,120,v0.7.14-113-ga7373af,2026-04-28 23:17,z")
  out <- .lnk_bcfp_log_ledger()
  expect_identical(out$model_run_id, 120L)
})

test_that(".lnk_bcfp_log_ledger is scoped to THIS host", {
  # Each host snapshots into its own local Postgres, so another host's stamp
  # says nothing about what this one loaded.
  withr::local_envvar(LNK_HOST_ALIAS = "m1")
  local_ledger(
    "2026-08-31 14:50,cypher-job1,snapshot,n/a,,v0.7.15-47-ga702229,2026-08-19T04:31:37Z,y")
  expect_null(.lnk_bcfp_log_ledger())
})

test_that(".lnk_bcfp_log_ledger returns NULL when the ledger is absent", {
  withr::local_envvar(LNK_BCFP_BASELINE = file.path(tempdir(), "no-such.csv"))
  expect_null(.lnk_bcfp_log_ledger())
})

test_that(".lnk_bcfp_log_current prefers the DB when bcfishpass.log is reachable", {
  # Tier 1 carries model_run_id, which the ledger cannot. It must win.
  withr::local_envvar(LNK_HOST_ALIAS = "m1")
  local_ledger(
    "2026-08-31 14:50,m1,snapshot,n/a,,LEDGER-VERSION,2026-08-19T04:31:37Z,y")
  out <- testthat::with_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (grepl("information_schema", statement)) return(data.frame(x = 1L))
      data.frame(model_run_id = 999L, model_version = "DB-VERSION")
    },
    .package = "DBI",
    .lnk_bcfp_log_current(fake_conn()))
  expect_identical(out$model_version, "DB-VERSION")
  expect_identical(out$model_run_id, 999L)
})

test_that(".lnk_bcfp_log_current falls back to the ledger with no bcfishpass schema", {
  # The measured state of every study-area run: local docker fwapg holds ZERO
  # bcfishpass tables, so tier 1 returns NULL on every WSG. Before link#262
  # that left bcfp_model_version NULL on all 37 rows of the field run.
  withr::local_envvar(LNK_HOST_ALIAS = "m1")
  local_ledger(
    "2026-08-31 14:50,m1,snapshot,n/a,,v0.7.15-47-ga702229,2026-08-19T04:31:37Z,y")
  out <- testthat::with_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) data.frame(),
    .package = "DBI",
    .lnk_bcfp_log_current(fake_conn()))
  expect_identical(out$model_version, "v0.7.15-47-ga702229")
})


# --- lnk_log_read -----------------------------------------------------------

capture_read_sql <- function(expr) {
  seen <- character()
  testthat::with_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      seen <<- c(seen, statement)
      data.frame()
    },
    dbQuoteLiteral = function(conn, x, ...) {
      paste0("'", gsub("'", "''", as.character(x)), "'")
    },
    .package = "DBI",
    force(expr))
  seen
}

test_that("lnk_log_read reads <schema>.log by default", {
  cfg <- lnk_config("default")
  sql <- capture_read_sql(lnk_log_read(fake_conn(), cfg))
  expect_match(sql, sprintf("FROM %s\\.log", cfg$pipeline$schema))
  expect_match(sql, "DISTINCT ON \\(watershed_group_code\\)")
})

test_that("lnk_log_read(phase = 'recompute') reads log_recompute", {
  cfg <- lnk_config("default")
  sql <- capture_read_sql(lnk_log_read(fake_conn(), cfg, phase = "recompute"))
  expect_match(sql, sprintf("FROM %s\\.log_recompute", cfg$pipeline$schema))
})

test_that("lnk_log_read(run_uid=) filters on it", {
  cfg <- lnk_config("default")
  sql <- capture_read_sql(
    lnk_log_read(fake_conn(), cfg, run_uid = "20260901T120000-abcd1234"))
  expect_match(sql, "run_uid = '20260901T120000-abcd1234'")
})

test_that("lnk_log_read(run_uid=) overrides latest and returns every row", {
  # "Every row of a named run" is the acceptance criterion. DISTINCT ON would
  # return one row per WSG and silently hide a WSG re-run inside the same
  # dispatch — the case the identifier exists to make visible.
  cfg <- lnk_config("default")
  sql <- capture_read_sql(
    lnk_log_read(fake_conn(), cfg, run_uid = "uid-1", latest = TRUE))
  expect_no_match(sql, "DISTINCT ON")
})

test_that("lnk_log_read combines aoi and run_uid with AND", {
  cfg <- lnk_config("default")
  sql <- capture_read_sql(
    lnk_log_read(fake_conn(), cfg, aoi = "PINE", run_uid = "uid-1"))
  expect_match(sql, "watershed_group_code = 'PINE' AND run_uid = 'uid-1'")
})

test_that("lnk_log_read rejects a blank run_uid", {
  cfg <- lnk_config("default")
  expect_error(lnk_log_read(fake_conn(), cfg, run_uid = ""), "run_uid")
  expect_error(lnk_log_read(fake_conn(), cfg, run_uid = c("a", "b")), "run_uid")
})

test_that("lnk_log_read rejects an unknown phase", {
  cfg <- lnk_config("default")
  expect_error(lnk_log_read(fake_conn(), cfg, phase = "nonsense"))
})

test_that(".lnk_log_recompute_start defaults run_uid/run_label from the env", {
  # Regression for a bug an end-to-end run caught and the unit tests could not:
  # the env read was wired into lnk_pipeline_run() only, so the recompute row
  # landed with run_uid NULL and the model-vs-recompute join had nothing to
  # join on. The earlier tests passed the value explicitly and so never
  # exercised the default.
  withr::local_envvar(LNK_RUN_UID = "20260901T000000-fromenv",
                      LNK_RUN_LABEL = "label-from-env")
  cfg <- lnk_config("default")
  sql <- capture_write(
    .lnk_log_recompute_start(fake_conn(), cfg, "PINE"), probe_rows = 1L)
  ins <- grep("INSERT INTO .*\\.log_recompute \\(", sql, value = TRUE)
  expect_match(ins, "20260901T000000-fromenv")
  expect_match(ins, "label-from-env")
})

test_that("model and recompute rows agree on run_uid from one env setting", {
  # The pair the whole design exists to make queryable: one export, both rows.
  withr::local_envvar(LNK_RUN_UID = "20260901T000000-shared")
  cfg <- lnk_config("default")
  model <- capture_write(
    .lnk_log_run_start(fake_conn(), cfg, "PINE", "working_pine",
                       run_uid = Sys.getenv("LNK_RUN_UID", NA_character_)))
  recomp <- capture_write(
    .lnk_log_recompute_start(fake_conn(), cfg, "PINE"), probe_rows = 1L)
  expect_match(grep("INSERT INTO .*\\.log \\(", model, value = TRUE),
               "20260901T000000-shared")
  expect_match(grep("INSERT INTO .*\\.log_recompute \\(", recomp, value = TRUE),
               "20260901T000000-shared")
})

test_that(".lnk_bcfp_log_current tier 0 reads LNK_BCFP_MODEL_VERSION", {
  # A cypher has no ledger row of its own -- it git-resets the repo but never
  # snapshots under its own hostname -- so without this every cypher row lands
  # unpinned. Same shape as the FWAPG_GIT_SHA export the driver already does.
  withr::local_envvar(LNK_BCFP_MODEL_VERSION = "v0.7.15-47-ga702229",
                      LNK_HOST_ALIAS = "cypher-job1")
  out <- .lnk_bcfp_log_current(fake_conn())
  expect_identical(out$model_version, "v0.7.15-47-ga702229")
  expect_identical(out$source, "env")
})

test_that("bcfp_pin_source records which tier answered", {
  # So "not pinned" is distinguishable from "pinned, from the ledger" without
  # inferring it from a NULL model_run_id.
  withr::local_envvar(LNK_HOST_ALIAS = "m1", LNK_BCFP_MODEL_VERSION = "")
  local_ledger(
    "2026-08-31 14:50,m1,snapshot,n/a,,v0.7.15-47-ga702229,2026-08-19T04:31:37Z,y")
  expect_identical(.lnk_bcfp_log_ledger()$source, "ledger")

  cfg <- lnk_config("default")
  sql <- capture_write(
    .lnk_log_run_start(fake_conn(), cfg, "PINE", "working_pine"))
  ins <- grep("INSERT INTO .*\\.log \\(", sql, value = TRUE)
  expect_match(ins, "bcfp_pin_source")
})

test_that("both log tables carry the new code-identity columns (link#264)", {
  # BOTH tables, asserted together. link#262's most expensive defect was a
  # value wired into one write path only -- every unit test passed it
  # explicitly, so the gap was invisible until an end-to-end run landed a NULL.
  sql <- capture_ddl(.lnk_log_create_tables(NULL, "s"))
  for (tbl in c("log", "log_recompute")) {
    ddl <- grep(sprintf("CREATE TABLE IF NOT EXISTS s\\.%s \\(", tbl),
                sql, value = TRUE)
    expect_length(ddl, 1L)
    expect_match(ddl, "bcfishobs_sha")
    expect_match(ddl, "fresh_sha_source")
  }

  # And the ALTER path, which is what an EXISTING fresh.log takes -- the 39
  # rows already in the table are reached by ADD COLUMN, never by CREATE.
  for (col in c("bcfishobs_sha", "fresh_sha_source")) {
    for (tbl in c("log", "log_recompute")) {
      expect_gt(length(grep(sprintf(
        "ALTER TABLE s\\.%s ADD COLUMN IF NOT EXISTS %s ", tbl, col), sql)), 0L)
    }
  }
})

test_that("both INSERT paths write bcfishobs_sha and fresh_sha_source", {
  withr::local_envvar(BCFISHOBS_GIT_SHA = "bcfishobs264",
                      FRESH_GIT_SHA = "freshsha264", FRESH_GIT_DIRTY = "")
  cfg <- lnk_config("default")

  model <- capture_write(
    .lnk_log_run_start(fake_conn(), cfg, "PINE", "working_pine"))
  ins <- grep("INSERT INTO .*\\.log \\(", model, value = TRUE)
  expect_match(ins, "bcfishobs_sha")
  expect_match(ins, "'bcfishobs264'")
  expect_match(ins, "fresh_sha_source")
  # The tier that answered, recorded rather than inferred from a NULL.
  expect_match(ins, "'env'")

  recomp <- capture_write(
    .lnk_log_recompute_start(fake_conn(), cfg, "PINE"), probe_rows = 1L)
  ins_rc <- grep("INSERT INTO .*\\.log_recompute \\(", recomp, value = TRUE)
  expect_match(ins_rc, "bcfishobs_sha")
  expect_match(ins_rc, "'bcfishobs264'")
  expect_match(ins_rc, "fresh_sha_source")
})

test_that("log_input stores NULL, not -1, for a never-analyzed table", {
  # PG14+ uses reltuples = -1 for "never analyzed". Stored raw it became a
  # row count of -1 on bcfishobs.observations (1 of 429 rows). -1 is unknown,
  # not a quantity, and row_count_estimated must not claim a method for a
  # count that does not exist.
  sql <- capture_write(
    .lnk_log_inputs(fake_conn(), "s", "run-1", "PINE"))
  ins <- grep("INSERT INTO s\\.log_input", sql, value = TRUE)
  expect_length(ins, 1L)
  expect_match(ins, "nullif\\(c\\.reltuples, -1\\)::bigint")
  expect_match(ins, "CASE WHEN nullif\\(c\\.reltuples, -1\\) IS NULL THEN NULL")
  # Premise: the bare form is gone, not merely accompanied by the guarded one.
  expect_false(grepl("[^)]c\\.reltuples::bigint", ins))
})

test_that("log_recompute is created before its indexes are", {
  # An intermediate state during this work had log_recompute's indexes in the
  # idx vector while the table did not yet exist, which makes
  # .lnk_log_create_tables() throw -- and it is called from the LOUD
  # .lnk_log_run_start(), i.e. every run dies at second one.
  sql <- capture_ddl(.lnk_log_create_tables(NULL, "s"))
  create <- grep("CREATE TABLE IF NOT EXISTS s\\.log_recompute", sql)
  index <- grep("CREATE INDEX IF NOT EXISTS log_rc_", sql)
  expect_gt(length(create), 0L)
  expect_gt(length(index), 0L)
  expect_lt(max(create), min(index))
})
