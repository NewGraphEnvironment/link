#' Verify Config Bundle File Checksums
#'
#' Recomputes sha256 for every file declared in the bundle's
#' `provenance:` block and compares against the recorded checksum.
#' Returns a tibble of expected vs observed; flags drift.
#'
#' Use this at run time to detect silent drift — a file that was edited
#' without re-recording its checksum, or an external CSV that was
#' re-synced under the same path. Drift between two pipeline runs on
#' the same DB state with the same package versions almost always
#' traces back to a config-file edit; `lnk_config_verify()` is the
#' fastest way to localize the change.
#'
#' @param cfg An `lnk_config` object from [lnk_config()].
#' @param strict Logical. When `TRUE`, errors if any file has drifted.
#'   Default `FALSE` warns and returns the tibble for inspection.
#'
#' @return A tibble with columns:
#'
#'   - `file` — path relative to `cfg$dir`
#'   - `expected` — checksum recorded in the manifest (sha256 hex)
#'   - `observed` — checksum recomputed from the current file (sha256
#'     hex)
#'   - `drift` — logical, `TRUE` when expected != observed
#'   - `missing` — logical, `TRUE` when the file no longer exists on
#'     disk (observed is `NA` in this case)
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
#' # In a verification log: error if anything drifted
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
    expected <- prov[[rel]][["checksum"]] %||% NA_character_
    abs_path <- file.path(cfg$dir, rel)
    if (!file.exists(abs_path)) {
      return(data.frame(
        file     = rel,
        expected = expected,
        observed = NA_character_,
        drift    = TRUE,
        missing  = TRUE,
        stringsAsFactors = FALSE
      ))
    }
    observed <- paste0("sha256:",
                       digest::digest(file = abs_path, algo = "sha256"))
    data.frame(
      file     = rel,
      expected = expected,
      observed = observed,
      drift    = !identical(expected, observed),
      missing  = FALSE,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)

  if (any(out$drift)) {
    drifted <- out[out$drift, "file", drop = TRUE]
    msg <- paste0(
      "Config bundle '", cfg$name, "' has ", length(drifted),
      " file(s) drifted from recorded checksum:\n  - ",
      paste(drifted, collapse = "\n  - "))
    if (strict) {
      stop(msg, call. = FALSE)
    }
    warning(msg, call. = FALSE)
  }

  out
}

.lnk_verify_empty <- function() {
  data.frame(
    file     = character(0),
    expected = character(0),
    observed = character(0),
    drift    = logical(0),
    missing  = logical(0),
    stringsAsFactors = FALSE
  )
}
