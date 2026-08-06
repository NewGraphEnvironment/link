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
