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
#     [--wsgs=DUNC,KOTL] [--species=BT,RB] [--report=<dir>]
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
#   2. Parts go up with put-object --content-md5, so S3 refuses a body that
#      does not hash to the manifest's md5.
#   3. Before anything is written: the live manifest's configs must all be in
#      this root, and each provenance/ and config/ key must be absent or carry
#      the same md5 (its single-PUT ETag under the bucket's SSE-S3). Absent
#      keys are then put with --if-none-match, so they are written once and
#      never deleted.
#   4. manifest.json goes up last, no-cache.
#   5. Keys under segment/ that the manifest no longer names are deleted.
#      Nothing outside segment/ is ever deleted.
#   6. The published manifest is read back through lnk_catalog() and must
#      list the same parts and md5s.
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
  ent <- c(m$parts, m$files)
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

  aws <- function(...) {
    x <- suppressWarnings(system2("aws", shQuote(c(...)), stdout = TRUE,
                                  stderr = TRUE))
    attr(x, "status_code") <- attr(x, "status") %||% 0L
    x
  }
  aws_ok <- function(...) {
    x <- aws(...)
    if (attr(x, "status_code") != 0L) {
      stop("aws ", paste(c(...)[1:2], collapse = " "), " failed: ",
           paste(x, collapse = " "), call. = FALSE)
    }
    x
  }
  md5_b64 <- function(hex) {
    jsonlite::base64_enc(as.raw(strtoi(substring(hex, seq(1, 31, 2),
                                                 seq(2, 32, 2)), 16L)))
  }
  put <- function(file, key, type, md5, ...) {
    aws_ok("s3api", "put-object", "--bucket", bucket, "--key", key,
           "--body", file, "--content-md5", md5_b64(md5),
           "--content-type", type, ...)
  }
  # ETag of an existing key, or NA when it is absent (404). Any other failure
  # (403, network) stops: absence must be proven, not assumed.
  etag <- function(key) {
    x <- aws("s3api", "head-object", "--bucket", bucket, "--key", key,
             "--query", "ETag", "--output", "text")
    if (attr(x, "status_code") == 0L) return(gsub('"', "", x[length(x)]))
    if (any(grepl("\\(404\\)|Not Found", x))) return(NA_character_)
    stop("aws s3api head-object ", key, " failed: ", paste(x, collapse = " "),
         call. = FALSE)
  }

  # Every check before the first write, so a refusal leaves the bucket as it
  # was. (a) The live manifest's configs must all be in this root: the root is
  # the whole published tree, and a config it lacks would be dropped and its
  # parts deleted. (b) Each write-once key is absent or already these bytes.
  live <- paste(prefix, "manifest.json", sep = "/")
  if (!is.na(etag(live))) {
    live_cfg <- vapply(attr(lnk_catalog(paste0(target, "/manifest.json")),
                            "configs"), function(x) x$config, character(1))
    local_cfg <- vapply(m$configs, function(x) x$config, character(1))
    lost <- setdiff(live_cfg, local_cfg)
    if (length(lost) > 0L) {
      stop("the published tree holds config ", paste(lost, collapse = ", "),
           " and this root does not; build into a root seeded from the ",
           "bucket (aws s3 sync) so the publish keeps it", call. = FALSE)
    }
  }
  new_files <- Filter(function(f) {
    e <- etag(paste(prefix, f$key, sep = "/"))
    if (!is.na(e) && !identical(e, f$md5)) {
      stop(f$key, " is already published with ETag ", e, ", not md5 ", f$md5,
           ". provenance/ and config/ are written once; seed the root's ",
           "copies from the bucket (aws s3 sync) rather than rebuilding them.",
           call. = FALSE)
    }
    is.na(e)
  }, m$files)

  for (f in new_files) {
    type <- "text/plain"
    if (grepl("\\.parquet$", f$key)) type <- "application/vnd.apache.parquet"
    # the write is the check: S3 refuses it (412) if the key appeared since
    put(file.path(root, f$key), paste(prefix, f$key, sep = "/"), type, f$md5,
        "--if-none-match", "*")
  }
  stamp(length(new_files), " of ", length(m$files),
        " provenance/bundle files new")
  for (p in m$parts) {
    put(file.path(root, p$key), paste(prefix, p$key, sep = "/"),
        "application/vnd.apache.parquet", p$md5)
    stamp("put ", p$key)
  }

  f_man <- file.path(root, "manifest.json")
  put(f_man, paste(prefix, "manifest.json", sep = "/"), "application/json",
      unname(tools::md5sum(f_man)), "--cache-control", "no-cache")
  stamp("put manifest.json")

  seg <- paste0(prefix, "/segment/")
  keys <- aws_ok("s3api", "list-objects-v2", "--bucket", bucket,
                 "--prefix", seg, "--query", "Contents[].Key",
                 "--output", "text")
  keys <- setdiff(unlist(strsplit(keys, "\t")), c("None", ""))
  stale <- setdiff(keys, paste(prefix, vapply(m$parts, function(p) p$key,
                                              character(1)), sep = "/"))
  stopifnot(all(startsWith(stale, seg)))
  for (k in stale) {
    aws_ok("s3api", "delete-object", "--bucket", bucket, "--key", k)
    stamp("deleted stale ", k)
  }

  pub <- lnk_catalog(paste0(target, "/manifest.json"))
  loc <- lnk_catalog(f_man)
  if (!identical(pub$key, loc$key) || !identical(pub$md5, loc$md5)) {
    stop("the published manifest does not list the local parts",
         call. = FALSE)
  }
  stamp("published ", nrow(pub), " parts; ", length(stale),
        " stale segment keys deleted")
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
                    species = split_csv(opt("species")))
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
                 model = r$model %||% NA_character_,
                 link_dirty = r$link_dirty %||% NA,
                 recomputes = length(r$recompute_keys),
                 stringsAsFactors = FALSE)
    }))
  }))
  utils::write.csv(runs, file.path(report, "runs.csv"), row.names = FALSE)
  stamp("report in ", report)
}
