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
#'   - `fwapg_sha` — git SHA of the `fwapg` checkout that loaded the FWA
#'     primitives
#'   - `bcfishobs_sha` — git SHA of the `bcfishobs` checkout that matched
#'     observations onto the network. A model input, not a reference
#'     dataset: it decides which barriers are skipped, and so which
#'     segments are accessible (link#264)
#'   - `software` — list of versions, git SHAs and `sha_source` (which
#'     resolver tier answered) for `link` and `fresh`, plus
#'     `R.version.string`
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

  # One .lnk_pkg_git_state() call per package, not four wrapper calls: the
  # sha, the dirty flag and the tier that answered are three facts about one
  # resolution, and resolving them separately is how they drift apart.
  link_git  <- .lnk_pkg_git_state("link")
  fresh_git <- .lnk_pkg_git_state("fresh")

  software <- list(
    link  = list(version = as.character(utils::packageVersion("link")),
                  git_sha    = link_git$sha,
                  dirty      = link_git$dirty,
                  sha_source = link_git$source),
    fresh = list(version = .lnk_pkg_version_or_na("fresh"),
                  git_sha    = fresh_git$sha,
                  dirty      = fresh_git$dirty,
                  sha_source = fresh_git$source),
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
    config_name   = cfg$name,
    config_dir    = cfg$dir,
    config_hash   = .lnk_config_hash(cfg),
    config_drift  = if (is.null(prov)) {
      NA
    } else {
      any(prov$byte_drift, prov$shape_drift, na.rm = TRUE)
    },
    host          = .lnk_host(),
    fwapg_sha     = .lnk_fwapg_sha(),
    bcfishobs_sha = .lnk_bcfishobs_sha(),
    provenance    = prov,
    software      = software,
    db            = db,
    run           = list(aoi = aoi, start_time = start_time, end_time = NULL),
    result        = NULL
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

# `RemoteSha` from an installed package's DESCRIPTION, or NA.
#
# pak and remotes write `Remote*` fields at install time recording the source
# they actually built from. A package installed from a source checkout
# (`pak::local_install`, `R CMD INSTALL`) gets `RemoteType: local` and no
# `RemoteSha`; one installed from a git ref gets both. A source tree under
# `pkgload::load_all()` has neither — the fields do not exist until install.
#
# This is a more honest answer than a `.git` walk would give for an installed
# package even if one were possible: it is what was BUILT, not what a checkout
# on the same machine happens to sit at now.
#
# `packageDescription()` returns a bare `NA` (not a list) for a package that is
# not installed, and `NA$RemoteSha` is an error rather than NULL — hence the
# `is.list()` guard rather than a bare `$`.
#
# THE SHAPE GUARD IS NOT DEFENSIVE PROGRAMMING. `RemoteSha` holds a git commit
# only for git-backed installs; for `RemoteType: standard` (CRAN, PPM,
# r-universe) remotes writes the package **version** into the same field.
# Measured 2026-09-01 in this library: 278 of 300 installed packages carry a
# non-hex `RemoteSha` — `"1.4-8"`, `"0.5.3"`. Taking it unfiltered would put
# `fresh_sha = "0.33.0"` in a column that `study_area_verify.sql` and
# `lnk_preflight_parity()` both treat as a commit, with `source = "remote_sha"`
# and `dirty = FALSE` asserting it. Reachable rather than hypothetical: `fresh`
# resolves from CRAN-style remotes on any host installed through PPM or
# r-universe.
#
# The OTHER install path worth knowing about writes no `Remote*` fields at all:
# `scripts/update_hosts.sh` uses `R CMD INSTALL` on a GitHub source tarball,
# deliberately, to route around r-lib/pak#658 on cypher. That leaves this tier
# with nothing to read and no `.git` to fall back to, so the SHA is genuinely
# unrecoverable from the install. It is why that script now writes
# `FRESH_GIT_SHA` itself, and why `preflight_local()` gates on the resolved
# value BEFORE any spend rather than discovering it at the parity check.
#
# Anything that is not a hex object name declines the tier and falls through,
# which is the honest outcome: a version is not a code identity.
.lnk_pkg_remote_sha <- function(pkg) {
  d <- tryCatch(suppressWarnings(utils::packageDescription(pkg)),
                error = function(e) NULL)
  if (!is.list(d)) return(NA_character_)
  sha <- .lnk_blank_to_na(d$RemoteSha)
  if (is.na(sha) || !grepl("^[0-9a-f]{7,40}$", sha)) return(NA_character_)
  sha
}

# The first directory at or above a package's install dir that carries a `.git`
# whose HEAD reads. Returns `list(dir, sha)`, both NULL when none does.
#
# One lookup serving both the SHA and the dirty predicate is the point: the
# dirty flag then describes the *same* checkout the SHA came from, which two
# independent walks are free to disagree about.
.lnk_pkg_git_lookup <- function(pkg) {
  none <- list(dir = NULL, sha = NULL)
  pkg_dir <- tryCatch(
    find.package(pkg, quiet = TRUE),
    error = function(e) character(0))
  if (length(pkg_dir) == 0L) return(none)

  for (d in c(pkg_dir, dirname(pkg_dir))) {
    git <- file.path(d, ".git")
    if (!file.exists(git)) next
    sha <- .lnk_read_git_head(git)
    if (!is.null(sha)) return(list(dir = d, sha = sha))
  }
  none
}

# A package's code identity: which commit, was the tree modified, and which
# tier answered.
#
# ONE resolver with two wrappers, not two parallel three-tier resolvers. The
# two answers are read from the same DESCRIPTION and the same checkout, so
# splitting them lets them drift about the same package — silently, since
# neither function can see the other's tiers.
#
# `sha` and `dirty` walk their OWN tier lists over that shared lookup, because
# the env vars are set independently: `cypher_prep.sh` has always written
# `FRESH_GIT_SHA` and never `FRESH_GIT_DIRTY`, so a design where one env var
# claims the whole state would leave `dirty` NA on exactly the host that set
# the SHA.
#
#   tier            sha                        dirty
#   ------------------------------------------------------------------
#   1 env           <PKG>_GIT_SHA              <PKG>_GIT_DIRTY, else fall through
#   2 DESCRIPTION   RemoteSha                  FALSE when RemoteSha is present
#   3 .git walk     .lnk_read_git_head()       .lnk_git_dirty_at()
#   -               NA                         NA
#
# Tier 2's dirty is an inference, and a sound one: `RemoteSha` is only written
# when the install came from a published ref, which is not a working tree and
# cannot have been modified. It is what makes `fresh_dirty` answerable on a
# host with no `fresh` checkout at all — the state it was NULL in on all 39
# rows of the first provenanced runs (link#264).
#
# `source` names the tier that answered for the SHA, so "pinned, from the
# DESCRIPTION" is distinguishable from "pinned, by the orchestrator" without
# inferring it. Same reasoning as `bcfp_pin_source` (link#262).
.lnk_pkg_git_state <- function(pkg) {
  key <- toupper(pkg)

  env_sha <- .lnk_blank_to_na(Sys.getenv(paste0(key, "_GIT_SHA"), ""))
  env_dirty_raw <- .lnk_blank_to_na(Sys.getenv(paste0(key, "_GIT_DIRTY"), ""))
  env_dirty <- if (is.na(env_dirty_raw)) {
    NA
  } else {
    tolower(trimws(env_dirty_raw)) %in% c("1", "true", "yes", "t")
  }

  remote_sha <- .lnk_pkg_remote_sha(pkg)
  git <- .lnk_pkg_git_lookup(pkg)

  sha <- NA_character_
  source <- NA_character_
  if (!is.na(env_sha)) {
    sha <- env_sha
    source <- "env"
  } else if (!is.na(remote_sha)) {
    sha <- remote_sha
    source <- "remote_sha"
  } else if (!is.null(git$sha)) {
    sha <- git$sha
    source <- "git"
  }

  # `identical(sha, remote_sha)` is load-bearing. Tier 2's FALSE is a statement
  # about the commit `RemoteSha` names, and it may only be applied to a SHA
  # that IS that commit. Without the equality an orchestrator setting
  # `<PKG>_GIT_SHA` to anything else would have `dirty = FALSE` attached to a
  # commit this host never built — clean asserted about the wrong tree, which
  # is the failure the flag exists to prevent.
  #
  # It costs nothing in the case that matters: `cypher_prep.sh` derives
  # `FRESH_GIT_SHA` from `RemoteSha`, so the two are equal on a cypher. Where
  # they genuinely differ this falls through to the `.git` walk and then to NA,
  # and `FRESH_GIT_DIRTY` — which `cypher_prep.sh` now also writes — is what
  # answers instead.
  dirty <- if (!is.na(env_dirty)) {
    env_dirty
  } else if (!is.na(remote_sha) && identical(sha, remote_sha)) {
    FALSE
  } else if (!is.null(git$dir)) {
    .lnk_git_dirty_at(git$dir)
  } else {
    NA
  }

  list(sha = sha, dirty = dirty, source = source)
}

# Thin wrappers over [.lnk_pkg_git_state()]. Kept because they are the shape
# every caller already uses, and because a caller that wants one fact should
# not have to know the other exists.
.lnk_pkg_git_sha <- function(pkg) .lnk_pkg_git_state(pkg)$sha

.lnk_pkg_git_dirty <- function(pkg) .lnk_pkg_git_state(pkg)$dirty

# Is a git working directory dirty? A SHA recorded against a dirty tree is a
# lie, so provenance records the flag alongside it.
#
# The pathspec is load-bearing (link#257). `data-raw/logs/` is TRACKED on
# purpose — run logs are retained as contemporaneous evidence — and the run
# writes ~15 files into it while it runs, plus `bcfp_baselines.csv` which
# snapshot_bcfp.sh stamps on every host. So the dispatcher dirties its own
# checkout by operating, and a bare `git status --porcelain` reported
# link_dirty = TRUE on all 21 dispatcher rows of the first provenanced run
# while the tracked code was byte-identical to origin/main. A flag that is
# always set carries no information, and the one field that exists to say
# "this SHA cannot be trusted" was itself untrustworthy.
#
# The subject is "does tracked code differ from what a cypher will check out",
# so the run's own outputs are excluded and nothing else is. Untracked files
# are deliberately still counted: a new uncommitted R/*.R is invisible to a
# cypher, which is exactly the drift being detected.
#
# Two details, both probed against a temp checkout in both states rather than
# reasoned about:
#
#   * `:(exclude)` LONG FORM ONLY. `:!data-raw/logs` keeps parsing pathspec
#     magic after the `!`, so `d` aborts the whole command — and an aborted
#     git status returns empty, which reads as CLEAN. Fail-toward-skip on the
#     guard whose job is to catch a lie.
#   * `top` anchors the exclude at the REPO ROOT. `-- . ':(exclude)…'` resolves
#     both terms against the cwd, so were `-C` ever pointed at a subdirectory
#     the exclude would name a path that does not exist while `.` narrowed the
#     scan — silently missing a modified file one level up. A lone anchored
#     exclude means "everything except this", from anywhere.
#
# Measured on a fixture with a modified tracked log, an untracked log, a
# modified tracked R file and an untracked R file: 0 hits with only the logs
# touched, 2 once R/ was touched, identical from the root and from a subdir.
#
# shQuote() is REQUIRED, not decoration. system2() shell-quotes the command and
# pastes the arguments on raw, so the parentheses in `:(top,exclude)` are
# parsed by the shell:
#   sh: -c: line 0: syntax error near unexpected token `('
# The command then never runs, `out` is NULL, and this returns NA — so the
# predicate silently stops measuring anything at all. Caught on the first probe
# after writing it; it is invisible by reading, because the pathspec is correct
# and only its transport is not.
.lnk_git_dirty_pathspec <- c("--", shQuote(":(top,exclude)data-raw/logs"))

# The git call, split out from .lnk_pkg_git_state() so it can be tested
# against a REAL checkout in both states. The defect this guards is in what
# git is ASKED, so a mocked return value cannot see it — the test has to run
# the command.
#
# Returns TRUE (dirty), FALSE (clean), or NA (could not tell). NA must never
# be collapsed into FALSE: "git failed" and "nothing changed" are different
# facts, and only one of them means the SHA can be trusted.
.lnk_git_dirty_at <- function(d) {
  # system2() RAISES rather than returning a status when the command does not
  # exist, so a machine without git would error the caller instead of
  # degrading to NA. Test for the tool before calling it.
  if (!nzchar(Sys.which("git"))) return(NA)

  out <- tryCatch(
    suppressWarnings(system2("git",
                             c("-C", shQuote(d), "status", "--porcelain",
                               .lnk_git_dirty_pathspec),
                             stdout = TRUE, stderr = FALSE)),
    error = function(e) NULL)
  if (is.null(out)) return(NA)
  status <- attr(out, "status")
  if (!is.null(status) && !identical(as.integer(status), 0L)) return(NA)
  length(out) > 0L
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
