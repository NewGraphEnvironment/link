# nolint start: indentation_linter
#' What stops a built habitat export from being published (link#334).
#'
#' A floodplain item that pins a habitat build must be able to name it and
#' rebuild it. So PUBLISH refuses a tree in which any build it carries:
#'
#' - has no `run_uid` (a direct `wsg_run_one.R` run, outside a dispatch);
#' - was modelled from a dirty link or fresh tree (`link_dirty`,
#'   `fresh_dirty`), or from one whose state was not recorded;
#' - logged no habitat thresholds at its `config_hash`, so its spawning and
#'   rearing ratios are NA (`thresholds_logged`);
#'
#' or in which a recompute that rewrote its access has no `run_uid` or ran
#' from a dirty tree, or a config was exported from a dirty link tree.
#' Builds are read from the manifest's `configs[].runs`, which every part and
#' per-group part of the config comes from; recomputes from the
#' `provenance/recompute_id=<id>/log_recompute.parquet` files the runs name.
#'
#' @param m The manifest, as read by `jsonlite::fromJSON(simplifyVector =
#'   FALSE)`.
#' @param root The local tree the manifest describes.
#' @return A character vector, one line per refusal; empty when none.
#' @noRd
.lnk_publish_refusals <- function(m, root) {
  out <- character(0)
  # TRUE, or not recorded: an unknown tree is not a clean one, so it too
  # needs LNK_PUBLISH_ALLOW to name it (review round 1)
  flag <- function(x) !isFALSE(as.logical(x %||% NA))
  blank <- function(x) is.null(x) || length(x) == 0L || is.na(x) || !nzchar(x)
  for (cf in m$configs) {
    if (flag(cf$exported_by$link_dirty)) {
      out <- c(out, sprintf("%s: exported from a dirty link tree", cf$config))
    }
    for (r in cf$runs) {
      who <- sprintf("%s %s run %s", cf$config, r$watershed_group_code,
                     r$run_id)
      if (blank(r$run_uid)) out <- c(out, paste0(who, ": no run_uid"))
      if (flag(r$link_dirty)) out <- c(out, paste0(who, ": link_dirty"))
      if (flag(r$fresh_dirty)) out <- c(out, paste0(who, ": fresh_dirty"))
      thr <- cf$thresholds_logged[[r$config_hash %||% ""]]
      if (!isTRUE(thr)) {
        out <- c(out, paste0(who, ": no thresholds logged at ",
                             r$config_hash %||% "<no config_hash>"))
      }
      for (k in unlist(r$recompute_keys)) {
        rc <- .lnk_publish_recompute(root, k)
        rwho <- sprintf("%s %s recompute %s", cf$config,
                        r$watershed_group_code, sub("^.*=", "", k))
        if (blank(rc$run_uid)) out <- c(out, paste0(rwho, ": no run_uid"))
        if (flag(rc$link_dirty)) out <- c(out, paste0(rwho, ": link_dirty"))
      }
    }
  }
  unique(out)
}

#' One recompute's log row from the tree.
#' @noRd
.lnk_publish_recompute <- function(root, key) {
  f <- file.path(root, key, "log_recompute.parquet")
  if (!file.exists(f)) {
    stop(key, "/log_recompute.parquet is named by the manifest and missing ",
         "from ", root, call. = FALSE)
  }
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("checking a tree's recomputes needs the duckdb package",
         call. = FALSE)
  }
  duck <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(duck, shutdown = TRUE), add = TRUE)
  x <- DBI::dbGetQuery(duck, sprintf("SELECT * FROM read_parquet(%s)",
                                     DBI::dbQuoteString(duck, f)))
  list(run_uid = if ("run_uid" %in% names(x)) as.character(x$run_uid[1]),
       link_dirty = if ("link_dirty" %in% names(x)) x$link_dirty[1])
}

#' Decide PUBLISH from the refusals and the operator's written reason.
#'
#' No refusal: proceed. Refusals and no reason: stop, naming them. Refusals
#' and a reason (`LNK_PUBLISH_ALLOW`): proceed, and return the record the
#' manifest carries, so a reader sees what was published past the gate.
#' @param refusals From `.lnk_publish_refusals()`.
#' @param allow The reason, or "" for none.
#' @return `NULL`, or a list `reason`, `refusals` for the manifest.
#' @noRd
.lnk_publish_gate <- function(refusals, allow = "") {
  if (length(refusals) == 0L) return(NULL)
  if (!nzchar(trimws(allow))) {
    shown <- utils::head(refusals, 20L)
    stop("PUBLISH refused (link#334): ", length(refusals),
         " build(s) a floodplain item could not name or rebuild:\n  ",
         paste(shown, collapse = "\n  "),
         if (length(refusals) > 20L) sprintf("\n  ... and %d more",
                                             length(refusals) - 20L),
         "\nRe-model them in a dispatch from a clean tree, or set ",
         "LNK_PUBLISH_ALLOW=\"<reason>\", which the manifest records.",
         call. = FALSE)
  }
  list(reason = trimws(allow), refusals = I(refusals))
}
# nolint end: indentation_linter
