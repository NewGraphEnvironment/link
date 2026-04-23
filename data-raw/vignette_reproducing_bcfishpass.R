# data-raw/vignette_reproducing_bcfishpass.R
#
# Generates artifacts consumed by vignettes/reproducing-bcfishpass.Rmd:
#   - inst/extdata/vignette-data/rollup.rds   (from tar_make rollup)
#   - inst/extdata/vignette-data/bulk_ch.rds  (sf of BULK CH habitat)
#
# Vignette loads the RDS files and renders tables/maps without hitting
# the DB (pkgdown build does not have fwapg access). Follows the
# CLAUDE.md convention for "vignettes that need external resources":
# pre-compute from here, commit the .rds.
#
# Regenerate after any pipeline change that would shift the rollup or
# habitat classification.
#
# Usage:
#   Rscript data-raw/vignette_reproducing_bcfishpass.R

t_start <- proc.time()

out_dir <- "inst/extdata/vignette-data"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ---------------------------------------------------------------------------
# 1. Rollup tibble (from data-raw/_targets targets store)
# ---------------------------------------------------------------------------
rollup <- targets::tar_read(rollup,
  store = "data-raw/_targets")

saveRDS(rollup, file.path(out_dir, "rollup.rds"))
message("rollup: ", nrow(rollup), " rows -> ",
  file.path(out_dir, "rollup.rds"))

# ---------------------------------------------------------------------------
# 2. BULK CH habitat geometry (for the vignette map)
# ---------------------------------------------------------------------------
# Joined from the local fwapg DB: fresh.streams (geom) + fresh.streams_habitat
# (booleans) filtered to CH in BULK. Habitat-TRUE segments only
# (spawning OR rearing), simplified to 50 m tolerance to keep the .rds
# compact. EPSG:4326 for mapgl.
conn <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 5432, dbname = "fwapg",
  user = "postgres", password = "postgres")
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

# Re-seed fresh.streams from a BULK run — targets runs may have left
# ADMS/ELKR state there.
link::lnk_pipeline_setup(conn, "working_bulk", overwrite = TRUE)
cfg <- link::lnk_config("bcfishpass")
link::lnk_pipeline_load(conn, aoi = "BULK", cfg = cfg, schema = "working_bulk")
link::lnk_pipeline_prepare(conn, aoi = "BULK", cfg = cfg, schema = "working_bulk")
link::lnk_pipeline_break(conn, aoi = "BULK", cfg = cfg, schema = "working_bulk")
link::lnk_pipeline_classify(conn, aoi = "BULK", cfg = cfg, schema = "working_bulk")
link::lnk_pipeline_connect(conn, aoi = "BULK", cfg = cfg, schema = "working_bulk")

bulk_ch <- sf::st_read(conn, query = "
  SELECT
    s.id_segment,
    h.spawning,
    h.rearing,
    ST_SimplifyPreserveTopology(
      ST_Transform(s.geom, 4326),
      0.0005
    ) AS geom
  FROM fresh.streams s
  JOIN fresh.streams_habitat h ON s.id_segment = h.id_segment
  WHERE h.species_code = 'CH'
    AND s.watershed_group_code = 'BULK'
    AND (h.spawning IS TRUE OR h.rearing IS TRUE)
")

# Coalesce NULL / NA habitat booleans to FALSE for the R-side ifelse so
# the `habitat` category never falls through to NA_character_. Matches
# the intent of the SQL IS TRUE predicate above.
bulk_ch$spawning[is.na(bulk_ch$spawning)] <- FALSE
bulk_ch$rearing[is.na(bulk_ch$rearing)] <- FALSE

# Add a single categorical column the vignette can colour by
bulk_ch$habitat <- ifelse(
  bulk_ch$spawning & bulk_ch$rearing, "spawning + rearing",
  ifelse(bulk_ch$spawning, "spawning only",
    ifelse(bulk_ch$rearing, "rearing only", NA_character_)))

saveRDS(bulk_ch, file.path(out_dir, "bulk_ch.rds"))
message("bulk_ch: ", nrow(bulk_ch), " segments -> ",
  file.path(out_dir, "bulk_ch.rds"))
message("  size: ",
  round(file.info(file.path(out_dir, "bulk_ch.rds"))$size / 1024, 1),
  " KB")

message("\nDone. Total: ",
  round((proc.time() - t_start)["elapsed"], 1), " s")
