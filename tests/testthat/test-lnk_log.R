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

test_that(".lnk_log_create_tables emits all four CREATE TABLE statements", {
  sql <- capture_ddl(.lnk_log_create_tables(NULL, "fresh_test"))
  joined <- paste(sql, collapse = "\n")
  for (tbl in c("log", "log_input", "log_parameters_fresh", "log_dimensions")) {
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
