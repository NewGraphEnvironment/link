#' Persist per-WSG output into the province-wide habitat tables
#'
#' Copies the per-WSG staging tables (`<schema>.streams`,
#' `<schema>.streams_habitat`) from the working schema into the
#' persistent province-wide tables (`<persist_schema>.streams`,
#' `<persist_schema>.streams_habitat_<sp>`, one per species). Wide-per-
#' species pivot — fresh's long-format `streams_habitat` (one row per
#' segment-species) becomes one row per segment in each per-species
#' table.
#'
#' Idempotent: each call DELETEs all rows for the given AOI before
#' INSERTing the fresh ones, so re-running a WSG cleanly replaces its
#' data without affecting other WSGs.
#'
#' Column projection is driven by `cols_streams` + `cols_habitat` (named
#' vectors at the top of `R/lnk_persist_init.R`) — single source of
#' truth shared with [lnk_persist_init()].
#'
#' Call after [lnk_pipeline_connect()] in the per-WSG orchestrator,
#' before computing any rollup queries that should reflect the final
#' per-species classification.
#'
#' @param conn DBI connection.
#' @param aoi Watershed group code (e.g. `"LRDO"`).
#' @param cfg An `lnk_config` object with `cfg$pipeline$schema` set.
#' @param species Character vector of species codes to persist. Should
#'   match what `lnk_persist_init()` was called with — typically
#'   [lnk_pipeline_species()] output for the AOI.
#' @param schema Working schema (per-WSG staging). Default
#'   `paste0("working_", tolower(aoi))`.
#'
#' @return `conn` invisibly.
#' @export
lnk_pipeline_persist <- function(conn, aoi, cfg, species,
                                 schema = paste0("working_", tolower(aoi))) {
  if (!is.character(aoi) || length(aoi) != 1L || !nzchar(aoi)) {
    stop("aoi must be a single non-empty WSG code", call. = FALSE)
  }
  if (!inherits(cfg, "lnk_config")) {
    stop("cfg must be an lnk_config object", call. = FALSE)
  }
  if (!is.character(species) || length(species) == 0L) {
    stop("species must be a non-empty character vector", call. = FALSE)
  }

  tn <- .lnk_table_names(cfg)
  aoi_lit <- .lnk_quote_literal(aoi)

  # ----- streams -----
  streams_cols <- paste(names(cols_streams), collapse = ", ")
  .lnk_db_execute(conn, sprintf(
    "DELETE FROM %s WHERE watershed_group_code = %s",
    tn$streams, aoi_lit))
  .lnk_db_execute(conn, sprintf(
    "INSERT INTO %s (%s) SELECT %s FROM %s.streams",
    tn$streams, streams_cols, streams_cols, schema))

  # ----- per-species streams_habitat_<sp> -----
  # Long-format working schema has `species_code` column; persistent
  # wide-per-species tables don't. Drop species_code from the SELECT
  # projection.
  habitat_cols <- paste(names(cols_habitat), collapse = ", ")
  for (sp in species) {
    sp_table <- tn$habitat_for(sp)
    sp_lit <- .lnk_quote_literal(sp)
    .lnk_db_execute(conn, sprintf(
      "DELETE FROM %s WHERE watershed_group_code = %s",
      sp_table, aoi_lit))
    .lnk_db_execute(conn, sprintf(
      "INSERT INTO %s (%s)
       SELECT %s FROM %s.streams_habitat WHERE species_code = %s",
      sp_table, habitat_cols, habitat_cols, schema, sp_lit))
  }

  invisible(conn)
}
