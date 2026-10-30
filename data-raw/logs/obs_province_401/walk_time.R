# What does counting every group's fish records cost the access walk (#401)?
#
#   Rscript data-raw/logs/obs_province_401/walk_time.R [WSG ...]
#
# For each group, the group's segments are copied from fresh_default.streams
# into a temp table (a build walks a one-group working table), and the
# `default` config's record tables are rebuilt with link's own
# .lnk_pipeline_prep_observations() into scratch schema zz401_walk: the
# group's own records (`observations`, no index, as a build makes it) and every
# group's (`observations_province`, GiST on wscode and localcode). Four walk
# shapes, each timed on its own:
#   A  arrays_group     the walk before #401: one upstream array walk over the
#                       group's own records (frs_network_features, arrays)
#   B  pairs_province   the same walk over every group's records, counted on
#                       the server only (count(*) of the join; fetching the
#                       arrays into R is what makes it infeasible)
#   C  exists_province  #401's walk: one existence walk per active species over
#                       that species' records in every group
#   D  exists_gate      bcfishpass's gate: one existence walk over the group's
#                       own records, any species
# Writes walk_time.csv (one row per group and shape: seconds, rows or pairs,
# 1-minute load at start and end) beside this script.
pkgload::load_all(quiet = TRUE)
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
out <- "data-raw/logs/obs_province_401"
wsgs <- commandArgs(TRUE)
if (length(wsgs) == 0L) {
  wsgs <- c("LKEL", "BULK", "UPCE", "PARS", "ELKR", "LNTH", "SETN", "LFRA")
}
cfg <- lnk_config("default")
loaded <- lnk_load_overrides(cfg)
ex <- function(sql) invisible(DBI::dbExecute(conn, sql))
q <- function(sql) DBI::dbGetQuery(conn, sql)
loadavg <- function() as.numeric(strsplit(system("sysctl -n vm.loadavg",
  intern = TRUE), " ")[[1]][3])
quiet_sf <- function(expr) withCallingHandlers(expr, warning = function(w) {
  if (grepl("simple features geometry column", conditionMessage(w))) {
    invokeRestart("muffleWarning")
  }
})
timed <- function(wsg, shape, n_species, fn) {
  l0 <- loadavg()
  t0 <- proc.time()[["elapsed"]]
  n <- fn()
  data.frame(wsg = wsg, shape = shape, n_species = n_species,
             seconds = round(proc.time()[["elapsed"]] - t0, 2), n = n,
             load_start = l0, load_end = loadavg(), stringsAsFactors = FALSE)
}

ex("SET statement_timeout = '30min'")
ex("CREATE SCHEMA IF NOT EXISTS zz401_walk")
rows <- list()
for (wsg in wsgs) {
  message(format(Sys.time(), "%H:%M:%S"), " ", wsg)
  sp <- toupper(lnk_pipeline_species(cfg, loaded, wsg))
  .lnk_pipeline_prep_observations(conn, wsg, loaded, "zz401_walk")
  ex("DROP TABLE IF EXISTS pg_temp.seg401")
  ex(sprintf(
    "CREATE TEMP TABLE seg401 AS
     SELECT id_segment, watershed_group_code, blue_line_key,
            downstream_route_measure, wscode_ltree, localcode_ltree
       FROM fresh_default.streams WHERE watershed_group_code = '%s'", wsg))
  ex("ANALYZE pg_temp.seg401")
  walk <- function(features, result) quiet_sf(fresh::frs_network_features(
    conn, segments = "pg_temp.seg401", features = features,
    segment_id_col = "id_segment", feature_id_col = "species_code",
    direction = "upstream", aoi = wsg, include_equivalents = FALSE,
    features_wscode_col = "wscode", features_localcode_col = "localcode",
    result = result))
  rows[[length(rows) + 1L]] <- timed(wsg, "arrays_group", length(sp), function() {
    r <- walk("zz401_walk.observations", "ids")
    sum(lengths(r[[2]]))
  })
  rows[[length(rows) + 1L]] <- timed(wsg, "pairs_province", length(sp), function() {
    q("SELECT count(*)::float8 AS n
         FROM pg_temp.seg401 a
         JOIN zz401_walk.observations_province b
           ON whse_basemapping.fwa_upstream(
                a.blue_line_key, a.downstream_route_measure,
                a.wscode_ltree, a.localcode_ltree,
                b.blue_line_key, b.downstream_route_measure,
                b.wscode, b.localcode, false, 1)")$n
  })
  rows[[length(rows) + 1L]] <- timed(wsg, "exists_province", length(sp), function() {
    n <- 0
    for (s in sp) {
      ex("DROP VIEW IF EXISTS pg_temp.obs401_sp")
      ex(sprintf("CREATE TEMP VIEW obs401_sp AS
                  SELECT * FROM zz401_walk.observations_province
                   WHERE species_code = '%s'", s))
      n <- n + nrow(walk("pg_temp.obs401_sp", "exists"))
    }
    # The view depends on the province table, which the next group rebuilds.
    ex("DROP VIEW pg_temp.obs401_sp")
    n
  })
  rows[[length(rows) + 1L]] <- timed(wsg, "exists_gate", length(sp), function() {
    nrow(walk("zz401_walk.observations", "exists"))
  })
  utils::write.csv(do.call(rbind, rows), file.path(out, "walk_time.csv"),
                   row.names = FALSE)
}
ex("DROP SCHEMA zz401_walk CASCADE")
DBI::dbDisconnect(conn)
message("WALK_TIME_DONE")
