#!/usr/bin/env Rscript
# recompute_readers_check.R — which groups outside a run read it, and which of
# them may be recomputed now (link#274). Called by study_area_finish.sh's
# run_finish, from the repo root with LNK_LOAD=loadall, the environment
# recompute_one runs each job in, so the stamp it compares against is the one
# the recompute would write.
#
# Usage: Rscript data-raw/recompute_readers_check.R <config> <schema> <run_uid>
#          <deps.tsv> <run_wsgs.tsv or -> <rebuilt csv> <missing csv> <out.tsv>
#
#   deps.tsv      recompute_deps.R's map (line rows read)
#   run_wsgs.tsv  the run's <TS>_run_wsgs.tsv (every row, SKIPs included, is
#                 the run's), or - when there is none
#   rebuilt       the run's groups whose rows it wrote or tried to (RUN_WSGS)
#   missing       those of them coverage did not find finished (COV_MISSING)
#   out.tsv       wsg, class (recompute | refused | waiting), reason, reads
#
# The run is the rebuilt groups, every row of run_wsgs.tsv and every group
# with a log row of the run_uid; a group in it is never a reader. Writes
# out.tsv whole (tmp + rename) and exits 0; on any unknown input exits 1 and
# writes nothing, which the caller treats as "readers not checked".

source("data-raw/recompute_readers.R")
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 8L) {
  stop("usage: recompute_readers_check.R <config> <schema> <run_uid> <deps.tsv> ",
    "<run_wsgs.tsv|-> <rebuilt csv> <missing csv> <out.tsv>",
    call. = FALSE
  )
}
config <- args[1]
schema <- args[2]
run_uid <- args[3]
deps_f <- args[4]
wsgs_f <- args[5]
csv <- function(x) {
  v <- strsplit(x, ",", fixed = TRUE)[[1]]
  v[nzchar(v)]
}
rebuilt <- csv(args[6])
missing <- csv(args[7])
out <- args[8]
if (!grepl("^[a-z_][a-z0-9_]*$", schema)) stop("schema '", schema, "' is not a plain name", call. = FALSE)
if (!nzchar(run_uid)) stop("run_uid is empty", call. = FALSE)
if (!all(missing %in% rebuilt)) stop("a missing group is not a rebuilt one", call. = FALSE)

read_tsv <- function(f) {
  utils::read.delim(f,
    colClasses = "character", quote = "", na.strings = character(),
    comment.char = ""
  )
}
deps <- read_tsv(deps_f)
if (!identical(names(deps), c("wsg", "rule", "dep")) || !any(deps$rule == "line")) {
  stop(deps_f, " is not a dependency map with line rows", call. = FALSE)
}
in_tsv <- character()
if (wsgs_f != "-") {
  w <- read_tsv(wsgs_f)
  if (!all(c("wsg", "host", "skip", "run_uid") %in% names(w)) || any(w$run_uid != run_uid)) {
    stop(wsgs_f, " is not this run's group list", call. = FALSE)
  }
  in_tsv <- w$wsg
}

cfg <- lnk_config(config)
cfg$pipeline$schema <- schema
conn <- lnk_db_conn(
  dbname = "fwapg", host = "localhost", port = 5432L,
  user = "postgres", password = "postgres"
)
q <- function(sql) DBI::dbGetQuery(conn, sql)
uid <- DBI::dbQuoteLiteral(conn, run_uid)
held <- q(sprintf("SELECT DISTINCT watershed_group_code AS wsg FROM %s.streams", schema))$wsg
in_log <- q(sprintf(
  "SELECT DISTINCT watershed_group_code AS wsg FROM %s.log WHERE run_uid = %s", schema, uid
))$wsg
run <- sort(unique(c(rebuilt, in_tsv, in_log)))
readers <- readers_outside(deps, run = run, rebuilt = rebuilt, held = held)

write_out <- function(tab) {
  tmp <- paste0(out, ".tmp")
  utils::write.table(tab, tmp, sep = "\t", quote = FALSE, row.names = FALSE, na = "")
  if (!file.rename(tmp, out)) stop("could not write ", out, call. = FALSE)
  n <- table(factor(tab$class, levels = c("recompute", "refused", "waiting")))
  message(sprintf(
    "[recompute_readers] %d outside reader(s) in %s: %d recompute, %d refused, %d waiting",
    nrow(tab), schema, n[["recompute"]], n[["refused"]], n[["waiting"]]
  ))
}

if (nrow(readers) == 0L) {
  write_out(readers_classify(readers, missing, data.frame(
    wsg = character(), has_log = logical(), open = logical(), config_hash = character(),
    fresh_sha = character(), fwapg_sha = character(), link_dirty = logical(),
    fresh_dirty = logical(), link_sha = character(), path_changed = integer(),
    downstream = character()
  ), list(config_hash = "", fresh_sha = "", fwapg_sha = "")))
  quit(status = 0L)
}

# What the recompute would stamp now.
st <- lnk_stamp(cfg, db_snapshot = FALSE)
na_chr <- function(x) if (is.null(x) || length(x) != 1L || is.na(x)) "" else as.character(x)
expect <- list(
  config_hash = na_chr(st$config_hash),
  fresh_sha = na_chr(st$software$fresh$git_sha),
  fwapg_sha = na_chr(st$fwapg_sha)
)

git <- function(...) {
  suppressWarnings(system2("git", c(...), stdout = TRUE, stderr = FALSE))
}
refuse_all <- character()
# The recompute runs the working tree under load_all, so a file not yet
# committed on its path is something no reader's sha describes.
dirty <- git("status", "--porcelain", "--untracked-files=all", "--", READERS_PATHS)
if (!is.null(attr(dirty, "status")) || length(dirty)) refuse_all <- c(refuse_all, "dispatcher_tree_dirty")
# The run's own groups were built under the hash a reader is compared with.
run_hash <- q(sprintf(
  "SELECT DISTINCT ON (watershed_group_code) config_hash FROM %s.log
    WHERE run_uid = %s AND date_end IS NOT NULL
    ORDER BY watershed_group_code, date_start DESC", schema, uid
))$config_hash
if (length(run_hash) == 0L || any(is.na(run_hash) | run_hash != expect$config_hash)) {
  refuse_all <- c(refuse_all, "config_changed_since_run")
}

wl <- paste(DBI::dbQuoteLiteral(conn, readers$wsg), collapse = ", ")
last <- q(sprintf(
  "SELECT DISTINCT ON (watershed_group_code) watershed_group_code AS wsg,
          date_end IS NULL AS open, config_hash, fresh_sha, fwapg_sha,
          link_dirty, fresh_dirty, link_sha
     FROM %s.log WHERE watershed_group_code IN (%s)
    ORDER BY watershed_group_code, date_start DESC", schema, wl
))
changed <- function(sha) {
  if (is.na(sha) || !grepl("^[0-9a-f]{7,40}$", sha)) {
    return(NA_integer_)
  }
  ok <- git("cat-file", "-e", paste0(sha, "^{commit}"))
  if (!is.null(attr(ok, "status"))) {
    return(NA_integer_)
  }
  d <- git("diff", "--name-only", sha, "--", READERS_PATHS)
  if (!is.null(attr(d, "status"))) {
    return(NA_integer_)
  }
  length(d)
}
shas <- unique(last$link_sha)
pc <- stats::setNames(vapply(shas, changed, integer(1)), shas)
facts <- data.frame(
  wsg = last$wsg, has_log = TRUE, open = last$open, config_hash = last$config_hash,
  fresh_sha = last$fresh_sha, fwapg_sha = last$fwapg_sha, link_dirty = last$link_dirty,
  fresh_dirty = last$fresh_dirty, link_sha = last$link_sha,
  path_changed = unname(pc[last$link_sha]), downstream = "pass"
)

tab <- readers_classify(readers, missing, facts, expect, refuse_all)
# The error-mode downstream check the recompute ends with fails after the group
# has been rewritten; ask it first, only of readers that would otherwise run.
go <- tab$wsg[tab$class == "recompute"]
if (length(go)) {
  loaded <- lnk_load_overrides(cfg)
  for (g in go) {
    s <- tryCatch(
      suppressWarnings(lnk_wsg_downstream_check(conn,
        aoi = g, cfg = cfg, loaded = loaded,
        on_fail = "warn"
      ))$status,
      error = function(e) NA_character_
    )
    facts$downstream[facts$wsg == g] <- if (identical(s, "pass")) "pass" else NA_character_
  }
  tab <- readers_classify(readers, missing, facts, expect, refuse_all)
}
DBI::dbDisconnect(conn)
write_out(tab)
