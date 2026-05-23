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

  # ----- barriers -----
  # Unified province-wide barriers (link#152). Per-WSG slice copied
  # from working <schema>.barriers (built by lnk_barriers_unify) into
  # <persist_schema>.barriers via the same DELETE-WHERE-WSG + INSERT
  # idiom. Cross-WSG dnstr queries (e.g. PARS BT through dams in
  # PCEA/UPCE) resolve correctly once all WSGs have written their
  # slice.
  #
  # Probe for <schema>.barriers — only copy if lnk_barriers_unify has
  # produced it. Older orchestrators that don't yet call unify keep
  # the existing streams-only persistence behaviour.
  barriers_present <- nrow(DBI::dbGetQuery(conn, sprintf(
    "SELECT 1 FROM information_schema.tables
      WHERE table_schema = %s AND table_name = 'barriers'
      LIMIT 1;",
    DBI::dbQuoteString(conn, schema)
  ))) > 0L
  if (barriers_present) {
    barriers_table <- paste0(tn$schema, ".barriers")
    barriers_cols <- paste(names(cols_barriers), collapse = ", ")
    .lnk_db_execute(conn, sprintf(
      "DELETE FROM %s WHERE watershed_group_code = %s",
      barriers_table, aoi_lit))
    .lnk_db_execute(conn, sprintf(
      "INSERT INTO %s (%s) SELECT %s FROM %s.barriers",
      barriers_table, barriers_cols, barriers_cols, schema))
  }

  # ----- streams_access (link#187) -----
  # Per-segment per-species access. Working `<schema>.streams_access` is
  # built by lnk_pipeline_access; persist phase copies the per-WSG slice
  # into <persist_schema>.streams_access. Gated by presence — operators
  # who don't run the mapping_code path won't have the working table
  # and we skip cleanly.
  #
  # JOIN to working.streams for watershed_group_code: lnk_pipeline_access
  # writes scalar projection via dbWriteTable which doesn't include the
  # WSG column. Join-back is the simplest way to keep the persist
  # DELETE-WHERE-WSG idiom working without modifying lnk_pipeline_access.
  access_present <- nrow(DBI::dbGetQuery(conn, sprintf(
    "SELECT 1 FROM information_schema.tables
      WHERE table_schema = %s AND table_name = 'streams_access'
      LIMIT 1;",
    DBI::dbQuoteString(conn, schema)
  ))) > 0L
  if (access_present) {
    access_table <- paste0(tn$schema, ".streams_access")
    # MUST mirror the DDL column set in lnk_persist_init exactly:
    # base + per-source flags (#196) + per-species. Missing the source
    # flags here was the v0.40.3 bug — DDL had the columns but the INSERT
    # projection didn't populate them, so they stayed NULL and
    # lnk_pipeline_mapping_code's second token defaulted to NONE.
    access_cols_v <- c(cols_streams_access_base,
                       .lnk_cols_streams_access_source_flags(),
                       .lnk_cols_streams_access_per_sp(species))
    access_cols <- paste(names(access_cols_v), collapse = ", ")
    # SELECT projection: pull watershed_group_code from streams (JOIN),
    # everything else from streams_access (a.*-minus-id_segment).
    select_cols <- vapply(names(access_cols_v), function(col) {
      if (col == "watershed_group_code") "s.watershed_group_code"
      else if (col == "id_segment") "a.id_segment"
      else paste0("a.", col)
    }, character(1))
    select_clause <- paste(select_cols, collapse = ", ")
    .lnk_db_execute(conn, sprintf(
      "DELETE FROM %s WHERE watershed_group_code = %s",
      access_table, aoi_lit))
    .lnk_db_execute(conn, sprintf(
      "INSERT INTO %s (%s)
       SELECT %s FROM %s.streams_access a
       JOIN %s.streams s USING (id_segment)
       WHERE s.watershed_group_code = %s",
      access_table, access_cols, select_clause,
      schema, schema, aoi_lit))
  }

  # ----- streams_mapping_code (link#187) -----
  # Same JOIN-back pattern: lnk_pipeline_mapping_code's output has only
  # id_segment + mapping_code_<sp> cols; WSG comes from streams.
  mapping_present <- nrow(DBI::dbGetQuery(conn, sprintf(
    "SELECT 1 FROM information_schema.tables
      WHERE table_schema = %s AND table_name = 'streams_mapping_code'
      LIMIT 1;",
    DBI::dbQuoteString(conn, schema)
  ))) > 0L
  if (mapping_present) {
    mapping_table <- paste0(tn$schema, ".streams_mapping_code")
    mapping_cols_v <- c(cols_streams_mapping_code_base,
                        .lnk_cols_streams_mapping_code_per_sp(species))
    mapping_cols <- paste(names(mapping_cols_v), collapse = ", ")
    select_cols <- vapply(names(mapping_cols_v), function(col) {
      if (col == "watershed_group_code") "s.watershed_group_code"
      else if (col == "id_segment") "m.id_segment"
      else paste0("m.", col)
    }, character(1))
    select_clause <- paste(select_cols, collapse = ", ")
    .lnk_db_execute(conn, sprintf(
      "DELETE FROM %s WHERE watershed_group_code = %s",
      mapping_table, aoi_lit))
    .lnk_db_execute(conn, sprintf(
      "INSERT INTO %s (%s)
       SELECT %s FROM %s.streams_mapping_code m
       JOIN %s.streams s USING (id_segment)
       WHERE s.watershed_group_code = %s",
      mapping_table, mapping_cols, select_clause,
      schema, schema, aoi_lit))
  }

  invisible(conn)
}
