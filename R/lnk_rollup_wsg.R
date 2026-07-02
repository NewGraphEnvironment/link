#' Roll up per-(WSG, species) length metrics from persisted state
#'
#' Reusable, predicate-driven roll-up over link's persisted per-species
#' tables. For each species it joins `<schema>.streams` (length + edge
#' type) to `<schema>.streams_access` (per-species `access_<sp>` code)
#' and `<schema>.streams_habitat_<sp>` (spawning / rearing flags) on the
#' full PK `(id_segment, watershed_group_code)` (#203), exposes the
#' three species-varying inputs under **generic aliases** — `access`
#' (int: -9 absent / 0 blocked / 1 modelled / 2 observed), `spawning`,
#' `rearing` (bool) — then aggregates by `(watershed_group_code,
#' species_code)`.
#'
#' Because the per-species columns are aliased to fixed names, the
#' `metrics` SQL is written **once**, species-agnostic — mirroring
#' `fresh::frs_aggregate()`'s `metrics` / `where` shape. Adding a species
#' is a `species` vector edit, not a query edit.
#'
#' This is a **flat per-WSG `GROUP BY`** — it sums whole-WSG length by
#' `(watershed_group_code, species_code)`. It is distinct from
#' [lnk_aggregate()] / [fresh::frs_aggregate()], which roll habitat up the
#' network *upstream of individual crossings* (point-based traversal). Use
#' this for WSG totals; use those for per-crossing upstream summaries.
#'
#' `accessible_km` sums `access IN (1, 2)` — link's per-species access
#' model on `streams_access`, the number validated against the
#' tunnel-free bcfp reference in `data-raw/accessible_km_proof_co.R`
#' (coho, 19/20 WSGs within +/-5%). It deliberately does **not** use the
#' `accessible` boolean on `streams_habitat_<sp>`, which carries
#' different (pre-gating) semantics and diverges from the access model
#' (MORR coho: 3424 km vs the validated 3330 km).
#'
#' @param conn A [DBI::DBIConnection-class] object (from [lnk_db_conn()]).
#' @param aoi Watershed group code (e.g. `"MORR"`). Uppercase 3-5 letters.
#' @param species Character vector of species codes (e.g. `c("CO","BT")`).
#'   Each must name existing `<schema>.streams_habitat_<sp>` and
#'   `<schema>.streams_access.access_<sp>`. Restricted to alpha
#'   characters — interpolated into identifiers, so validated to make
#'   SQL injection structurally impossible.
#' @param schema Persist schema holding `streams`, `streams_access`,
#'   `streams_habitat_<sp>`. Default `"fresh"`. Validated against the SQL
#'   identifier whitelist.
#' @param metrics Named character vector: names are output columns,
#'   values are SQL aggregate expressions over the generic aliases
#'   `length_metre`, `access`, `spawning`, `rearing`. Default emits
#'   `accessible_km`, `spawning_km`, `rearing_km`. Raw SQL — trusted
#'   caller input, like `frs_aggregate()`.
#' @param where Character or `NULL`. Optional SQL predicate applied to the
#'   per-species rows before aggregation (aliases available). Default
#'   `NULL`.
#'
#' @return A data.frame with one row per `(wsg, species)` and one column
#'   per metric. Columns: `wsg`, `species`, then `names(metrics)`.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' # Coho accessible / spawning / rearing km for Morice, from persisted state.
#' lnk_rollup_wsg(conn, aoi = "MORR", species = "CO")
#'
#' # Custom metric: count accessible segments per species.
#' lnk_rollup_wsg(conn, aoi = "MORR", species = c("CO", "BT"),
#'   metrics = c(n_accessible = "COUNT(*) FILTER (WHERE access IN (1, 2))"))
#' }
#'
#' @family compare
#' @seealso [lnk_compare_rollup()], [lnk_aggregate()],
#'   [fresh::frs_aggregate()]
#' @export
# nolint start: indentation_linter
lnk_rollup_wsg <- function(conn, aoi, species,
                           schema = "fresh",
                           metrics = c(
                             accessible_km =
                               "round(sum(length_metre) FILTER (WHERE access IN (1, 2))::numeric / 1000, 2)", # nolint: line_length_linter
                             spawning_km =
                               "round(sum(length_metre) FILTER (WHERE spawning)::numeric / 1000, 2)", # nolint: line_length_linter
                             rearing_km =
                               "round(sum(length_metre) FILTER (WHERE rearing)::numeric / 1000, 2)" # nolint: line_length_linter
                           ),
                           where = NULL) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(aoi), length(aoi) == 1L, nzchar(aoi),
    grepl("^[A-Z]{3,5}$", aoi),
    is.character(species), length(species) >= 1L, all(nzchar(species)),
    # Species suffix is interpolated into `streams_habitat_<sp>` and
    # `access_<sp>`; alpha-only makes injection structurally impossible.
    all(grepl("^[A-Za-z]+$", species)),
    is.character(schema), length(schema) == 1L,
    grepl("^[a-z_][a-z0-9_]*$", schema),
    is.character(metrics), length(metrics) >= 1L,
    !is.null(names(metrics)), all(nzchar(names(metrics))),
    is.null(where) || (is.character(where) && length(where) == 1L)
  )

  sql <- .lnk_rollup_wsg_sql(
    conn = conn, aoi = aoi, species = species,
    schema = schema, metrics = metrics, where = where)
  DBI::dbGetQuery(conn, sql)
}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

#' Build the per-(WSG, species) roll-up SQL.
#'
#' Split out from [lnk_rollup_wsg()] so the query text is unit-testable
#' without a live connection (arg validation happens in the exported fn).
#'
#' @noRd
.lnk_rollup_wsg_sql <- function(conn, aoi, species, schema, metrics, where) {
  aoi_lit <- DBI::dbQuoteLiteral(conn, aoi)

  per_species <- paste(vapply(species, function(sp) {
    sp_lit <- DBI::dbQuoteLiteral(conn, toupper(sp))
    sprintf(
      "SELECT %s AS species_code, s.watershed_group_code,
              s.length_metre, s.edge_type,
              a.access_%s AS access, h.spawning, h.rearing
         FROM %s.streams s
         JOIN %s.streams_access a
           ON s.id_segment = a.id_segment
          AND s.watershed_group_code = a.watershed_group_code
         JOIN %s.streams_habitat_%s h
           ON s.id_segment = h.id_segment
          AND s.watershed_group_code = h.watershed_group_code
        WHERE s.watershed_group_code = %s",
      sp_lit, tolower(sp),
      schema, schema, schema, tolower(sp), aoi_lit)
  }, character(1)), collapse = "\n      UNION ALL\n      ")

  cols_metric <- paste(
    sprintf("%s AS %s", unname(metrics), names(metrics)),
    collapse = ",\n         ")

  where_clause <- if (!is.null(where)) paste("\n     WHERE", where) else ""

  sprintf(
    "SELECT watershed_group_code AS wsg,
         species_code AS species,
         %s
    FROM (
      %s
    ) per_species%s
    GROUP BY watershed_group_code, species_code
    ORDER BY species_code",
    cols_metric, per_species, where_clause)
}
# nolint end: indentation_linter
