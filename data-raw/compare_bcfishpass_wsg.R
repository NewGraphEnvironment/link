# data-raw/compare_bcfishpass_wsg.R
#
# Per-AOI target function for the targets pipeline in data-raw/_targets.R.
# Runs the six lnk_pipeline_* phases for one watershed group and returns
# a small comparison tibble against the bcfishpass reference on the
# tunnel DB.
#
# Return is KB-scale only — safe to ship over SSH for distributed runs.
# Heavy tables (fresh.streams, working_<wsg>.*) stay on the worker's
# local fwapg.
#
# Compound rollup shape (#51) — one row per (wsg, species, habitat_type):
#
#   wsg            — watershed group code
#   species        — species code
#   habitat_type   — one of spawning, rearing, lake_rearing, wetland_rearing
#   unit           — km (linear, for spawning + rearing) or ha (area, for
#                    lake_rearing + wetland_rearing)
#   link_value     — link's value in that unit
#   bcfishpass_value — bcfishpass reference value, same unit
#   diff_pct       — 100 * (link - bcfishpass) / bcfishpass, NA when ref is 0
#
# rearing_km includes lake + wetland centerline length today — see
# research/default_vs_bcfishpass.md for the decision + revisit note.

compare_bcfishpass_wsg <- function(wsg, config, dams = TRUE,
                                   species = NULL) {
  stopifnot(
    is.character(wsg), length(wsg) == 1L, nzchar(wsg),
    grepl("^[A-Z]{3,5}$", wsg),
    inherits(config, "lnk_config"),
    is.logical(dams), length(dams) == 1L,
    is.null(species) || is.character(species)
  )
  schema <- paste0("working_", tolower(wsg))

  conn <- DBI::dbConnect(RPostgres::Postgres(),
    host = "localhost", port = 5432, dbname = "fwapg",
    user = "postgres", password = "postgres")
  on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

  tunnel_pass <- Sys.getenv("PG_PASS_SHARE", "")
  if (!nzchar(tunnel_pass)) {
    stop("PG_PASS_SHARE env var is not set — needed to connect to the ",
         "bcfishpass reference tunnel (localhost:63333). Set it in ",
         "~/.Renviron.", call. = FALSE)
  }
  conn_ref <- DBI::dbConnect(RPostgres::Postgres(),
    host = "localhost", port = 63333, dbname = "bcfishpass",
    user = Sys.getenv("PG_USER_SHARE", "newgraph"),
    password = tunnel_pass)
  on.exit(try(DBI::dbDisconnect(conn_ref), silent = TRUE), add = TRUE)

  # Stamp the run before doing any work — captures config provenance,
  # software versions, and DB snapshot counts so two runs on the same
  # state can be diffed for what changed.
  stamp <- link::lnk_stamp(config, conn = conn, aoi = wsg)
  message(format(stamp, "markdown"))

  # Materialize the data files declared in the manifest. One call,
  # threaded through every pipeline phase.
  loaded <- link::lnk_load_overrides(config)

  # Defensive reset of shared-schema outputs from any prior partial run.
  DBI::dbExecute(conn,
    "DROP TABLE IF EXISTS fresh.streams, fresh.streams_habitat,
     fresh.streams_breaks CASCADE")

  # -------------------------------------------------------------------------
  # Pipeline
  # -------------------------------------------------------------------------
  link::lnk_pipeline_setup(conn, schema, overwrite = TRUE)
  link::lnk_pipeline_load(conn, aoi = wsg, cfg = config,
    loaded = loaded, schema = schema)
  link::lnk_pipeline_prepare(conn, aoi = wsg, cfg = config,
    loaded = loaded, schema = schema,
    conn_tunnel = if (dams) conn_ref else NULL)
  link::lnk_pipeline_break(conn, aoi = wsg, cfg = config,
    loaded = loaded, schema = schema)
  link::lnk_pipeline_classify(conn, aoi = wsg, cfg = config,
    loaded = loaded, schema = schema)
  link::lnk_pipeline_connect(conn, aoi = wsg, cfg = config,
    loaded = loaded, schema = schema)

  # -------------------------------------------------------------------------
  # Link-side linear rollup (spawning_km + rearing_km per species)
  # rearing_km includes lake + wetland centerline length today. That choice
  # is documented in research/default_vs_bcfishpass.md as a known
  # double-count (linear-km and polygon-ha both credit the same lake);
  # revisit once we compare against bcfishpass's WCRP multiplier approach.
  # -------------------------------------------------------------------------
  # Default species set: link's pipeline-active list intersected with the
  # AOI's wsg_species_presence flags. Caller can pass `species` to restrict
  # the rollup further — e.g. `c("BT","CH","CM","CO","PK","SK","ST","WCT")`
  # to drop GR / KO / RB which bcfp doesn't model (avoids NA-heavy rows
  # in the comparison table). Species not present in the WSG are silently
  # dropped (intersect with the active set).
  active <- link::lnk_pipeline_species(config, loaded, wsg)
  species <- if (is.null(species)) active else intersect(species, active)
  if (length(species) == 0L) {
    stop("no species to roll up in ", wsg, " (active=",
         paste(active, collapse = ","), ", requested=",
         paste(species, collapse = ","), ")", call. = FALSE)
  }

  species_sql <- paste(
    vapply(species,
      function(s) as.character(DBI::dbQuoteLiteral(conn, s)),
      character(1)),
    collapse = ", ")
  # Edge-type slices for the rearing decomposition:
  # - stream-like (stream + canal categories) vs lake centerline vs
  #   wetland centerline. The existing `rearing_km` total double-counts
  #   lake/wetland centerlines when combined with the `_ha` columns;
  #   these slices make it easy to subtract back out downstream.
  # Note: 1050 / 1150 are "stream main/secondary flow through wetland"
  # and are in the `stream` edge-type category per fresh::frs_edge_types.
  # They contribute to rearing_stream_km, not rearing_wetland_centerline_km.
  # Wetland centerline here means only edge_type 1700 (wetland shoreline).
  # Lake / wetland / stream slices are mutually exclusive; the 4 slices
  # (stream, lake-centerline, wetland-centerline, and the implicit
  # "other" — construction/connector/river-polygon interior) sum to
  # rearing_km.
  et_stream_sql  <- "(1000, 1050, 1100, 1150, 2000, 2100, 2300)"
  et_lake_sql    <- "(1500, 1525)"
  et_wetland_sql <- "(1700)"

  ours_km <- DBI::dbGetQuery(conn, sprintf("
    SELECT h.species_code,
      round(SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric
        / 1000, 2) AS spawning_km,
      round(SUM(CASE WHEN h.rearing  THEN s.length_metre ELSE 0 END)::numeric
        / 1000, 2) AS rearing_km,
      round(SUM(CASE WHEN h.rearing AND s.edge_type IN %s
                     THEN s.length_metre ELSE 0 END)::numeric / 1000, 2)
        AS rearing_stream_km,
      round(SUM(CASE WHEN h.rearing AND s.edge_type IN %s
                     THEN s.length_metre ELSE 0 END)::numeric / 1000, 2)
        AS rearing_lake_centerline_km,
      round(SUM(CASE WHEN h.rearing AND s.edge_type IN %s
                     THEN s.length_metre ELSE 0 END)::numeric / 1000, 2)
        AS rearing_wetland_centerline_km
    FROM fresh.streams s JOIN fresh.streams_habitat h
      ON s.id_segment = h.id_segment
    WHERE s.watershed_group_code = %s
      AND h.species_code IN (%s)
    GROUP BY h.species_code ORDER BY h.species_code",
    et_stream_sql, et_lake_sql, et_wetland_sql,
    DBI::dbQuoteLiteral(conn, wsg),
    species_sql))

  # -------------------------------------------------------------------------
  # Link-side polygon-area rollup
  # lake_rearing_ha: sum of DISTINCT fwa_lakes_poly.area_ha where segments
  #   in the WSG are flagged lake_rearing = TRUE for the species.
  # wetland_rearing_ha: same against fwa_wetlands_poly.
  # DISTINCT on waterbody_key avoids double-counting lakes with multiple
  # centerline segments.
  # Requires fresh >= 0.17.1 (lake_rearing / wetland_rearing columns in
  # fresh.streams_habitat). DESCRIPTION pins the version at load time,
  # but if someone runs this against a legacy schema the SQL below
  # errors with a clear "column does not exist" message; catch early.
  # -------------------------------------------------------------------------
  hab_cols <- DBI::dbGetQuery(conn, "
    SELECT column_name FROM information_schema.columns
    WHERE table_schema = 'fresh' AND table_name = 'streams_habitat'")$column_name
  need <- c("lake_rearing", "wetland_rearing")
  missing <- setdiff(need, hab_cols)
  if (length(missing) > 0) {
    stop(sprintf(
      "fresh.streams_habitat is missing required columns: %s. Requires fresh >= 0.17.1.",
      paste(missing, collapse = ", ")), call. = FALSE)
  }
  ours_lake_ha <- DBI::dbGetQuery(conn, sprintf("
    SELECT species_code, round(SUM(area_ha)::numeric, 2) AS lake_rearing_ha
    FROM (
      SELECT DISTINCT h.species_code, l.waterbody_key, l.area_ha
      FROM fresh.streams s
      JOIN fresh.streams_habitat h ON s.id_segment = h.id_segment
      JOIN whse_basemapping.fwa_lakes_poly l
        ON l.waterbody_key = s.waterbody_key
      WHERE s.watershed_group_code = %s
        AND h.species_code IN (%s)
        AND h.lake_rearing = TRUE
    ) sub
    GROUP BY species_code",
    DBI::dbQuoteLiteral(conn, wsg),
    species_sql))

  ours_wetland_ha <- DBI::dbGetQuery(conn, sprintf("
    SELECT species_code, round(SUM(area_ha)::numeric, 2) AS wetland_rearing_ha
    FROM (
      SELECT DISTINCT h.species_code, w.waterbody_key, w.area_ha
      FROM fresh.streams s
      JOIN fresh.streams_habitat h ON s.id_segment = h.id_segment
      JOIN whse_basemapping.fwa_wetlands_poly w
        ON w.waterbody_key = s.waterbody_key
      WHERE s.watershed_group_code = %s
        AND h.species_code IN (%s)
        AND h.wetland_rearing = TRUE
    ) sub
    GROUP BY species_code",
    DBI::dbQuoteLiteral(conn, wsg),
    species_sql))

  # -------------------------------------------------------------------------
  # Bcfishpass-side rollup (option b-amended: same methodology both sides
  # applied to bcfishpass.habitat_linear_<sp>, joined to the same fwa_*
  # polygon tables). Bcfishpass's per-segment classification doesn't
  # distinguish lake_rearing / wetland_rearing — it has a single rearing
  # boolean. We derive the _ha columns by filtering to segments that join
  # to fwa_lakes_poly / fwa_wetlands_poly on waterbody_key.
  # -------------------------------------------------------------------------
  ref_list <- lapply(species, function(sp) {
    ref_cols <- DBI::dbGetQuery(conn_ref, sprintf(
      "SELECT column_name FROM information_schema.columns
       WHERE table_schema = 'bcfishpass'
         AND table_name = 'habitat_linear_%s'", tolower(sp)))
    # has_table: does bcfishpass.habitat_linear_<sp> exist at all?
    # has_rear:  if it exists, does it carry a `rearing` column?
    has_table <- nrow(ref_cols) > 0
    has_rear <- "rearing" %in% ref_cols$column_name
    rear_expr <- if (has_rear) {
      "CASE WHEN h.rearing THEN s.length_metre ELSE 0 END"
    } else {
      "0"
    }

    # Linear km — gate the whole query on table existence. Bcfishpass
    # doesn't model every species (e.g. RB has no habitat_linear_rb),
    # so species present in link's config but absent in bcfishpass get
    # 0 for both sides of the diff (our number still populates via the
    # link-side query; this is just the reference side).
    slice_expr <- function(edge_in) {
      if (has_rear) {
        sprintf("CASE WHEN h.rearing AND s.edge_type IN %s THEN s.length_metre ELSE 0 END",
                edge_in)
      } else {
        "0"
      }
    }

    km_row <- if (has_table) {
      DBI::dbGetQuery(conn_ref, sprintf("
        SELECT %s AS species_code,
          round(SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric
            / 1000, 2) AS spawning_km,
          round(SUM(%s)::numeric / 1000, 2) AS rearing_km,
          round(SUM(%s)::numeric / 1000, 2) AS rearing_stream_km,
          round(SUM(%s)::numeric / 1000, 2) AS rearing_lake_centerline_km,
          round(SUM(%s)::numeric / 1000, 2) AS rearing_wetland_centerline_km
        FROM bcfishpass.streams s
        JOIN bcfishpass.habitat_linear_%s h
          ON s.segmented_stream_id = h.segmented_stream_id
        WHERE s.watershed_group_code = %s",
        DBI::dbQuoteLiteral(conn_ref, sp),
        rear_expr,
        slice_expr(et_stream_sql),
        slice_expr(et_lake_sql),
        slice_expr(et_wetland_sql),
        tolower(sp),
        DBI::dbQuoteLiteral(conn_ref, wsg)))
    } else {
      # bcfp doesn't model this species — return NA so diff_pct
      # cleanly resolves to NA downstream. Distinguishes "0 in bcfp"
      # (real measured zero) from "not modelled by bcfp at all" (NA).
      data.frame(species_code = sp,
                 spawning_km                   = NA_real_,
                 rearing_km                    = NA_real_,
                 rearing_stream_km             = NA_real_,
                 rearing_lake_centerline_km    = NA_real_,
                 rearing_wetland_centerline_km = NA_real_)
    }

    # Lake area — same DISTINCT waterbody_key pattern as link side.
    # Zero if table or rearing column is missing.
    lake_ha <- if (has_table && has_rear) {
      DBI::dbGetQuery(conn_ref, sprintf("
        SELECT round(COALESCE(SUM(area_ha), 0)::numeric, 2) AS lake_rearing_ha
        FROM (
          SELECT DISTINCT l.waterbody_key, l.area_ha
          FROM bcfishpass.streams s
          JOIN bcfishpass.habitat_linear_%s h
            ON s.segmented_stream_id = h.segmented_stream_id
          JOIN whse_basemapping.fwa_lakes_poly l
            ON l.waterbody_key = s.waterbody_key
          WHERE s.watershed_group_code = %s
            AND h.rearing = TRUE
        ) sub",
        tolower(sp),
        DBI::dbQuoteLiteral(conn_ref, wsg)))
    } else {
      # bcfp doesn't model this species — NA, not 0 (see note above on
      # km_row fallback for distinguishing real-zero from not-modelled).
      data.frame(lake_rearing_ha = NA_real_)
    }

    wetland_ha <- if (has_table && has_rear) {
      DBI::dbGetQuery(conn_ref, sprintf("
        SELECT round(COALESCE(SUM(area_ha), 0)::numeric, 2) AS wetland_rearing_ha
        FROM (
          SELECT DISTINCT w.waterbody_key, w.area_ha
          FROM bcfishpass.streams s
          JOIN bcfishpass.habitat_linear_%s h
            ON s.segmented_stream_id = h.segmented_stream_id
          JOIN whse_basemapping.fwa_wetlands_poly w
            ON w.waterbody_key = s.waterbody_key
          WHERE s.watershed_group_code = %s
            AND h.rearing = TRUE
        ) sub",
        tolower(sp),
        DBI::dbQuoteLiteral(conn_ref, wsg)))
    } else {
      data.frame(wetland_rearing_ha = NA_real_)
    }

    cbind(km_row, lake_ha, wetland_ha)
  })
  ref <- do.call(rbind, ref_list)

  # -------------------------------------------------------------------------
  # Assemble long-format output — 7 rows per species: 4 originals
  # (spawning, rearing, lake_rearing, wetland_rearing) plus 3 rearing
  # edge-type slices (stream, lake_centerline, wetland_centerline).
  # -------------------------------------------------------------------------
  habitat_types <- c(
    "spawning", "rearing", "lake_rearing", "wetland_rearing",
    "rearing_stream", "rearing_lake_centerline", "rearing_wetland_centerline"
  )
  units <- c(
    spawning = "km", rearing = "km",
    lake_rearing = "ha", wetland_rearing = "ha",
    rearing_stream = "km",
    rearing_lake_centerline = "km",
    rearing_wetland_centerline = "km"
  )
  col_suffix <- c(
    spawning = "spawning_km", rearing = "rearing_km",
    lake_rearing = "lake_rearing_ha",
    wetland_rearing = "wetland_rearing_ha",
    rearing_stream = "rearing_stream_km",
    rearing_lake_centerline = "rearing_lake_centerline_km",
    rearing_wetland_centerline = "rearing_wetland_centerline_km"
  )

  n_species <- length(species)
  n_rows <- n_species * length(habitat_types)
  sp_col  <- rep(species, each = length(habitat_types))
  hab_col <- rep(habitat_types, n_species)
  unit_col <- units[hab_col]

  out <- tibble::tibble(
    wsg              = wsg,
    species          = sp_col,
    habitat_type     = hab_col,
    unit             = unit_col,
    link_value       = NA_real_,
    bcfishpass_value = NA_real_,
    diff_pct         = NA_real_
  )

  link_sources <- list(
    spawning                   = ours_km,
    rearing                    = ours_km,
    lake_rearing               = ours_lake_ha,
    wetland_rearing            = ours_wetland_ha,
    rearing_stream             = ours_km,
    rearing_lake_centerline    = ours_km,
    rearing_wetland_centerline = ours_km
  )

  for (i in seq_len(nrow(out))) {
    sp  <- out$species[i]
    hab <- out$habitat_type[i]
    col <- col_suffix[hab]

    ours_tab <- link_sources[[hab]]
    ours_row <- ours_tab[ours_tab$species_code == sp, , drop = FALSE]
    out$link_value[i] <-
      if (nrow(ours_row) > 0) ours_row[[col]] else 0

    ref_row <- ref[ref$species_code == sp, , drop = FALSE]
    # NA when bcfp didn't return a row for this species (not modelled),
    # OR when the column isn't in bcfp's schema (e.g. bcfp's habitat_linear_*
    # has no `rearing_lake_centerline_km`). Distinct from a real 0 measurement.
    out$bcfishpass_value[i] <-
      if (nrow(ref_row) > 0 && col %in% names(ref_row)) ref_row[[col]] else NA_real_
  }
  out$diff_pct <- ifelse(
    is.na(out$bcfishpass_value) | out$bcfishpass_value == 0,
    NA_real_,
    round(100 * (out$link_value - out$bcfishpass_value) /
          out$bcfishpass_value, 1))

  out
}
