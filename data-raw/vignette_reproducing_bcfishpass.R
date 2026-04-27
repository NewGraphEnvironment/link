# data-raw/vignette_reproducing_bcfishpass.R
#
# Generates artifacts consumed by vignettes/reproducing-bcfishpass.Rmd:
#   - inst/extdata/vignette-data/rollup.rds       (from tar_make rollup)
#   - inst/extdata/vignette-data/sub_ch.rds       (link CH habitat in AOI)
#   - inst/extdata/vignette-data/sub_ch_bcfp.rds  (bcfishpass CH habitat in AOI)
#
# Vignette loads the RDS files and renders tables / map without hitting
# the DB. Follows the CLAUDE.md vignette convention.
#
# The vignette's map AOI is the Neexdzii Kwa (Upper Bulkley River)
# watershed — everything upstream of the Bulkley–Morice confluence,
# built via FWA_WatershedAtMeasure(blk = 360873822, drm = 166030.4).
# Stays inside the BULK watershed group, so BULK rollup numbers cover
# this area.
#
# Usage:
#   Rscript data-raw/vignette_reproducing_bcfishpass.R

t_start <- proc.time()

out_dir <- "inst/extdata/vignette-data"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# AOI anchor point
aoi_blk <- 360873822L
aoi_drm <- 166030.4

# ---------------------------------------------------------------------------
# 1. Rollup tibble (from data-raw/_targets store)
# ---------------------------------------------------------------------------
rollup <- targets::tar_read(rollup, store = "data-raw/_targets")
saveRDS(rollup, file.path(out_dir, "rollup.rds"))
message("rollup: ", nrow(rollup), " rows -> ",
  file.path(out_dir, "rollup.rds"))

# ---------------------------------------------------------------------------
# 2. Build AOI polygon and clip link's CH habitat to it
# ---------------------------------------------------------------------------
conn <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 5432, dbname = "fwapg",
  user = "postgres", password = "postgres")
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

# Re-seed BULK so fresh.streams / streams_habitat reflect this WSG
# (other `tar_make` targets may have overwritten it).
link::lnk_pipeline_setup(conn, "working_bulk", overwrite = TRUE)
cfg <- link::lnk_config("bcfishpass")
link::lnk_pipeline_load(conn, aoi = "BULK", cfg = cfg, schema = "working_bulk")
link::lnk_pipeline_prepare(conn, aoi = "BULK", cfg = cfg, schema = "working_bulk")
link::lnk_pipeline_break(conn, aoi = "BULK", cfg = cfg, schema = "working_bulk")
link::lnk_pipeline_classify(conn, aoi = "BULK", cfg = cfg, schema = "working_bulk")
link::lnk_pipeline_connect(conn, aoi = "BULK", cfg = cfg, schema = "working_bulk")

# Materialize AOI polygon once for both clip queries
DBI::dbExecute(conn,
  "DROP TABLE IF EXISTS working_bulk.aoi_neexdzii_kwa")
DBI::dbExecute(conn, sprintf(
  "CREATE TABLE working_bulk.aoi_neexdzii_kwa AS
   SELECT geom
   FROM whse_basemapping.fwa_watershedatmeasure(%d, %f)",
  aoi_blk, aoi_drm))

sub_ch <- sf::st_read(conn, query = "
  SELECT
    CASE
      WHEN h.spawning IS TRUE AND h.rearing IS TRUE THEN 'spawning + rearing'
      WHEN h.spawning IS TRUE                       THEN 'spawning only'
      WHEN h.rearing  IS TRUE                       THEN 'rearing only'
    END AS habitat,
    ST_SimplifyPreserveTopology(ST_Transform(s.geom, 4326), 0.001) AS geom
  FROM fresh.streams s
  JOIN fresh.streams_habitat h ON s.id_segment = h.id_segment
  JOIN working_bulk.aoi_neexdzii_kwa a
    ON ST_Intersects(s.geom, a.geom)
  WHERE h.species_code = 'CH'
    AND s.watershed_group_code = 'BULK'
    AND (h.spawning IS TRUE OR h.rearing IS TRUE)
")

sub_ch <- by(sub_ch, sub_ch$habitat, function(rows) {
  sf::st_sf(
    habitat = rows$habitat[1],
    geom = sf::st_union(sf::st_geometry(rows))
  )
})
sub_ch <- do.call(rbind, sub_ch)
rownames(sub_ch) <- NULL

saveRDS(sub_ch, file.path(out_dir, "sub_ch.rds"))
message("sub_ch (link): ", nrow(sub_ch), " dissolved features -> ",
  file.path(out_dir, "sub_ch.rds"))
message("  size: ",
  round(file.info(file.path(out_dir, "sub_ch.rds"))$size / 1024, 1),
  " KB")

# ---------------------------------------------------------------------------
# 3. Same AOI, bcfishpass reference (tunnel DB). Polygon comes back
#    with the local query; we pass it as WKT into the tunnel query.
# ---------------------------------------------------------------------------
aoi_wkt <- DBI::dbGetQuery(conn,
  "SELECT ST_AsText(geom) AS wkt FROM working_bulk.aoi_neexdzii_kwa")$wkt

conn_ref <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 63333, dbname = "bcfishpass",
  user = Sys.getenv("PG_USER_SHARE", "newgraph"),
  password = Sys.getenv("PG_PASS_SHARE", ""))
on.exit(try(DBI::dbDisconnect(conn_ref), silent = TRUE), add = TRUE)

# Read from `streams_habitat_linear` (the integer-column table that
# blends model + known) rather than `habitat_linear_ch` (model-only),
# so the comparison is apples-to-apples with link's post-overlay
# output. spawning_ch / rearing_ch values: 1-2 = model, 3 = known.
sub_ch_bcfp <- sf::st_read(conn_ref, query = sprintf("
  SELECT
    CASE
      WHEN h.spawning_ch > 0 AND h.rearing_ch > 0 THEN 'spawning + rearing'
      WHEN h.spawning_ch > 0                      THEN 'spawning only'
      WHEN h.rearing_ch  > 0                      THEN 'rearing only'
    END AS habitat,
    ST_SimplifyPreserveTopology(ST_Transform(s.geom, 4326), 0.001) AS geom
  FROM bcfishpass.streams s
  JOIN bcfishpass.streams_habitat_linear h
    ON s.segmented_stream_id = h.segmented_stream_id
  WHERE ST_Intersects(s.geom, ST_GeomFromText('%s', 3005))
    AND (h.spawning_ch > 0 OR h.rearing_ch > 0)",
  aoi_wkt))

sub_ch_bcfp <- by(sub_ch_bcfp, sub_ch_bcfp$habitat, function(rows) {
  sf::st_sf(
    habitat = rows$habitat[1],
    geom = sf::st_union(sf::st_geometry(rows))
  )
})
sub_ch_bcfp <- do.call(rbind, sub_ch_bcfp)
rownames(sub_ch_bcfp) <- NULL

saveRDS(sub_ch_bcfp, file.path(out_dir, "sub_ch_bcfp.rds"))
message("sub_ch_bcfp (bcfishpass): ", nrow(sub_ch_bcfp),
  " dissolved features -> ",
  file.path(out_dir, "sub_ch_bcfp.rds"))
message("  size: ",
  round(file.info(file.path(out_dir, "sub_ch_bcfp.rds"))$size / 1024, 1),
  " KB")

message("\nDone. Total: ",
  round((proc.time() - t_start)["elapsed"], 1), " s")
