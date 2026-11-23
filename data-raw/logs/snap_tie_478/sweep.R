# link#383's sweep: link's own FWA_LocateAlong calls, before and after
# fwapg#41's rework, without migrating the database (link#478, Phase 1).
#
#   Rscript data-raw/logs/snap_tie_478/sweep.R <migration file> [<migration file> ...]
#
# Runs on the local docker fwapg only. The "before" pass reads committed state
# on its own connection; the "after" pass applies the migration files inside a
# transaction that fresh::frs_migration_trial() rolls back when the pass
# returns, on a second connection. Every call runs under its own SAVEPOINT with
# a statement timeout, so one error is counted and does not abort the rest.
#
# Inputs, each a (blue_line_key, measure) to locate:
#   pscis    every PSCIS pick of the branch's snap (zz478_after.pscis_picked,
#            from snap_pick.R), at its whole-metre measure;
#   barriers fresh_default.barriers (what lnk_barriers_unify() located): every
#            row at or above its blue line's top, plus a fixed sample of 20,000;
#   obs_top  data-raw/query_habitat_thresholds_obs.R's upper locate: a record
#            within 100 m of its blue line's top is located at that top.
#
# Counted per input: positions where FWA_LocateAlong returns no point (the
# first arm of .lnk_sql_locate(), which its COALESCE fallback hides), and
# calls that error. Ties at the snap are counted by snap_pick.R. Writes
# sweep.csv beside this script.

args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) >= 1L, all(file.exists(args)))
files <- normalizePath(args)
out <- "data-raw/logs/snap_tie_478"

connect <- function() {
  DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                 port = 5432L, user = "postgres", password = "postgres")
}

inputs <- function(conn) {
  q <- function(sql) DBI::dbGetQuery(conn, sql)
  list(
    pscis = q("SELECT blue_line_key AS blk, downstream_route_measure::float8 AS m
               FROM zz478_after.pscis_picked"),
    barriers = q("
      WITH b AS (SELECT DISTINCT blue_line_key, downstream_route_measure
                 FROM fresh_default.barriers),
      tops AS (SELECT blue_line_key, max(upstream_route_measure) AS top
               FROM whse_basemapping.fwa_stream_networks_sp
               WHERE blue_line_key IN (SELECT blue_line_key FROM b)
               GROUP BY 1),
      at_top AS (SELECT b.* FROM b JOIN tops USING (blue_line_key)
                 WHERE round(b.downstream_route_measure::numeric, 4)
                       >= round(tops.top::numeric, 4)),
      smp AS (SELECT * FROM b
              ORDER BY md5(blue_line_key::text || ':' || downstream_route_measure::text)
              LIMIT 20000)
      SELECT blue_line_key AS blk, downstream_route_measure AS m, true AS at_top FROM at_top
      UNION
      SELECT blue_line_key, downstream_route_measure, false FROM smp"),
    obs_top = q("
      WITH tops AS (SELECT blue_line_key, max(upstream_route_measure) AS top
                    FROM whse_basemapping.fwa_stream_networks_sp GROUP BY 1)
      SELECT DISTINCT o.blue_line_key AS blk, t.top AS m
      FROM bcfishobs.observations o JOIN tops t USING (blue_line_key)
      WHERE o.downstream_route_measure + 100 >= t.top")
  )
}

# One locate per row under a savepoint; NA = no point, -1 = error.
locate <- function(conn, d) {
  DBI::dbExecute(conn, "SET LOCAL statement_timeout = '10s'")
  vapply(seq_len(nrow(d)), function(i) {
    DBI::dbExecute(conn, "SAVEPOINT s")
    r <- tryCatch(
      DBI::dbGetQuery(conn, sprintf(
        "SELECT count(*)::int AS n FROM whse_basemapping.fwa_locatealong(%d, %s)",
        as.integer(d$blk[i]), sprintf("%.17g", d$m[i])))$n,
      error = function(e) -1L)
    DBI::dbExecute(conn, if (r < 0L) "ROLLBACK TO SAVEPOINT s" else "RELEASE SAVEPOINT s")
    r
  }, integer(1))
}

pass <- function(label, ins, trial = FALSE) {
  conn <- connect()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  if (trial) fresh::frs_migration_trial(conn, files) else DBI::dbBegin(conn)
  if (!trial) on.exit(DBI::dbRollback(conn), add = TRUE, after = FALSE)
  locatealong_src <- DBI::dbGetQuery(conn, "
    SELECT md5(prosrc) AS h FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'whse_basemapping' AND p.proname = 'fwa_locatealong'")$h
  t0 <- Sys.time()
  res <- lapply(names(ins), function(k) {
    n <- locate(conn, ins[[k]])
    data.frame(pass = label, input = k, positions = nrow(ins[[k]]),
               no_point = sum(n == 0L), error = sum(n < 0L),
               no_point_at_top = if ("at_top" %in% names(ins[[k]]))
                 sum(n == 0L & ins[[k]]$at_top) else NA_integer_,
               locatealong_md5 = substr(locatealong_src, 1, 8))
  })
  message(sprintf("[sweep] %s pass in %.1f min", label,
                  as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  do.call(rbind, res)
}

conn0 <- connect()
ins <- inputs(conn0)
DBI::dbDisconnect(conn0)
message("[sweep] positions: ", paste(names(ins), vapply(ins, nrow, 1L), collapse = ", "))

res <- rbind(pass("before", ins), pass("after", ins, trial = TRUE))
fwapg_dir <- path.expand("~/Projects/repo/fwapg")
res$migrations <- paste(basename(files), collapse = " ")
res$migrations_md5 <- paste(substr(unname(tools::md5sum(files)), 1, 8), collapse = " ")
utils::write.csv(res, file.path(out, "sweep.csv"), row.names = FALSE)
print(res[, c("pass", "input", "positions", "no_point", "no_point_at_top", "error",
              "locatealong_md5")])
