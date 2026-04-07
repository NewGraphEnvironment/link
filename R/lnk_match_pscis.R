#' Match PSCIS assessments to modelled crossings
#'
#' Convenience wrapper around [lnk_match_sources()] with BC PSCIS defaults.
#' Optionally applies a hand-curated cross-reference CSV first — these
#' known matches take priority over spatial matching.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param crossings Character. Modelled crossings table.
#' @param pscis Character. PSCIS assessment table.
#' @param xref_csv Character. Optional path to a CSV of known
#'   PSCIS-to-modelled matches (GPS error corrections from field work).
#'   Must have columns `stream_crossing_id` and `modelled_crossing_id`.
#'   Applied first; remaining unmatched records go through spatial matching.
#' @param distance Numeric. Maximum network distance (metres) for spatial
#'   matching.
#' @param to Character. Output table name.
#' @param verbose Logical. Report match statistics.
#'
#' @return The output table name (invisibly).
#'
#' @details
#' **Why matching matters:** PSCIS assessments have field measurements
#' (outlet drop, culvert slope, channel width). Modelled crossings have
#' precise network position (blue_line_key, downstream_route_measure).
#' Matching links the measurements to the network so [lnk_score_severity()]
#' can classify crossings using real data.
#'
#' **xref CSV priority:** the most valuable part of this function.
#' Hand-curated matches from field work represent thousands of hours of
#' GPS correction. When provided, these override spatial matching — if a
#' PSCIS crossing is in the xref, it won't be re-matched spatially.
#'
#' @examples
#' # --- Zero-config for BC ---
#' \dontrun{
#' conn <- lnk_db_conn()
#'
#' # Default tables — just works
#' lnk_match_pscis(conn)
#' # Matched 4,231 pairs: PSCIS <-> modelled within 100m
#' #
#' # Now your crossings table has both stream_crossing_id AND
#' # modelled_crossing_id — the bridge between field data and network.
#'
#' # With hand-curated corrections from field work
#' lnk_match_pscis(conn,
#'   xref_csv = "data/overrides/pscis_modelled_xref.csv")
#' # Applied 892 known matches from xref
#' # Matched 3,339 additional pairs spatially
#' # Total: 4,231 matches
#'
#' # Then score using the linked measurements
#' lnk_score_severity(conn, "working.crossings")
#' }
#'
#' @export
lnk_match_pscis <- function(conn,
                            crossings = "bcfishpass.modelled_stream_crossings",
                            pscis = "whse_fish.pscis_assessment_svw",
                            xref_csv = NULL,
                            distance = 100,
                            to = "working.matched_pscis",
                            verbose = TRUE) {
  .lnk_validate_identifier(to, "output table")

  # Load xref first if provided
  if (!is.null(xref_csv)) {
    if (!file.exists(xref_csv)) {
      stop("xref CSV not found: '", xref_csv, "'.", call. = FALSE)
    }

    xref <- utils::read.csv(xref_csv, stringsAsFactors = FALSE)
    required <- c("stream_crossing_id", "modelled_crossing_id")
    missing <- setdiff(required, names(xref))
    if (length(missing) > 0) {
      stop(
        "xref CSV missing required columns: ",
        paste(missing, collapse = ", "),
        call. = FALSE
      )
    }

    # Write xref to output table
    parts <- .lnk_parse_table(to)
    tbl_id <- DBI::Id(schema = parts$schema, table = parts$table)

    xref_out <- data.frame(
      source_a = pscis,
      id_a = as.character(xref$stream_crossing_id),
      source_b = crossings,
      id_b = as.character(xref$modelled_crossing_id),
      distance_m = 0,
      stringsAsFactors = FALSE
    )
    DBI::dbWriteTable(conn, tbl_id, xref_out, overwrite = TRUE)

    if (verbose) {
      message("Applied ", nrow(xref), " known matches from xref CSV")
    }

    # Build WHERE clauses to exclude already-matched IDs
    qt_to <- .lnk_quote_table(conn, to)
    pscis_exclude <- paste0(
      "stream_crossing_id::text NOT IN ",
      "(SELECT id_a FROM ", qt_to, ")"
    )
    cross_exclude <- paste0(
      "modelled_crossing_id::text NOT IN ",
      "(SELECT id_b FROM ", qt_to, ")"
    )

    # Spatial match remaining records (append to output)
    srcs <- list(
      list(table = pscis, col_id = "stream_crossing_id",
           where = pscis_exclude),
      list(table = crossings, col_id = "modelled_crossing_id",
           where = cross_exclude)
    )
    lnk_match_sources(
      conn, sources = srcs, distance = distance,
      to = to, overwrite = FALSE, verbose = verbose
    )
  } else {
    # No xref — pure spatial match
    srcs <- list(
      list(table = pscis, col_id = "stream_crossing_id"),
      list(table = crossings, col_id = "modelled_crossing_id")
    )
    lnk_match_sources(
      conn, sources = srcs, distance = distance,
      to = to, overwrite = TRUE, verbose = verbose
    )
  }

  invisible(to)
}
