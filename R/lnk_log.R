# Run-provenance log on the persist schema (link#127).
#
# `<persist_schema>.streams` and friends accumulate rows across many runs but
# carry no provenance: given a network in the database you cannot say which
# config produced it, what that config actually said at the time, which
# primitive vintage it was built from, or when it was written.
#
# Four sidecar tables answer that, mirroring `bcfishpass.log` and its FK'd
# children (which snapshot actual parameter *values*, not pointers to them):
#
#   <schema>.log                   one row per lnk_pipeline_run() call
#   <schema>.log_parameters_fresh  full parameters_fresh.csv rows per config
#   <schema>.log_dimensions        full dimensions.csv rows per config
#   <schema>.log_input             DB primitive fingerprints per run
#
# Design notes that are load-bearing (see planning/active/findings.md):
#
#   * `run_id` is TEXT, not a serial. `data-raw/schema_consolidate.R` COPYs
#     literal values between hosts whose sequences would both start at 1, so a
#     serial guarantees PK collisions and silent loss of run history. It also
#     avoids a RETURNING round-trip, which would break the `.lnk_db_execute`
#     mocking the tests rely on.
#   * Snapshot values are stored as `text`. These are provenance, not compute
#     inputs; `text` preserves the "" vs NA distinction the CSVs actually use
#     and is immune to type drift.
#   * Column lists come from the config dictionaries (link#233), so adding a
#     parameter updates the dictionary and the log table together.


# ---------------------------------------------------------------------------
# Identity + hashing primitives
# ---------------------------------------------------------------------------

#' Deterministic fingerprint of a config bundle's *observed* bytes.
#'
#' Hashes the resolved file set rather than the declared `provenance:` block.
#' Two reasons this matters:
#'
#'   * `config.yaml` itself is absent from its own `provenance:` block, so a
#'     verify-derived hash would be blind to `pipeline$schema`, `break_order`,
#'     `gradient_classes`, `cluster` and `spawn_connected` — all of which change
#'     model output.
#'   * The declared checksums are declared, not verified ([lnk_config_verify()]
#'     is never called during a run), so copying them could record a lie.
#'
#' Missing files hash to the literal `MISSING` rather than erroring — the hash
#' should describe whatever is actually on disk.
#'
#' @param cfg An `lnk_config` object.
#' @return A single string, `"sha256:<hex>"`.
#' @noRd
.lnk_config_hash <- function(cfg) {
  if (!inherits(cfg, "lnk_config")) {
    stop("cfg must be an lnk_config object", call. = FALSE)
  }

  paths <- c(
    file.path(cfg$dir, "config.yaml"),
    cfg$rules,
    cfg$dimensions,
    unlist(lapply(cfg$files, function(f) f$path), use.names = FALSE),
    if (!is.null(cfg$provenance)) file.path(cfg$dir, names(cfg$provenance))
  )
  paths <- unique(paths[!is.na(paths) & nzchar(paths)])

  rel <- vapply(paths, function(p) {
    r <- sub(paste0("^", .lnk_regex_escape(cfg$dir), "/?"), "", p)
    if (nzchar(r)) r else basename(p)
  }, character(1), USE.NAMES = FALSE)

  digests <- vapply(paths, function(p) {
    if (!file.exists(p)) {
      return("MISSING")
    }
    digest::digest(file = p, algo = "sha256")
  }, character(1), USE.NAMES = FALSE)

  ord <- order(rel)
  payload <- paste(
    c(
      paste0("name=", cfg$name),
      paste0("species=", paste(sort(cfg$species), collapse = ";")),
      paste0(rel[ord], "=", digests[ord])
    ),
    collapse = "\n"
  )

  paste0("sha256:", digest::digest(payload, algo = "sha256", serialize = FALSE))
}


#' Escape a string for literal use inside a regex.
#' @noRd
.lnk_regex_escape <- function(x) {
  gsub("([.\\\\|()\\[\\]{}^$*+?])", "\\\\\\1", x, perl = TRUE)
}


#' Globally unique run identifier.
#'
#' `<host>-<UTC timestamp to ms>-<6 hex>`. Host-prefixed and random-suffixed so
#' that ids minted independently on several cyphers never collide when
#' `schema_consolidate.R` COPYs them into one province-wide schema.
#'
#' @return A single string.
#' @noRd
.lnk_run_id <- function() {
  host <- gsub("[^A-Za-z0-9]+", "", .lnk_host())
  if (!nzchar(host)) host <- "host"
  ts <- format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y%m%dT%H%M%OS3", tz = "UTC")
  suffix <- paste(sprintf("%x", sample.int(16L, 6L, replace = TRUE) - 1L),
                  collapse = "")
  paste(host, ts, suffix, sep = "-")
}


#' DB primitives whose vintage determines model output.
#'
#' The pipeline's inputs, in the order they matter. `source` records where the
#' data actually comes from — a fact that lives in the loader scripts, not the
#' database, and which nothing else records.
#'
#' @return A data.frame with `table_name` and `source`.
#' @noRd
.lnk_input_primitives <- function() {
  fwapg <- "fwapg/load.sh <- nrs.objectstore.gov.bc.ca/bchamp/fwapg"
  data.frame(
    table_name = c(
      "whse_basemapping.fwa_stream_networks_sp",
      "whse_basemapping.fwa_stream_networks_channel_width",
      "whse_basemapping.fwa_stream_networks_order_parent",
      "whse_basemapping.fwa_lakes_poly",
      "whse_basemapping.fwa_wetlands_poly",
      "whse_basemapping.fwa_rivers_poly",
      "whse_basemapping.fwa_obstacles_sp",
      "bcfishobs.observations",
      "whse_fish.pscis_assessment_svw",
      "cabd.dams",
      "fresh.modelled_stream_crossings",
      "public.wsg_outlet"
    ),
    source = c(
      rep(fwapg, 7L),
      "bcfishobs",
      "bcdata bc2pg",
      "CABD",
      "snapshot_bcfp.sh <- bchamp objectstore",
      "ad-hoc (link#227)"
    ),
    stringsAsFactors = FALSE
  )
}


# ---------------------------------------------------------------------------
# DDL
# ---------------------------------------------------------------------------

# One row per lnk_pipeline_run() call. `run_id` is TEXT (see file header).
# `watershed_group_code` is present so schema_consolidate.R auto-discovers the
# table — it keys off "has a watershed_group_code column".
cols_log <- c(
  run_id                 = "text NOT NULL",
  watershed_group_code   = "varchar(4) NOT NULL",
  date_start             = "timestamptz NOT NULL",
  date_end               = "timestamptz",
  run_label              = "text",
  host                   = "text",
  config_name            = "text",
  config_hash            = "text",
  config_drift           = "boolean",
  link_version           = "text",
  link_sha               = "text",
  link_dirty             = "boolean",
  fresh_version          = "text",
  fresh_sha              = "text",
  fresh_dirty            = "boolean",
  crate_version          = "text",
  fwapg_sha              = "text",
  arg_dams               = "boolean",
  arg_mapping_code       = "boolean",
  arg_cleanup_working    = "boolean",
  schema_persist         = "text",
  species                = "text[]",
  wsg_upstream           = "text[]",
  bcfp_model_run_id      = "integer",
  bcfp_model_version     = "text",
  notes                  = "text"
)

# Per-primitive fingerprints. Carries watershed_group_code for the same
# auto-discovery reason as `log`.
cols_log_input <- c(
  run_id                 = "text NOT NULL",
  watershed_group_code   = "varchar(4)",
  table_name             = "text NOT NULL",
  row_count              = "bigint",
  row_count_estimated    = "boolean",
  size_bytes             = "bigint",
  last_analyze           = "timestamptz",
  source                 = "text",
  source_at              = "timestamptz"
)


#' Column vectors for the config-snapshot tables, driven by the dictionaries.
#'
#' `dictionary_parameters_fresh.csv` and `dictionary_dimensions.csv` (link#233)
#' are the canonical column lists, and they cover the *union* of all bundles —
#' which matters because bundles carry different subsets (bcfishpass's
#' `dimensions.csv` has 30 columns to the `default*` bundles' 32). Generating
#' DDL from them means adding a parameter updates the dictionary and the log
#' table together, by construction.
#'
#' Every value column is `text`: these are provenance snapshots, not compute
#' inputs, so `text` is lossless (it preserves the `""` vs `NA` distinction the
#' CSVs actually use) and immune to type drift.
#'
#' @noRd
.lnk_dictionary_columns <- function(which) {
  path <- system.file("extdata", "configs",
                      paste0("dictionary_", which, ".csv"), package = "link")
  if (!nzchar(path) || !file.exists(path)) {
    stop("dictionary_", which, ".csv not found in the installed package",
         call. = FALSE)
  }
  as.character(utils::read.csv(path, check.names = FALSE)$column)
}

#' @noRd
.lnk_cols_log_parameters_fresh <- function() {
  cols <- .lnk_dictionary_columns("parameters_fresh")
  out <- stats::setNames(rep("text", length(cols)), cols)
  out[["species_code"]] <- "text NOT NULL"
  c(config_hash = "text NOT NULL", out)
}

#' @noRd
.lnk_cols_log_dimensions <- function() {
  cols <- .lnk_dictionary_columns("dimensions")
  out <- stats::setNames(rep("text", length(cols)), cols)
  out[["species"]] <- "text NOT NULL"
  c(config_hash = "text NOT NULL", out)
}


#' Bring an existing log table up to the expected column set.
#'
#' `CREATE TABLE IF NOT EXISTS` is a no-op against a table that already exists,
#' even with a drifted shape — so on its own it can never ship a *new* config
#' column, and config columns are the entire point of these tables. A new
#' parameter would be silently never logged, reintroducing the exact
#' silent-drift failure this issue exists to prevent.
#'
#' `ADD COLUMN IF NOT EXISTS` is Postgres-native and idempotent, so this is
#' cheap to run on every init.
#'
#' @noRd
.lnk_log_align_columns <- function(conn, schema, table, cols) {
  for (nm in names(cols)) {
    # Drop NOT NULL when back-filling: an existing table may already hold rows.
    type <- sub("\\s+NOT NULL$", "", cols[[nm]])
    .lnk_db_execute(conn, sprintf(
      "ALTER TABLE %s.%s ADD COLUMN IF NOT EXISTS %s %s",
      schema, table, nm, type))
  }
  invisible(conn)
}


#' Create the four provenance tables. Idempotent.
#'
#' Called from [lnk_persist_init()] so a standalone init produces a complete
#' schema, and again from the run-start path so a run never fails for want of
#' a table.
#'
#' @noRd
.lnk_log_create_tables <- function(conn, schema) {
  specs <- list(
    list(table = "log", cols = cols_log, pk = "run_id"),
    list(table = "log_input", cols = cols_log_input,
         pk = c("run_id", "table_name")),
    list(table = "log_parameters_fresh", cols = .lnk_cols_log_parameters_fresh(),
         pk = c("config_hash", "species_code")),
    list(table = "log_dimensions", cols = .lnk_cols_log_dimensions(),
         pk = c("config_hash", "species"))
  )

  for (s in specs) {
    .lnk_db_execute(conn, sprintf(
      "CREATE TABLE IF NOT EXISTS %s.%s (\n  %s\n)",
      schema, s$table, .lnk_cols_clause(s$cols, s$pk)))
    .lnk_log_align_columns(conn, schema, s$table, s$cols)
  }

  idx <- c(
    log_wsg_date = "log (watershed_group_code, date_start DESC)",
    log_config   = "log (config_hash)",
    log_input_rn = "log_input (run_id)"
  )
  for (nm in names(idx)) {
    .lnk_db_execute(conn, sprintf(
      "CREATE INDEX IF NOT EXISTS %s_idx ON %s.%s", nm, schema, idx[[nm]]))
  }

  invisible(conn)
}


#' git SHA of the fwapg checkout that loaded the FWA primitives.
#'
#' The stream network is the most load-bearing input the pipeline has and it
#' carries **no** provenance in the database: `bcdata.log` records only `bc2pg`
#' downloads (which FWA is not), and `pg_stat_user_tables` for
#' `fwa_stream_networks_sp` is empty because it is bulk-restored and never
#' analyzed. It is loaded by fwapg's own `load.sh` from
#' `nrs.objectstore.gov.bc.ca/bchamp/fwapg/...parquet`, so the fwapg checkout's
#' commit is the closest thing to a version for it.
#'
#' Three-tier, mirroring [.lnk_pkg_git_sha()]: `FWAPG_GIT_SHA` env var, then a
#' `.git` walk of `FWAPG_DIR` (or the conventional `../../fwapg` sibling
#' checkout), then `NA`.
#'
#' @return A single string or `NA_character_`.
#' @noRd
.lnk_fwapg_sha <- function() {
  v <- Sys.getenv("FWAPG_GIT_SHA", "")
  if (nzchar(v)) return(v)

  candidates <- c(
    Sys.getenv("FWAPG_DIR", ""),
    file.path(path.expand("~"), "Projects", "repo", "fwapg")
  )
  for (d in candidates[nzchar(candidates)]) {
    git <- file.path(d, ".git")
    if (file.exists(git)) {
      sha <- .lnk_read_git_head(git)
      if (!is.null(sha)) return(sha)
    }
  }
  NA_character_
}
