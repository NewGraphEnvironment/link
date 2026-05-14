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
#' 11. [lnk_pipeline_persist()] — copy per-WSG streams + per-species
#'     habitat + barriers into `<persist_schema>` (idempotent
#'     DELETE-WHERE-WSG + INSERT).
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
                             cleanup_working = TRUE) {
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
    is.logical(cleanup_working), length(cleanup_working) == 1L
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

  lnk_pipeline_persist(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                       species = active_species, schema = schema)

  if (isTRUE(cleanup_working)) {
    DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", schema))
  }

  invisible(conn)
}
