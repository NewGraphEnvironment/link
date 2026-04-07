#' Apply user-defined scoring rules
#'
#' Compute a custom priority score beyond standard severity classification.
#' For project-specific metrics like cost-effectiveness, species-weighted
#' priority, or multi-criteria ranking.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param crossings Character. Schema-qualified crossings table.
#' @param rules Named list of scoring rule specs. Each rule is a named list
#'   with:
#'   \describe{
#'     \item{col}{Column to evaluate (required).}
#'     \item{weight}{Numeric weight (default 1).}
#'     \item{direction}{`"higher"` (default) or `"lower"` is better.}
#'     \item{sql}{Optional raw SQL expression instead of `col`. Developer
#'       API — must not contain user input.}
#'   }
#' @param col_id Character. Primary key column in the crossings table.
#'   Used for joining scores back to rows.
#' @param col_score Character. Name of output score column.
#' @param to Character. If `NULL`, updates in-place. Otherwise writes to
#'   new table.
#' @param verbose Logical. Report score distribution summary.
#'
#' @return The table name (invisibly).
#'
#' @details
#' **Composable:** severity from [lnk_score_severity()] is one input.
#' Upstream habitat value (from [lnk_habitat_upstream()]) is another.
#' Custom scoring combines them into a single priority number.
#'
#' **Weighted rank:** each rule produces a rank (1 = best), multiplied by
#' its weight, summed into a composite score. Lower composite = higher
#' priority. This avoids unit-mixing problems (you can't add metres of
#' habitat to severity categories, but you can add their ranks).
#'
#' @examples
#' # --- "Which 10 crossings should we fix first?" ---
#' \dontrun{
#' conn <- lnk_db_conn()
#'
#' # Score severity first
#' lnk_score_severity(conn, "working.crossings")
#'
#' # Then add upstream habitat (from fresh output)
#' lnk_habitat_upstream(conn, "working.crossings", "fresh.habitat")
#'
#' # Now rank: severity weight 2x, habitat weight 3x
#' lnk_score_custom(conn, "working.crossings",
#'   rules = list(
#'     severity = list(col = "severity", weight = 2,
#'       sql = "CASE severity
#'              WHEN 'high' THEN 3
#'              WHEN 'moderate' THEN 2
#'              ELSE 1 END"),
#'     habitat  = list(col = "spawning_km", weight = 3)))
#' # Priority score distribution:
#' #   min: 5.0  median: 12.3  max: 42.7
#' #
#' # Lower score = higher priority for remediation.
#' # Top 10: SELECT * FROM working.crossings
#' #         ORDER BY priority_score LIMIT 10
#' }
#'
#' @export
lnk_score_custom <- function(conn,
                             crossings,
                             rules,
                             col_id = "modelled_crossing_id",
                             col_score = "priority_score",
                             to = NULL,
                             verbose = TRUE) {
  .lnk_validate_identifier(crossings, "crossings table")
  .lnk_validate_identifier(col_id, "col_id")
  .lnk_validate_identifier(col_score, "col_score")

  if (!is.list(rules) || length(rules) == 0) {
    stop("`rules` must be a non-empty named list.", call. = FALSE)
  }
  if (is.null(names(rules)) || any(names(rules) == "")) {
    stop("`rules` must be a named list (each rule needs a name).",
         call. = FALSE)
  }

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
  q_score <- DBI::dbQuoteIdentifier(conn, col_score)

  # Add score column if missing
  cols <- .lnk_table_columns(conn, target)
  if (!col_score %in% cols) {
    .lnk_db_execute(conn, paste0(
      "ALTER TABLE ", qt_target, " ADD COLUMN ", q_score, " numeric"
    ))
  }

  # Build weighted rank expression for each rule
  rank_parts <- vapply(names(rules), function(nm) {
    rule <- rules[[nm]]
    weight <- rule$weight %||% 1
    direction <- rule$direction %||% "higher"

    if (!is.numeric(weight) || length(weight) != 1 ||
          !is.finite(weight) || weight <= 0) {
      stop("Rule '", nm, "' weight must be a positive finite number.",
           call. = FALSE)
    }

    if (!is.null(rule$sql)) {
      expr <- rule$sql
    } else if (!is.null(rule$col)) {
      .lnk_validate_identifier(rule$col, paste("rule", nm, "col"))
      expr <- DBI::dbQuoteIdentifier(conn, rule$col)
    } else {
      stop("Rule '", nm, "' must have `col` or `sql`.", call. = FALSE)
    }

    valid_dirs <- c("higher", "lower")
    if (!direction %in% valid_dirs) {
      stop("Rule '", nm, "' direction must be 'higher' or 'lower', not '",
           direction, "'.", call. = FALSE)
    }
    order_dir <- if (direction == "higher") "DESC" else "ASC"
    paste0(weight, " * RANK() OVER (ORDER BY ", expr, " ", order_dir,
           " NULLS LAST)")
  }, character(1))

  score_expr <- paste(rank_parts, collapse = " + ")

  # Join scores back via primary key — stable under concurrency.
  q_id <- DBI::dbQuoteIdentifier(conn, col_id)
  .lnk_db_execute(conn, paste0(
    "UPDATE ", qt_target, " t SET ", q_score, " = sub.score FROM (",
    "SELECT ", q_id, ", ", score_expr, " AS score FROM ", qt_target,
    ") sub WHERE t.", q_id, " = sub.", q_id
  ))

  if (verbose) {
    stats <- DBI::dbGetQuery(conn, paste0(
      "SELECT min(", q_score, ") AS min_score, ",
      "percentile_cont(0.5) WITHIN GROUP (ORDER BY ", q_score,
      ") AS median_score, ",
      "max(", q_score, ") AS max_score FROM ", qt_target
    ))
    message("Priority score distribution:")
    message("  min: ", round(stats$min_score, 1),
            "  median: ", round(stats$median_score, 1),
            "  max: ", round(stats$max_score, 1))
  }

  invisible(target)
}
