#!/usr/bin/env Rscript
# data-raw/wsg_vignette_data.R
#
# Generic — runs for any BC watershed group. Set `aoi` below; every output
# path is namespaced by `stub <- tolower(aoi)`, so re-pointing at another
# study area is a one-line edit (matches the flooded package's
# data-raw/wsg_vignette_data.R).
#
# Generates the cached artifacts that back vignettes/pars-habitat-connectivity.Rmd.
# Runs ONCE locally. pkgdown CI has no Postgres and no bcfp snapshot, so the
# vignette only *loads* these artifacts — it never touches a database at
# build time. This is the flooded data-gen pattern, not the .Rmd.orig
# pre-knit pattern (which breaks bookdown figure numbering).
#
# Produces (inst/vignette-data/):
#   <stub>.gpkg        layers: aoi (WSG boundary), streams (per-segment
#                      mapping_code_bt from `fresh` + mapping_code_gr from
#                      `fresh_default`), waterbodies (lakes + rivers +
#                      manmade), named_streams, plus the basemapping context
#                      layers reserves, parks, roads, railways
#   <stub>_parity.rds  tunnel-free per-species mapping_code parity
#                      (lnk_compare_mapping_code vs the local bcfp snapshot)
#
# TWO data sources (mirrors flooded / the Peace 2025 report appendix):
#   * MODEL STATE + FWA — local fwapg (localhost:5432). The #175 study-area
#     run persisted PARS to `fresh` (bcfishpass config) + `fresh_default`
#     (default config) DS-first (most-downstream WSG first) so cross-WSG
#     `;DAM` tokens are correct. READ it; do not recompute (a standalone
#     single-WSG re-run would diverge on those segments).
#   * CONTEXT BASEMAPPING — the db_newgraph full catalog via
#     fresh::frs_db_conn() (localhost:63333, dbname `bcfishpass`). reserves
#     (whse_admin_boundaries), parks (whse_tantalis), roads + railways
#     (whse_basemapping.transport_line / gba_railway_tracks_sp) are not in
#     the FWA-only local subset. These are the same `fetch_layer` queries
#     flooded uses. If the 63333 tunnel is down, those layers are skipped
#     (the gpkg still builds, just without context). Bring the tunnel up to
#     ship real context data — see soul/skills/db-newgraph.
#
# Usage: LNK_LOAD=loadall Rscript data-raw/wsg_vignette_data.R

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
stub     <- tolower(aoi)
out_dir  <- "inst/vignette-data"
gpkg     <- file.path(out_dir, paste0(stub, ".gpkg"))
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# local fwapg — model state (fresh / fresh_default) + FWA base layers
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")

cfg_bcfp <- lnk_config("bcfishpass")             # persists to `fresh`

# --- model-state guard — read the authoritative #175 persist, do not recompute
persisted <- function(schema) {
  q <- sprintf(
    "SELECT count(*)::int n FROM %s.streams_mapping_code WHERE watershed_group_code = %s",
    schema, DBI::dbQuoteLiteral(conn, aoi))
  DBI::dbGetQuery(conn, q)$n > 0L
}
if (!persisted("fresh") || !persisted("fresh_default")) {
  stop(aoi, " not persisted in `fresh` and/or `fresh_default`. Run the #175 ",
       "study-area pipeline DS-first before generating vignette data — a ",
       "standalone re-run here would miss cross-WSG `;DAM` tokens. The ",
       "modelling invocation, for reference:\n",
       "  loaded <- lnk_load_overrides(cfg_bcfp)\n",
       "  lnk_pipeline_run(conn, aoi = '", aoi, "', cfg = cfg_bcfp, loaded = loaded,\n",
       "                   schema = 'working_", stub, "', mapping_code = TRUE)\n",
       "  # and likewise for the default config into fresh_default",
       call. = FALSE)
}
message("[wsg_vignette_data] authoritative ", aoi, " state present in fresh + fresh_default")

# --- tunnel-free parity (BT is the only bcfp-config species in the Peace) -----
parity <- lnk_compare_mapping_code(conn, aoi = aoi, cfg = cfg_bcfp)
saveRDS(parity, file.path(out_dir, paste0(stub, "_parity.rds")))
message("[wsg_vignette_data] parity rows: ", nrow(parity),
        " (median match_pct = ", stats::median(parity$match_pct, na.rm = TRUE), ")")

# --- spatial layers -----------------------------------------------------------
aoi_lit <- DBI::dbQuoteLiteral(conn, aoi)

# WSG boundary
q_boundary <- sprintf(
  "SELECT watershed_group_code, watershed_group_name, geom
     FROM whse_basemapping.fwa_watershed_groups_poly
    WHERE watershed_group_code = %s", aoi_lit)
boundary <- sf::st_read(conn, query = q_boundary, quiet = TRUE)

# Streams: bcfp-config BT token (`fresh`) + default-config GR token
# (`fresh_default`), keyed on the persist PK (id_segment, watershed_group_code).
# Keep only the modelled network (a BT or GR token present).
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

# Waterbodies: lakes + rivers + manmade within the WSG, one layer
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

# Named streams (labels) — FWA, present in the local subset
q_named <- sprintf(
  "SELECT gnis_name, blue_line_key, stream_order, geom
     FROM whse_basemapping.fwa_named_streams
    WHERE watershed_group_code = %s", aoi_lit)
named_streams <- sf::st_read(conn, query = q_named, quiet = TRUE)
named_streams <- sf::st_zm(named_streams, drop = TRUE)

# --- context basemapping from the db_newgraph full catalog (63333) ------------
# reserves / parks / roads / railways are absent from the FWA-only local
# subset. Pull them the way flooded + the Peace report do: frs_db_conn().
boundary_wkt <- sf::st_as_text(sf::st_union(sf::st_geometry(boundary)))
intersect_clause <- function(geom_col = "geom") {
  sprintf("ST_Intersects(%s, ST_GeomFromText('%s', 3005))", geom_col, boundary_wkt)
}

conn_ctx <- try(fresh::frs_db_conn(), silent = TRUE)
context_layers <- list()
if (inherits(conn_ctx, "try-error") || is.null(conn_ctx)) {
  message("[wsg_vignette_data] frs_db_conn() unavailable — context layers ",
          "(reserves/parks/roads/railways) skipped. Bring up the 63333 ",
          "db_newgraph tunnel to ship them (soul/skills/db-newgraph).")
} else {
  fetch_ctx <- function(query_sql, label) {
    x <- try(sf::st_read(conn_ctx, query = query_sql, quiet = TRUE), silent = TRUE)
    if (inherits(x, "try-error") || nrow(x) == 0L) {
      message(sprintf("  %s: 0 features (skipping)", label))
      return(NULL)
    }
    message(sprintf("  %s: %d features", label, nrow(x)))
    sf::st_zm(x, drop = TRUE)
  }
  message("[wsg_vignette_data] fetching context layers from db_newgraph ...")
  context_layers$reserves <- fetch_ctx(
    sprintf("SELECT english_name, band_name, geom
               FROM whse_admin_boundaries.adm_indian_reserves_bands_sp
              WHERE %s", intersect_clause()),
    "reserves")
  context_layers$parks <- fetch_ctx(
    sprintf("SELECT protected_lands_name, protected_lands_designation, geom
               FROM whse_tantalis.ta_park_ecores_pa_svw
              WHERE %s", intersect_clause()),
    "parks")
  # roads pre-filtered to resource roads (RR*) — the only class the map draws
  context_layers$roads <- fetch_ctx(
    sprintf("SELECT transport_line_id, structured_name_1, transport_line_type_code,
                    highway_route_1, geom
               FROM whse_basemapping.transport_line
              WHERE transport_line_type_code IN ('RRS', 'RRD', 'RRN')
                AND %s", intersect_clause()),
    "roads")
  context_layers$railways <- fetch_ctx(
    sprintf("SELECT track_name, geom
               FROM whse_basemapping.gba_railway_tracks_sp
              WHERE %s", intersect_clause()),
    "railways")
  DBI::dbDisconnect(conn_ctx)
}
context_layers <- Filter(Negate(is.null), context_layers)

# --- write (fresh file; layered) ----------------------------------------------
if (file.exists(gpkg)) unlink(gpkg)
sf::st_write(boundary,      gpkg, layer = "aoi",           quiet = TRUE)
sf::st_write(streams,       gpkg, layer = "streams",       quiet = TRUE, append = TRUE)
if (nrow(named_streams) > 0L) {
  sf::st_write(named_streams, gpkg, layer = "named_streams", quiet = TRUE, append = TRUE)
}
if (length(wb_layers) > 0L) {
  waterbodies <- sf::st_zm(do.call(rbind, wb_layers), drop = TRUE)
  sf::st_write(waterbodies, gpkg, layer = "waterbodies", quiet = TRUE, append = TRUE)
} else {
  waterbodies <- boundary[0, ]
  message("[wsg_vignette_data] no waterbodies for ", aoi, " — layer skipped")
}
for (nm in names(context_layers)) {
  sf::st_write(context_layers[[nm]], gpkg, layer = nm, quiet = TRUE, append = TRUE)
}

# --- report -------------------------------------------------------------------
sizes <- file.info(list.files(out_dir, full.names = TRUE))["size"]
message("[wsg_vignette_data] wrote artifacts:")
for (f in rownames(sizes)) {
  message(sprintf("  %-40s %s", f, format(structure(sizes[f, ], class = "object_size"),
                                          units = "auto")))
}
message("[wsg_vignette_data] gpkg layers: ",
        paste(sf::st_layers(gpkg)$name, collapse = ", "))
message("[wsg_vignette_data] streams kept: ", nrow(streams),
        "; waterbodies: ", nrow(waterbodies),
        "; named_streams: ", nrow(named_streams))

DBI::dbDisconnect(conn)
