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
#' One `aws` call, in this process or a pool worker (link#488).
#'
#' Uses base R only, because a PSOCK worker is a fresh R session with no link
#' loaded: `.lnk_publish_run()` sends it with a global environment. stderr is
#' kept with stdout, so a failure's message reaches the caller.
#' @param call A list: `label` (what the call is for, named in a failure) and
#'   `args` (the `aws` arguments).
#' @return A list: `label`, `status` (the exit status), `out` (its lines).
#' @noRd
.lnk_publish_aws <- function(call) {
  out <- tryCatch(
    suppressWarnings(system2("aws", shQuote(call$args), stdout = TRUE,
                             stderr = TRUE)),
    error = function(e) structure(conditionMessage(e), status = -1L))
  st <- attr(out, "status")
  list(label = call$label, status = if (is.null(st)) 0L else as.integer(st),
       out = as.character(out))
}

#' Run `aws` calls on a bounded pool, and stop unless every one succeeded.
#'
#' Each process costs about 2.4 s whatever it moves (#488), so PUBLISH runs its
#' puts, and the deletes after the manifest, `jobs` at a time. The pool is a
#' PSOCK cluster, not forks: the refusal gate has opened a duckdb connection by
#' then, and forking after a multithreaded library has loaded can deadlock.
#' `clusterApplyLB()` returns only when every call has, so nothing the caller
#' runs next (the manifest) can start while one is in flight. Every result is
#' checked before returning: a missing result, a non-zero exit or an R error
#' stops, naming each failed call.
#' @param calls A list of calls for `.lnk_publish_aws()`.
#' @param jobs At most this many at once; 1 runs them here, in order.
#' @return The results, in the order of `calls`.
#' @noRd
.lnk_publish_run <- function(calls, jobs = 1L) {
  if (length(calls) == 0L) return(list())
  f <- .lnk_publish_aws
  environment(f) <- globalenv()
  n <- min(as.integer(jobs), length(calls))
  if (n <= 1L) {
    res <- lapply(calls, f)
  } else {
    cl <- parallel::makePSOCKcluster(n)
    on.exit(parallel::stopCluster(cl), add = TRUE)
    res <- parallel::clusterApplyLB(cl, calls, f)
  }
  if (length(res) != length(calls)) {
    stop("aws pool returned ", length(res), " results for ", length(calls),
         " calls", call. = FALSE)
  }
  bad <- character(0)
  for (i in seq_along(calls)) {
    r <- res[[i]]
    if (!is.list(r) || is.null(r$status) || !identical(r$status, 0L)) {
      why <- if (is.list(r)) paste(utils::tail(r$out, 3L), collapse = " ") else
        paste(format(r), collapse = " ")
      bad <- c(bad, sprintf("%s: %s", calls[[i]]$label, why))
    }
  }
  if (length(bad) > 0L) {
    stop(length(bad), " of ", length(calls), " aws call(s) failed:\n  ",
         paste(utils::head(bad, 20L), collapse = "\n  "),
         if (length(bad) > 20L) sprintf("\n  ... and %d more",
                                        length(bad) - 20L),
         call. = FALSE)
  }
  res
}

#' The base64 Content-MD5 of a hex md5.
#' @noRd
.lnk_md5_b64 <- function(hex) {
  jsonlite::base64_enc(as.raw(strtoi(substring(hex, seq(1, 31, 2),
                                               seq(2, 32, 2)), 16L)))
}

#' A `put-object` call that answers with its VersionId and ETag.
#' @param extra More arguments (`--if-none-match`, `--cache-control`).
#' @noRd
.lnk_publish_put_call <- function(bucket, key, file, type, md5,
                                  extra = character(0)) {
  list(label = paste("put", key),
       args = c("s3api", "put-object", "--bucket", bucket, "--key", key,
                "--body", file, "--content-md5", .lnk_md5_b64(md5),
                "--content-type", type, extra,
                "--query", "[VersionId,ETag]", "--output", "text"))
}

#' A put's VersionId, read from its reply; refused when there is none.
#'
#' The reply is `--output text` of `[VersionId,ETag]`: one line, tab-separated.
#' A bucket without versioning answers `None`, which would pin nothing.
#' @param r One result of `.lnk_publish_run()` for a put call.
#' @return The VersionId.
#' @noRd
.lnk_publish_put_version <- function(r) {
  line <- utils::tail(r$out[nzchar(trimws(r$out))], 1L)
  v <- if (length(line) == 0L) "" else trimws(strsplit(line, "\t")[[1]][1])
  if (is.na(v) || !nzchar(v) || v %in% c("None", "null")) {
    stop(sub("^put ", "", r$label), " has no VersionId in its put reply",
         call. = FALSE)
  }
  v
}

#' Key-to-value pairs from one listing, every page of it.
#'
#' `what = "etag"`: each current object's ETag (`list-objects-v2`), quotes
#' removed. `what = "version"`: each key's latest VersionId
#' (`list-object-versions`, `IsLatest`; delete markers are listed apart, so a
#' key whose latest is a delete marker has none). One process for the whole
#' prefix instead of one per key (#488). A failed listing stops: absence must
#' be proven, not assumed.
#' @return A named character vector, names the full keys.
#' @noRd
.lnk_publish_list <- function(bucket, prefix, what = c("etag", "version")) {
  what <- match.arg(what)
  args <- switch(what,
    etag = c("s3api", "list-objects-v2", "--bucket", bucket, "--prefix", prefix,
             "--query", "Contents[].[Key,ETag]", "--output", "text"),
    version = c("s3api", "list-object-versions", "--bucket", bucket,
                "--prefix", prefix, "--query",
                "Versions[?IsLatest].[Key,VersionId]", "--output", "text"))
  r <- .lnk_publish_run(list(list(label = paste("list", what, prefix),
                                  args = args)))[[1]]
  rows <- strsplit(r$out[grepl("\t", r$out, fixed = TRUE)], "\t", fixed = TRUE)
  v <- gsub('"', "", vapply(rows, `[`, character(1), 2L), fixed = TRUE)
  names(v) <- vapply(rows, `[`, character(1), 1L)
  v
}

#' How many `aws` calls PUBLISH runs at once (`LNK_PUBLISH_JOBS`, default 8).
#' @noRd
.lnk_publish_jobs <- function(x = Sys.getenv("LNK_PUBLISH_JOBS", "")) {
  if (!nzchar(x)) return(8L)
  if (!grepl("^[0-9]{1,3}$", x) || as.integer(x) < 1L || as.integer(x) > 64L) {
    stop("LNK_PUBLISH_JOBS must be a whole number from 1 to 64, not '", x, "'",
         call. = FALSE)
  }
  as.integer(x)
}
# nolint end: indentation_linter
