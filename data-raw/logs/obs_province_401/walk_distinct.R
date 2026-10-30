# One walk returning the distinct species upstream of each segment, as
# bcfishpass's spp CTE does (SELECT DISTINCT segment, species_code), against
# the array walk link makes today (#401). Same tables as walk_time.R; the
# query is written here because fresh has no distinct mode.
#
#   Rscript data-raw/logs/obs_province_401/walk_distinct.R [WSG ...]
pkgload::load_all(quiet = TRUE)
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
out <- "data-raw/logs/obs_province_401"
wsgs <- commandArgs(TRUE)
if (length(wsgs) == 0L) wsgs <- c("SETN", "LFRA", "BULK")
cfg <- lnk_config("default")
loaded <- lnk_load_overrides(cfg)
ex <- function(sql) invisible(DBI::dbExecute(conn, sql))
loadavg <- function() as.numeric(strsplit(system("sysctl -n vm.loadavg",
  intern = TRUE), " ")[[1]][3])
quiet_sf <- function(expr) withCallingHandlers(expr, warning = function(w) {
  if (grepl("simple features geometry column", conditionMessage(w))) {
    invokeRestart("muffleWarning")
  }
})
ex("SET statement_timeout = '30min'")
ex("CREATE SCHEMA IF NOT EXISTS zz401_walk")
rows <- list()
for (wsg in wsgs) {
  .lnk_pipeline_prep_observations(conn, wsg, loaded, "zz401_walk")
  ex("DROP TABLE IF EXISTS pg_temp.seg401")
  ex(sprintf(
    "CREATE TEMP TABLE seg401 AS
     SELECT id_segment, watershed_group_code, blue_line_key,
            downstream_route_measure, wscode_ltree, localcode_ltree
       FROM fresh_default.streams WHERE watershed_group_code = '%s'", wsg))
  ex("ANALYZE pg_temp.seg401")
  for (rep in 1:2) for (shape in c("arrays_group", "distinct_province")) {
    l0 <- loadavg(); t0 <- proc.time()[["elapsed"]]
    n <- if (shape == "arrays_group") {
      r <- quiet_sf(fresh::frs_network_features(
        conn, segments = "pg_temp.seg401",
        features = "zz401_walk.observations", segment_id_col = "id_segment",
        feature_id_col = "species_code", direction = "upstream", aoi = wsg,
        include_equivalents = FALSE, features_wscode_col = "wscode",
        features_localcode_col = "localcode"))
      sum(lengths(r[[2]]))
    } else {
      nrow(DBI::dbGetQuery(conn,
        "SELECT DISTINCT a.id_segment, b.species_code
           FROM pg_temp.seg401 a
           JOIN zz401_walk.observations_province b
             ON whse_basemapping.fwa_upstream(
                  a.blue_line_key, a.downstream_route_measure,
                  a.wscode_ltree, a.localcode_ltree,
                  b.blue_line_key, b.downstream_route_measure,
                  b.wscode, b.localcode, false, 1)"))
    }
    rows[[length(rows) + 1L]] <- data.frame(
      wsg = wsg, rep = rep, shape = shape,
      seconds = round(proc.time()[["elapsed"]] - t0, 2), n = n,
      load_start = l0, load_end = loadavg())
    message(wsg, " ", rep, " ", shape, " ", rows[[length(rows)]]$seconds)
  }
  utils::write.csv(do.call(rbind, rows), file.path(out, "walk_distinct.csv"),
                   row.names = FALSE)
}
ex("DROP SCHEMA zz401_walk CASCADE")
message("WALK_DISTINCT_DONE")
