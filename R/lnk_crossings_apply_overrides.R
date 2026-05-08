#' Apply user_pscis_barrier_status + user_modelled_crossing_fixes overrides
#'
#' Internal helper for [lnk_pipeline_crossings()]. After
#' [.lnk_crossings_union()] builds `<schema>.crossings` from primitives,
#' this applies the two user-override CSV families that
#' [lnk_pipeline_load()] has already staged as `<schema>.pscis_fixes` +
#' `<schema>.crossing_fixes`.
#'
#' Mirrors the same row-level effects as the existing override path in
#' [lnk_pipeline_load()] when crossings come from `fresh::extdata/crossings.csv`,
#' just routed against the primitives-build crossings table instead.
#'
#' @param conn A DBI connection.
#' @param schema Working schema. Must contain `<schema>.crossings`
#'   (output of `.lnk_crossings_union()`). Optionally
#'   `<schema>.pscis_fixes` and/or `<schema>.crossing_fixes` — both treated
#'   as no-ops if absent.
#'
#' @return `invisible(NULL)`. Side effect: UPDATEs `barrier_status` on
#'   matching rows of `<schema>.crossings`.
#'
#' @details
#' **PSCIS override** (`<schema>.pscis_fixes`):
#' - JOIN on `aggregated_crossings_id` (PSCIS rows have id =
#'   `stream_crossing_id::text` direct — same as pscis_fixes).
#' - SET `barrier_status` from `pscis_fixes.barrier_status`.
#'
#' **Modelled crossing fix** (`<schema>.crossing_fixes`):
#' - `crossing_fixes.aggregated_crossings_id` is the un-offset
#'   `modelled_crossing_id` (per [lnk_pipeline_load()]'s rename).
#'   Our crossings table offsets modelled IDs by +1e9, so the join
#'   reconstructs: `c.aggregated_crossings_id = (cf.aggregated_crossings_id::bigint + 1000000000)::text`.
#' - Mirrors bcfp: when `structure IN ('NONE', 'OBS')`, the crossing is
#'   PASSABLE. Otherwise (CBS/etc.), no change.
#'
#' @keywords internal
#' @noRd
.lnk_crossings_apply_overrides <- function(conn, schema) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(schema), length(schema) == 1L, nzchar(schema)
  )

  s <- DBI::dbQuoteIdentifier(conn, schema)

  has_table <- function(tbl) {
    res <- DBI::dbGetQuery(conn, sprintf(
      "SELECT EXISTS (
         SELECT 1 FROM information_schema.tables
         WHERE table_schema = %s AND table_name = %s
       ) AS present;",
      DBI::dbQuoteString(conn, schema),
      DBI::dbQuoteString(conn, tbl)
    ))
    isTRUE(res$present)
  }

  if (has_table("pscis_fixes")) {
    pscis_sql <- sprintf("
      UPDATE %s.crossings c
      SET barrier_status = pf.barrier_status
      FROM %s.pscis_fixes pf
      WHERE c.crossing_source = 'PSCIS'
        AND c.aggregated_crossings_id = pf.aggregated_crossings_id;
      ", s, s)
    DBI::dbExecute(conn, pscis_sql)
  }

  if (has_table("crossing_fixes")) {
    modelled_sql <- sprintf("
      UPDATE %s.crossings c
      SET barrier_status = 'PASSABLE'
      FROM %s.crossing_fixes cf
      WHERE c.crossing_source = 'MODELLED_CROSSINGS'
        AND c.aggregated_crossings_id =
            (cf.aggregated_crossings_id::bigint + 1000000000)::text
        AND cf.structure IN ('NONE', 'OBS');
      ", s, s)
    DBI::dbExecute(conn, modelled_sql)
  }

  invisible(NULL)
}
