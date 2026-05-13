#' Compare one watershed group against a reference dataset
#'
#' Per-WSG convenience wrapper around the existing `lnk_pipeline_*`
#' helpers that produces a long-format rollup tibble suitable for
#' provincial parity comparisons. Optionally adds a per-segment
#' `mapping_code` lens when `with_mapping_code = TRUE`.
#'
#' `reference` is a string identifying the comparison source. Today
#' only `"bcfishpass"` is supported (queries `bcfishpass.habitat_linear_<sp>`
#' on `conn_ref`). The arg is future-proofed for default-bundle parity,
#' regression detection across link runs, or non-bcfp external data.
#'
#' ## Additive, not duplicative
#'
#' Both `with_mapping_code = FALSE` and `with_mapping_code = TRUE` run
#' the per-WSG pipeline **once**. The `TRUE` path is purely additive —
#' it adds `lnk_barriers_unify`, `lnk_barriers_views`, `lnk_pipeline_access`,
#' and `lnk_pipeline_mapping_code` phases on top of the same network
#' state, then queries `bcfishpass.streams_mapping_code` for the segment-
#' level diff. The rollup tibble is unchanged between the two modes.
#'
#' @param conn DBI connection to the local pipeline database (typically
#'   localhost fwapg).
#' @param aoi Watershed group code (e.g. `"ADMS"`).
#' @param cfg An `lnk_config` object (from [lnk_config()]).
#' @param loaded Named list from [lnk_load_overrides()].
#' @param reference Character scalar identifying the reference dataset.
#'   Currently only `"bcfishpass"` is supported.
#' @param with_mapping_code Logical. When `TRUE`, run the additional
#'   `barriers_unify` → `barriers_views` → `access` → `mapping_code`
#'   phases and emit per-species segment-match stats. Default `FALSE`.
#' @param conn_ref DBI connection to the reference database. Required
#'   when `reference = "bcfishpass"` (the bcfp tunnel at
#'   `localhost:63333`). Caller manages this connection.
#' @param species Character vector of species codes to restrict the
#'   rollup to (e.g. `c("BT","CH","CM","CO","PK","SK","ST","WCT")` for
#'   the 8 bcfp-bundle species). Default `NULL` uses
#'   [lnk_pipeline_species()] intersected with WSG presence.
#' @param schema Working schema name. Default
#'   `paste0("working_", tolower(aoi))`.
#' @param dams Logical. When `TRUE` (default), pass `conn` as
#'   `conn_tunnel` to [lnk_pipeline_prepare()] so the CABD dams step
#'   runs from local `cabd.dams`. Pass `FALSE` to skip dams entirely.
#' @param cleanup_working Logical. When `TRUE` (default), drop the
#'   `<schema>` working schema at the end. Pass `FALSE` for interactive
#'   debug / manual inspection.
#'
#' @return A list with two elements:
#'   - `rollup`: tibble with one row per (species, habitat_type) — 7
#'     habitat types: `spawning`, `rearing`, `lake_rearing`,
#'     `wetland_rearing`, `rearing_stream`, `rearing_lake_centerline`,
#'     `rearing_wetland_centerline`. Columns: `wsg`, `species`,
#'     `habitat_type`, `unit` (`km` | `ha`), `link_value`,
#'     `ref_value`, `diff_pct`.
#'   - `mapping_code`: tibble with one row per species — segment-level
#'     match stats vs `bcfishpass.streams_mapping_code`. Columns:
#'     `wsg`, `species`, `total_segs`, `match_pct`, `n_diffs`,
#'     `top_pattern`, `top_pattern_count`. `NULL` when
#'     `with_mapping_code = FALSE`.
#'
#' @details
#' Side effects: writes per-WSG segment-level data to the persistent
#' `<persist_schema>.streams` + `streams_habitat_<sp>` tables via
#' [lnk_pipeline_persist()]. Drops the `<schema>` working schema at end
#' unless `cleanup_working = FALSE`.
#'
#' Rollup methodology mirrors what bcfp's `habitat_linear_<sp>` measures:
#' linear km from `length_metre` summed over rearing/spawning-flagged
#' segments, with edge-type decomposition into stream / lake-centerline /
#' wetland-centerline slices. Lake / wetland area in hectares uses
#' `DISTINCT waterbody_key` joins to `whse_basemapping.fwa_lakes_poly` /
#' `fwa_wetlands_poly` to avoid double-counting multi-segment lakes.
#' See `research/default_vs_bcfishpass.md` for the measurement-asymmetry
#' decision (link reports both centerline km and polygon ha; bcfp credits
#' only one depending on species rule).
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' conn_ref <- DBI::dbConnect(RPostgres::Postgres(),
#'   host = "localhost", port = 63333, dbname = "bcfishpass",
#'   user = "newgraph", password = Sys.getenv("PG_PASS_SHARE"))
#' cfg <- lnk_config("bcfishpass")
#' loaded <- lnk_load_overrides(cfg)
#'
#' # Rollup-only (~70s per WSG)
#' result <- lnk_compare_wsg(
#'   conn = conn, aoi = "ADMS",
#'   cfg = cfg, loaded = loaded,
#'   reference = "bcfishpass", conn_ref = conn_ref
#' )
#' print(result$rollup)
#'
#' # Add mapping_code lens (~100s per WSG)
#' result_mc <- lnk_compare_wsg(
#'   conn = conn, aoi = "ADMS",
#'   cfg = cfg, loaded = loaded,
#'   reference = "bcfishpass", conn_ref = conn_ref,
#'   with_mapping_code = TRUE
#' )
#' print(result_mc$mapping_code)
#' }
#'
#' @family compare
#' @seealso [lnk_pipeline_setup()], [lnk_pipeline_load()],
#'   [lnk_pipeline_prepare()], [lnk_pipeline_persist()],
#'   [lnk_parity_annotate()]
#' @export
lnk_compare_wsg <- function(conn, aoi, cfg, loaded,
                            reference = "bcfishpass",
                            with_mapping_code = FALSE,
                            conn_ref = NULL,
                            species = NULL,
                            schema = paste0("working_", tolower(aoi)),
                            dams = TRUE,
                            cleanup_working = TRUE) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(aoi), length(aoi) == 1L, nzchar(aoi),
    grepl("^[A-Z]{3,5}$", aoi),
    inherits(cfg, "lnk_config"),
    is.list(loaded),
    is.character(reference), length(reference) == 1L, nzchar(reference),
    is.logical(with_mapping_code), length(with_mapping_code) == 1L,
    is.null(species) || is.character(species),
    is.character(schema), length(schema) == 1L, nzchar(schema),
    # `schema` is interpolated raw into DDL (DROP TABLE / DROP SCHEMA
    # CASCADE) via sprintf elsewhere in this function and propagated
    # through every lnk_pipeline_* call. Whitelist regex makes SQL
    # injection structurally impossible even if a caller overrides
    # the default `working_<aoi>` value.
    grepl("^[a-z_][a-z0-9_]*$", schema),
    is.logical(dams), length(dams) == 1L,
    is.logical(cleanup_working), length(cleanup_working) == 1L
  )

  # Reference dispatch. Currently only "bcfishpass" lands a real
  # `<reference>` query handler; future references (default-bundle
  # parity, federal data) wire in here without renaming the public arg.
  supported_references <- c("bcfishpass")
  if (!reference %in% supported_references) {
    stop(
      "Unsupported reference '", reference, "'. Supported: ",
      paste(supported_references, collapse = ", "), ".",
      call. = FALSE
    )
  }
  if (reference == "bcfishpass" && !inherits(conn_ref, "DBIConnection")) {
    stop(
      "reference = 'bcfishpass' requires `conn_ref` (DBI connection to ",
      "the bcfp tunnel at localhost:63333).",
      call. = FALSE
    )
  }
  # `with_mapping_code = TRUE` requires conn_ref also for the
  # streams_mapping_code comparison query. Already validated above
  # when reference == 'bcfishpass' (the only supported reference today).
  # No additional gate needed.

  # Defensive reset of per-WSG staging from any prior partial run.
  DBI::dbExecute(conn, sprintf(
    "DROP TABLE IF EXISTS %1$s.streams, %1$s.streams_habitat,
     %1$s.streams_breaks CASCADE", schema))

  # =====================================================================
  # Build phases — shared between rollup and mapping_code modes
  # =====================================================================
  lnk_pipeline_setup(conn, schema, overwrite = TRUE) # nolint: object_usage_linter
  lnk_pipeline_load(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                    loaded = loaded, schema = schema)
  lnk_pipeline_prepare(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                       loaded = loaded, schema = schema,
                       conn_tunnel = if (dams) conn else NULL)
  lnk_pipeline_crossings(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                         loaded = loaded, schema = schema)
  lnk_pipeline_break(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                     loaded = loaded, schema = schema)
  lnk_pipeline_classify(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                        loaded = loaded, schema = schema)
  lnk_pipeline_connect(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                       loaded = loaded, schema = schema)

  # Resolve active species set BEFORE persist. Empty here means the WSG
  # has no presence for any bundle species — there's nothing to persist
  # or compare. Error out before calling persist (which would otherwise
  # run with an empty species vector and either no-op silently or fail
  # with a less-clear downstream message).
  active_species <- lnk_pipeline_species(cfg, loaded, aoi) # nolint: object_usage_linter
  if (length(active_species) == 0L) {
    stop("no active species in ", aoi,
         " — cfg$species intersected with wsg_species_presence is empty.",
         call. = FALSE)
  }

  # Persist init creates the province-wide target tables (streams,
  # streams_habitat_<sp>, barriers). Always runs.
  lnk_persist_init(conn, cfg, species = active_species) # nolint: object_usage_linter

  # `with_mapping_code = TRUE`: build the unified per-WSG barriers
  # table BEFORE persist so persist handles streams + habitat + barriers
  # in one idempotent transaction. Mirrors data-raw/compare_bcfp_mapping_code.R
  # ordering (link#152 cross-WSG dam_dnstr_ind fix).
  if (isTRUE(with_mapping_code)) {
    lnk_barriers_unify(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                       loaded = loaded, schema = schema)
  }

  # Persist per-WSG segment-level data to province-wide tables.
  lnk_pipeline_persist(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                       species = active_species, schema = schema)

  # Resolve final species list for the rollup. Caller-passed `species`
  # is intersected with the pipeline-active set (anything outside that
  # has no habitat data anyway).
  if (is.null(species)) {
    species <- active_species
  } else {
    species <- intersect(species, active_species)
  }
  if (length(species) == 0L) {
    stop("no species to roll up in ", aoi, " (active=",
         paste(active_species, collapse = ","),
         ") after intersecting with caller-passed `species`.",
         call. = FALSE)
  }

  # =====================================================================
  # Rollup queries — link side
  # =====================================================================
  rollup_link <- .lnk_compare_wsg_rollup_link( # nolint: object_usage_linter
    conn = conn, aoi = aoi, schema = schema, species = species)

  # =====================================================================
  # Rollup queries — reference side (dispatched on `reference`)
  # =====================================================================
  rollup_ref <- .lnk_compare_wsg_rollup_reference( # nolint: object_usage_linter
    reference = reference, conn_ref = conn_ref,
    aoi = aoi, species = species)

  # =====================================================================
  # Assemble long-format output
  # =====================================================================
  rollup <- .lnk_compare_wsg_assemble_rollup( # nolint: object_usage_linter
    aoi = aoi, species = species,
    rollup_link = rollup_link, rollup_ref = rollup_ref)

  # =====================================================================
  # Mapping_code branch — additive phases on the same network state
  # =====================================================================
  mapping_code <- NULL
  if (isTRUE(with_mapping_code)) {
    mapping_code <- .lnk_compare_wsg_mapping_code( # nolint: object_usage_linter
      conn = conn, conn_ref = conn_ref,
      aoi = aoi, cfg = cfg, loaded = loaded,
      schema = schema, reference = reference)
  }

  # Optional cleanup.
  if (isTRUE(cleanup_working)) {
    DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", schema))
  }

  list(rollup = rollup, mapping_code = mapping_code)
}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

#' Compute link-side rollup queries (linear km + lake/wetland ha)
#'
#' Returns a list with three data.frames keyed by `species_code`:
#'   - `km`: spawning_km + rearing_km + 3 rearing edge-type slices
#'   - `lake_ha`: DISTINCT-waterbody_key lake area in ha
#'   - `wetland_ha`: DISTINCT-waterbody_key wetland area in ha
#'
#' Pre-flight checks the `<schema>.streams_habitat` columns for the
#' `lake_rearing` / `wetland_rearing` flags (fresh >= 0.17.1).
#'
#' @noRd
.lnk_compare_wsg_rollup_link <- function(conn, aoi, schema, species) {
  species_sql <- paste(
    vapply(species,
           function(s) as.character(DBI::dbQuoteLiteral(conn, s)),
           character(1)),
    collapse = ", ")
  aoi_lit <- DBI::dbQuoteLiteral(conn, aoi)

  # Edge-type slices for the rearing decomposition. Stream / lake /
  # wetland centerline are mutually exclusive; the implicit "other"
  # (construction / connector / river-polygon interior) sums to
  # rearing_km - sum(slices). See fresh::frs_edge_types for the
  # canonical category map.
  et_stream_sql  <- "(1000, 1050, 1100, 1150, 2000, 2100, 2300)"
  et_lake_sql    <- "(1500, 1525)"
  et_wetland_sql <- "(1700)"

  km <- DBI::dbGetQuery(conn, sprintf("
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
    FROM %s.streams s JOIN %s.streams_habitat h
      ON s.id_segment = h.id_segment
    WHERE s.watershed_group_code = %s
      AND h.species_code IN (%s)
    GROUP BY h.species_code ORDER BY h.species_code",
    et_stream_sql, et_lake_sql, et_wetland_sql,
    schema, schema, aoi_lit, species_sql))  # nolint: indentation_linter

  # Lake / wetland ha — require fresh >= 0.17.1 for the lake_rearing /
  # wetland_rearing flags on streams_habitat.
  hab_cols <- DBI::dbGetQuery(conn, sprintf(
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = %s AND table_name = 'streams_habitat'",
    DBI::dbQuoteLiteral(conn, schema)))$column_name
  missing_cols <- setdiff(c("lake_rearing", "wetland_rearing"), hab_cols)
  if (length(missing_cols) > 0) {
    stop(sprintf(
      "%s.streams_habitat is missing required columns: %s. ",
      schema, paste(missing_cols, collapse = ", ")),
      "Requires fresh >= 0.17.1.", call. = FALSE)
  }

  lake_ha <- DBI::dbGetQuery(conn, sprintf("
    SELECT species_code, round(SUM(area_ha)::numeric, 2) AS lake_rearing_ha
    FROM (
      SELECT DISTINCT h.species_code, l.waterbody_key, l.area_ha
      FROM %s.streams s
      JOIN %s.streams_habitat h ON s.id_segment = h.id_segment
      JOIN whse_basemapping.fwa_lakes_poly l
        ON l.waterbody_key = s.waterbody_key
      WHERE s.watershed_group_code = %s
        AND h.species_code IN (%s)
        AND h.lake_rearing = TRUE
    ) sub
    GROUP BY species_code",
    schema, schema, aoi_lit, species_sql))  # nolint: indentation_linter

  wetland_ha <- DBI::dbGetQuery(conn, sprintf("
    SELECT species_code, round(SUM(area_ha)::numeric, 2) AS wetland_rearing_ha
    FROM (
      SELECT DISTINCT h.species_code, w.waterbody_key, w.area_ha
      FROM %s.streams s
      JOIN %s.streams_habitat h ON s.id_segment = h.id_segment
      JOIN whse_basemapping.fwa_wetlands_poly w
        ON w.waterbody_key = s.waterbody_key
      WHERE s.watershed_group_code = %s
        AND h.species_code IN (%s)
        AND h.wetland_rearing = TRUE
    ) sub
    GROUP BY species_code",
    schema, schema, aoi_lit, species_sql))  # nolint: indentation_linter

  list(km = km, lake_ha = lake_ha, wetland_ha = wetland_ha)
}


#' Compute reference-side rollup queries for the requested `reference`
#'
#' Dispatches on `reference`. Currently only `"bcfishpass"` is wired —
#' queries `bcfishpass.habitat_linear_<sp>` per species, joined to the
#' same `fwa_lakes_poly` / `fwa_wetlands_poly` for the ha columns
#' bcfp doesn't materialize natively.
#'
#' @noRd
.lnk_compare_wsg_rollup_reference <- function(reference, conn_ref,
                                              aoi, species) {
  if (reference == "bcfishpass") {
    return(.lnk_compare_wsg_rollup_bcfishpass(
      conn_ref = conn_ref, aoi = aoi, species = species))
  }
  stop("Unknown reference '", reference, "' in dispatch.", call. = FALSE)
}


#' Reference dispatch: bcfishpass tunnel
#'
#' Mirrors the link-side methodology applied to `bcfishpass.habitat_linear_<sp>`
#' joined to `bcfishpass.streams`. Species absent from bcfp (e.g. RB —
#' bcfp doesn't model it) return NA rather than 0, so `diff_pct`
#' resolves to NA distinguishing "not modelled" from "real zero".
#'
#' @noRd
.lnk_compare_wsg_rollup_bcfishpass <- function(conn_ref, aoi, species) {
  et_stream_sql  <- "(1000, 1050, 1100, 1150, 2000, 2100, 2300)"
  et_lake_sql    <- "(1500, 1525)"
  et_wetland_sql <- "(1700)"
  aoi_lit <- DBI::dbQuoteLiteral(conn_ref, aoi)

  ref_list <- lapply(species, function(sp) {
    ref_cols <- DBI::dbGetQuery(conn_ref, sprintf(
      "SELECT column_name FROM information_schema.columns
       WHERE table_schema = 'bcfishpass'
         AND table_name = 'habitat_linear_%s'", tolower(sp)))
    has_table <- nrow(ref_cols) > 0
    has_rear <- "rearing" %in% ref_cols$column_name

    rear_expr <- if (has_rear) {
      "CASE WHEN h.rearing THEN s.length_metre ELSE 0 END"
    } else {
      "0"
    }
    slice_expr <- function(edge_in) {
      if (has_rear) {
        sprintf("CASE WHEN h.rearing AND s.edge_type IN %s THEN s.length_metre ELSE 0 END", # nolint: line_length_linter
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
        tolower(sp), aoi_lit))  # nolint: indentation_linter
    } else {
      data.frame(species_code                  = sp,
                 spawning_km                   = NA_real_,
                 rearing_km                    = NA_real_,
                 rearing_stream_km             = NA_real_,
                 rearing_lake_centerline_km    = NA_real_,
                 rearing_wetland_centerline_km = NA_real_)
    }

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
        tolower(sp), aoi_lit))  # nolint: indentation_linter
    } else {
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
        tolower(sp), aoi_lit))  # nolint: indentation_linter
    } else {
      data.frame(wetland_rearing_ha = NA_real_)
    }

    cbind(km_row, lake_ha, wetland_ha)
  })
  do.call(rbind, ref_list)
}


#' Assemble long-format output tibble from link + ref rollup data
#'
#' Produces 7 rows per species (spawning, rearing, lake_rearing,
#' wetland_rearing, rearing_stream, rearing_lake_centerline,
#' rearing_wetland_centerline). `diff_pct = NA` when `ref_value` is
#' `NA` (species not modelled by reference) or `0` (avoid div-by-zero
#' even when the measurement is real).
#'
#' @noRd
.lnk_compare_wsg_assemble_rollup <- function(aoi, species,
                                             rollup_link, rollup_ref) {
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

  sp_col <- rep(species, each = length(habitat_types))
  hab_col <- rep(habitat_types, length(species))

  out <- tibble::tibble(
    wsg          = aoi,
    species      = sp_col,
    habitat_type = hab_col,
    unit         = unname(units[hab_col]),
    link_value   = NA_real_,
    ref_value    = NA_real_,
    diff_pct     = NA_real_
  )

  link_sources <- list(
    spawning                   = rollup_link$km,
    rearing                    = rollup_link$km,
    lake_rearing               = rollup_link$lake_ha,
    wetland_rearing            = rollup_link$wetland_ha,
    rearing_stream             = rollup_link$km,
    rearing_lake_centerline    = rollup_link$km,
    rearing_wetland_centerline = rollup_link$km
  )

  for (i in seq_len(nrow(out))) {
    sp  <- out$species[i]
    hab <- out$habitat_type[i]
    col <- col_suffix[hab]

    ours_tab <- link_sources[[hab]]
    ours_row <- ours_tab[ours_tab$species_code == sp, , drop = FALSE]
    out$link_value[i] <- if (nrow(ours_row) > 0) ours_row[[col]] else 0

    ref_row <- rollup_ref[rollup_ref$species_code == sp, , drop = FALSE]
    out$ref_value[i] <-
      if (nrow(ref_row) > 0 && col %in% names(ref_row)) {
        ref_row[[col]]
      } else {
        NA_real_
      }
  }
  out$diff_pct <- ifelse(
    is.na(out$ref_value) | out$ref_value == 0,
    NA_real_,
    round(100 * (out$link_value - out$ref_value) /
          out$ref_value, 1))
  out
}


# ---------------------------------------------------------------------------
# Mapping_code branch — additive phases on top of the rollup pipeline
# ---------------------------------------------------------------------------

#' Run the mapping_code phases and compute per-species segment-level
#' match stats vs the reference's `streams_mapping_code` table.
#'
#' Additive on top of the rollup pipeline — operates on the network
#' state already produced by setup → ... → connect → persist (with
#' `lnk_barriers_unify` slotted before persist). Adds:
#'   1. `lnk_barriers_views` — per-species + per-source VIEWs over
#'      `<persist_schema>.barriers` (cross-WSG access barriers).
#'   2. Stage reference's per-species barriers from `conn_ref` into
#'      `<schema>` — the `barriers_per_sp` arg of `lnk_pipeline_access`
#'      needs bcfp-shape per-species tables that capture minimal-position
#'      semantics the unified table doesn't encode.
#'   3. `lnk_pipeline_access` — per-segment access classification.
#'   4. Pivot `streams_habitat` long → wide for the mapping_code call.
#'   5. `lnk_pipeline_mapping_code` — per-segment token classification.
#'   6. Query reference's `streams_mapping_code` and diff per species.
#'
#' Returns one row per species: `wsg`, `species`, `total_segs`,
#' `match_pct`, `n_diffs`, `top_pattern` (the dominant "link | bcfp"
#' diff string), `top_pattern_count`.
#'
#' @noRd
.lnk_compare_wsg_mapping_code <- function(conn, conn_ref, aoi, cfg, loaded,
                                          schema, reference) {
  if (reference != "bcfishpass") {
    stop("Mapping_code branch currently supports reference = 'bcfishpass' ",
         "only (got '", reference, "').", call. = FALSE)
  }

  # 1. Per-species + per-source VIEWs over <persist_schema>.barriers.
  lnk_barriers_views(conn, schema = schema, cfg = cfg) # nolint: object_usage_linter

  # 2. Stage reference's per-species barriers into working schema. The
  # unified table doesn't capture per-species minimal-position semantics
  # (link#152 footnote); per-species access needs bcfp-shape tables.
  # Cross-WSG dam_dnstr_ind still uses the unified VIEWs (link#152 fix).
  .lnk_compare_wsg_stage_reference_barriers( # nolint: object_usage_linter
    conn = conn, conn_ref = conn_ref, aoi = aoi, schema = schema)

  # 3. Per-segment access classification.
  pres <- lnk_presence(loaded$wsg_species_presence, aoi) # nolint: object_usage_linter
  bcfp_per_sp <- list(
    bt  = "barriers_bt",
    ch  = "barriers_ch_cm_co_pk_sk",
    cm  = "barriers_ch_cm_co_pk_sk",
    co  = "barriers_ch_cm_co_pk_sk",
    pk  = "barriers_ch_cm_co_pk_sk",
    sk  = "barriers_ch_cm_co_pk_sk",
    st  = "barriers_st",
    wct = "barriers_wct"
  )
  barriers_per_sp <- setNames(
    lapply(names(bcfp_per_sp),
           function(sp) paste0(schema, ".", bcfp_per_sp[[sp]])),
    names(bcfp_per_sp))

  acc <- lnk_pipeline_access( # nolint: object_usage_linter
    conn,
    segments        = paste0(schema, ".streams"),
    aoi             = aoi,
    to              = paste0(schema, ".streams_access"),
    barriers_per_sp = barriers_per_sp,
    observations    = paste0(schema, ".observations"),
    presence        = pres,
    barrier_sources = list(
      anthropogenic = paste0(schema, ".barriers_anthropogenic_unified"),
      pscis         = paste0(schema, ".barriers_pscis"),
      dams          = paste0(schema, ".barriers_dams_unified"),
      remediations  = paste0(schema, ".barriers_remediations")),
    crossings_table = paste0(schema, ".crossings"))

  # 4. Pivot habitat long → wide. lnk_pipeline_mapping_code expects
  # `spawning_<sp>` / `rearing_<sp>` columns for all 8 bcfp species.
  # Pre-allocate missing species cols with 0 (link#153 followup).
  hab_long <- DBI::dbGetQuery(conn, sprintf(
    "SELECT id_segment, lower(species_code) AS species_code,
            COALESCE(spawning::int, 0) AS spawning,
            COALESCE(rearing::int, 0)  AS rearing
       FROM %s.streams_habitat
      WHERE watershed_group_code = %s",
    schema, DBI::dbQuoteLiteral(conn, aoi)))
  if (nrow(hab_long) == 0L) {
    stop(sprintf("%s.streams_habitat empty for WSG %s", schema, aoi),
         call. = FALSE)
  }
  hab_wide <- tidyr::pivot_wider(
    hab_long,
    id_cols     = "id_segment",
    names_from  = "species_code",
    values_from = c("spawning", "rearing"),
    values_fill = list(spawning = 0L, rearing = 0L))
  bcfp_species <- c("bt", "ch", "cm", "co", "pk", "sk", "st", "wct")
  for (sp in bcfp_species) {
    for (col in c(paste0("spawning_", sp), paste0("rearing_", sp))) {
      if (!(col %in% names(hab_wide))) {
        hab_wide[[col]] <- 0L
      }
    }
  }

  fc <- DBI::dbGetQuery(conn, sprintf(
    "SELECT id_segment, feature_code FROM %s.streams
      WHERE watershed_group_code = %s",
    schema, DBI::dbQuoteLiteral(conn, aoi)))

  # 5. Per-segment token classification.
  lnk_pipeline_mapping_code( # nolint: object_usage_linter
    access       = acc,
    habitat      = hab_wide,
    feature_code = fc,
    to           = paste0(schema, ".streams_mapping_code"),
    conn         = conn,
    presence     = pres)

  # 6. Diff vs reference per species.
  .lnk_compare_wsg_mapping_code_diff( # nolint: object_usage_linter
    conn = conn, conn_ref = conn_ref,
    aoi = aoi, schema = schema, bcfp_species = bcfp_species)
}


#' Stage per-species reference barriers into the working schema
#'
#' Pulls `bcfishpass.barriers_bt`, `barriers_ch_cm_co_pk_sk`, `barriers_st`,
#' `barriers_wct` from the reference tunnel filtered to `aoi`, writes to
#' `<schema>.<table>`. Re-casts `wscode_ltree` / `localcode_ltree` to
#' `ltree` after `dbWriteTable` (which degrades them to text).
#'
#' Workaround until link#152's `blocks_species` predicate captures
#' per-species minimal-position semantics. Documented in
#' research/provincial_parity_2026_05_11.md operational notes.
#'
#' @noRd
.lnk_compare_wsg_stage_reference_barriers <- function(conn, conn_ref,
                                                      aoi, schema) {
  tables <- c("barriers_bt", "barriers_ch_cm_co_pk_sk",
              "barriers_st", "barriers_wct")
  aoi_lit_ref <- DBI::dbQuoteLiteral(conn_ref, aoi)
  for (tbl in tables) {
    # `tbl` is a hardcoded whitelisted name above; `aoi` is regex-validated
    # at the lnk_compare_wsg entry; `schema` passes the same whitelist.
    # No untrusted interpolation in these statements.
    rows <- DBI::dbGetQuery(conn_ref, sprintf(
      "SELECT * FROM bcfishpass.%s WHERE watershed_group_code = %s",
      tbl, aoi_lit_ref))
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s.%s CASCADE",
                                 schema, tbl))
    DBI::dbWriteTable(conn,
      DBI::Id(schema = schema, table = tbl),
      rows, overwrite = TRUE)
    DBI::dbExecute(conn, sprintf(
      "ALTER TABLE %1$s.%2$s
         ALTER COLUMN wscode_ltree   TYPE ltree USING wscode_ltree::ltree,
         ALTER COLUMN localcode_ltree TYPE ltree USING localcode_ltree::ltree",
      schema, tbl))
  }
}


#' Diff link's streams_mapping_code vs reference's, return per-species stats
#'
#' Joins on `(blue_line_key, downstream_route_measure, length_metre)` —
#' the canonical segment identity across link and bcfp. NA-aware
#' comparison: `NA == NA` counts as match; `NA` vs concrete value is a
#' mismatch.
#'
#' Returns one row per `bcfp_species`. `top_pattern` is the dominant
#' "<link_value> | <bcfp_value>" diff string; useful for class-A/B/C/D
#' taxonomy lookup downstream.
#'
#' @noRd
.lnk_compare_wsg_mapping_code_diff <- function(conn, conn_ref, aoi, schema,
                                               bcfp_species) {
  aoi_lit_link <- DBI::dbQuoteLiteral(conn, aoi)
  aoi_lit_ref  <- DBI::dbQuoteLiteral(conn_ref, aoi)

  # Round float join keys to 3 decimal places (mm precision on values
  # already in metres). `downstream_route_measure` + `length_metre` are
  # PostGIS-computed doubles; deterministic across runs that share the
  # same fwapg segmentation, but rounding makes the join robust to any
  # future ULP-level drift between link's and bcfp's tunnels.
  link_mc <- DBI::dbGetQuery(conn, sprintf("
    SELECT lmc.*, ls.blue_line_key,
           round(ls.downstream_route_measure::numeric, 3) AS downstream_route_measure,
           round(ls.length_metre::numeric, 3)             AS length_metre
      FROM %1$s.streams_mapping_code lmc
      JOIN %1$s.streams ls ON ls.id_segment = lmc.id_segment
     WHERE ls.watershed_group_code = %2$s",
    schema, aoi_lit_link))

  bcfp_mc <- DBI::dbGetQuery(conn_ref, sprintf("
    SELECT bmc.*, bs.blue_line_key,
           round(bs.downstream_route_measure::numeric, 3) AS downstream_route_measure,
           round(bs.length_metre::numeric, 3)             AS length_metre
      FROM bcfishpass.streams_mapping_code bmc
      JOIN bcfishpass.streams bs
        ON bs.segmented_stream_id = bmc.segmented_stream_id
     WHERE bs.watershed_group_code = %s", aoi_lit_ref))

  joined <- merge(
    link_mc, bcfp_mc,
    by = c("blue_line_key", "downstream_route_measure", "length_metre"),
    suffixes = c("_link", "_bcfp"))

  # No-overlap handling. Two distinct cases:
  #   (a) bcfp has 0 rows for this WSG — bcfp's bundle filter doesn't
  #       model it (link#157-style, but on the bcfp side: ~36 WSGs we
  #       model that bcfp's 2026-05-12 build does not, spanning
  #       Mackenzie/Peace drainages, Stikine, and central-BC basins
  #       like BEAV/COAL/DUNE). Not a defect — emit a warning +
  #       NA-filled per-species mapping_code stats so the rollup
  #       tibble still returns and the run continues.
  #   (b) bcfp has rows but no key overlap — that IS a fwapg snapshot
  #       misalignment between tunnels, worth surfacing loudly.
  if (nrow(joined) == 0L) {
    if (nrow(bcfp_mc) == 0L) {
      warning(sprintf(
        "bcfishpass.streams_mapping_code has 0 rows for %s — bcfp does ",
        aoi),
        "not model this WSG. Returning NA-filled mapping_code stats.",
        call. = FALSE)
      return(do.call(rbind, lapply(bcfp_species, function(sp) {
        tibble::tibble(
          wsg = aoi, species = sp,
          total_segs = 0L, match_pct = NA_real_,
          n_diffs = NA_integer_,
          top_pattern = NA_character_, top_pattern_count = NA_integer_)
      })))
    }
    stop(sprintf(
      "no overlap between link's and bcfishpass's streams_mapping_code for %s ",
      aoi),
      "(link rows: ", nrow(link_mc), ", bcfp rows: ", nrow(bcfp_mc),
      "). Check fwapg snapshot alignment between the two tunnels.",
      call. = FALSE)
  }

  rows <- lapply(bcfp_species, function(sp) {
    link_col <- paste0("mapping_code_", sp, "_link")
    bcfp_col <- paste0("mapping_code_", sp, "_bcfp")
    if (!(link_col %in% names(joined)) || !(bcfp_col %in% names(joined))) {
      return(tibble::tibble(
        wsg = aoi, species = sp,
        total_segs = nrow(joined), match_pct = NA_real_,
        n_diffs = NA_integer_,
        top_pattern = NA_character_, top_pattern_count = NA_integer_))
    }
    l <- joined[[link_col]]
    b <- joined[[bcfp_col]]
    matches <- (is.na(l) & is.na(b)) | (!is.na(l) & !is.na(b) & l == b)
    n_match <- sum(matches)
    n_total <- nrow(joined)
    diff_idx <- which(!matches)

    top_pattern <- NA_character_
    top_pattern_count <- NA_integer_
    if (length(diff_idx) > 0L) {
      patt <- paste0(ifelse(is.na(l[diff_idx]), "<NA>", l[diff_idx]),
                     " | ",
                     ifelse(is.na(b[diff_idx]), "<NA>", b[diff_idx]))
      tab <- sort(table(patt), decreasing = TRUE)
      top_pattern <- names(tab)[1]
      top_pattern_count <- as.integer(tab[1])
    }
    tibble::tibble(
      wsg = aoi, species = sp,
      total_segs = n_total,
      match_pct = round(100 * n_match / n_total, 2),
      n_diffs = as.integer(n_total - n_match),
      top_pattern = top_pattern,
      top_pattern_count = top_pattern_count)
  })
  do.call(rbind, rows)
}
