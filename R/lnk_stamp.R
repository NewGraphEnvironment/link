#' Capture a Pipeline Run Stamp
#'
#' Returns a structured snapshot of every input that influences a
#' habitat-classification run: config-bundle provenance with current
#' checksums, software versions and git SHAs, optional database
#' snapshot counts, plus AOI and timestamps. The stamp is the artifact
#' that makes pipeline drift attributable — diff two stamps to localize
#' "what changed" between two runs.
#'
#' Workflow:
#'
#' ```r
#' stamp <- lnk_stamp(cfg, conn, aoi = "ADMS")
#' # ... run pipeline ...
#' stamp <- lnk_stamp_finish(stamp, result = comparison_tibble)
#' message(format(stamp, "markdown"))
#' ```
#'
#' The markdown rendering is one of multiple output formats; covers the
#' report-appendix scope of [issue #24](
#' https://github.com/NewGraphEnvironment/link/issues/24).
#'
#' @param cfg An `lnk_config` object from [lnk_config()].
#' @param conn Optional [DBI::DBIConnection-class] for local fwapg.
#'   When non-`NULL` and `db_snapshot = TRUE`, populates the `db` slot
#'   with row counts from `bcfishobs.observations` and
#'   `whse_basemapping.fwa_stream_networks_sp`. When `NULL`, `db` is
#'   `NULL`.
#' @param aoi Optional character. Watershed group code or arbitrary AOI
#'   identifier. Recorded verbatim in `stamp$run$aoi`.
#' @param db_snapshot Logical. When `FALSE`, skips DB row-count queries
#'   even if `conn` is provided. Default `TRUE`.
#' @param start_time A [base::Sys.time()] value. Default `Sys.time()`
#'   captured at the call. Override only when reconstructing a stamp
#'   from a known start.
#'
#' @return An `lnk_stamp` S3 list with these slots:
#'
#'   - `config_name` — `cfg$name`
#'   - `config_dir` — `cfg$dir`
#'   - `provenance` — output of [lnk_config_verify()] called on `cfg`
#'     at stamp time (carries observed checksums + drift status)
#'   - `software` — list of versions + git SHAs for `link`, `fresh`,
#'     plus `R.version.string`
#'   - `db` — list of DB snapshot counts, or `NULL`
#'   - `run` — list with `aoi`, `start_time`, `end_time` (initially
#'     `NULL` — set by [lnk_stamp_finish()])
#'   - `result` — the result tibble or `NULL` (set by
#'     [lnk_stamp_finish()])
#'
#' @family stamp
#'
#' @export
#'
#' @examples
#' cfg <- lnk_config("bcfishpass")
#' stamp <- lnk_stamp(cfg, aoi = "ADMS")
#' stamp
#' format(stamp, "markdown")
#'
#' \dontrun{
#' # Full workflow with DB and a result
#' conn <- lnk_db_conn()
#' stamp <- lnk_stamp(cfg, conn, aoi = "ADMS")
#' result <- compare_bcfishpass_wsg(wsg = "ADMS", config = cfg)
#' stamp <- lnk_stamp_finish(stamp, result = result)
#' writeLines(format(stamp, "markdown"), "stamp.md")
#' }
lnk_stamp <- function(cfg,
                       conn = NULL,
                       aoi = NULL,
                       db_snapshot = TRUE,
                       start_time = Sys.time()) {
  if (!inherits(cfg, "lnk_config")) {
    stop("cfg must be an lnk_config object (from lnk_config())",
         call. = FALSE)
  }
  if (!is.null(aoi) &&
      (!is.character(aoi) || length(aoi) != 1L || !nzchar(aoi))) {
    stop("aoi must be NULL or a single non-empty string", call. = FALSE)
  }

  prov <- if (!is.null(cfg$provenance)) {
    suppressWarnings(lnk_config_verify(cfg, strict = FALSE))
  } else {
    NULL
  }

  software <- list(
    link  = list(version = as.character(utils::packageVersion("link")),
                  git_sha = .lnk_pkg_git_sha("link")),
    fresh = list(version = .lnk_pkg_version_or_na("fresh"),
                  git_sha = .lnk_pkg_git_sha("fresh")),
    R     = R.version.string
  )

  db <- if (!is.null(conn) && isTRUE(db_snapshot)) {
    list(
      bcfishobs_observations = .lnk_db_count(conn, "bcfishobs.observations"),
      fwa_stream_networks_sp = .lnk_db_count(conn,
        "whse_basemapping.fwa_stream_networks_sp")
    )
  } else {
    NULL
  }

  out <- list(
    config_name = cfg$name,
    config_dir  = cfg$dir,
    provenance  = prov,
    software    = software,
    db          = db,
    run         = list(aoi = aoi, start_time = start_time, end_time = NULL),
    result      = NULL
  )
  class(out) <- c("lnk_stamp", "list")
  out
}

#' Finalize an in-progress run stamp
#'
#' Sets `end_time` to `Sys.time()` and attaches an optional `result`
#' object (typically the comparison tibble or rollup). Returns the
#' updated stamp.
#'
#' @param stamp An `lnk_stamp` object from [lnk_stamp()].
#' @param result Optional. Any R object representing the run's output.
#'   Stored verbatim in `stamp$result`.
#' @param end_time Default `Sys.time()`.
#'
#' @return An `lnk_stamp` with `run$end_time` and `result` populated.
#'
#' @family stamp
#'
#' @export
lnk_stamp_finish <- function(stamp, result = NULL, end_time = Sys.time()) {
  if (!inherits(stamp, "lnk_stamp")) {
    stop("stamp must be an lnk_stamp object (from lnk_stamp())",
         call. = FALSE)
  }
  stamp$run$end_time <- end_time
  stamp$result <- result
  stamp
}

#' @export
print.lnk_stamp <- function(x, ...) {
  cat("<lnk_stamp> ", x$config_name, "\n", sep = "")
  cat("  aoi:        ",
      if (is.null(x$run$aoi)) "(none)" else x$run$aoi,
      "\n", sep = "")
  cat("  started:    ", format(x$run$start_time, "%Y-%m-%d %H:%M:%S %Z"),
      "\n", sep = "")
  if (!is.null(x$run$end_time)) {
    elapsed <- as.numeric(difftime(x$run$end_time, x$run$start_time,
                                    units = "secs"))
    cat("  ended:      ", format(x$run$end_time, "%Y-%m-%d %H:%M:%S %Z"),
        " (", round(elapsed, 1), "s elapsed)\n", sep = "")
  }
  cat("  link:       ", x$software$link$version, "\n", sep = "")
  cat("  fresh:      ", x$software$fresh$version, "\n", sep = "")
  if (!is.null(x$provenance)) {
    n_byte <- sum(x$provenance$byte_drift)
    n_shape <- sum(x$provenance$shape_drift)
    cat("  provenance: ", nrow(x$provenance), " files (",
        n_byte, " byte, ", n_shape, " shape drifted)\n", sep = "")
  }
  if (!is.null(x$db)) {
    cat("  db:         bcfishobs.observations=",
        format(x$db$bcfishobs_observations %||% NA_integer_,
               big.mark = ","), "\n", sep = "")
  }
  invisible(x)
}

#' @export
format.lnk_stamp <- function(x, type = c("markdown", "text"), ...) {
  type <- match.arg(type)
  if (type == "markdown") .lnk_stamp_markdown(x) else .lnk_stamp_text(x)
}

# -- internals ----------------------------------------------------------------

.lnk_stamp_markdown <- function(x) {
  lines <- c(
    paste0("## Run stamp — ", x$config_name),
    "",
    sprintf("- AOI: `%s`", x$run$aoi %||% "(none)"),
    sprintf("- Started: %s",
            format(x$run$start_time, "%Y-%m-%d %H:%M:%S %Z")))
  if (!is.null(x$run$end_time)) {
    elapsed <- as.numeric(difftime(x$run$end_time, x$run$start_time,
                                    units = "secs"))
    lines <- c(lines,
      sprintf("- Ended: %s (%.1fs elapsed)",
              format(x$run$end_time, "%Y-%m-%d %H:%M:%S %Z"), elapsed))
  }
  lines <- c(lines,
    "",
    "### Software",
    sprintf("- link: %s (sha %s)",
            x$software$link$version, x$software$link$git_sha %||% "NA"),
    sprintf("- fresh: %s (sha %s)",
            x$software$fresh$version, x$software$fresh$git_sha %||% "NA"),
    sprintf("- R: %s", x$software$R))

  if (!is.null(x$db)) {
    lines <- c(lines,
      "",
      "### Database snapshot",
      sprintf("- bcfishobs.observations: %s",
              format(x$db$bcfishobs_observations %||% NA_integer_,
                     big.mark = ",")),
      sprintf("- whse_basemapping.fwa_stream_networks_sp: %s",
              format(x$db$fwa_stream_networks_sp %||% NA_integer_,
                     big.mark = ",")))
  }

  if (!is.null(x$provenance) && nrow(x$provenance) > 0L) {
    n_byte  <- sum(x$provenance$byte_drift)
    n_shape <- sum(x$provenance$shape_drift)
    lines <- c(lines,
      "",
      sprintf("### Config provenance (%d files, %d byte / %d shape drifted)",
              nrow(x$provenance), n_byte, n_shape),
      "",
      "| file | byte drift | shape drift |",
      "|---|---|---|")
    for (i in seq_len(nrow(x$provenance))) {
      lines <- c(lines, sprintf("| `%s` | %s | %s |",
                                 x$provenance$file[i],
                                 if (x$provenance$byte_drift[i]) "**yes**" else "no",
                                 if (x$provenance$shape_drift[i]) "**yes**" else "no"))
    }
  }
  paste(lines, collapse = "\n")
}

.lnk_stamp_text <- function(x) {
  paste(utils::capture.output(print(x)), collapse = "\n")
}

.lnk_pkg_version_or_na <- function(pkg) {
  tryCatch(as.character(utils::packageVersion(pkg)),
           error = function(e) NA_character_)
}

# Discover a package's git SHA from its install dir, falling back to an
# env var when the package was installed without `.git/` (R CMD INSTALL,
# pak, CRAN). Three-tier:
#   1. `LINK_GIT_SHA` (or `<PKG>_GIT_SHA`) env var — explicit override
#   2. `.git/HEAD` chain in the package dir or its parent (devtools::load_all)
#   3. NA when neither resolves.
.lnk_pkg_git_sha <- function(pkg) {
  env_key <- paste0(toupper(pkg), "_GIT_SHA")
  v <- Sys.getenv(env_key, "")
  if (nzchar(v)) return(v)

  pkg_dir <- tryCatch(
    find.package(pkg, quiet = TRUE),
    error = function(e) character(0))
  if (length(pkg_dir) == 0L) return(NA_character_)

  # Walk up looking for a .git directory or file.
  for (d in c(pkg_dir, dirname(pkg_dir))) {
    git <- file.path(d, ".git")
    if (file.exists(git)) {
      sha <- .lnk_read_git_head(git)
      if (!is.null(sha)) return(sha)
    }
  }
  NA_character_
}

.lnk_read_git_head <- function(git_path) {
  # `git_path` can be a directory (.git/) or a file (worktree pointer).
  if (file.info(git_path)$isdir) {
    head_file <- file.path(git_path, "HEAD")
  } else {
    # gitdir pointer file ("gitdir: /path/to/.git/worktrees/foo")
    pointer <- readLines(git_path, warn = FALSE, n = 1)
    if (length(pointer) == 0L) return(NULL)
    gitdir <- sub("^gitdir:\\s*", "", pointer)
    head_file <- file.path(gitdir, "HEAD")
  }
  if (!file.exists(head_file)) return(NULL)
  head <- readLines(head_file, warn = FALSE, n = 1)
  if (length(head) == 0L) return(NULL)
  if (grepl("^ref:", head)) {
    ref <- sub("^ref:\\s*", "", head)
    ref_file <- file.path(dirname(head_file), ref)
    if (!file.exists(ref_file)) return(NULL)
    sha <- readLines(ref_file, warn = FALSE, n = 1)
    if (length(sha) == 0L) return(NULL)
    return(sha)
  }
  head
}

.lnk_db_count <- function(conn, qualified_table) {
  if (!grepl("^[A-Za-z_][A-Za-z0-9_]*\\.[A-Za-z_][A-Za-z0-9_]*$",
             qualified_table)) {
    stop("qualified_table must be 'schema.name' with no quoting", call. = FALSE)
  }
  tryCatch({
    res <- DBI::dbGetQuery(conn,
      sprintf("SELECT count(*) AS n FROM %s", qualified_table))
    as.integer(res$n[1])
  }, error = function(e) NA_integer_)
}
