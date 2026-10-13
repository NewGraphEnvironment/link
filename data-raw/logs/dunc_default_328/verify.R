#!/usr/bin/env Rscript
# verify.R — checks the DUNC build in fresh_default against link#328's "Done when".
# Read-only. Usage: Rscript data-raw/logs/dunc_default_328/verify.R
suppressPackageStartupMessages({
  pkgload::load_all(quiet = TRUE)
  library(DBI)
})
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
q <- function(sql) DBI::dbGetQuery(conn, sql)
w <- "DUNC"
build_sha <- "8215d2d072f21c6c915612234b41ef3e47da747e"  # the commit the run was made from
sp <- c("bt", "wct", "rb")
fail <- character(0)
check <- function(ok, msg) {
  cat(sprintf("[%s] %s\n", if (isTRUE(ok)) "PASS" else "FAIL", msg))
  if (!isTRUE(ok)) fail <<- c(fail, msg)
}

cat("== stamp\n")
cat("date_utc:", format(Sys.time(), tz = "UTC", usetz = TRUE), "\n")
cat("link HEAD:", system("git rev-parse HEAD", intern = TRUE), "\n")
cat("fresh:", as.character(packageVersion("fresh")),
    packageDescription("fresh")$RemoteSha, "\n")

cat("\n== log row\n")
lg <- q(sprintf("SELECT run_id, run_uid, run_label, config_name, config_hash,
  config_drift, link_version, link_sha, link_dirty, fresh_version, fresh_sha,
  fwapg_sha, schema_persist, species, arg_dams, arg_mapping_code,
  date_start, date_end
  FROM fresh_default.log WHERE watershed_group_code = '%s'
  ORDER BY date_start DESC", w))
print(t(lg[1, , drop = FALSE]))
check(nrow(lg) == 1L, "exactly one fresh_default.log row for DUNC")
check(identical(lg$config_name[1], "default"), "config_name = default")
check(!is.na(lg$date_end[1]), "run closed (date_end set)")
check(isFALSE(lg$link_dirty[1]), "link_dirty = f")
check(identical(lg$link_sha[1], build_sha), "link_sha = the build commit")
check(identical(lg$schema_persist[1], "fresh_default"), "schema_persist = fresh_default")
check(!is.na(lg$config_hash[1]) && !is.na(lg$fwapg_sha[1]),
      "config_hash and fwapg_sha recorded")

cat("\n== FWA inputs: DUNC against KOTL (fwapg_sha is the fwapg checkout, not the data)\n")
fwa <- q(sprintf("SELECT i.table_name, l.watershed_group_code wsg, i.row_count, i.size_bytes
  FROM fresh_default.log_input i JOIN fresh_default.log l USING (run_id)
  WHERE l.watershed_group_code IN ('KOTL', '%s') AND i.table_name LIKE 'whse_basemapping.fwa_%%'", w))
both <- merge(fwa[fwa$wsg == "KOTL", -2], fwa[fwa$wsg == w, -2], by = "table_name",
              suffixes = c("_kotl", "_dunc"))
print(both, row.names = FALSE)
check(nrow(both) > 0 && identical(both$row_count_kotl, both$row_count_dunc) &&
        identical(both$size_bytes_kotl, both$size_bytes_dunc),
      sprintf("%d FWA tables logged for both carry the same fingerprint", nrow(both)))

cat("\n== nothing written to fresh\n")
fr <- q(sprintf("SELECT count(*)::int n FROM fresh.log WHERE watershed_group_code = '%s'", w))$n
check(fr == 0, "no DUNC row added to fresh.log")

cat("\n== streams\n")
km <- function(tbl) q(sprintf(
  "SELECT count(*)::int n, round(sum(length_metre) FILTER (WHERE stream_order >= 2)::numeric / 1000, 1) km2
   FROM %s WHERE watershed_group_code = '%s'", tbl, w))
fd <- km("fresh_default.streams"); fs <- km("fresh.streams")
fwa_km <- km("whse_basemapping.fwa_stream_networks_sp")
cat(sprintf("fresh_default: %d segments, %.1f km order>=2\nfresh:         %d segments, %.1f km order>=2\nFWA:           %d lines,    %.1f km order>=2\n",
            fd$n, fd$km2, fs$n, fs$km2, fwa_km$n, fwa_km$km2))
check(fd$n > 0, "fresh_default.streams holds DUNC")
check(abs(fd$km2 - fwa_km$km2) < 1 && abs(fd$km2 - fs$km2) < 1,
      "order>=2 km matches raw FWA and fresh.streams to the km")

cat("\n== habitat, access, mapping_code (full-PK joins)\n")
for (s in sp) {
  n <- q(sprintf("SELECT count(h.*)::int n FROM fresh_default.streams s
    JOIN fresh_default.streams_habitat_%s h
      ON h.id_segment = s.id_segment AND h.watershed_group_code = s.watershed_group_code
    WHERE s.watershed_group_code = '%s'", s, w))$n
  check(n == fd$n, sprintf("streams_habitat_%s: %d of %d segments", s, n, fd$n))
}
for (s in sp) {
  fl <- q(sprintf("SELECT count(*) FILTER (WHERE spawning)::int spawn,
    count(*) FILTER (WHERE rearing)::int rear, count(*) FILTER (WHERE accessible)::int acc
    FROM fresh_default.streams_habitat_%s WHERE watershed_group_code = '%s'", s, w))
  cat(sprintf("%s segments: %d spawning, %d rearing, %d accessible\n", toupper(s), fl$spawn, fl$rear, fl$acc))
  check(fl$acc > 0 && (fl$spawn + fl$rear) > 0, sprintf("streams_habitat_%s carries non-zero flags", s))
}
for (tb in c("streams_access", "streams_mapping_code")) {
  n <- q(sprintf("SELECT count(*)::int n FROM fresh_default.%s t
    JOIN fresh_default.streams s
      ON s.id_segment = t.id_segment AND s.watershed_group_code = '%s'
    WHERE t.watershed_group_code = '%s'", tb, w, w))$n
  check(n == fd$n, sprintf("%s: %d of %d segments", tb, n, fd$n))
}

cat("\n== context, not parity: link default against the bcfishpass reference view\n")
cat("   (default differs from bcfishpass by design; the view has no rb columns)\n")
lk <- lnk_rollup_wsg(conn, aoi = w, species = sp, schema = "fresh_default")
lake_conn <- .lnk_sql_lake_connection()
wb_join <- .lnk_sql_waterbody_join()
bc_sp <- c("bt", "wct")   # the view carries no rb columns
cols <- unlist(lapply(bc_sp, function(s) sprintf(
  "round((coalesce(sum(length_metre) FILTER (WHERE access_%1$s IN (1,2)),0)/1000)::numeric,1) acc_%1$s,
   round((coalesce(sum(length_metre) FILTER (WHERE spawning_%1$s IN (1,2)),0)/1000)::numeric,1) spawn_%1$s,
   round((coalesce(sum(length_metre) FILTER (WHERE rearing_%1$s IN (1,2) AND NOT %2$s),0)/1000)::numeric,1) rear_%1$s",
  s, lake_conn)))
bc <- q(sprintf("SELECT %s FROM fresh.streams_vw_bcfp s %s WHERE s.watershed_group_code = '%s'",
                paste(cols, collapse = ", "), wb_join, w))
rows <- list()
for (s in bc_sp) {
  r <- lk[lk$species == toupper(s), ]
  prefix <- c(accessible = "acc_", spawning = "spawn_", rearing = "rear_")
  for (m in names(prefix)) {
    lkv <- as.numeric(r[[paste0(m, "_km")]])
    bcv <- as.numeric(bc[[paste0(prefix[[m]], s)]])
    rows[[length(rows) + 1L]] <- data.frame(
      species = toupper(s), metric = m, link_default = lkv,
      bcfishpass = bcv, diff_pct = round(100 * (lkv - bcv) / bcv, 1))
  }
}
par <- do.call(rbind, rows)
print(par, row.names = FALSE)
cat("\nlink default, all species:\n")
print(as.data.frame(lk), row.names = FALSE)

DBI::dbDisconnect(conn)
cat(sprintf("\n== %d check(s) failed\n", length(fail)))
if (length(fail)) quit(status = 1)
