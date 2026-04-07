#' Classify crossings by biological impact severity
#'
#' Score crossings into severity levels (high/moderate/low) based on actual
#' crossing measurements rather than the binary BARRIER/PASSABLE provincial
#' classification. Thresholds are configurable per project, species, and
#' life stage via [lnk_thresholds()].
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param crossings Character. Schema-qualified crossings table (after
#'   overrides applied).
#' @param thresholds List. Output of [lnk_thresholds()]. Named list with
#'   `high`, `moderate`, `low` severity specs.
#' @param col_drop Character. Column name for outlet drop measurement.
#'   Default `"outlet_drop"` matches PSCIS field names.
#' @param col_slope Character. Column name for culvert slope.
#' @param col_length Character. Column name for culvert length.
#' @param col_severity Character. Name of the output column written to
#'   the crossings table.
#' @param to Character. If `NULL` (default), updates `crossings` in-place.
#'   If specified, writes a scored copy to a new table.
#' @param verbose Logical. Report severity distribution.
#'
#' @return The table name (invisibly) for piping.
#'
#' @details
#' **Beyond binary:** provincial `barrier_result` treats very different
#' crossings identically. A 1.2m outlet drop and a 0.3m drop with steep
#' slope are both "BARRIER" but have very different biological impact.
#'
#' **Measurement-based:** uses actual culvert dimensions, not just the
#' assessment checkbox. Scoring logic evaluates outlet drop and
#' slope * length (a composite metric for sustained velocity barriers).
#'
#' **Column-agnostic:** `col_drop = "outlet_drop"` is the PSCIS default.
#' A New Zealand user might pass `col_drop = "perch_height"`. The scoring
#' logic is identical.
#'
#' **Threshold-driven:** all cutoffs come from [lnk_thresholds()] — nothing
#' is hardcoded in the function body.
#'
#' @section Scoring logic (default thresholds):
#' \tabular{lll}{
#'   \strong{Severity} \tab \strong{Criteria} \tab \strong{Interpretation} \cr
#'   High \tab outlet_drop >= 0.6m OR slope x length >= 120 \tab Impassable at most flows \cr
#'   Moderate \tab outlet_drop >= 0.3m OR slope x length >= 60 \tab Flow-dependent, potentially passable \cr
#'   Low \tab everything else with a crossing present \tab Likely passable for target species
#' }
#'
#' @examples
#' # --- What severity scoring reveals ---
#' # Two crossings both classified as "BARRIER" by the province:
#' #   Crossing A: outlet_drop = 1.2m  -> HIGH severity (impassable)
#' #   Crossing B: outlet_drop = 0.3m  -> MODERATE severity (flow-dependent)
#' # Same provincial classification, very different biological impact.
#' # Severity scoring tells you WHERE to invest remediation dollars.
#'
#' # --- Score with default BC thresholds ---
#' \dontrun{
#' conn <- lnk_db_conn()
#'
#' # Apply overrides first, then score
#' lnk_override_apply(conn, "working.crossings",
#'   "working.overrides_modelled")
#' lnk_score_severity(conn, "working.crossings")
#' # Severity distribution:
#' #   high:     234  (impassable at most flows)
#' #   moderate: 891  (flow-dependent)
#' #   low:    2,103  (likely passable)
#' #
#' # Then produce break sources for fresh:
#' src <- lnk_break_source(conn, "working.crossings")
#' frs_habitat(conn, "BULK", break_sources = list(src))
#'
#' # --- Custom thresholds for bull trout ---
#' # Bull trout are stronger swimmers — higher drop tolerance
#' lnk_score_severity(conn, "working.crossings",
#'   thresholds = lnk_thresholds(high = list(outlet_drop = 0.8)))
#'
#' # --- Non-PSCIS data (column remapping) ---
#' lnk_score_severity(conn, "working.crossings",
#'   col_drop = "perch_height",
#'   col_slope = "pipe_gradient",
#'   col_length = "pipe_length_m")
#' }
#'
#' @export
lnk_score_severity <- function(conn,
                               crossings,
                               thresholds = lnk_thresholds(),
                               col_drop = "outlet_drop",
                               col_slope = "culvert_slope",
                               col_length = "culvert_length_m",
                               col_severity = "severity",
                               to = NULL,
                               verbose = TRUE) {
  .lnk_validate_identifier(crossings, "crossings table")
  .lnk_validate_identifier(col_drop, "col_drop")
  .lnk_validate_identifier(col_slope, "col_slope")
  .lnk_validate_identifier(col_length, "col_length")
  .lnk_validate_identifier(col_severity, "col_severity")

  if (!.lnk_table_exists(conn, crossings)) {
    stop("Crossings table not found: '", crossings, "'.", call. = FALSE)
  }

  # Determine target table
  target <- crossings
  if (!is.null(to)) {
    .lnk_validate_identifier(to, "output table")
    qt_cross <- .lnk_quote_table(conn, crossings)
    qt_to <- .lnk_quote_table(conn, to)
    .lnk_db_execute(conn, paste("DROP TABLE IF EXISTS", qt_to))
    .lnk_db_execute(conn, paste("CREATE TABLE", qt_to, "AS SELECT * FROM",
                                qt_cross))
    target <- to
  }

  qt_target <- .lnk_quote_table(conn, target)
  q_sev <- DBI::dbQuoteIdentifier(conn, col_severity)
  q_drop <- DBI::dbQuoteIdentifier(conn, col_drop)
  q_slope <- DBI::dbQuoteIdentifier(conn, col_slope)
  q_length <- DBI::dbQuoteIdentifier(conn, col_length)

  # Add severity column if it doesn't exist
  cols <- .lnk_table_columns(conn, target)
  if (!col_severity %in% cols) {
    .lnk_db_execute(conn, paste0(
      "ALTER TABLE ", qt_target, " ADD COLUMN ", q_sev, " text"
    ))
  }

  # Score in priority order: high first, then moderate, then low
  # High severity
  high_th <- thresholds$high
  if (length(high_th) > 0) {
    high_conds <- .lnk_build_severity_condition(
      high_th, q_drop, q_slope, q_length, conn
    )
    .lnk_db_execute(conn, paste0(
      "UPDATE ", qt_target, " SET ", q_sev, " = 'high'",
      " WHERE ", high_conds
    ))
  }

  # Moderate severity (only where not already scored)
  mod_th <- thresholds$moderate
  if (length(mod_th) > 0) {
    mod_conds <- .lnk_build_severity_condition(
      mod_th, q_drop, q_slope, q_length, conn
    )
    .lnk_db_execute(conn, paste0(
      "UPDATE ", qt_target, " SET ", q_sev, " = 'moderate'",
      " WHERE (", q_sev, " IS NULL) AND ", mod_conds
    ))
  }

  # Low severity: everything else still NULL
  .lnk_db_execute(conn, paste0(
    "UPDATE ", qt_target, " SET ", q_sev, " = 'low'",
    " WHERE ", q_sev, " IS NULL"
  ))

  if (verbose) {
    dist_sql <- paste0(
      "SELECT ", q_sev, ", count(*) AS n FROM ", qt_target,
      " GROUP BY ", q_sev, " ORDER BY ",
      "CASE ", q_sev,
      " WHEN 'high' THEN 1 WHEN 'moderate' THEN 2 ELSE 3 END"
    )
    dist <- DBI::dbGetQuery(conn, dist_sql)
    message("Severity distribution:")
    for (i in seq_len(nrow(dist))) {
      message("  ", format(dist[[1]][i], width = 10), ": ",
              format(dist$n[i], big.mark = ","))
    }
  }

  invisible(target)
}


#' Build SQL condition from threshold metrics
#' All values validated as finite numerics before SQL interpolation.
#' @noRd
.lnk_build_severity_condition <- function(th, q_drop, q_slope, q_length,
                                          conn = NULL) {
  conds <- character(0)

  # Validate all threshold values are safe for SQL interpolation
  for (nm in names(th)) {
    val <- th[[nm]]
    if (!is.numeric(val) || length(val) != 1 || !is.finite(val)) {
      stop("Threshold metric '", nm, "' must be a single finite number.",
           call. = FALSE)
    }
  }

  if (!is.null(th$outlet_drop)) {
    conds <- c(conds, paste0(
      "(", q_drop, " IS NOT NULL AND ", q_drop, " >= ", th$outlet_drop, ")"
    ))
  }

  if (!is.null(th$slope_length)) {
    conds <- c(conds, paste0(
      "(", q_slope, " IS NOT NULL AND ", q_length, " IS NOT NULL",
      " AND ", q_slope, " * ", q_length, " >= ", th$slope_length, ")"
    ))
  }

  # Support arbitrary metrics as direct column >= value
  known <- c("outlet_drop", "slope_length")
  extra <- setdiff(names(th), known)
  for (metric in extra) {
    .lnk_validate_identifier(metric, "threshold metric")
    q_metric <- if (!is.null(conn)) {
      DBI::dbQuoteIdentifier(conn, metric)
    } else {
      metric
    }
    conds <- c(conds, paste0(
      "(", q_metric, " >= ", th[[metric]], ")"
    ))
  }

  if (length(conds) == 0) return("FALSE")
  paste(conds, collapse = " OR ")
}
