#' Read a habitat export's manifest
#'
#' The manifest written by [lnk_scenario_export()] is the only index of a
#' published tree: the bucket is not listable, so readers go through it. Each
#' part's Hive fields (`config`, `species`, `code`) come from its key, the one
#' place they are written, and its `href` resolves relative to the manifest.
#'
#' `manifest` may be a local path, an `https://` URL (an anonymous read, for a
#' public prefix) or an `s3://` URL. An `s3://` read goes through the `aws`
#' command line with the caller's credentials, which a private prefix needs:
#' `habitat/` is staged private (link#308).
#'
#' @param manifest Path or URL of `manifest.json`.
#' @return A data frame, one row per part: `dataset`, `config`, `species`,
#'   `code`, `drainage`, `wsgs`, `key`, `href`, `rows`, `bytes`, `md5`.
#'   Attributes: `manifest` (where it was read), `id`, `built`, `provenance`,
#'   `configs` (per config: the log rows of each build, config hashes,
#'   discharge, bundles) and `files` (the provenance and bundle files).
#' @family export
#' @export
#' @examples
#' \dontrun{
#' cat <- lnk_catalog("s3://fresh-bc/habitat/fwa/v1/manifest.json")
#' table(cat$config, cat$species)
#'
#' # which builds produced the default config's parts?
#' runs <- attr(cat, "configs")[[1]]$runs
#' vapply(runs, function(r) r$run_id, character(1))
#' }
lnk_catalog <- function(manifest) {
  stopifnot(is.character(manifest), length(manifest) == 1L, nzchar(manifest))
  txt <- .lnk_fetch_text(manifest)
  m <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE),
                error = function(e) {
                  stop("not a JSON manifest: ", manifest, " (",
                       conditionMessage(e), ")", call. = FALSE)
                })
  if (!identical(as.integer(m$manifest_version), 1L)) {
    stop("unsupported manifest_version in ", manifest, call. = FALSE)
  }
  parts <- m$parts
  if (length(parts) == 0L) stop("manifest lists no parts: ", manifest,
                                call. = FALSE)
  base <- sub("/[^/]*$", "", manifest)
  out <- do.call(rbind, lapply(parts, function(p) {
    h <- .lnk_part_parse(p$key)
    md5 <- as.character(p$md5 %||% NA_character_)
    if (!grepl("^[0-9a-f]{32}$", md5)) {
      stop("part ", p$key, " has no valid md5 in the manifest", call. = FALSE)
    }
    data.frame(
      dataset = as.character(p$dataset %||% .lnk_export_dataset()),
      config = h$config, species = h$species, code = h$code,
      drainage = as.character(p$drainage %||% NA_character_),
      wsgs = as.character(p$wsgs %||% NA_character_),
      key = p$key, href = paste0(base, "/", p$key),
      rows = as.numeric(p$rows), bytes = as.numeric(p$bytes), md5 = md5,
      stringsAsFactors = FALSE)
  }))
  attr(out, "manifest") <- manifest
  attr(out, "id") <- m$id
  attr(out, "built") <- m$built
  attr(out, "provenance") <- m$provenance
  attr(out, "configs") <- m$configs
  attr(out, "files") <- m$files
  out
}

#' Hive fields of a part key; the one parser for writer-shaped keys.
#' @noRd
.lnk_part_parse <- function(key) {
  re <- paste0("^segment/config=([A-Za-z0-9_.-]+)/species=([A-Z]{2,3})/",
               "part-([0-9A-Za-z]+)\\.parquet$")
  if (!is.character(key) || length(key) != 1L || !grepl(re, key)) {
    stop("not a habitat part key: ", key, call. = FALSE)
  }
  list(config = sub(re, "\\1", key), species = sub(re, "\\2", key),
       code = sub(re, "\\3", key))
}

#' Copy an `s3://` object to a local file with the `aws` command line.
#'
#' The caller's credentials and profile apply, which is the point: the prefix
#' is private. A failed copy stops with aws's own message.
#' @noRd
.lnk_s3_cp <- function(src, dest) {
  out <- .lnk_aws(c("s3", "cp", shQuote(src), shQuote(dest),
                    "--only-show-errors"))
  st <- attr(out, "status")
  if (!is.null(st) && st != 0L) {
    stop("aws s3 cp ", src, " failed (exit ", st, "): ",
         paste(out, collapse = " "), call. = FALSE)
  }
  invisible(dest)
}

#' Run the `aws` command line; output and exit status as `system2()` gives
#' them (status in `attr(, "status")`, NULL on success).
#' @noRd
.lnk_aws <- function(args) {
  if (!nzchar(Sys.which("aws"))) {
    stop("this needs the aws command line on PATH", call. = FALSE)
  }
  suppressWarnings(system2("aws", args, stdout = TRUE, stderr = TRUE))
}

#' Download `src` (https:// or s3://) to `dest`, or copy a local file.
#' @noRd
.lnk_fetch_file <- function(src, dest) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  if (startsWith(src, "s3://")) {
    return(.lnk_s3_cp(src, dest))
  }
  if (grepl("^https?://", src)) {
    resp <- httr::GET(src, httr::write_disk(dest, overwrite = TRUE))
    if (httr::status_code(resp) >= 400L) {
      unlink(dest)
      stop(sprintf("HTTP %d for %s", httr::status_code(resp), src),
           call. = FALSE)
    }
    return(invisible(dest))
  }
  if (!file.exists(src)) stop("no such file: ", src, call. = FALSE)
  if (!file.copy(src, dest, overwrite = TRUE)) {
    stop("could not copy ", src, call. = FALSE)
  }
  invisible(dest)
}

#' Read a small text object from a path, https:// or s3://.
#' @noRd
.lnk_fetch_text <- function(src) {
  if (!startsWith(src, "s3://") && !grepl("^https?://", src)) {
    if (!file.exists(src)) stop("no such file: ", src, call. = FALSE)
    return(paste(readLines(src, warn = FALSE, encoding = "UTF-8"),
                 collapse = "\n"))
  }
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp), add = TRUE)
  .lnk_fetch_file(src, tmp)
  paste(readLines(tmp, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}
