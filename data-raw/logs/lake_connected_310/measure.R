# Usage: Rscript measure.R <repo> <out_dir>
# Measures every run recorded in <out_dir>/runs.csv from its snapshot
# (zz310_snap.<aoi>_<run>) against the segmentation it was classified on
# (<schema>.streams), one rule for every run, into <out_dir>/measure.csv.
# Then rolls the live working schemas (the last run) up through
# .lnk_compare_wsg_rollup_link() and checks stream + lake + wetland =
# rearing km, into <out_dir>/rollup_check.csv.
args <- commandArgs(trailingOnly = TRUE)
repo <- args[1]; out_dir <- args[2]
suppressMessages(devtools::load_all(repo, quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
runs <- utils::read.csv(file.path(out_dir, "runs.csv"), stringsAsFactors = FALSE)

# Polygon class by waterbody_key against the polygon tables (the #310
# rule, written out here so the old code's run is measured the same way):
# lakes + reservoirs lake, wetlands wetland, else stream. Hectares sum
# every polygon of a key; the divergence counts polygons both ways.
sql_measure <- "
WITH wb AS (SELECT DISTINCT waterbody_key, 'lake' AS cls
            FROM whse_basemapping.fwa_lakes_poly
            UNION ALL SELECT DISTINCT waterbody_key, 'lake'
            FROM whse_basemapping.fwa_manmade_waterbodies_poly
            UNION ALL SELECT DISTINCT waterbody_key, 'wetland'
            FROM whse_basemapping.fwa_wetlands_poly),
lak AS (SELECT waterbody_key, sum(area_ha) AS ha FROM (
          SELECT waterbody_key, area_ha FROM whse_basemapping.fwa_lakes_poly
          UNION ALL
          SELECT waterbody_key, area_ha
          FROM whse_basemapping.fwa_manmade_waterbodies_poly) u GROUP BY 1),
wet AS (SELECT waterbody_key, sum(area_ha) AS ha
        FROM whse_basemapping.fwa_wetlands_poly GROUP BY 1),
h AS (
  SELECT h.species_code, h.spawning, h.rearing, h.lake_rearing,
         h.wetland_rearing, s.length_metre, s.waterbody_key,
         coalesce(wb.cls, 'stream') AS cls
  FROM %1$s h
  JOIN %2$s.streams s USING (id_segment)
  LEFT JOIN wb ON wb.waterbody_key = s.waterbody_key),
poly AS (
  SELECT species_code, waterbody_key, cls,
         bool_or(rearing) AS any_rear,
         bool_or(CASE WHEN cls = 'lake' THEN lake_rearing
                      ELSE wetland_rearing END) AS bucket
  FROM h WHERE cls IN ('lake', 'wetland') GROUP BY 1, 2, 3),
pha AS (
  SELECT p.*, CASE WHEN p.cls = 'lake' THEN lak.ha ELSE wet.ha END AS ha
  FROM poly p
  LEFT JOIN lak ON p.cls = 'lake' AND lak.waterbody_key = p.waterbody_key
  LEFT JOIN wet ON p.cls = 'wetland' AND wet.waterbody_key = p.waterbody_key),
km AS (
  SELECT species_code,
    sum(length_metre) FILTER (WHERE spawning) / 1000 AS spawn_km,
    sum(length_metre) FILTER (WHERE rearing) / 1000 AS rear_km,
    sum(length_metre) FILTER (WHERE rearing AND cls = 'stream') / 1000
      AS rear_stream_km,
    sum(length_metre) FILTER (WHERE rearing AND cls = 'lake') / 1000
      AS rear_lake_km,
    sum(length_metre) FILTER (WHERE rearing AND cls = 'wetland') / 1000
      AS rear_wetland_km
  FROM h GROUP BY 1),
ph AS (
  SELECT species_code,
    sum(ha) FILTER (WHERE cls = 'lake' AND bucket) AS lake_ha,
    sum(ha) FILTER (WHERE cls = 'wetland' AND bucket) AS wetland_ha,
    count(*) FILTER (WHERE cls = 'lake' AND bucket) AS n_lake,
    count(*) FILTER (WHERE cls = 'wetland' AND bucket) AS n_wetland,
    -- the known divergence, both ways
    count(*) FILTER (WHERE cls = 'lake' AND bucket AND NOT any_rear)
      AS n_lake_ha_no_km,
    count(*) FILTER (WHERE cls = 'lake' AND any_rear AND NOT bucket)
      AS n_lake_km_no_ha,
    count(*) FILTER (WHERE cls = 'wetland' AND bucket AND NOT any_rear)
      AS n_wet_ha_no_km,
    count(*) FILTER (WHERE cls = 'wetland' AND any_rear AND NOT bucket)
      AS n_wet_km_no_ha
  FROM pha GROUP BY 1)
SELECT km.*, ph.lake_ha, ph.wetland_ha, ph.n_lake, ph.n_wetland,
       ph.n_lake_ha_no_km, ph.n_lake_km_no_ha, ph.n_wet_ha_no_km,
       ph.n_wet_km_no_ha
FROM km LEFT JOIN ph USING (species_code) ORDER BY 1"

num <- function(d) {
  d[] <- lapply(d, function(x) {
    if (inherits(x, "integer64")) x <- as.numeric(x)
    # an empty FILTER sums to NULL: a measured zero here
    if (is.numeric(x)) round(ifelse(is.na(x), 0, x), 3) else x
  })
  d
}
m <- do.call(rbind, lapply(seq_len(nrow(runs)), function(i) {
  r <- runs[i, ]
  d <- num(DBI::dbGetQuery(conn, sprintf(sql_measure, tolower(r$snapshot),
                                         r$schema)))
  cbind(r[rep(1L, nrow(d)), c("run", "aoi", "n_segments", "link_sha", "fresh")],
        d, row.names = NULL)
}))
utils::write.csv(m, file.path(out_dir, "measure.csv"), row.names = FALSE)

# The rollup itself, on the live working schemas
last <- runs[!duplicated(runs$aoi, fromLast = TRUE), ]
chk <- do.call(rbind, lapply(seq_len(nrow(last)), function(i) {
  sp <- DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT species_code FROM %s.streams_habitat ORDER BY 1",
    last$schema[i]))$species_code
  k <- .lnk_compare_wsg_rollup_link(conn, last$aoi[i], last$schema[i], sp)$km
  data.frame(run = last$run[i], aoi = last$aoi[i], k, row.names = NULL,
             parts_minus_total = round(k$rearing_stream_km + k$rearing_lake_km +
                                         k$rearing_wetland_km - k$rearing_km, 3))
}))
utils::write.csv(chk, file.path(out_dir, "rollup_check.csv"), row.names = FALSE)
print(chk[, c("run", "aoi", "species_code", "rearing_km", "parts_minus_total")],
      row.names = FALSE)
DBI::dbDisconnect(conn)
