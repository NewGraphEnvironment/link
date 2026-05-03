#' Apply Rearing-Spawning and Waterbody Connectivity
#'
#' Sixth and final phase of the habitat classification pipeline. Runs
#' the connectivity logic that `frs_habitat()` executes internally —
#' rearing-spawning clustering via [fresh::frs_cluster()] and
#' connected-waterbody rules via `fresh:::.frs_connected_waterbody()`
#' — configured by per-species flags in `loaded$parameters_fresh`:
#'
#'   - `cluster_rearing` — enables three-phase rearing-spawning
#'     clustering for the species
#'   - `cluster_direction`, `cluster_bridge_gradient`,
#'     `cluster_bridge_distance`, `cluster_confluence_m` — cluster
#'     parameters
#'   - `cluster_spawning` — enables spawn clustering for rules with
#'     `requires_connected: rearing` (e.g. SK spawning adjacent to
#'     rearing lakes)
#'
#' Mutates `fresh.streams_habitat` in place, adjusting `spawning` /
#' `rearing` booleans per species based on connectivity.
#'
#' `lnk_pipeline_connect` is a thin wrapper over fresh's internal
#' `.frs_run_connectivity` orchestrator. Accessing fresh internals is
#' an acknowledged fragility — a fresh issue will be filed to export a
#' stable API for this composition. The wrapper isolates link from the
#' internal name, so future renames in fresh affect one file here.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param aoi Character. Watershed group code (kept for signature
#'   consistency with the other pipeline phases; not used in this
#'   phase — connectivity operates on the classified table which is
#'   already AOI-scoped).
#' @param cfg An `lnk_config` object from [lnk_config()].
#' @param loaded Named list of tibbles from [lnk_load_overrides()].
#'   Carries `parameters_fresh` and `wsg_species_presence`.
#' @param schema Character. Working schema name (kept for signature
#'   consistency; connectivity reads `fresh.streams_habitat` directly).
#' @param species Character vector. Species to run connectivity for.
#'   Default derives the same way as [lnk_pipeline_classify()].
#' @param thresholds_csv Path to the habitat thresholds CSV. Default
#'   uses the copy shipped with fresh.
#'
#' @return `conn` invisibly, for pipe chaining.
#'
#' @family pipeline
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn   <- lnk_db_conn()
#' cfg    <- lnk_config("bcfishpass")
#' loaded <- lnk_load_overrides(cfg)
#' schema <- "working_bulk"
#'
#' lnk_pipeline_setup(conn, schema)
#' lnk_pipeline_load(conn, "BULK", cfg, loaded, schema)
#' lnk_pipeline_prepare(conn, "BULK", cfg, loaded, schema)
#' lnk_pipeline_break(conn, "BULK", cfg, loaded, schema)
#' lnk_pipeline_classify(conn, "BULK", cfg, loaded, schema)
#' lnk_pipeline_connect(conn, "BULK", cfg, loaded, schema)
#'
#' DBI::dbDisconnect(conn)
#' }
lnk_pipeline_connect <- function(conn, aoi, cfg, loaded, schema,
                                  species = NULL,
                                  thresholds_csv = system.file(
                                    "extdata",
                                    "parameters_habitat_thresholds.csv",
                                    package = "fresh")) {
  .lnk_validate_identifier(schema, "schema")
  if (!is.character(aoi) || length(aoi) != 1L || !nzchar(aoi)) {
    stop("aoi must be a single non-empty string (watershed group code)",
         call. = FALSE)
  }
  if (!inherits(cfg, "lnk_config")) {
    stop("cfg must be an lnk_config object (from lnk_config())",
         call. = FALSE)
  }
  if (!is.list(loaded)) {
    stop("loaded must be a named list (from lnk_load_overrides())",
         call. = FALSE)
  }
  if (!nzchar(thresholds_csv) || !file.exists(thresholds_csv)) {
    stop("thresholds_csv not found: ", thresholds_csv, call. = FALSE)
  }

  species <- species %||% lnk_pipeline_species(cfg, loaded, aoi)
  if (length(species) == 0L) {
    stop("No species resolved for AOI '", aoi, "'. Either pass `species` ",
         "explicitly or ensure loaded$parameters_fresh and ",
         "loaded$wsg_species_presence cover this AOI.", call. = FALSE)
  }

  params <- fresh::frs_params(
    csv = thresholds_csv,
    rules_yaml = cfg$rules)

  # Fresh's connectivity orchestrator is not exported. Accessing the
  # internal name here keeps behavior bit-identical to the legacy
  # compare script. Tracked for export in a fresh follow-up.
  run_conn <- getFromNamespace(".frs_run_connectivity", "fresh")
  run_conn(conn,
    table = paste0(schema, ".streams"),
    habitat = paste0(schema, ".streams_habitat"),
    species = species,
    params = params,
    params_fresh = loaded$parameters_fresh,
    verbose = FALSE)

  invisible(conn)
}
