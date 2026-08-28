# Downstream-state guard (link#227).
#
# `lnk_pipeline_run()` does not compute accessibility from the focal WSG alone:
# it reads the ALREADY-PERSISTED barriers of the WSGs downstream. Run a WSG
# against an empty or partial persist schema and the access query finds no
# downstream dams, concludes nothing blocks, writes `streams_access` /
# `streams_mapping_code` marking segments accessible that are in fact dammed
# off, and exits 0 — a wrong answer indistinguishable from a right one.
#
# `data-raw/wsg_run_one.R` states the DS-first precondition in its own header
# and nothing enforced it until this guard.
#
# Two design points that are load-bearing:
#
#   * **Path, not membership.** The question is not "does a downstream watershed
#     group contain a blocking dam" but "is there a blocking dam on this WSG's
#     downstream flow path". The membership form over-fires badly — BULK's
#     closure holds 18 blocking dams across LSKE/KISP/KLUM, of which ~1 is
#     actually below its outlet. Tested with the measure-aware
#     `whse_basemapping.fwa_downstream()` from `fresh::frs_wsg_outlets()`.
#     This is complete, not merely cheaper: access walks downstream from every
#     segment, and every focal segment exits through the focal outlet, so the
#     out-of-WSG barriers reachable from ANY focal segment are exactly those
#     below the outlet.
#
#   * **Shared SQL, not a second copy.** The dam snap and its edit-CSV filters
#     are defined once, in `.lnk_dams_cabd_sql()` / `.lnk_dams_matched_sql()`
#     below, and consumed by BOTH this guard and `.lnk_pipeline_prep_dams()`.
#     A guard that flags dams the pipeline treats as passable trains operators
#     to reach for the override, and then it means nothing.


# ---------------------------------------------------------------------------
# Shared dam-snap SQL — single source of truth for prep_dams AND the guard
# ---------------------------------------------------------------------------

#' The `cabd` CTE body: apply the edit CSVs to a dam source.
#'
#' Parameterized on where the dams and the three edit tables come from, so the
#' pipeline can read its staged `<schema>.cabd_*` tables while the guard inlines
#' `(VALUES …)` subqueries and touches nothing.
#'
#' @param dams_expr SQL for the dam source, aliased `d`, exposing `cabd_id`,
#'   `passability_status_code` and a `geom` in BC Albers.
#' @param excl_ref,xref_ref,upd_ref SQL table references or `(VALUES …) AS t(…)`
#'   subqueries for exclusions / blue-line xref / passability updates.
#' @noRd
.lnk_dams_cabd_sql <- function(dams_expr, excl_ref, xref_ref, upd_ref) {
  sprintf(
    "SELECT d.cabd_id::text  AS dam_id,
            blk.blue_line_key,
            d.geom,
            d.dam_name_en, d.height_m, d.owner, d.dam_use,
            d.operating_status,
            COALESCE(u.passability_status_code,
                     d.passability_status_code) AS passability_status_code
     FROM %s d
     LEFT OUTER JOIN %s x ON d.cabd_id = x.cabd_id
     LEFT OUTER JOIN %s blk ON d.cabd_id = blk.cabd_id
     LEFT OUTER JOIN %s u ON d.cabd_id = u.cabd_id
     WHERE x.cabd_id IS NULL",
    dams_expr, excl_ref, xref_ref, upd_ref)
}


#' The `matched` CTE body: snap dams to the FWA network.
#'
#' The 65 m lateral nearest-stream snap. This is the most delicate SQL in the
#' package and the whole reason the guard shares rather than copies: a guard
#' that snapped differently would flag dams the pipeline never models.
#'
#' Reads the `cabd` CTE, so both callers must define that first.
#'
#' @noRd
.lnk_dams_matched_sql <- function() {
  "SELECT DISTINCT ON (c.dam_id)
          c.dam_id,
          str.linear_feature_id,
          str.blue_line_key,
          str.wscode_ltree,
          str.localcode_ltree,
          str.watershed_group_code,
          ST_Distance(str.geom, c.geom) AS distance_to_stream,
          ST_InterpolatePoint(str.geom, c.geom) AS downstream_route_measure,
          c.dam_name_en, c.height_m, c.owner, c.dam_use,
          c.operating_status, c.passability_status_code,
          str.geom AS line_geom
   FROM cabd c
   CROSS JOIN LATERAL (
     SELECT linear_feature_id, blue_line_key, wscode_ltree, localcode_ltree,
            watershed_group_code, geom
     FROM whse_basemapping.fwa_stream_networks_sp str
     WHERE str.localcode_ltree IS NOT NULL
       AND NOT str.wscode_ltree <@ '999'::ltree
       AND (
         (c.blue_line_key IS NULL)
         OR (c.blue_line_key = str.blue_line_key)
       )
     ORDER BY str.geom <-> c.geom
     LIMIT 1
   ) str
   WHERE ST_Distance(str.geom, c.geom) <= 65
   ORDER BY c.dam_id, ST_Distance(str.geom, c.geom), str.linear_feature_id"
}


#' Inline `(VALUES …)` fragments for the three edit CSVs.
#'
#' Lets the guard apply exactly the pipeline's exclusions / xref / passability
#' overrides without staging tables — the same VALUES-list pattern fresh 0.33.0
#' uses to retire `public.wsg_outlet`.
#'
#' An absent or empty CSV yields a typed single-NULL-row sentinel so the LEFT
#' JOIN shape survives (a bare `VALUES` with no rows is a syntax error, and an
#' untyped NULL makes Postgres reject the join predicate).
#'
#' @return named list of SQL strings: `excl`, `xref`, `upd`.
#' @noRd
.lnk_dams_edit_values_sql <- function(conn, loaded) {
  lit <- function(x) {
    if (is.na(x) || !nzchar(as.character(x))) {
      return("NULL")
    }
    as.character(DBI::dbQuoteLiteral(conn, as.character(x)))
  }
  int_lit <- function(x) {
    x <- suppressWarnings(as.integer(x))
    if (is.na(x)) "NULL" else as.character(x)
  }

  build <- function(key, cols, casts, coercers) {
    df <- loaded[[key]]
    if (is.null(df) || nrow(df) == 0L || !all(cols %in% names(df))) {
      row <- paste(sprintf("NULL::%s", casts), collapse = ", ")
      return(sprintf("(VALUES (%s)) AS t(%s)", row, paste(cols, collapse = ", ")))
    }
    rows <- vapply(seq_len(nrow(df)), function(i) {
      vals <- vapply(seq_along(cols), function(j) {
        coercers[[j]](df[[cols[j]]][i])
      }, character(1))
      paste0("(", paste(vals, collapse = ", "), ")")
    }, character(1))
    # Cast the first row so the VALUES list has determinate column types.
    first <- vapply(seq_along(cols), function(j) {
      v <- coercers[[j]](df[[cols[j]]][1L])
      sprintf("%s::%s", v, casts[j])
    }, character(1))
    rows[1] <- paste0("(", paste(first, collapse = ", "), ")")
    sprintf("(VALUES %s) AS t(%s)",
            paste(rows, collapse = ", "), paste(cols, collapse = ", "))
  }

  list(
    excl = build("cabd_exclusions", "cabd_id", "text", list(lit)),
    xref = build("cabd_blkey_xref", c("cabd_id", "blue_line_key"),
                 c("text", "integer"), list(lit, int_lit)),
    upd  = build("cabd_passability_status_updates",
                 c("cabd_id", "passability_status_code"),
                 c("text", "integer"), list(lit, int_lit))
  )
}
