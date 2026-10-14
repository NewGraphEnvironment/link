#!/usr/bin/env Rscript
# verify.R — pilot check of the habitat export (link#308).
#
# Loads a built tree into local fwapg (habitat.fwa_v1_segment) and compares
# km per config x species x group with lnk_rollup_wsg() on the persist schema
# it came from: an independent query of the same build. Writes verify.csv and
# verify.txt beside this script.
#
#   Rscript data-raw/logs/habitat_export_308/verify.R <root> [--reuse-csv]
#
# --reuse-csv summarises an existing verify.csv (the rollup pass takes over an
# hour on the full `fresh` schema) against the table already loaded.

suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
args <- commandArgs(trailingOnly = TRUE)
root <- args[1]
out <- "data-raw/logs/habitat_export_308"
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")

reuse <- "--reuse-csv" %in% args && file.exists(file.path(out, "verify.csv"))
cat <- lnk_catalog(file.path(root, "manifest.json"))
t_load <- NA
if (!reuse) {
  t0 <- Sys.time()
  lnk_db_load(conn, cat, cache_dir = tempfile())
  t_load <- difftime(Sys.time(), t0, units = "secs")
}

if (reuse) {
  v <- utils::read.csv(file.path(out, "verify.csv"))
} else {
ex <- DBI::dbGetQuery(conn, "
  SELECT config, species, watershed_group_code AS wsg, count(*) AS n,
         round(sum(length_metre) FILTER (WHERE spawning)::numeric / 1000, 2)
           AS spawning_km,
         round(sum(length_metre) FILTER (WHERE rearing)::numeric / 1000, 2)
           AS rearing_flag_km,
         round(sum(length_metre) FILTER (WHERE accessible)::numeric / 1000, 2)
           AS accessible_flag_km,
         round(sum(length_metre) FILTER (WHERE has_barriers_dnstr IS FALSE)
               ::numeric / 1000, 2) AS no_barrier_dnstr_km,
         count(*) FILTER (WHERE accessible AND has_barriers_dnstr)
           AS n_accessible_but_barrier
    FROM habitat.fwa_v1_segment GROUP BY 1, 2, 3 ORDER BY 1, 2, 3")

# the schema each group's build was persisted to, from its run row
schema_of <- do.call(rbind, lapply(attr(cat, "configs"), function(x) {
  do.call(rbind, lapply(x$runs, function(r) {
    data.frame(config = x$config, wsg = r$watershed_group_code,
               schema = r$schema_persist)
  }))
}))
ref <- do.call(rbind, lapply(seq_len(nrow(ex)), function(i) {
  sch <- schema_of$schema[schema_of$config == ex$config[i] &
                            schema_of$wsg == ex$wsg[i]]
  r <- lnk_rollup_wsg(conn, aoi = ex$wsg[i], species = ex$species[i],
                      schema = sch)
  data.frame(rollup_spawning_km = r$spawning_km,
             rollup_rearing_km = r$rearing_km + r$rearing_lake_connection_km,
             rollup_accessible_km = r$accessible_km)
}))
v <- cbind(ex, ref)
v$spawning_diff <- v$spawning_km - v$rollup_spawning_km
v$rearing_diff <- v$rearing_flag_km - v$rollup_rearing_km
utils::write.csv(v, file.path(out, "verify.csv"), row.names = FALSE)

}
dup <- DBI::dbGetQuery(conn, "
  SELECT count(*) - count(DISTINCT (config, species, blue_line_key,
                                    downstream_route_measure)) AS d
    FROM habitat.fwa_v1_segment")$d
off <- function(a, b) {
  sum(xor(is.na(a), is.na(b)) | (!is.na(a) & !is.na(b) & abs(a - b) > 0.011))
}
lines <- c(
  sprintf("link %s @ %s", utils::packageVersion("link"),
          .lnk_pkg_git_sha("link")),
  sprintf("manifest %s built %s: %d parts, %s rows, %.1f MB",
          attr(cat, "manifest"), attr(cat, "built"), nrow(cat),
          format(sum(cat$rows), big.mark = ","), sum(cat$bytes) / 1e6),
  sprintf("load: %s; duplicate keys: %s",
          if (is.na(t_load)) "not re-run (--reuse-csv)" else
            sprintf("%.0f s", as.numeric(t_load)), dup),
  sprintf("config x species x group rows compared: %d", nrow(v)),
  # the rollup rounds rearing and connection km separately, then adds:
  # up to 0.01 km apart from rounding alone
  # NA on both sides is no habitat on both sides: agreement
  sprintf("spawning km beyond rounding of lnk_rollup_wsg: %d of %d (max |diff| %.2f)",
          off(v$spawning_km, v$rollup_spawning_km), nrow(v),
          max(abs(v$spawning_diff), 0, na.rm = TRUE)),
  sprintf("rearing flag km beyond rounding of lnk_rollup_wsg: %d of %d (max |diff| %.2f)",
          off(v$rearing_flag_km, v$rollup_rearing_km), nrow(v),
          max(abs(v$rearing_diff), 0, na.rm = TRUE)),
  sprintf("km with no barrier downstream vs rollup accessible_km (access 1/2) beyond rounding: %d of %d",
          off(v$no_barrier_dnstr_km, v$rollup_accessible_km), nrow(v)),
  sprintf("groups x species with segments flagged accessible and a barrier downstream in streams_access (#336): %s (%s segments, %.1f km of accessible flag over rollup)",
          sum(v$n_accessible_but_barrier > 0),
          format(sum(v$n_accessible_but_barrier), big.mark = ","),
          sum(v$accessible_flag_km - v$rollup_accessible_km, na.rm = TRUE)))
writeLines(lines, file.path(out, "verify.txt"))
writeLines(lines)
