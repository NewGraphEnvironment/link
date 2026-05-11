#' Unify per-WSG barrier sources into the working-schema `<schema>.barriers`
#'
#' Consolidates four barrier families from the per-WSG working schema
#' (`<schema>.crossings`, `<schema>.gradient_barriers_raw`, `<schema>.falls`,
#' `<schema>.barriers_subsurfaceflow`) into one `<schema>.barriers`
#' table matching the [cols_barriers] shape used by the persistent
#' province-wide `<persist_schema>.barriers`. Each row carries a
#' pre-computed `blocks_species text[]` predicate that
#' [lnk_pipeline_access()] queries via `WHERE 'BT' = ANY(blocks_species)`.
#'
#' Per-WSG output is persisted to the province-wide table by
#' [lnk_pipeline_persist()] using the same idempotent DELETE-WHERE-WSG +
#' INSERT pattern already used for `streams` and
#' `streams_habitat_<sp>`. Cross-WSG `dam_dnstr_ind` resolves correctly
#' because [fresh::frs_network_features()] walks FWA topology and
#' doesn't care which WSG a barrier physically lives in — fixes the
#' PARS BT 60% defect (PARS drains through dams in PCEA/UPCE WSGs)
#' and unblocks any regional run.
#'
#' Source families + `blocks_species` semantics:
#'
#' - **Anthropogenic** (`barrier_source IN ('PSCIS','CABD','MODELLED_CROSSINGS')`,
#'   from `<schema>.crossings WHERE barrier_status IN ('BARRIER','POTENTIAL')`):
#'   blocks all 8 species. `crossing_source` is mapped through verbatim,
#'   keeping the `MODELLED_CROSSINGS` value (vs. lossy normalization to
#'   `MODELLED`).
#' - **Gradient** (`barrier_source = 'GRADIENT'`, from
#'   `<schema>.gradient_barriers_raw`): blocks species whose
#'   `access_gradient_max <= gradient_class / 100`. Derived per row from
#'   `loaded$parameters_fresh`.
#' - **Falls** (`barrier_source = 'FALLS'`, from `<schema>.falls`):
#'   blocks all 8 species.
#' - **Subsurface_flow** (`barrier_source = 'SUBSURFACE_FLOW'`, from
#'   `<schema>.barriers_subsurfaceflow`): blocks all 8 species. Opt-in
#'   (only built when `cfg$pipeline$break_order` includes `"subsurfaceflow"`).
#'
#' Remediations (PASSABLE remediation crossings) are intentionally NOT
#' in this table. They're consumed via `<schema>.barriers_remediations`
#' (emitted by [lnk_barriers_emit()]) for the `remediated_dnstr_ind`
#' sequence-aware logic in [lnk_pipeline_access()], which joins to
#' `<schema>.crossings` directly.
#'
#' `id_barrier` is namespaced per source family so rows stay unique
#' inside a WSG without coordinating sequence IDs across sources.
#' Mirrors the offset trick `.lnk_crossings_union` uses for modelled
#' crossings.
#'
#' @param conn A DBI connection.
#' @param aoi Watershed group code, e.g. `"PARS"`.
#' @param cfg An `lnk_config` object.
#' @param loaded Named list from [lnk_load_overrides()]. Must include
#'   `loaded$parameters_fresh` (used to derive gradient-class
#'   `blocks_species`).
#' @param schema Working schema name (per-WSG staging). Default
#'   `paste0("working_", tolower(aoi))`.
#' @param species Character vector of species codes whose access
#'   thresholds drive the gradient `blocks_species` derivation. Default
#'   `unique(loaded$parameters_fresh$species_code)`. Pass a subset
#'   (e.g. the 8 bcfp species) to control which species the gradient
#'   blocks_species column references.
#'
#' @return `invisible(conn)`. Side effect: drops + recreates
#'   `<schema>.barriers`.
#'
#' @details
#' Required pre-existing tables in `schema`:
#' - `<schema>.crossings` (from [lnk_pipeline_crossings()]).
#' - `<schema>.gradient_barriers_raw` (from [lnk_pipeline_prepare()]).
#' - `<schema>.falls` (from [lnk_pipeline_prepare()]).
#'
#' Optional:
#' - `<schema>.barriers_subsurfaceflow` (only when the config opts in).
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' cfg <- lnk_config("bcfishpass")
#' loaded <- lnk_load_overrides(cfg)
#'
#' lnk_pipeline_setup(conn, schema = "working_pars")
#' lnk_pipeline_load(conn, "PARS", cfg, loaded, "working_pars")
#' lnk_pipeline_prepare(conn, "PARS", cfg, loaded, "working_pars",
#'                      conn_tunnel = conn)
#' lnk_pipeline_crossings(conn, "PARS", cfg, loaded, "working_pars")
#' lnk_barriers_unify(conn, aoi = "PARS", cfg = cfg, loaded = loaded,
#'                    schema = "working_pars")
#'
#' DBI::dbReadTable(conn, c("working_pars", "barriers"))
#' }
#'
#' @family barriers
#' @seealso [lnk_persist_init()], [lnk_pipeline_persist()],
#'   [lnk_pipeline_access()]
#' @export
lnk_barriers_unify <- function(conn, aoi, cfg, loaded,
                               schema = paste0("working_", tolower(aoi)),
                               species = NULL) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(aoi), length(aoi) == 1L, nzchar(aoi),
    inherits(cfg, "lnk_config"),
    is.list(loaded),
    is.character(schema), length(schema) == 1L, nzchar(schema)
  )
  if (is.null(loaded$parameters_fresh)) {
    stop("loaded$parameters_fresh is required to derive gradient ",
         "blocks_species. Materialize via lnk_load_overrides(cfg).",
         call. = FALSE)
  }

  params_fresh <- loaded$parameters_fresh
  if (is.null(species)) {
    species <- unique(params_fresh$species_code)
  }
  stopifnot(is.character(species), length(species) > 0L)

  # Build the gradient blocks_species CASE expression from
  # parameters_fresh. `.lnk_classes_bcfp` is a named vector mapping
  # basis-points class IDs (1500, 2000, 2500, 3000 — the values stored
  # in `gradient_barriers_raw.gradient_class`) to fractional thresholds
  # (0.15, 0.20, 0.25, 0.30). A class is a barrier for species `s` when
  # `class_value >= s$access_gradient_max`. Pre-compute the species
  # array per distinct class so each row's lookup is a CASE branch.
  classes_bcfp <- .lnk_classes_bcfp
  gradient_class_ids <- as.integer(names(classes_bcfp))
  class_blocks <- lapply(gradient_class_ids, function(cls_id) {
    cls_value <- classes_bcfp[[as.character(cls_id)]]
    blockers <- character(0)
    for (sp in species) {
      sp_amax <- params_fresh$access_gradient_max[ # nolint: indentation_linter
        params_fresh$species_code == sp]
      sp_amax <- sp_amax[1L]
      if (length(sp_amax) == 0L || is.na(sp_amax) || sp_amax <= 0) next
      if (cls_value >= sp_amax) blockers <- c(blockers, sp)
    }
    blockers
  })
  names(class_blocks) <- gradient_class_ids
  case_branches <- vapply(names(class_blocks), function(cls) {
    spp <- class_blocks[[cls]]
    if (length(spp) == 0L) {
      arr <- "ARRAY[]::text[]"
    } else {
      arr <- sprintf("ARRAY[%s]::text[]",
                     paste(sprintf("'%s'", spp), collapse = ", "))
    }
    sprintf("WHEN gradient_class = %s THEN %s", cls, arr)
  }, character(1))
  gradient_case <- paste(
    "CASE", paste(case_branches, collapse = " "),
    "ELSE ARRAY[]::text[] END"
  )

  # Universal-block array for natural barriers and anthropogenic
  # passability IN ('BARRIER', 'POTENTIAL') — all 8 species blocked.
  all_species_arr <- sprintf(
    "ARRAY[%s]::text[]",
    paste(sprintf("'%s'", species), collapse = ", ")
  )

  aoi_lit <- .lnk_quote_literal(aoi)

  # Probe optional barriers_subsurfaceflow — present only when the
  # bundle opts in via cfg$pipeline$break_order.
  has_subsurface <- nrow(DBI::dbGetQuery(conn, sprintf(
    "SELECT 1 FROM information_schema.tables
      WHERE table_schema = %s AND table_name = 'barriers_subsurfaceflow'
      LIMIT 1;",
    DBI::dbQuoteString(conn, schema)
  ))) > 0L

  # Source 1: anthropogenic. id_barrier reuses aggregated_crossings_id
  # which already namespaces PSCIS (raw) + modelled (offset 1e9) +
  # CABD (dam_id). Cast to bigint explicitly.
  sql_anth <- sprintf("
    SELECT
      aggregated_crossings_id::text     AS id_barrier,
      watershed_group_code,
      crossing_source                   AS barrier_source,
      crossing_feature_type             AS barrier_subtype,
      barrier_status                    AS passability,
      %1$s                              AS blocks_species,
      linear_feature_id,
      blue_line_key,
      watershed_key,
      downstream_route_measure,
      wscode_ltree,
      localcode_ltree,
      ST_Force2D(geom)::geometry(Point, 3005) AS geom
    FROM %2$s.crossings
    WHERE barrier_status IN ('BARRIER', 'POTENTIAL')
      AND blue_line_key = watershed_key",
    all_species_arr, schema)  # nolint: indentation_linter

  # Source 2: gradient. id_barrier = 3_000_000_000 + row_number().
  # gradient_barriers_raw has no watershed_group_code column; the
  # entire table is per-AOI per lnk_pipeline_prepare. geom derived
  # via FWA_LocateAlong + Force2D for cross-source uniformity.
  sql_gradient <- sprintf("
    SELECT
      ('GRADIENT-' || row_number() OVER ()::text)::text AS id_barrier,
      %1$s::varchar(4)                  AS watershed_group_code,
      'GRADIENT'::text                  AS barrier_source,
      label                             AS barrier_subtype,
      'BARRIER'::text                   AS passability,
      %2$s                              AS blocks_species,
      NULL::bigint                      AS linear_feature_id,
      blue_line_key,
      NULL::integer                     AS watershed_key,
      downstream_route_measure,
      wscode_ltree,
      localcode_ltree,
      ST_Force2D(FWA_LocateAlong(blue_line_key, downstream_route_measure))::geometry(Point, 3005) AS geom
    FROM %3$s.gradient_barriers_raw",
    aoi_lit, gradient_case, schema)  # nolint: indentation_linter

  # Source 3: falls. id_barrier = 4_000_000_000 + row_number().
  # falls staging table from fresh's bundled CSV has blue_line_key +
  # downstream_route_measure + watershed_group_code only — JOIN to FWA
  # for ltrees + length to compute integer drm.
  sql_falls <- sprintf("
    SELECT
      ('FALLS-' || row_number() OVER ()::text)::text AS id_barrier,
      f.watershed_group_code,
      'FALLS'::text                     AS barrier_source,
      'falls'::text                     AS barrier_subtype,
      'BARRIER'::text                   AS passability,
      %1$s                              AS blocks_species,
      s.linear_feature_id,
      f.blue_line_key,
      s.watershed_key,
      f.downstream_route_measure::double precision,
      s.wscode_ltree,
      s.localcode_ltree,
      ST_Force2D(FWA_LocateAlong(f.blue_line_key, f.downstream_route_measure))::geometry(Point, 3005) AS geom
    FROM %2$s.falls f
    JOIN whse_basemapping.fwa_stream_networks_sp s
      ON f.blue_line_key = s.blue_line_key
     AND f.downstream_route_measure >= s.downstream_route_measure
     AND f.downstream_route_measure <  s.upstream_route_measure
    WHERE f.watershed_group_code = %3$s",
    all_species_arr, schema, aoi_lit)  # nolint: indentation_linter

  union_parts <- c(sql_anth, sql_gradient, sql_falls)

  if (has_subsurface) {
    sql_subsurface <- sprintf("
      SELECT
        ('SUBSURFACE-' || row_number() OVER ()::text)::text AS id_barrier,
        %1$s::varchar(4)                AS watershed_group_code,
        'SUBSURFACE_FLOW'::text         AS barrier_source,
        'subsurface_flow'::text         AS barrier_subtype,
        'BARRIER'::text                 AS passability,
        %2$s                            AS blocks_species,
        NULL::bigint                    AS linear_feature_id,
        blue_line_key,
        NULL::integer                   AS watershed_key,
        downstream_route_measure::double precision,
        wscode_ltree,
        localcode_ltree,
        ST_Force2D(FWA_LocateAlong(blue_line_key, downstream_route_measure))::geometry(Point, 3005) AS geom
      FROM %3$s.barriers_subsurfaceflow",
      aoi_lit, all_species_arr, schema)  # nolint: indentation_linter
    union_parts <- c(union_parts, sql_subsurface)
  }

  # Drop + recreate <schema>.barriers as the UNION ALL of all sources.
  .lnk_db_execute(conn, sprintf(
    "DROP TABLE IF EXISTS %s.barriers", schema))
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE %s.barriers AS\n%s",
    schema, paste(union_parts, collapse = "\nUNION ALL\n")))

  invisible(conn)
}
