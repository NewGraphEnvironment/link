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

compare_bcfishpass_wsg <- function(wsg, config) {
  stopifnot(
    is.character(wsg), length(wsg) == 1L, nzchar(wsg),
    grepl("^[A-Z]{3,5}$", wsg),
    inherits(config, "lnk_config")
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

  # Defensive reset of shared-schema outputs from any prior partial run.
  DBI::dbExecute(conn,
    "DROP TABLE IF EXISTS fresh.streams, fresh.streams_habitat,
     fresh.streams_breaks CASCADE")

  # -------------------------------------------------------------------------
  # Pipeline
  # -------------------------------------------------------------------------
  link::lnk_pipeline_setup(conn, schema, overwrite = TRUE)
  link::lnk_pipeline_load(conn, aoi = wsg, cfg = config, schema = schema)
  link::lnk_pipeline_prepare(conn, aoi = wsg, cfg = config, schema = schema)
  link::lnk_pipeline_break(conn, aoi = wsg, cfg = config, schema = schema)
  link::lnk_pipeline_classify(conn, aoi = wsg, cfg = config, schema = schema)
  link::lnk_pipeline_connect(conn, aoi = wsg, cfg = config, schema = schema)

  # -------------------------------------------------------------------------
  # Link-side linear rollup (spawning_km + rearing_km per species)
  # rearing_km includes lake + wetland centerline length today. That choice
  # is documented in research/default_vs_bcfishpass.md as a known
  # double-count (linear-km and polygon-ha both credit the same lake);
  # revisit once we compare against bcfishpass's WCRP multiplier approach.
  # -------------------------------------------------------------------------
  species <- link::lnk_pipeline_species(config, wsg)

  species_sql <- paste(
    vapply(species,
      function(s) as.character(DBI::dbQuoteLiteral(conn, s)),
      character(1)),
    collapse = ", ")
  ours_km <- DBI::dbGetQuery(conn, sprintf("
    SELECT h.species_code,
      round(SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric
        / 1000, 2) AS spawning_km,
      round(SUM(CASE WHEN h.rearing THEN s.length_metre ELSE 0 END)::numeric
        / 1000, 2) AS rearing_km
    FROM fresh.streams s JOIN fresh.streams_habitat h
      ON s.id_segment = h.id_segment
    WHERE s.watershed_group_code = %s
      AND h.species_code IN (%s)
    GROUP BY h.species_code ORDER BY h.species_code",
    DBI::dbQuoteLiteral(conn, wsg),
    species_sql))

  # -------------------------------------------------------------------------
  # Link-side polygon-area rollup
  # lake_rearing_ha: sum of DISTINCT fwa_lakes_poly.area_ha where segments
  #   in the WSG are flagged lake_rearing = TRUE for the species.
  # wetland_rearing_ha: same against fwa_wetlands_poly.
  # DISTINCT on waterbody_key avoids double-counting lakes with multiple
  # centerline segments.
  # -------------------------------------------------------------------------
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
    km_row <- if (has_table) {
      DBI::dbGetQuery(conn_ref, sprintf("
        SELECT %s AS species_code,
          round(SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric
            / 1000, 2) AS spawning_km,
          round(SUM(%s)::numeric / 1000, 2) AS rearing_km
        FROM bcfishpass.streams s
        JOIN bcfishpass.habitat_linear_%s h
          ON s.segmented_stream_id = h.segmented_stream_id
        WHERE s.watershed_group_code = %s",
        DBI::dbQuoteLiteral(conn_ref, sp),
        rear_expr,
        tolower(sp),
        DBI::dbQuoteLiteral(conn_ref, wsg)))
    } else {
      data.frame(species_code = sp, spawning_km = 0, rearing_km = 0)
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
      data.frame(lake_rearing_ha = 0)
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
      data.frame(wetland_rearing_ha = 0)
    }

    cbind(km_row, lake_ha, wetland_ha)
  })
  ref <- do.call(rbind, ref_list)

  # -------------------------------------------------------------------------
  # Assemble long-format output — 4 rows per species.
  # -------------------------------------------------------------------------
  habitat_types <- c("spawning", "rearing", "lake_rearing", "wetland_rearing")
  units <- c(spawning = "km", rearing = "km",
             lake_rearing = "ha", wetland_rearing = "ha")
  col_suffix <- c(spawning = "spawning_km", rearing = "rearing_km",
                  lake_rearing = "lake_rearing_ha",
                  wetland_rearing = "wetland_rearing_ha")

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
    spawning        = ours_km,
    rearing         = ours_km,
    lake_rearing    = ours_lake_ha,
    wetland_rearing = ours_wetland_ha
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
    out$bcfishpass_value[i] <-
      if (nrow(ref_row) > 0 && col %in% names(ref_row)) ref_row[[col]] else 0
  }
  out$diff_pct <- ifelse(
    is.na(out$bcfishpass_value) | out$bcfishpass_value == 0,
    NA_real_,
    round(100 * (out$link_value - out$bcfishpass_value) /
          out$bcfishpass_value, 1))

  out
}
