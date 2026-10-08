# Usage: Rscript run.R <mode> <repo> <config> <aoi> <schema> <run_label> <out_csv>
#   mode = build       setup .. connect into a scratch working schema
#   mode = reclassify  classify + connect only, segmentation held fixed
# Then measures <schema>.streams_habitat per species, appends to <out_csv>,
# and snapshots the habitat table to zz311_snap.<aoi>_<run_label>.
# Never persists to fresh / fresh_default.
args <- commandArgs(trailingOnly = TRUE)
mode <- args[1]; repo <- args[2]; cfg_arg <- args[3]; aoi <- args[4]
schema <- args[5]; run_label <- args[6]; out_csv <- args[7]
suppressMessages(devtools::load_all(repo, quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config(cfg_arg)
loaded <- suppressWarnings(lnk_load_overrides(cfg))
t0 <- Sys.time()
if (mode == "build") {
  lnk_pipeline_setup(conn, schema, overwrite = TRUE)
  lnk_pipeline_load(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
  lnk_pipeline_prepare(conn, aoi = aoi, cfg = cfg, loaded = loaded,
                       schema = schema, conn_tunnel = conn)
  lnk_pipeline_crossings(conn, aoi = aoi, cfg = cfg, loaded = loaded,
                         schema = schema)
  lnk_pipeline_break(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
} else if (mode != "reclassify") {
  stop("mode must be build or reclassify")
}
lnk_pipeline_classify(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
lnk_pipeline_connect(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)

# Per-species wetland floor, as the bundle declares it (NA = no floor)
dims <- utils::read.csv(cfg$dimensions, stringsAsFactors = FALSE)
floors <- data.frame(
  species_code = dims$species,
  floor_ha = suppressWarnings(as.numeric(dims$rear_wetland_ha_min)))
floors$floor_ha[is.na(floors$floor_ha)] <- -1  # never below: counts nothing
floor_values <- paste(sprintf("('%s', %s)", floors$species_code, floors$floor_ha),
                      collapse = ", ")

# Wetland / lake polygon area per waterbody_key: max polygon (fresh admits
# a key when any polygon meets the floor) and summed area for hectares.
sql <- sprintf("
WITH fl(species_code, floor_ha) AS (VALUES %1$s),
wet AS (SELECT waterbody_key, max(area_ha) AS max_ha, sum(area_ha) AS sum_ha
        FROM whse_basemapping.fwa_wetlands_poly GROUP BY 1),
lak AS (SELECT waterbody_key, sum(area_ha) AS sum_ha
        FROM whse_basemapping.fwa_lakes_poly GROUP BY 1),
h AS (
  SELECT h.species_code, h.rearing, h.lake_rearing, h.wetland_rearing,
         s.length_metre, s.edge_type, s.waterbody_key,
         wet.max_ha AS wet_max_ha, fl.floor_ha
  FROM %2$s.streams_habitat h
  JOIN %2$s.streams s USING (id_segment)
  LEFT JOIN wet ON wet.waterbody_key = s.waterbody_key
  LEFT JOIN fl ON fl.species_code = h.species_code)
SELECT species_code,
  count(*) FILTER (WHERE rearing) AS n_rear,
  round((sum(length_metre) FILTER (WHERE rearing) / 1000)::numeric, 3) AS rear_km,
  round((sum(length_metre) FILTER (WHERE rearing AND edge_type IN (1050, 1150))
         / 1000)::numeric, 3) AS rear_km_wetflow,
  count(*) FILTER (WHERE rearing AND wet_max_ha < floor_ha) AS n_rear_subfloor,
  round((coalesce(sum(length_metre) FILTER (WHERE rearing AND wet_max_ha < floor_ha),
         0) / 1000)::numeric, 3) AS rear_km_subfloor,
  -- 1050/1150 only: what the floored carve-out removes. The stream rule
  -- admits 1000/1100 lines in sub-floor wetlands by design.
  round((coalesce(sum(length_metre) FILTER (WHERE rearing AND wet_max_ha < floor_ha
         AND edge_type IN (1050, 1150)), 0) / 1000)::numeric, 3)
    AS rear_km_subfloor_wetflow,
  round((sum(length_metre) FILTER (WHERE lake_rearing) / 1000)::numeric, 3)
    AS lake_rear_km,
  round((sum(length_metre) FILTER (WHERE wetland_rearing) / 1000)::numeric, 3)
    AS wetland_rear_km,
  max(floor_ha) AS floor_ha
FROM h GROUP BY species_code ORDER BY species_code", floor_values, schema)
d <- DBI::dbGetQuery(conn, sql)

ha <- DBI::dbGetQuery(conn, sprintf("
SELECT h.species_code,
  round(coalesce(sum(l.sum_ha) FILTER (WHERE k.lk), 0)::numeric, 1) AS lake_rear_ha,
  round(coalesce(sum(w.sum_ha) FILTER (WHERE k.wk), 0)::numeric, 1) AS wetland_rear_ha
FROM (SELECT DISTINCT species_code FROM %1$s.streams_habitat) h
LEFT JOIN (
  SELECT DISTINCT h.species_code, s.waterbody_key,
         bool_or(h.lake_rearing) OVER w AS lk, bool_or(h.wetland_rearing) OVER w AS wk
  FROM %1$s.streams_habitat h JOIN %1$s.streams s USING (id_segment)
  WHERE (h.lake_rearing OR h.wetland_rearing) AND s.waterbody_key IS NOT NULL
  WINDOW w AS (PARTITION BY h.species_code, s.waterbody_key)) k
  ON k.species_code = h.species_code
LEFT JOIN (SELECT waterbody_key, sum(area_ha) AS sum_ha
           FROM whse_basemapping.fwa_lakes_poly GROUP BY 1) l
  ON l.waterbody_key = k.waterbody_key AND k.lk
LEFT JOIN (SELECT waterbody_key, sum(area_ha) AS sum_ha
           FROM whse_basemapping.fwa_wetlands_poly GROUP BY 1) w
  ON w.waterbody_key = k.waterbody_key AND k.wk
GROUP BY h.species_code ORDER BY 1", schema))
d <- merge(d, ha, by = "species_code", all.x = TRUE)
d[] <- lapply(d, function(x) if (inherits(x, "integer64")) as.numeric(x) else x)
d$floor_ha[d$floor_ha < 0] <- NA

# count(*) arrives as integer64, which data.frame() will not recycle
seg <- as.numeric(DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*) AS n FROM %s.streams", schema))$n)
fresh_sha <- packageDescription("fresh")$RemoteSha
link_sha <- system2("git", c("-C", repo, "rev-parse", "--short", "HEAD"),
                    stdout = TRUE)
d <- data.frame(run = run_label, aoi = aoi, n_segments = seg,
           link_sha = link_sha,
           fresh = as.character(utils::packageVersion("fresh")),
           fresh_sha = if (is.null(fresh_sha)) NA else substr(fresh_sha, 1, 7),
           cfg_hash = .lnk_config_hash(cfg), d, check.names = FALSE)

DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS zz311_snap")
snap <- sprintf("zz311_snap.%s_%s", tolower(aoi), run_label)
DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", snap))
DBI::dbExecute(conn, sprintf(
  "CREATE TABLE %s AS SELECT * FROM %s.streams_habitat", snap, schema))

# Environment stamp, once per run label (link + fresh SHAs, DB snapshot)
stamp_file <- file.path(dirname(out_csv), sprintf("stamp_%s.txt", run_label))
if (!file.exists(stamp_file)) {
  writeLines(utils::capture.output(print(lnk_stamp(cfg, conn = conn, aoi = aoi))),
             stamp_file)
}

utils::write.table(d, out_csv, sep = ",", row.names = FALSE,
                   col.names = !file.exists(out_csv), append = file.exists(out_csv))
cat(sprintf("## %s %s %s %s  %.1f min\n", run_label, aoi, cfg$name, schema,
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))
print(d[, c("species_code", "n_rear", "rear_km", "rear_km_subfloor_wetflow",
            "lake_rear_km", "wetland_rear_km")], row.names = FALSE)
DBI::dbDisconnect(conn)
