#!/usr/bin/env Rscript
# habitat_publish.R — build and publish the habitat export (link#308).
#
# Two modes, as wet's discharge publish (NewGraphEnvironment/wet#7):
#
# BUILD (default): lnk_scenario_export() into a local root, then check the
# tree against its own manifest. Reads persisted runs; writes only files.
#
#   Rscript data-raw/habitat_publish.R --root=<dir> \
#     --configs=default:fresh_default[,bcfishpass:fresh] \
#     [--wsgs=DUNC,KOTL] [--species=BT,RB] [--replace] [--report=<dir>]
#
# --wsgs / --species into a root that already holds more of a config stop
# unless --replace: an export replaces each config it names wholesale.
#
# A root holds every config published to it. An export replaces only the
# configs it names and carries the others forward from the root's manifest,
# so build into the same root the bucket was published from.
#
# PUBLISH (LNK_PUBLISH=1): upload a built root. Nothing is rebuilt.
#
#   LNK_PUBLISH=1 Rscript data-raw/habitat_publish.R --root=<dir> \
#     [--target=s3://fresh-bc/habitat/fwa/v1]
#
#   1. The local tree must still match its manifest (every part and file).
#   2. Before anything is written: this root must not lose anything live
#      (a config, a group:species pair, or a group's newer build;
#      LNK_PUBLISH_REPLACE=1 to remove or roll back on purpose), and each
#      provenance/ and config/ key must be absent or carry the same md5 (its
#      single-PUT ETag under the bucket's SSE-S3). The current ETags come from
#      one listing of the prefix (list-objects-v2), not a call per key.
#   3. Every put goes on one pool of LNK_PUBLISH_JOBS aws processes (default
#      8; link#488, where one at a time took 53 min for a province): parts,
#      per-group parts whose ETag is not already their md5 (barriers/,
#      barrier_overrides/, #465), the dependency map (replaced), and the new
#      provenance/ and config/ keys, which go with --if-none-match, so they are
#      written once and never deleted. Each put carries --content-md5, so S3
#      refuses a body that does not hash to the manifest's md5, and answers
#      with its VersionId. The pool returns only when every put has, and a
#      failed put stops PUBLISH before the manifest.
#   4. Each part's VersionId goes into the manifest: from its put, or for an
#      unchanged per-group part from one list-object-versions of its prefix.
#   5. manifest.json goes up last, no-cache.
#   6. Keys under segment/, barriers/ and barrier_overrides/ that the manifest
#      no longer names are deleted (on the pool). Nothing outside them is ever
#      deleted.
#   7. The published manifest is read back and must list the same parts,
#      per-group parts and md5s.
#
# Each step prints its seconds, and the end the minutes in all.
#
# Before step 2 (link#334): a build in the tree with no run_uid, a dirty
# link or fresh tree, or no logged thresholds, a recompute with no run_uid or
# a dirty tree, or a config exported from a dirty tree, refuses the publish
# (.lnk_publish_refusals()). LNK_PUBLISH_ALLOW="<reason>" publishes past it,
# and the manifest records the reason and the refusals (publish_allowed). The
# bucket's versioning must be Enabled: each part's and per-group part's S3
# VersionId is written into the manifest (atomically, locally) before the
# manifest goes up, so a reader can pin the exact bytes.
#
# The prefix is private (link#308, "Staged private first"): every call uses
# the caller's aws credentials, and readers need theirs too.
#
# Database for BUILD: local docker fwapg by default; override with
# LNK_EXPORT_DB / LNK_EXPORT_HOST / LNK_EXPORT_PORT / LNK_EXPORT_USER /
# LNK_EXPORT_PASSWORD.

suppressPackageStartupMessages({
  pkgload::load_all(quiet = TRUE)
})

opt <- function(name, default = NULL) {
  a <- grep(paste0("^--", name, "="), commandArgs(trailingOnly = TRUE),
            value = TRUE)
  if (length(a) == 0L) return(default)
  sub(paste0("^--", name, "="), "", a[length(a)])
}
split_csv <- function(x) {
  if (is.null(x)) return(NULL)
  v <- trimws(strsplit(x, ",")[[1]])
  v[nzchar(v)]
}
stamp <- function(...) {
  cat(format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), " ", ..., "\n",
      sep = "")
}

root <- opt("root")
if (is.null(root)) stop("--root=<dir> is required", call. = FALSE)
root <- normalizePath(root, mustWork = FALSE)

# Every part and file the manifest lists, checked on disk.
verify_tree <- function(root) {
  m <- jsonlite::fromJSON(file.path(root, "manifest.json"),
                          simplifyVector = FALSE)
  ent <- c(m$parts, m$group_parts, m$files,
           if (!is.null(m$dependencies)) list(m$dependencies))
  bad <- Filter(Negate(is.null), lapply(ent, function(e) {
    f <- file.path(root, e$key)
    if (!file.exists(f)) return(paste(e$key, "missing"))
    if (!identical(as.numeric(file.size(f)), as.numeric(e$bytes))) {
      return(paste(e$key, "size differs"))
    }
    if (!identical(unname(tools::md5sum(f)), e$md5)) {
      return(paste(e$key, "md5 differs"))
    }
    NULL
  }))
  list(manifest = m, n = length(ent), bad = unlist(bad))
}

if (identical(Sys.getenv("LNK_PUBLISH"), "1")) {
  # ---- PUBLISH ---------------------------------------------------------------
  target <- sub("/$", "", opt("target", "s3://fresh-bc/habitat/fwa/v1"))
  if (!grepl("^s3://[a-z0-9.-]+/.+", target)) {
    stop("--target must be s3://<bucket>/<prefix>", call. = FALSE)
  }
  bucket <- sub("^s3://([^/]+)/.*$", "\\1", target)
  prefix <- sub("^s3://[^/]+/", "", target)
  stamp("PUBLISH ", root, " -> ", target)

  v <- verify_tree(root)
  if (length(v$bad) > 0L) {
    stop("the local tree no longer matches its manifest: ",
         paste(v$bad, collapse = "; "), call. = FALSE)
  }
  m <- v$manifest

  jobs <- .lnk_publish_jobs()
  t_all <- Sys.time()
  t_step <- Sys.time()
  step_done <- function(what) {
    now <- Sys.time()
    stamp(sprintf("%s in %.1f s", what, as.numeric(difftime(now, t_step,
                                                             units = "secs"))))
    t_step <<- now
  }
  aws_ok <- function(...) .lnk_publish_run(list(list(
    label = paste(c(...)[1:2], collapse = " "), args = c(...))))[[1]]$out
  # ETag of one existing key, or NA when it is absent (404). Any other failure
  # (403, network) stops: absence must be proven, not assumed.
  etag <- function(key) {
    r <- .lnk_publish_aws(list(label = key, args = c(
      "s3api", "head-object", "--bucket", bucket, "--key", key,
      "--query", "ETag", "--output", "text")))
    if (r$status == 0L) return(gsub('"', "", r$out[length(r$out)]))
    if (any(grepl("\\(404\\)|Not Found", r$out))) return(NA_character_)
    stop("aws s3api head-object ", key, " failed: ",
         paste(r$out, collapse = " "), call. = FALSE)
  }

  # The builds a floodplain item can name and rebuild (link#334), and the
  # bucket keeping every version a manifest will name.
  allowed <- .lnk_publish_gate(.lnk_publish_refusals(m, root),
                               Sys.getenv("LNK_PUBLISH_ALLOW", ""))
  if (!is.null(allowed)) {
    stamp("PUBLISH past ", length(allowed$refusals), " refusal(s): ",
          allowed$reason)
  }
  vs <- aws_ok("s3api", "get-bucket-versioning", "--bucket", bucket,
               "--query", "Status", "--output", "text")
  if (!identical(trimws(vs[length(vs)]), "Enabled")) {
    stop("bucket ", bucket, " versioning is '", vs[length(vs)], "', not ",
         "Enabled: the manifest's version ids would not pin anything",
         call. = FALSE)
  }

  # Every check before the first write, so a refusal leaves the bucket as it
  # was. (a) The root must not lose anything live (.lnk_manifest_regressions:
  # a config, a pair, a newer build or recompute, a newer export); the root is
  # the whole published tree. (b) Each write-once key is absent or already
  # these bytes. Current ETags come from one listing of the prefix, not one
  # head-object per key (link#488).
  live <- paste(prefix, "manifest.json", sep = "/")
  if (!is.na(etag(live))) {
    live_cfg <- attr(lnk_catalog(paste0(target, "/manifest.json")), "configs")
    live_m <- jsonlite::fromJSON(.lnk_fetch_text(paste0(target,
                                                         "/manifest.json")),
                                 simplifyVector = FALSE)
    lost <- .lnk_manifest_regressions(
      live_m, m, vapply(live_cfg, function(x) x$config, character(1)))
    if (length(lost) > 0L && !identical(Sys.getenv("LNK_PUBLISH_REPLACE"),
                                        "1")) {
      stop("this root would replace what is published: ",
           paste(lost, collapse = "; "), ". Seed the root from the bucket ",
           "(aws s3 sync) and re-export, or set LNK_PUBLISH_REPLACE=1.",
           call. = FALSE)
    }
  }
  etags <- .lnk_publish_list(bucket, paste0(prefix, "/"), "etag")
  have <- function(key) {
    e <- etags[paste(prefix, key, sep = "/")]
    if (is.na(e)) NA_character_ else unname(e)
  }
  new_files <- Filter(function(f) {
    e <- have(f$key)
    if (!is.na(e) && !identical(e, f$md5)) {
      stop(f$key, " is already published with ETag ", e, ", not md5 ", f$md5,
           ". provenance/ and config/ are written once; seed the root's ",
           "copies from the bucket (aws s3 sync) rather than rebuilding them.",
           call. = FALSE)
    }
    is.na(e)
  }, m$files)
  # one part per group per config, most unchanged between runs: an ETag that
  # is already the md5 (a single PUT under SSE-S3) is these bytes
  gp_same <- vapply(m$group_parts, function(p) identical(have(p$key), p$md5),
                    logical(1))
  step_done(sprintf("checks: %d keys listed, %d of %d files new, %d of %d per-group parts unchanged",
                    length(etags), length(new_files), length(m$files),
                    sum(gp_same), length(m$group_parts)))

  # Every put on one pool (LNK_PUBLISH_JOBS at once), each with --content-md5
  # so S3 refuses a body that does not hash to the manifest's md5, and each
  # answering with its VersionId. provenance/ and config/ go with
  # --if-none-match: the write is the check, a key that appeared since is a 412
  # and stops PUBLISH. The pool returns only when every put has, and every
  # result is checked, so a failed put stops before the manifest.
  pq <- "application/vnd.apache.parquet"
  calls <- c(
    lapply(new_files, function(f) {
      type <- if (grepl("\\.parquet$", f$key)) pq else "text/plain"
      .lnk_publish_put_call(bucket, paste(prefix, f$key, sep = "/"),
                            file.path(root, f$key), type, f$md5,
                            c("--if-none-match", "*"))
    }),
    lapply(c(m$parts, m$group_parts[!gp_same],
             if (!is.null(m$dependencies)) list(m$dependencies)),
           function(p) .lnk_publish_put_call(
             bucket, paste(prefix, p$key, sep = "/"), file.path(root, p$key),
             pq, p$md5)))
  res <- .lnk_publish_run(calls, jobs)
  put_version <- vapply(res, .lnk_publish_put_version, character(1))
  names(put_version) <- vapply(calls, function(x) sub("^put ", "", x$label),
                               character(1))
  step_done(sprintf("put %d new files, %d parts, %d of %d per-group parts%s (%d at once)",
                    length(new_files), length(m$parts), sum(!gp_same),
                    length(m$group_parts),
                    if (!is.null(m$dependencies)) ", the dependency map" else "",
                    min(jobs, length(calls))))

  # Name each part's version in the manifest before it goes up (link#334):
  # from its put's reply, or for an unchanged per-group part from one listing
  # of the per-group prefixes. Rewritten locally first, atomically, so the
  # local copy is what is read back; the manifest cannot name its own version
  # (list-object-versions).
  latest <- character(0)
  if (any(gp_same)) {
    dirs <- unique(sub("/.*$", "", vapply(m$group_parts[gp_same],
                                          function(p) p$key, character(1))))
    for (d in dirs) {
      latest <- c(latest, .lnk_publish_list(bucket, paste0(prefix, "/", d, "/"),
                                            "version"))
    }
  }
  version <- function(key) {
    k <- paste(prefix, key, sep = "/")
    v <- if (k %in% names(put_version)) put_version[[k]] else
      if (k %in% names(latest)) latest[[k]] else NA_character_
    if (is.na(v) || !nzchar(v) || v %in% c("None", "null")) {
      stop(k, " has no VersionId", call. = FALSE)
    }
    v
  }
  for (i in seq_along(m$parts)) {
    m$parts[[i]]$version_id <- version(m$parts[[i]]$key)
  }
  for (i in seq_along(m$group_parts)) {
    m$group_parts[[i]]$version_id <- version(m$group_parts[[i]]$key)
  }
  if (!is.null(m$dependencies)) {
    m$dependencies$version_id <- version(m$dependencies$key)
  }
  m$publish_allowed <- allowed
  f_man <- file.path(root, "manifest.json")
  tmp_man <- tempfile(tmpdir = root, fileext = ".json")
  jsonlite::write_json(m, tmp_man, auto_unbox = TRUE, pretty = TRUE,
                       digits = NA, null = "null", na = "null")
  if (!file.rename(tmp_man, f_man)) {
    unlink(tmp_man)
    stop("could not write the versioned manifest", call. = FALSE)
  }
  step_done(sprintf("versions recorded for %d parts and %d per-group parts",
                    length(m$parts), length(m$group_parts)))
  .lnk_publish_run(list(.lnk_publish_put_call(
    bucket, paste(prefix, "manifest.json", sep = "/"), f_man,
    "application/json", unname(tools::md5sum(f_man)),
    c("--cache-control", "no-cache"))))
  step_done("put manifest.json")

  named <- paste(prefix, vapply(c(m$parts, m$group_parts), function(p) p$key,
                                character(1)), sep = "/")
  stale <- character(0)
  for (d in c("segment", "barriers", "barrier_overrides")) {
    seg <- paste0(prefix, "/", d, "/")
    keys <- names(.lnk_publish_list(bucket, seg, "etag"))
    st <- setdiff(keys, named)
    stopifnot(all(startsWith(st, seg)))
    stale <- c(stale, st)
  }
  .lnk_publish_run(lapply(stale, function(k) list(
    label = paste("delete", k),
    args = c("s3api", "delete-object", "--bucket", bucket, "--key", k))), jobs)
  for (k in stale) stamp("deleted stale ", k)
  step_done(sprintf("%d stale keys deleted", length(stale)))

  pub <- lnk_catalog(paste0(target, "/manifest.json"))
  loc <- lnk_catalog(f_man)
  if (!identical(pub$key, loc$key) || !identical(pub$md5, loc$md5)) {
    stop("the published manifest does not list the local parts",
         call. = FALSE)
  }
  gp_keys <- function(mf) {
    vapply(mf$group_parts, function(p) paste(p$key, p$md5), character(1))
  }
  pub_m <- jsonlite::fromJSON(.lnk_fetch_text(paste0(target, "/manifest.json")),
                              simplifyVector = FALSE)
  if (!identical(gp_keys(pub_m), gp_keys(m)) ||
      !identical(pub_m$dependencies$md5, m$dependencies$md5)) {
    stop("the published manifest does not list the local per-group parts",
         call. = FALSE)
  }
  step_done("read back")
  stamp(sprintf("published %d parts and %d per-group parts; %d stale keys deleted; %.1f min in all",
                nrow(pub), length(m$group_parts), length(stale),
                as.numeric(difftime(Sys.time(), t_all, units = "mins"))))
  quit(save = "no")
}

# ---- BUILD -------------------------------------------------------------------
configs_arg <- opt("configs")
if (is.null(configs_arg)) {
  stop("--configs=<config>:<schema>[,...] is required: say which persist ",
       "schema holds each config's build", call. = FALSE)
}
pairs <- strsplit(split_csv(configs_arg), ":", fixed = TRUE)
if (!all(lengths(pairs) == 2L)) {
  stop("bad --configs: want <config>:<schema>[,<config>:<schema>]",
       call. = FALSE)
}
configs <- stats::setNames(vapply(pairs, `[`, character(1), 2L),
                           vapply(pairs, `[`, character(1), 1L))

conn <- lnk_db_conn(
  dbname = Sys.getenv("LNK_EXPORT_DB", "fwapg"),
  host = Sys.getenv("LNK_EXPORT_HOST", "localhost"),
  port = as.integer(Sys.getenv("LNK_EXPORT_PORT", "5432")),
  user = Sys.getenv("LNK_EXPORT_USER", "postgres"),
  password = Sys.getenv("LNK_EXPORT_PASSWORD", "postgres"))

t0 <- Sys.time()
stamp("BUILD ", paste(names(configs), configs, sep = ":", collapse = ","),
      " -> ", root)
lnk_scenario_export(conn, configs, root, wsgs = split_csv(opt("wsgs")),
                    species = split_csv(opt("species")),
                    replace = "--replace" %in% commandArgs(trailingOnly = TRUE))
DBI::dbDisconnect(conn)

v <- verify_tree(root)
if (length(v$bad) > 0L) {
  stop("the tree does not match its own manifest: ",
       paste(v$bad, collapse = "; "), call. = FALSE)
}
cat_local <- lnk_catalog(file.path(root, "manifest.json"))
stamp("built ", nrow(cat_local), " parts and ",
      length(v$manifest$files), " provenance/bundle files in ",
      format(round(difftime(Sys.time(), t0, units = "mins"), 1)),
      "; all verify")

report <- opt("report")
if (!is.null(report)) {
  dir.create(report, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(cat_local[, c("config", "species", "code", "drainage",
                                 "wsgs", "rows", "bytes", "md5")],
                   file.path(report, "parts.csv"), row.names = FALSE)
  cfgs <- attr(cat_local, "configs")
  runs <- do.call(rbind, lapply(cfgs, function(cf) {
    do.call(rbind, lapply(cf$runs, function(r) {
      data.frame(config = cf$config, wsg = r$watershed_group_code,
                 run_id = r$run_id, run_uid = r$run_uid %||% NA_character_,
                 config_hash = r$config_hash,
                 thresholds_logged = isTRUE(cf$thresholds_logged[[
                   r$config_hash]]),
                 discharge_fill = r$discharge_fill %||% NA,
                 # NULL on a run from before #331, which read fwapg
                 discharge_source = r$discharge_source %||% "fwapg",
                 model = r$model %||% NA_character_,
                 link_dirty = r$link_dirty %||% NA,
                 recomputes = length(r$recompute_keys),
                 stringsAsFactors = FALSE)
    }))
  }))
  utils::write.csv(runs, file.path(report, "runs.csv"), row.names = FALSE)
  stamp("report in ", report)
}
