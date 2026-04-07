#' Score crossings
#'
#' Classify crossings by severity or rank them by weighted criteria.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param crossings Character. Schema-qualified crossings table.
#' @param method Character. `"severity"` for biological impact
#'   classification (high/moderate/low), or `"rank"` for weighted
#'   multi-criteria ranking.
#' @param thresholds List. For `method = "severity"`. Output of
#'   [lnk_thresholds()].
#' @param col_drop,col_slope,col_length Character. Column names for
#'   `method = "severity"`. Defaults match PSCIS field names.
#' @param col_severity Character. Output column name for severity.
#' @param rules Named list. For `method = "rank"`. Each rule has
#'   `col` or `sql`, optional `weight` and `direction`.
#' @param col_id Character. Primary key for `method = "rank"`.
#' @param col_score Character. Output column name for rank score.
#' @param to Character. If `NULL`, updates in-place. Otherwise copies.
#' @param verbose Logical. Report distribution.
#'
#' @return The table name (invisibly).
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#'
#' # Severity classification
#' lnk_score(conn, "working.crossings", method = "severity")
#'
#' # Custom thresholds
#' lnk_score(conn, "working.crossings", method = "severity",
#'   thresholds = lnk_thresholds(high = list(outlet_drop = 0.8)))
#'
#' # Weighted ranking
#' lnk_score(conn, "working.crossings", method = "rank",
#'   rules = list(
#'     habitat = list(col = "spawning_km", weight = 3),
#'     severity = list(sql = "CASE severity
#'       WHEN 'high' THEN 3 WHEN 'moderate' THEN 2 ELSE 1 END",
#'       weight = 2)))
#' }
#'
#' @export
lnk_score <- function(conn,
                       crossings,
                       method = c("severity", "rank"),
                       thresholds = lnk_thresholds(),
                       col_drop = "outlet_drop",
                       col_slope = "culvert_slope",
                       col_length = "culvert_length_m",
                       col_severity = "severity",
                       rules = NULL,
                       col_id = "modelled_crossing_id",
                       col_score = "priority_score",
                       to = NULL,
                       verbose = TRUE) {
  method <- match.arg(method)

  if (method == "severity") {
    .lnk_score_severity(conn, crossings, thresholds,
                        col_drop, col_slope, col_length,
                        col_severity, to, verbose)
  } else {
    .lnk_score_rank(conn, crossings, rules, col_id,
                    col_score, to, verbose)
  }
}


#' @noRd
.lnk_score_severity <- function(conn, crossings, thresholds,
                                 col_drop, col_slope, col_length,
                                 col_severity, to, verbose) {
  .lnk_validate_identifier(crossings, "crossings table")
  .lnk_validate_identifier(col_drop, "col_drop")
  .lnk_validate_identifier(col_slope, "col_slope")
  .lnk_validate_identifier(col_length, "col_length")
  .lnk_validate_identifier(col_severity, "col_severity")

  if (!.lnk_table_exists(conn, crossings)) {
    stop("Crossings table not found: '", crossings, "'.", call. = FALSE)
  }

  target <- crossings
  if (!is.null(to)) {
    .lnk_validate_identifier(to, "output table")
    qt_cross <- .lnk_quote_table(conn, crossings)
    qt_to <- .lnk_quote_table(conn, to)
    .lnk_db_execute(conn, paste("DROP TABLE IF EXISTS", qt_to))
    .lnk_db_execute(conn, paste("CREATE TABLE", qt_to,
                                "AS SELECT * FROM", qt_cross))
    target <- to
  }

  qt_target <- .lnk_quote_table(conn, target)
  q_sev <- DBI::dbQuoteIdentifier(conn, col_severity)
  q_drop <- DBI::dbQuoteIdentifier(conn, col_drop)
  q_slope <- DBI::dbQuoteIdentifier(conn, col_slope)
  q_length <- DBI::dbQuoteIdentifier(conn, col_length)

  cols <- .lnk_table_columns(conn, target)
  if (!col_severity %in% cols) {
    .lnk_db_execute(conn, paste0(
      "ALTER TABLE ", qt_target, " ADD COLUMN ", q_sev, " text"
    ))
  }

  # High
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

  # Moderate
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

  # Low
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


#' @noRd
.lnk_score_rank <- function(conn, crossings, rules, col_id,
                             col_score, to, verbose) {
  .lnk_validate_identifier(crossings, "crossings table")
  .lnk_validate_identifier(col_id, "col_id")
  .lnk_validate_identifier(col_score, "col_score")

  if (!is.list(rules) || length(rules) == 0) {
    stop("`rules` must be a non-empty named list.", call. = FALSE)
  }
  if (is.null(names(rules)) || any(names(rules) == "")) {
    stop("`rules` must be a named list.", call. = FALSE)
  }

  if (!.lnk_table_exists(conn, crossings)) {
    stop("Crossings table not found: '", crossings, "'.", call. = FALSE)
  }

  target <- crossings
  if (!is.null(to)) {
    .lnk_validate_identifier(to, "output table")
    qt_cross <- .lnk_quote_table(conn, crossings)
    qt_to <- .lnk_quote_table(conn, to)
    .lnk_db_execute(conn, paste("DROP TABLE IF EXISTS", qt_to))
    .lnk_db_execute(conn, paste("CREATE TABLE", qt_to,
                                "AS SELECT * FROM", qt_cross))
    target <- to
  }

  qt_target <- .lnk_quote_table(conn, target)
  q_score <- DBI::dbQuoteIdentifier(conn, col_score)

  cols <- .lnk_table_columns(conn, target)
  if (!col_score %in% cols) {
    .lnk_db_execute(conn, paste0(
      "ALTER TABLE ", qt_target, " ADD COLUMN ", q_score, " numeric"
    ))
  }

  rank_parts <- vapply(names(rules), function(nm) {
    rule <- rules[[nm]]
    weight <- rule$weight %||% 1
    direction <- rule$direction %||% "higher"

    if (!is.numeric(weight) || length(weight) != 1 ||
          !is.finite(weight) || weight <= 0) {
      stop("Rule '", nm, "' weight must be a positive finite number.",
           call. = FALSE)
    }
    valid_dirs <- c("higher", "lower")
    if (!direction %in% valid_dirs) {
      stop("Rule '", nm, "' direction must be 'higher' or 'lower'.",
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

    order_dir <- if (direction == "higher") "DESC" else "ASC"
    paste0(weight, " * RANK() OVER (ORDER BY ", expr, " ", order_dir,
           " NULLS LAST)")
  }, character(1))

  score_expr <- paste(rank_parts, collapse = " + ")

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
