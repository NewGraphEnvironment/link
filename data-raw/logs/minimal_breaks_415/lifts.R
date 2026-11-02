#!/usr/bin/env Rscript
# lifts.R — #415: how far observation lifts move the minimal network's cuts.
#
# The minimal network is not independent of the fish records: gradient positions
# are reduced after lifts, so a lifted barrier is no longer that species' cut and
# positions above it can become cuts. `barrier_overrides` holds observation,
# habitat-classification and control lifts with no source column, so the
# counterfactual is built, not filtered. For each group, its kept working tables
# are copied to a scratch schema, `barrier_overrides` is rebuilt with an empty
# observations table (the other lifts stay), and the pipeline's own
# .lnk_pipeline_prep_minimal(), .lnk_pipeline_prep_network() and lnk_pipeline_break()
# run on it under `default_minimal`. Classes, presence, paused species and orphans
# are the build's own, and no SQL is copied here.
#
# Controls, each of which stops the script:
#   1. The same steps with the build's own overrides reproduce the build: the same
#      minimal positions and the same segments.
#   2. In a species with no observation lift, the no-lift set equals the built set.
#
# Reads working_<wsg>, which run.sh leaves holding the minimal build, so run it
# after run.sh and before anything else rebuilds a group. Writes, beside this script:
#   lifts.csv      per group and species, then per group ("ALL"): observation lifts,
#                  cuts removed and added, how far each moved, km of segment changed
#   lifts_obs.csv  #433's measure (research/species_paused.md), for reading beside it:
#                  records of modelled species, how many sit on a changed segment,
#                  and the median and largest gradient shift there
# Usage: Rscript data-raw/logs/minimal_breaks_415/lifts.R --wsgs=BULK,SETN,...
args <- commandArgs(trailingOnly = TRUE)
hit <- grep("^--wsgs=", args, value = TRUE)
if (length(hit) != 1L) stop("usage: lifts.R --wsgs=<WSG>,<WSG>", call. = FALSE)
wsgs <- toupper(strsplit(sub("^--wsgs=", "", hit), ",")[[1]])
stopifnot(all(grepl("^[A-Z]{4}$", wsgs)))
file_arg <- grep("^--file=", commandArgs(), value = TRUE)
here <- dirname(normalizePath(sub("^--file=", "", file_arg)))
repo <- normalizePath(file.path(here, "..", "..", ".."))
suppressPackageStartupMessages({
  pkgload::load_all(repo, quiet = TRUE)
  library(DBI); library(RPostgres)
})
conn <- dbConnect(Postgres(), dbname = "fwapg", host = "localhost", port = 5432L,
                  user = "postgres", password = "postgres")
# count(*) arrives as integer64, which binding beside an NA strips to raw bits.
q <- function(sql, ...) {
  r <- dbGetQuery(conn, sprintf(sql, ...))
  r[] <- lapply(r, function(v) if (inherits(v, "integer64")) as.integer(v) else v)
  r
}
x <- function(sql, ...) invisible(dbExecute(conn, sprintf(sql, ...)))
modelled_obs <- c("BT", "CH", "CM", "CO", "PK", "SK", "ST", "WCT", "GR", "DV")
cfg <- lnk_config("default_minimal")
loaded <- lnk_load_overrides(cfg)
classes <- link:::.lnk_resolve_classes(NULL, cfg)

# Positions keyed to the millimetre: measures are raw doubles.
pos <- function(tbl) sprintf(
  "SELECT DISTINCT blue_line_key, round(downstream_route_measure::numeric, 3) AS m FROM %s", tbl)
only <- function(a, b) q("SELECT count(*) n FROM (%s EXCEPT %s) d", pos(a), pos(b))$n
seg_only <- function(a, b) q(
  "SELECT count(*) n FROM (
     SELECT blue_line_key, round(downstream_route_measure::numeric, 3), round(upstream_route_measure::numeric, 3) FROM %s
     EXCEPT
     SELECT blue_line_key, round(downstream_route_measure::numeric, 3), round(upstream_route_measure::numeric, 3) FROM %s) d",
  a, b)$n
rebuild_segments <- function(aoi, schema) {
  link:::.lnk_pipeline_prep_network(conn, aoi, schema, fill = link:::.lnk_discharge_fill_applied(cfg, aoi),
                                    source = link:::.lnk_discharge_source(cfg))
  lnk_pipeline_break(conn, aoi, cfg, loaded, schema)
}
# How far each cut one side holds lies from the nearest cut the other holds on its line.
moved <- function(a, b) q(
  "WITH o AS (%s EXCEPT %s),
        d AS (SELECT (SELECT min(abs(o.m - n.m)) FROM (%s) n WHERE n.blue_line_key = o.blue_line_key) AS dist FROM o)
   SELECT count(*) FILTER (WHERE dist IS NULL) AS none_on_line,
          percentile_cont(0.5) WITHIN GROUP (ORDER BY dist) AS median_m, max(dist) AS max_m FROM d",
  pos(a), pos(b), pos(b))

res <- list(); obs <- list()
for (w in wsgs) {
  t0 <- Sys.time()
  W <- paste0("working_", tolower(w))
  L <- paste0("zz415_lift_", tolower(w))
  n_w <- q("SELECT count(*) n FROM %s.streams", W)$n
  n_min <- q("SELECT count(*) n FROM zz415_minimal.streams WHERE watershed_group_code = '%s'", w)$n
  if (n_w != n_min) stop(W, " holds ", n_w, " segments, zz415_minimal ", n_min, ": not the minimal build", call. = FALSE)

  x("DROP SCHEMA IF EXISTS %s CASCADE", L)
  x("CREATE SCHEMA %s", L)
  tabs <- q("SELECT table_name t FROM information_schema.tables
              WHERE table_schema = '%s' AND table_type = 'BASE TABLE'", W)$t
  for (t in setdiff(tabs, c("streams", "streams_habitat", "streams_access", "streams_breaks"))) {
    x("CREATE TABLE %s.%s AS TABLE %s.%s", L, t, W, t)
  }

  # Control 1: the build's own overrides reproduce the build.
  link:::.lnk_pipeline_prep_minimal(conn, w, cfg, loaded, L, classes)
  for (dir in list(c(W, L), c(L, W))) {
    n <- only(paste0(dir[1], ".gradient_barriers_minimal"), paste0(dir[2], ".gradient_barriers_minimal"))
    if (n != 0L) stop(w, " control: ", n, " minimal positions in ", dir[1], " only", call. = FALSE)
  }
  rebuild_segments(w, L)
  for (dir in list(c(W, L), c(L, W))) {
    n <- seg_only(paste0(dir[1], ".streams"), paste0(dir[2], ".streams"))
    if (n != 0L) stop(w, " control: ", n, " segments in ", dir[1], " only", call. = FALSE)
  }

  # The counterfactual: no observation lifts; habitat-classification and control lifts stay.
  x("CREATE TABLE %s.overrides_built AS TABLE %s.barrier_overrides", L, L)
  x("DROP TABLE IF EXISTS %s.observations_province", L)
  x("CREATE TABLE %s.observations_province AS SELECT * FROM %s.observations LIMIT 0", L, W)
  link:::.lnk_pipeline_prep_overrides(conn, loaded, L)
  link:::.lnk_pipeline_prep_minimal(conn, w, cfg, loaded, L, classes)
  rebuild_segments(w, L)

  spp <- sub("^barriers_(.*)_min$", "\\1", q(
    "SELECT table_name t FROM information_schema.tables
      WHERE table_schema = '%s' AND table_name ~ '^barriers_.*_min$'", W)$t)
  row <- function(species, a, b, lifts) {
    gone <- moved(b, a); added <- moved(a, b)
    data.frame(wsg = w, species = species, obs_lifts = lifts,
               cuts_built = q("SELECT count(*) n FROM (%s) d", pos(a))$n,
               cuts_no_lift = q("SELECT count(*) n FROM (%s) d", pos(b))$n,
               cuts_removed_by_lifts = only(b, a), cuts_added_by_lifts = only(a, b),
               removed_nearest_median_m = gone$median_m, removed_nearest_max_m = gone$max_m,
               removed_none_on_line = gone$none_on_line,
               added_nearest_median_m = added$median_m, added_nearest_max_m = added$max_m,
               added_none_on_line = added$none_on_line)
  }
  lift_n <- function(sp) q(
    "SELECT count(*) n FROM (
       SELECT blue_line_key, round(downstream_route_measure::numeric, 3) FROM %1$s.overrides_built WHERE species_code = '%2$s'
       EXCEPT
       SELECT blue_line_key, round(downstream_route_measure::numeric, 3) FROM %1$s.barrier_overrides WHERE species_code = '%2$s') d",
    L, sp)$n
  lost <- q("SELECT count(*) n FROM (
               SELECT blue_line_key, species_code, round(downstream_route_measure::numeric, 3) FROM %1$s.barrier_overrides
               EXCEPT
               SELECT blue_line_key, species_code, round(downstream_route_measure::numeric, 3) FROM %1$s.overrides_built) d", L)$n
  if (lost != 0L) stop(w, ": ", lost, " no-lift overrides the build does not hold; removing records added lifts", call. = FALSE)

  per_sp <- do.call(rbind, lapply(spp, function(s) {
    n <- lift_n(toupper(s))
    r <- row(toupper(s), sprintf("%s.barriers_%s_min", W, s), sprintf("%s.barriers_%s_min", L, s), n)
    # Control 2.
    if (n == 0L && (r$cuts_removed_by_lifts != 0L || r$cuts_added_by_lifts != 0L)) {
      stop(w, " ", r$species, " control: no observation lift, but its cuts differ", call. = FALSE)
    }
    r
  }))
  all <- row("ALL", paste0(W, ".gradient_barriers_minimal"), paste0(L, ".gradient_barriers_minimal"), sum(per_sp$obs_lifts))
  km <- q(
    "WITH a AS (SELECT blue_line_key b, round(downstream_route_measure::numeric, 3) d, round(upstream_route_measure::numeric, 3) u, length_metre l FROM %1$s.streams),
          c AS (SELECT blue_line_key b, round(downstream_route_measure::numeric, 3) d, round(upstream_route_measure::numeric, 3) u, length_metre l FROM %2$s.streams)
     SELECT (SELECT count(*) FROM a)::int segments_built, (SELECT count(*) FROM c)::int segments_no_lift,
            (SELECT sum(l) FROM a) / 1000 km_total,
            (SELECT sum(a.l) FROM a WHERE NOT EXISTS (SELECT 1 FROM c WHERE c.b = a.b AND c.d = a.d AND c.u = a.u)) / 1000 km_changed", W, L)
  km$km_changed[is.na(km$km_changed)] <- 0
  per_sp[c(names(km))] <- NA
  res[[w]] <- rbind(per_sp, cbind(all, km))

  # A record sits on the segment whose measures contain it (start inclusive).
  obs[[w]] <- cbind(wsg = w, q(
    "WITH o AS (
       SELECT species_code, blue_line_key, downstream_route_measure m
         FROM bcfishobs.observations
        WHERE watershed_group_code = '%3$s' AND species_code IN (%4$s)),
     s AS (
       SELECT o.*, a.downstream_route_measure dn_a, a.upstream_route_measure up_a, a.gradient g_a,
              b.downstream_route_measure dn_b, b.upstream_route_measure up_b, b.gradient g_b
         FROM o
         JOIN %1$s.streams a ON a.blue_line_key = o.blue_line_key
          AND o.m >= a.downstream_route_measure AND o.m < a.upstream_route_measure
         JOIN %2$s.streams b ON b.blue_line_key = o.blue_line_key
          AND o.m >= b.downstream_route_measure AND o.m < b.upstream_route_measure)
     SELECT count(*) n_records,
            count(*) FILTER (WHERE round(dn_a::numeric, 3) <> round(dn_b::numeric, 3)
                                OR round(up_a::numeric, 3) <> round(up_b::numeric, 3)) n_moved,
            percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(g_b - g_a))
              FILTER (WHERE round(dn_a::numeric, 3) <> round(dn_b::numeric, 3)
                         OR round(up_a::numeric, 3) <> round(up_b::numeric, 3)) med_abs_dgrad,
            max(abs(g_b - g_a)) max_abs_dgrad
       FROM s", W, L, w, paste0("'", modelled_obs, "'", collapse = ", ")))
  x("DROP SCHEMA %s CASCADE", L)
  message(sprintf("[lifts] %s done in %.1f min", w, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}
out <- do.call(rbind, res)
write.csv(out, file.path(here, "lifts.csv"), row.names = FALSE)
write.csv(do.call(rbind, obs), file.path(here, "lifts_obs.csv"), row.names = FALSE)
print(out[out$species == "ALL", ], digits = 4); print(do.call(rbind, obs), digits = 4)
dbDisconnect(conn)
cat("LIFTS_DONE\n")
