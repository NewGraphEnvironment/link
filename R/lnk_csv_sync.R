# Helpers for the weekly bcfishpass CSV sync (data-raw/sync_bcfishpass_csvs.R,
# #429). A bundle file whose provenance names the bcfishpass repo is a copy
# the sync keeps byte for byte; link's own changes to it live in an overlay
# (R/lnk_overlay.R). None of this runs in a model.

.lnk_sync_bcfp_source <- "https://github.com/smnorris/bcfishpass"

# Provenance keys (bundle-relative paths) the sync keeps as copies.
.lnk_sync_targets <- function(provenance) {
  if (is.null(provenance)) return(character(0))
  keep <- vapply(provenance, function(e) {
    identical(e$source, .lnk_sync_bcfp_source)
  }, logical(1))
  names(provenance)[keep]
}

# The weekly workflow's gate. `shape` (a header moved, or a canonical schema
# refused it) needs a coordinated change; `review` (an output token's spec
# moved, or the bundle no longer loads) needs a vocabulary row or an overlay
# fix; `byte` merges by itself. The worst kind present wins.
.lnk_sync_drift_kind <- function(byte, shape, review) {
  if (isTRUE(shape)) return("shape")
  if (isTRUE(review)) return("review")
  if (isTRUE(byte)) return("byte")
  "none"
}

# Token specs of the bundle at `dir`, loaded by path (never by name, which
# would read the installed package). NULL specs with the error message when
# the bundle does not load. A warning while loading counts as not loading:
# read.csv() truncates a file at a stray quote with only a warning, and
# crate reads a value that no longer parses as NA with only a warning, so a
# copy that loads short would otherwise pass as clean.
.lnk_sync_specs <- function(dir) {
  warned <- character(0)
  out <- tryCatch(withCallingHandlers({
    cfg <- lnk_config(dir)
    specs <- .lnk_vocabulary_specs(cfg, lnk_load_overrides(cfg))
    list(specs = specs, error = NULL)
  }, warning = function(w) {
    warned <<- c(warned, conditionMessage(w))
    invokeRestart("muffleWarning")
  }), error = function(e) list(specs = NULL, error = conditionMessage(e)))
  if (length(warned) > 0L) {
    out$error <- paste(c(out$error, paste("warned:",
                                          paste(unique(warned),
                                                collapse = " | "))),
                       collapse = "; ")
  }
  out
}

# Write `files` (named list: bundle-relative path -> raw bytes) into a copy
# of the bundle at `dir` and compare token specs before and after. The
# bundle itself is never touched. Returns `before`, `after` (named spec
# vectors), `moved` (axes whose spec changed) and `error` (the copy failed
# to load, or NULL).
.lnk_sync_trial <- function(dir, files) {
  before <- .lnk_sync_specs(dir)
  if (!is.null(before$error)) {
    stop("bundle at ", dir, " does not load before the sync: ",
         before$error, call. = FALSE)
  }
  tmp <- tempfile("lnk_sync_trial_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  if (!file.copy(dir, tmp, recursive = TRUE)) {
    stop("could not copy ", dir, " for the trial write", call. = FALSE)
  }
  trial <- file.path(tmp, basename(dir))
  for (rel in names(files)) {
    writeBin(files[[rel]], file.path(trial, rel))
  }
  after <- .lnk_sync_specs(trial)
  moved <- if (is.null(after$error)) {
    axes <- names(before$specs)
    axes[before$specs[axes] != after$specs[axes]]
  } else {
    character(0)
  }
  list(before = before$specs, after = after$specs, moved = moved,
       error = after$error)
}

# Overlay rows whose cell the copy already holds: upstream has adopted the
# change, so the row can be retired. Returns those overlay rows.
.lnk_sync_overlay_redundant <- function(base_path, overlay_path) {
  base <- utils::read.csv(base_path, colClasses = "character",
                          stringsAsFactors = FALSE)
  ovl <- utils::read.csv(overlay_path, colClasses = "character",
                         stringsAsFactors = FALSE,
                         na.strings = character(0))
  if (nrow(ovl) == 0L) return(ovl)
  key_col <- names(ovl)[[1]]
  rows <- match(ovl[[key_col]], base[[key_col]])
  same <- vapply(seq_len(nrow(ovl)), function(i) {
    col <- ovl$column[[i]]
    !is.na(rows[[i]]) && col %in% names(base) &&
      identical(base[[col]][[rows[[i]]]], ovl$value[[i]])
  }, logical(1))
  ovl[same, , drop = FALSE]
}
