#!/usr/bin/env Rscript
# rerun.R — one instrumented post-consolidate recompute of a group, timed step
# by step. Copied from data-raw/logs/recompute_cost_261/rerun.R for link#409:
# the same recompute run under fresh v0.44.0 and v0.46.0 (fresh#272's walk
# prefilter). Changes from the original: outputs carry a run label and the
# loaded fresh's version and RemoteSha, other active client backends are
# sampled at start and end, and the backup schema is zz409_backup.
#
# Runs what wsg_recompute_one.R runs (prior-access copy, lnk_access(merge =
# TRUE), lnk_habitat_gate(), the mapping-code persist, the downstream guard),
# with each step timed, and the walks inside lnk_access() timed by wrapping
# lnk_pipeline_access() and fresh::frs_network_features(). It writes no log row.
#
# It WRITES the group's rows, so it is guarded: run it from a worktree at the
# commit that produced the rows (log_recompute.link_sha), on unchanged inputs,
# where a recompute reproduces them. It digests every table it writes before
# and after, backs the rows up first into schema zz409_backup, and stops with
# the restore statement if any digest moves. Backups are dropped only when every
# digest matches.
#
# Usage, from the worktree root:
#   LNK_MEASURE_HOST=<host> [R_LIBS=<lib holding the other fresh>] \
#     Rscript <path>/rerun.R <WSG> <out_dir> <label>

suppressPackageStartupMessages({
  pkgload::load_all(quiet = TRUE)
  library(DBI)
})

args <- commandArgs(trailingOnly = TRUE)
wsg <- toupper(args[1])
out_dir <- args[2]
label <- args[3]
stopifnot(grepl("^[A-Z]{3,5}$", wsg), dir.exists(out_dir),
          !is.na(label), grepl("^[a-z0-9_]+$", label))
fresh_v <- as.character(utils::packageVersion("fresh"))
fresh_sha <- utils::packageDescription("fresh")$RemoteSha
cat(sprintf("[rerun] %s %s: fresh %s (%s) from %s\n", wsg, label, fresh_v,
            fresh_sha, find.package("fresh")))
sch <- "fresh_default"
conn <- lnk_db_conn(dbname = "fwapg", host = Sys.getenv("LNK_MEASURE_HOST", "localhost"),
                    port = 5432L, user = "postgres", password = "postgres")
DBI::dbExecute(conn, "SET statement_timeout = '1800000'")
DBI::dbExecute(conn, "SET lock_timeout = '60000'")

busy <- DBI::dbGetQuery(conn,
  "SELECT count(*)::int AS n FROM pg_stat_activity
   WHERE datname = current_database() AND state <> 'idle'
     AND pid <> pg_backend_pid() AND backend_type = 'client backend'")$n
# A write needs nobody else in the schema; timing tolerates one other backend
# (walk_prefilter.R gives the measurement).
locked <- DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*)::int AS n FROM pg_locks l
   JOIN pg_class c ON c.oid = l.relation
   JOIN pg_namespace s ON s.oid = c.relnamespace
   WHERE s.nspname = '%s' AND l.pid <> pg_backend_pid()", sch))$n
if (locked > 0L) stop("REFUSE: another backend holds ", locked, " lock(s) in ", sch, call. = FALSE)
if (busy > 1L) stop("REFUSE: ", busy, " other active client backends", call. = FALSE)
busy_start <- busy

head_sha <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE)
run_sha <- DBI::dbGetQuery(conn, sprintf(
  "SELECT link_sha FROM %s.log_recompute WHERE watershed_group_code = %s
   ORDER BY date_start DESC LIMIT 1", sch, DBI::dbQuoteLiteral(conn, wsg)))$link_sha
if (!identical(head_sha, run_sha)) {
  stop("REFUSE: HEAD ", head_sha, " is not the commit that wrote ", wsg,
       "'s rows (", run_sha, ")", call. = FALSE)
}

cfg <- lnk_config("default")
cfg$pipeline$schema <- sch
loaded <- lnk_load_overrides(cfg)
active <- lnk_pipeline_species(cfg, loaded, wsg)
pres <- lnk_presence(loaded$wsg_species_presence, wsg)

tables <- c("streams_access", "streams_mapping_code",
            paste0("streams_habitat_", tolower(active)))
digest <- function() {
  vapply(tables, function(t) DBI::dbGetQuery(conn, sprintf(
    "SELECT md5(coalesce(string_agg(x::text, '|' ORDER BY x.id_segment), ''))
       AS d, count(*)::int AS n
     FROM %s.%s x WHERE watershed_group_code = %s",
    sch, t, DBI::dbQuoteLiteral(conn, wsg)))$d, character(1))
}

# A backup left by an earlier run (digest moved, or an error mid-run) holds the
# only copy of the original rows; backing up again would overwrite it. Added
# after the 2026-10-27 runs (the lock check above was in place for them).
left <- vapply(tables, function(t) !is.na(DBI::dbGetQuery(conn, sprintf(
  "SELECT to_regclass('zz409_backup.%s_%s')::text AS r", t, tolower(wsg)))$r), logical(1))
if (any(left)) {
  stop("REFUSE: backup(s) from an earlier run still exist for ", wsg, ": ",
       paste(tables[left], collapse = ", "), "; restore or drop them first", call. = FALSE)
}
d0 <- digest()
DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS zz409_backup")
for (t in tables) {
  bk <- sprintf("zz409_backup.%s_%s", t, tolower(wsg))
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", bk))
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s AS SELECT * FROM %s.%s WHERE watershed_group_code = %s",
    bk, sch, t, DBI::dbQuoteLiteral(conn, wsg)))
}

# Time the walks inside lnk_access() without editing it.
walk_t <- list()
ns_f <- asNamespace("fresh")
orig_nf <- ns_f$frs_network_features
timed_nf <- function(conn, segments, features, ...) {
  t <- system.time(r <- orig_nf(conn, segments, features, ...))[["elapsed"]]
  walk_t[[length(walk_t) + 1L]] <<- data.frame(
    table = sub("^[^.]+\\.", "", features), s = t, rows = nrow(r),
    elements = sum(lengths(r[[2]])))
  r
}
utils::assignInNamespace("frs_network_features", timed_nf, "fresh")
pa_t <- NA_real_
ns_l <- asNamespace("link")
orig_pa <- ns_l$lnk_pipeline_access
timed_pa <- function(...) {
  pa_t <<- system.time(r <- orig_pa(...))[["elapsed"]]
  invisible(r)
}
utils::assignInNamespace("lnk_pipeline_access", timed_pa, "link")

step <- function(name, expr) {
  t <- system.time(force(expr))[["elapsed"]]
  data.frame(step = name, s = t)
}
gate_overlay <- utils::getFromNamespace(".lnk_habitat_gate_overlay", "link")
mc_persist <- utils::getFromNamespace(".lnk_mapping_code_persist", "link")
prior <- sprintf("%s.zz_lnk_access_prior_%s", sch, tolower(wsg))

t_all <- system.time({
  s <- rbind(
    step("prior_copy", {
      DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", prior))
      DBI::dbExecute(conn, sprintf(
        "CREATE TABLE %s AS SELECT id_segment, watershed_group_code, %s
         FROM %s.streams_access WHERE watershed_group_code = %s",
        prior, paste0("access_", tolower(active), collapse = ", "), sch,
        DBI::dbQuoteLiteral(conn, wsg)))
    }),
    step("lnk_access", lnk_access(conn, cfg, aoi = wsg,
      table_streams = paste0(sch, ".streams"),
      table_barriers = paste0(sch, ".barriers"),
      table_to = paste0(sch, ".streams_access"),
      merge = TRUE, presence = pres, species = active, build_views = FALSE)),
    step("habitat_gate", lnk_habitat_gate(conn, aoi = wsg,
      table_habitat = paste0(sch, ".streams_habitat"),
      table_access = paste0(sch, ".streams_access"),
      table_streams = paste0(sch, ".streams"),
      species = active, overlay = gate_overlay(cfg, loaded),
      table_access_prior = prior)),
    step("mapping_code", mc_persist(conn, schema = sch, aoi = wsg,
      species = active, presence = pres)),
    step("downstream_guard", lnk_wsg_downstream_check(conn, aoi = wsg,
      cfg = cfg, loaded = loaded, on_fail = "error")))
})[["elapsed"]]
DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", prior))

walks <- do.call(rbind, walk_t)
s <- rbind(s,
  data.frame(step = "lnk_access:walks", s = sum(walks$s)),
  data.frame(step = "lnk_access:pipeline_access_other", s = pa_t - sum(walks$s)),
  data.frame(step = "lnk_access:setup_and_update", s = s$s[s$step == "lnk_access"] - pa_t),
  data.frame(step = "total", s = t_all))
busy_end <- DBI::dbGetQuery(conn,
  "SELECT count(*)::int AS n FROM pg_stat_activity
   WHERE datname = current_database() AND state <> 'idle'
     AND pid <> pg_backend_pid() AND backend_type = 'client backend'")$n
stamp <- function(d) {
  d$wsg <- wsg
  d$label <- label
  d$fresh <- fresh_v
  d$fresh_sha <- fresh_sha
  d$others_start <- busy_start
  d$others_end <- busy_end
  d$utc_end <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  d
}
s <- stamp(s)
walks <- stamp(walks)
utils::write.table(s, file.path(out_dir, sprintf("steps_%s_%s.tsv", wsg, label)),
                   sep = "\t", row.names = FALSE, quote = FALSE)
utils::write.table(walks, file.path(out_dir, sprintf("walks_%s_%s.tsv", wsg, label)),
                   sep = "\t", row.names = FALSE, quote = FALSE)

d1 <- digest()
dg <- data.frame(wsg = wsg, label = label, fresh = fresh_v, table = tables,
                 before = d0, after = d1, same = d0 == d1)
utils::write.table(dg, file.path(out_dir, sprintf("digest_%s_%s.tsv", wsg, label)),
                   sep = "\t", row.names = FALSE, quote = FALSE)
print(s)
if (!all(dg$same)) {
  cat("DIGEST MOVED for:", paste(dg$table[!dg$same], collapse = ", "), "\n")
  for (t in dg$table[!dg$same]) {
    cat(sprintf("restore: BEGIN; DELETE FROM %1$s.%2$s WHERE watershed_group_code = '%3$s'; INSERT INTO %1$s.%2$s SELECT * FROM zz409_backup.%2$s_%4$s; COMMIT;\n",
                sch, t, wsg, tolower(wsg)))
  }
  quit(status = 1)
}
for (t in tables) {
  DBI::dbExecute(conn, sprintf("DROP TABLE zz409_backup.%s_%s", t, tolower(wsg)))
}
cat(sprintf("[rerun] %s %s (fresh %s) digests UNCHANGED across %d tables; total %.1f s\n",
            wsg, label, fresh_v, length(tables), t_all))
