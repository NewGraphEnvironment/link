#' Run the link pipeline end-to-end for one watershed group
#'
#' Modelling-only umbrella: chains the `lnk_pipeline_*` phases and the
#' persist write-out into a single call. Produces per-WSG segment data
#' in the persistent province-wide tables (`<persist_schema>.streams`,
#' `streams_habitat_<sp>` per species, `barriers`).
#'
#' This is the **modelling boundary** — the link package's deliverable.
#' Comparison against bcfishpass (or any future reference) lives in
#' [lnk_compare_rollup()], which reads the persisted state. The split
#' lets re-running the pipeline and re-running the comparison happen
#' independently; an orchestrator loop's resume check can probe PG
#' state via `link:::.lnk_wsg_persisted()` rather than the comparison
#' RDS artifact.
#'
#' ## Phase order
#'
#' 1. [lnk_pipeline_setup()] — create per-WSG working schema.
#' 2. [lnk_pipeline_load()] — crossings + modelled fixes + PSCIS status.
#' 3. [lnk_pipeline_prepare()] — falls, definite + control, habitat
#'    confirms, gradient barriers, natural barriers, barrier overrides,
#'    per-model minimal reduction, base segments. Passes `conn` as
#'    `conn_tunnel` when `dams = TRUE` so CABD dams flow through.
#' 4. [lnk_pipeline_crossings()] — match PSCIS to modelled crossings.
#' 5. [lnk_pipeline_break()] — observations, gradient minimal, definite,
#'    habitat endpoints, crossings — in config-defined order.
#' 6. [lnk_pipeline_classify()] — assemble `streams_breaks` and run
#'    `frs_habitat_classify()`.
#' 7. [lnk_pipeline_connect()] — per-species cluster + connected_waterbody.
#' 8. [lnk_pipeline_species()] — resolve the active species set for this
#'    AOI (cfg$species ∩ wsg_species_presence). Empty set is an error.
#' 9. [lnk_persist_init()] — create persistent target tables if absent.
#' 10. [lnk_barriers_unify()] — unify per-source barriers into a single
#'     working-schema table (always; promotes the mapping_code-only
#'     flag in `lnk_compare_wsg()` to canonical PG state).
#' 10b. *Optional* mapping_code phase — gated by `mapping_code = TRUE`.
#'      Runs between barriers_unify and persist:
#'      [lnk_barriers_views()] over working `<schema>.barriers` (tunnel-
#'      free, link-canonical per-species views), [lnk_pipeline_access()]
#'      (writes working `streams_access`), [lnk_mapping_code()] (writes
#'      working `streams_mapping_code`). Persist phase copies both to
#'      `<persist_schema>`. See link#187.
#' 11. [lnk_pipeline_persist()] — copy per-WSG streams + per-species
#'     habitat + barriers (+ optional streams_access + streams_mapping_code)
#'     into `<persist_schema>` (idempotent DELETE-WHERE-WSG + INSERT).
#'
#' @param conn DBI connection to the local pipeline database (typically
#'   localhost fwapg).
#' @param aoi Watershed group code (e.g. `"ADMS"`). Validated against
#'   `^[A-Z]{3,5}$`.
#' @param cfg An `lnk_config` object (from [lnk_config()]).
#' @param loaded Named list from [lnk_load_overrides()].
#' @param schema Working schema name. Default
#'   `paste0("working_", tolower(aoi))`. Per-WSG staging tables live
#'   here; dropped on exit when `cleanup_working = TRUE`.
#' @param dams Logical. When `TRUE` (default), pass `conn` as
#'   `conn_tunnel` to [lnk_pipeline_prepare()] so the CABD dams step
#'   runs from local `cabd.dams`. Pass `FALSE` to skip dams entirely.
#' @param cleanup_working Logical. When `TRUE` (default), drop the
#'   `<schema>` working schema at the end. Pass `FALSE` for interactive
#'   debug / manual inspection.
#' @param mapping_code Logical. When `TRUE`, additionally runs the
#'   tunnel-free mapping_code build phase (10b above) — produces
#'   `<persist_schema>.streams_access` and
#'   `<persist_schema>.streams_mapping_code` for the WSG, consumed
#'   downstream by `data-raw/build_species_views.R --bcfp` (QGIS bcfp-
#'   shape symbology). Default `FALSE`. Methodology shift from pre-#187
#'   compare_wsg: access uses link's own per-species barriers (via
#'   `blocks_species` predicate on `<schema>.barriers`), not bcfp's
#'   tunnel-staged tables.
#'
#' @return `conn`, invisibly. Side effects are the writes into
#'   `<persist_schema>.streams`, `streams_habitat_<sp>`, and `barriers`.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' cfg <- lnk_config("bcfishpass")
#' loaded <- lnk_load_overrides(cfg)
#'
#' # Model one WSG end-to-end (~70s)
#' lnk_pipeline_run(conn = conn, aoi = "ADMS",
#'                  cfg = cfg, loaded = loaded)
#'
#' # Verify PG state
#' DBI::dbGetQuery(conn,
#'   "SELECT count(*) FROM fresh.streams WHERE watershed_group_code = 'ADMS'")
#' }
#'
#' @family pipeline
#' @seealso [lnk_compare_rollup()], [lnk_compare_wsg()],
#'   [lnk_pipeline_setup()], [lnk_pipeline_persist()]
#' @export
lnk_pipeline_run <- function(conn, aoi, cfg, loaded,
                             schema = paste0("working_", tolower(aoi)),
                             dams = TRUE,
                             cleanup_working = TRUE,
                             mapping_code = FALSE) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(aoi), length(aoi) == 1L, nzchar(aoi),
    grepl("^[A-Z]{3,5}$", aoi),
    inherits(cfg, "lnk_config"),
    is.list(loaded),
    is.character(schema), length(schema) == 1L, nzchar(schema),
    # `schema` is interpolated raw into DDL (DROP TABLE / DROP SCHEMA
    # CASCADE) via sprintf in the phase functions and this one. Whitelist
    # regex makes SQL injection structurally impossible even if a caller
    # overrides the default `working_<aoi>` value.
    grepl("^[a-z_][a-z0-9_]*$", schema),
    is.logical(dams), length(dams) == 1L,
    is.logical(cleanup_working), length(cleanup_working) == 1L,
    is.logical(mapping_code), length(mapping_code) == 1L
  )

  # Defensive reset of per-WSG staging from any prior partial run.
  DBI::dbExecute(conn, sprintf(
    "DROP TABLE IF EXISTS %1$s.streams, %1$s.streams_habitat,
     %1$s.streams_breaks CASCADE", schema))

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
  # has no presence for any bundle species — nothing to persist. Error
  # out before calling persist (which would otherwise run with an empty
  # species vector and either no-op silently or fail downstream with a
  # less-clear message).
  active_species <- lnk_pipeline_species(cfg, loaded, aoi) # nolint: object_usage_linter
  if (length(active_species) == 0L) {
    stop("no active species in ", aoi,
         " — cfg$species intersected with wsg_species_presence is empty.",
         call. = FALSE)
  }

  lnk_persist_init(conn, cfg, species = active_species) # nolint: object_usage_linter

  # Always unify barriers — makes `<persist_schema>.barriers` canonical
  # for any future reader (e.g. a decoupled mapping_code comparison).
  # Cost is small: one per-WSG unify + copy.
  lnk_barriers_unify(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                     loaded = loaded, schema = schema)

  # Optional mapping_code phase (link#187). Tunnel-free build of
  # streams_access + streams_mapping_code in the working schema. Persist
  # phase (next) copies both to <persist_schema>. Methodology shift vs
  # pre-#187 compare_wsg: ACCESS now uses link's own per-species barriers
  # (derived from <schema>.barriers's `blocks_species` predicate via
  # lnk_barriers_views) instead of bcfp's barriers tables staged via the
  # tunnel. Yields a more meaningful diff vs bcfp's streams_mapping_code
  # (the prior compare_wsg path used bcfp access semantics, artificially
  # suppressing real link-vs-bcfp divergence). See NEWS v0.40.0.
  if (isTRUE(mapping_code)) {
    pres <- lnk_presence(loaded$wsg_species_presence, aoi) # nolint: object_usage_linter

    # 1. Per-species + per-source barrier views over working <schema>.barriers
    # (built by lnk_barriers_unify above). Tunnel-free, link-canonical.
    lnk_barriers_views(conn, schema = schema, cfg = cfg, # nolint: object_usage_linter
                       barriers_table = paste0(schema, ".barriers"))

    # 2. Per-segment access. barriers_per_sp keys cover the full bcfp
    # species set so all `access_<sp>` + `has_barriers_<sp>_dnstr` columns
    # in the persist table get populated (-9 for species absent from the
    # WSG via lnk_pipeline_access's presence-aware code-assignment).
    sp_set <- c("bt", "ch", "cm", "co", "pk", "sk", "st", "wct")
    barriers_per_sp <- setNames(
      lapply(sp_set, function(sp) paste0(schema, ".barriers_", sp, "_unified")),
      sp_set)

    lnk_pipeline_access(conn, # nolint: object_usage_linter
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

    # 3. Per-segment per-species mapping_code tokens. Schema-aware wrapper
    # over lnk_pipeline_mapping_code — delegates the pure data transform.
    lnk_mapping_code(conn, # nolint: object_usage_linter
      table_access  = paste0(schema, ".streams_access"),
      table_habitat = paste0(schema, ".streams_habitat"),
      table_streams = paste0(schema, ".streams"),
      aoi           = aoi,
      table_to      = paste0(schema, ".streams_mapping_code"),
      presence      = pres)
  }

  lnk_pipeline_persist(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                       species = active_species, schema = schema)

  if (isTRUE(cleanup_working)) {
    DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", schema))
  }

  invisible(conn)
}
