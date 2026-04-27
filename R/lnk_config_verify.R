#' Verify Config Bundle File Checksums and Shape
#'
#' Recomputes sha256 byte and shape checksums for every file declared
#' in the bundle's `provenance:` block and compares against the
#' recorded values. Returns a tibble of expected vs observed; flags
#' drift on each axis separately.
#'
#' **Byte drift** (`byte_drift`) — file content changed (rows
#' added/edited/removed, or whole-file re-shape). Detected via sha256
#' of the full file. Catches every kind of change but doesn't tell you
#' WHAT kind.
#'
#' **Shape drift** (`shape_drift`) — file's *header* changed (column
#' added / renamed / removed / reshaped). Detected via sha256 of the
#' first line of the file (whitespace-normalized). A pure-value
#' change (rows added with no column change) shows `byte_drift = TRUE`
#' but `shape_drift = FALSE`. A column rename shows both TRUE.
#' Header-only fingerprint catches the dominant failure mode (column
#' structure change); type changes within stable columns are not
#' detected — they require value-level inspection that's out of scope
#' here.
#'
#' Use this at run time to detect silent drift — a file that was
#' edited without re-recording its checksum, or an external CSV that
#' was re-synced under the same path. Drift between two pipeline runs
#' on the same DB state with the same package versions almost always
#' traces back to a config-file edit; `lnk_config_verify()` is the
#' fastest way to localize the change.
#'
#' @param cfg An `lnk_config` object from [lnk_config()].
#' @param strict Logical. When `TRUE`, errors if any file has drifted
#'   on either axis. Default `FALSE` warns and returns the tibble for
#'   inspection.
#'
#' @return A tibble with columns:
#'
#'   - `file` — path relative to `cfg$dir`
#'   - `byte_expected` — byte checksum recorded in the manifest
#'   - `byte_observed` — byte checksum recomputed from the current file
#'   - `byte_drift` — logical, `TRUE` when byte checksums differ
#'   - `shape_expected` — shape checksum recorded in the manifest, or
#'     `NA` when the manifest has no `shape_checksum` field
#'   - `shape_observed` — shape checksum recomputed from the current
#'     file's header line
#'   - `shape_drift` — logical, `TRUE` when shape checksums differ
#'     (and the manifest had a `shape_expected` to compare against)
#'   - `missing` — logical, `TRUE` when the file no longer exists on
#'     disk (observed values are `NA`)
#'
#'   The tibble carries one row per provenanced file. When the bundle
#'   has no `provenance:` block (`cfg$provenance` is `NULL`) returns
#'   an empty tibble with the same columns.
#'
#' @family config
#'
#' @export
#'
#' @examples
#' cfg <- lnk_config("bcfishpass")
#' verify <- lnk_config_verify(cfg)
#' verify
#'
#' \dontrun{
#' # In a verification log: error on either drift kind
#' lnk_config_verify(cfg, strict = TRUE)
#' }
lnk_config_verify <- function(cfg, strict = FALSE) {
  if (!inherits(cfg, "lnk_config")) {
    stop("cfg must be an lnk_config object (from lnk_config())",
         call. = FALSE)
  }
  if (!is.logical(strict) || length(strict) != 1L || is.na(strict)) {
    stop("strict must be a single TRUE or FALSE", call. = FALSE)
  }

  prov <- cfg$provenance
  if (is.null(prov) || length(prov) == 0L) {
    return(.lnk_verify_empty())
  }

  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required for lnk_config_verify(). ",
         "Install with: install.packages('digest')",
         call. = FALSE)
  }

  rows <- lapply(names(prov), function(rel) {
    byte_expected  <- prov[[rel]][["checksum"]]       %||% NA_character_
    shape_expected <- prov[[rel]][["shape_checksum"]] %||% NA_character_
    abs_path <- file.path(cfg$dir, rel)
    if (!file.exists(abs_path)) {
      return(data.frame(
        file           = rel,
        byte_expected  = byte_expected,
        byte_observed  = NA_character_,
        byte_drift     = TRUE,
        shape_expected = shape_expected,
        shape_observed = NA_character_,
        shape_drift    = !is.na(shape_expected),
        missing        = TRUE,
        stringsAsFactors = FALSE
      ))
    }
    byte_observed <- paste0("sha256:",
                            digest::digest(file = abs_path, algo = "sha256"))
    shape_observed <- .lnk_shape_fingerprint(abs_path)
    # `shape_drift` requires a non-empty recorded shape_checksum to
    # compare against — guard with both is.na() and nzchar() to swallow
    # the malformed-YAML case (`shape_checksum:` with no value parses
    # to empty string in some yaml versions, NULL in others).
    has_recorded <- !is.na(shape_expected) && nzchar(shape_expected)
    data.frame(
      file           = rel,
      byte_expected  = byte_expected,
      byte_observed  = byte_observed,
      byte_drift     = !identical(byte_expected, byte_observed),
      shape_expected = shape_expected,
      shape_observed = shape_observed,
      shape_drift    = has_recorded &&
                         !identical(shape_expected, shape_observed),
      missing        = FALSE,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)

  drifted_any <- out$byte_drift | out$shape_drift
  if (any(drifted_any)) {
    drifted <- out[drifted_any, ]
    parts <- vapply(seq_len(nrow(drifted)), function(i) {
      kinds <- c(if (drifted$byte_drift[i])  "byte",
                 if (drifted$shape_drift[i]) "shape")
      sprintf("  - %s (%s drift)", drifted$file[i],
              paste(kinds, collapse = " + "))
    }, character(1))
    msg <- paste0(
      "Config bundle '", cfg$name, "' has ", nrow(drifted),
      " file(s) drifted from recorded checksum:\n",
      paste(parts, collapse = "\n"))
    if (strict) {
      stop(msg, call. = FALSE)
    }
    warning(msg, call. = FALSE)
  }

  out
}

#' Compute a shape fingerprint for a CSV / YAML / TSV file
#'
#' Hashes the first line (whitespace-normalized) with sha256. Catches
#' header changes — column rename / add / remove / reshape — but not
#' type changes within stable columns.
#' @noRd
.lnk_shape_fingerprint <- function(file_path) {
  first_line <- tryCatch(
    readLines(file_path, n = 1, warn = FALSE),
    error = function(e) character(0))
  if (length(first_line) == 0L) return(NA_character_)
  # Normalize trailing whitespace + carriage return to avoid false
  # drifts from CRLF vs LF or trailing spaces in the header.
  normalized <- sub("\\s+$", "", first_line)
  paste0("sha256:", digest::digest(normalized,
                                    algo = "sha256",
                                    serialize = FALSE))
}

.lnk_verify_empty <- function() {
  data.frame(
    file           = character(0),
    byte_expected  = character(0),
    byte_observed  = character(0),
    byte_drift     = logical(0),
    shape_expected = character(0),
    shape_observed = character(0),
    shape_drift    = logical(0),
    missing        = logical(0),
    stringsAsFactors = FALSE
  )
}
