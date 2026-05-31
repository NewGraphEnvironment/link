#!/usr/bin/env Rscript
# data-raw/pars_vignette_data.R
#
# Generates the cached artifacts that back vignettes/pars-mapping-code.Rmd.
# Runs ONCE locally against the local fwapg (localhost:5432). pkgdown CI has
# no Postgres and no bcfp snapshot, so the vignette only *loads* these
# artifacts — it never touches a database at build time. This is the flooded
# data-gen pattern (data-raw/wsg_vignette_data.R), not the .Rmd.orig pre-knit
# pattern (which breaks bookdown figure numbering).
#
# Produces (inst/vignette-data/):
#   pars.gpkg        layers: aoi (PARS WSG boundary), streams (per-segment
#                    mapping_code_bt from `fresh` + mapping_code_gr from
#                    `fresh_default`), waterbodies (lakes + rivers + manmade)
#   pars_parity.rds  tunnel-free per-species mapping_code parity for PARS
#                    (lnk_compare_mapping_code vs the local bcfp snapshot)
#   pars_stamp.rds   lnk_stamp provenance for the bcfishpass-config run
#
# MODEL STATE — read, do not recompute. link's modelling pipeline
# (lnk_pipeline_run(mapping_code = TRUE)) is ALREADY persisted for PARS in
# schema `fresh` (bcfishpass config) and `fresh_default` (default config) by
# the authoritative #175 study-area run. That run modelled the Peace drainage
# DS-first (most-downstream WSG first) so a segment's downstream-dam `;DAM`
# tokens — which can live in another WSG — are correct. A naive standalone
# PARS re-run would diverge on those cross-WSG `;DAM` segments, so this script
# READS the persisted state. The run invocation is shown below (guarded by a
# persisted-state check) purely for reproducibility.
#
# Usage: LNK_LOAD=loadall Rscript data-raw/pars_vignette_data.R

suppressPackageStartupMessages({
  if (identical(Sys.getenv("LNK_LOAD"), "loadall")) {
    pkgload::load_all(quiet = TRUE)
  } else {
    library(link)
  }
  library(DBI)
  library(RPostgres)
  library(sf)
})

aoi      <- "PARS"
out_dir  <- "inst/vignette-data"
gpkg     <- file.path(out_dir, "pars.gpkg")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")

cfg_bcfp    <- lnk_config("bcfishpass")          # persists to `fresh`
cfg_default <- lnk_config("default")             # persists to `fresh_default`
cfg_default$pipeline$schema <- "fresh_default"   # YAML default is `fresh`; override

# --- (a)(b) model runs — guarded; skip when the authoritative state exists ----
# Show the invocation for reproducibility, but do NOT clobber the DS-first
# study-area state with a standalone single-WSG run (see header).
persisted <- function(schema) {
  q <- sprintf(
    "SELECT count(*)::int n FROM %s.streams_mapping_code WHERE watershed_group_code = %s",
    schema, DBI::dbQuoteLiteral(conn, aoi))
  DBI::dbGetQuery(conn, q)$n > 0L
}
if (!persisted("fresh") || !persisted("fresh_default")) {
  stop("PARS not persisted in `fresh` and/or `fresh_default`. Run the #175 ",
       "study-area pipeline DS-first before generating vignette data — a ",
       "standalone re-run here would miss cross-WSG `;DAM` tokens. The ",
       "modelling invocation, for reference:\n",
       "  loaded <- lnk_load_overrides(cfg_bcfp)\n",
       "  lnk_pipeline_run(conn, aoi = 'PARS', cfg = cfg_bcfp, loaded = loaded,\n",
       "                   schema = 'working_pars', mapping_code = TRUE)\n",
       "  # and likewise for cfg_default into fresh_default",
       call. = FALSE)
}
message("[pars_vignette_data] authoritative PARS state present in fresh + fresh_default")

# --- (c) tunnel-free parity (BT is the only bcfp-config species in the Peace) -
parity <- lnk_compare_mapping_code(conn, aoi = aoi, cfg = cfg_bcfp)
saveRDS(parity, file.path(out_dir, "pars_parity.rds"))
message("[pars_vignette_data] parity rows: ", nrow(parity),
        " (median match_pct = ", stats::median(parity$match_pct, na.rm = TRUE), ")")

# --- (d) provenance stamp for the report appendix (#24) -----------------------
stamp <- lnk_stamp(cfg_bcfp, conn = conn, aoi = aoi)
stamp <- lnk_stamp_finish(stamp, result = parity)
saveRDS(stamp, file.path(out_dir, "pars_stamp.rds"))
message("[pars_vignette_data] stamp captured")

# --- (e) spatial layers -> pars.gpkg ------------------------------------------
aoi_lit <- DBI::dbQuoteLiteral(conn, aoi)

# WSG boundary
q_boundary <- sprintf(
  "SELECT watershed_group_code, watershed_group_name, geom
     FROM whse_basemapping.fwa_watershed_groups_poly
    WHERE watershed_group_code = %s", aoi_lit)
boundary <- sf::st_read(conn, query = q_boundary, quiet = TRUE)

# Streams: bcfp-config BT token (`fresh`) + default-config GR token
# (`fresh_default`), keyed on the persist PK (id_segment, watershed_group_code).
# Keep only the modelled network (a BT or GR token present) — every tiny
# unmodelled headwater would bloat the shipped gpkg with no map value.
q_streams <- sprintf(
  "SELECT s.id_segment,
          s.blue_line_key,
          mc.mapping_code_bt,
          mcd.mapping_code_gr,
          s.geom
     FROM fresh.streams s
     LEFT JOIN fresh.streams_mapping_code mc
       ON mc.id_segment = s.id_segment
      AND mc.watershed_group_code = s.watershed_group_code
     LEFT JOIN fresh_default.streams_mapping_code mcd
       ON mcd.id_segment = s.id_segment
      AND mcd.watershed_group_code = s.watershed_group_code
    WHERE s.watershed_group_code = %s
      AND (NULLIF(mc.mapping_code_bt, '') IS NOT NULL
           OR NULLIF(mcd.mapping_code_gr, '') IS NOT NULL)", aoi_lit)
streams <- sf::st_read(conn, query = q_streams, quiet = TRUE)

# ship-small: drop Z/M, simplify centerlines (~15 m is invisible at WSG scale)
streams <- sf::st_zm(streams, drop = TRUE)
streams <- sf::st_simplify(streams, dTolerance = 15, preserveTopology = FALSE)
streams <- streams[!sf::st_is_empty(streams), ]

# Waterbodies: lakes + rivers + manmade within PARS, one layer
wb_one <- function(tbl) {
  q <- sprintf(
    "SELECT geom FROM whse_basemapping.%s WHERE watershed_group_code = %s",
    tbl, aoi_lit)
  x <- sf::st_read(conn, query = q, quiet = TRUE)
  if (nrow(x)) x$kind <- sub("^fwa_(.*)_poly$", "\\1", tbl)
  x
}
wb_tables <- c("fwa_lakes_poly", "fwa_rivers_poly", "fwa_manmade_waterbodies_poly")
wb_layers <- Filter(function(z) nrow(z) > 0, lapply(wb_tables, wb_one))

# write (fresh file; layered)
if (file.exists(gpkg)) unlink(gpkg)
sf::st_write(boundary, gpkg, layer = "aoi",     quiet = TRUE)
sf::st_write(streams,  gpkg, layer = "streams", quiet = TRUE, append = TRUE)
# waterbodies optional: a WSG with no lakes/rivers/manmade bodies skips the layer
# rather than erroring on do.call(rbind, list()) -> st_zm(NULL).
if (length(wb_layers) > 0L) {
  waterbodies <- sf::st_zm(do.call(rbind, wb_layers), drop = TRUE)
  sf::st_write(waterbodies, gpkg, layer = "waterbodies", quiet = TRUE, append = TRUE)
} else {
  waterbodies <- boundary[0, ]
  message("[pars_vignette_data] no waterbodies for ", aoi, " — layer skipped")
}

# --- report -------------------------------------------------------------------
sizes <- file.info(list.files(out_dir, full.names = TRUE))["size"]
message("[pars_vignette_data] wrote artifacts:")
for (f in rownames(sizes)) {
  message(sprintf("  %-40s %s", f, format(structure(sizes[f, ], class = "object_size"),
                                          units = "auto")))
}
message("[pars_vignette_data] streams kept: ", nrow(streams),
        "; waterbodies: ", nrow(waterbodies))

DBI::dbDisconnect(conn)
