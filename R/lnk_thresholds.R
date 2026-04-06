#' Load configurable severity scoring thresholds
#'
#' Build a named list of severity thresholds for crossing scoring. Ships
#' sensible BC fish passage defaults. Override via CSV or inline arguments
#' for project-specific tuning.
#'
#' @param csv Path to a CSV file with columns `severity`, `metric`, `value`.
#'   When provided, CSV values override in-code defaults. Use
#'   `system.file("extdata", "thresholds_default.csv", package = "link")` to
#'   see the expected format.
#' @param high Named list of metric thresholds for high severity. Merged with
#'   CSV values (inline wins on conflict).
#' @param moderate Named list of metric thresholds for moderate severity.
#' @param low Named list of metric thresholds for low severity.
#'
#' @return A named list with elements `high`, `moderate`, `low`, each
#'   containing a named list of metric thresholds (numeric values keyed by
#'   metric name).
#'
#' @details
#' Thresholds control how [lnk_score_severity()] classifies crossings. The
#' default values reflect BC provincial fish passage assessment criteria:
#'
#' \describe{
#'   \item{High severity}{outlet_drop >= 0.6m or slope_length >= 120 —
#'     impassable to most species at most flows}
#'   \item{Moderate severity}{outlet_drop >= 0.3m or slope_length >= 60 —
#'     flow-dependent, potentially passable at migration flows}
#'   \item{Low severity}{everything else with a crossing present}
#' }
#'
#' **System-agnostic:** metric names are user-defined strings, not hardcoded
#' to any provincial data system. A New Zealand user might define
#' `high = list(perch_height = 0.5, pipe_gradient = 0.05)`.
#'
#' **Merge order:** code defaults < CSV values < inline arguments. This lets
#' you ship a project CSV but still tweak one threshold inline.
#'
#' @examples
#' # Default BC thresholds — zero config
#' th <- lnk_thresholds()
#' th$high$outlet_drop
#' # [1] 0.6
#'
#' # Override from bundled CSV (same result, shows the format)
#' csv_path <- system.file("extdata", "thresholds_default.csv", package = "link")
#' th_csv <- lnk_thresholds(csv = csv_path)
#' identical(th, th_csv)
#'
#' # Project-specific: bull trout tolerate higher drops
#' th_bt <- lnk_thresholds(high = list(outlet_drop = 0.8))
#' th_bt$high$outlet_drop
#' # [1] 0.8 — inline override wins
#'
#' # How thresholds plug into scoring (the integration point)
#' \dontrun{
#' conn <- lnk_db_conn()
#' lnk_score_severity(conn, "working.crossings",
#'   thresholds = lnk_thresholds(high = list(outlet_drop = 0.8)))
#' }
#'
#' @export
lnk_thresholds <- function(csv = NULL,
                           high = NULL,
                           moderate = NULL,
                           low = NULL) {
  # Code defaults
  defaults <- list(
    high = list(outlet_drop = 0.6, slope_length = 120),
    moderate = list(outlet_drop = 0.3, slope_length = 60),
    low = list()
  )

  # CSV layer
  if (!is.null(csv)) {
    if (!file.exists(csv)) {
      stop("Thresholds CSV not found: '", csv, "'.", call. = FALSE)
    }
    csv_data <- utils::read.csv(csv, stringsAsFactors = FALSE)

    required_cols <- c("severity", "metric", "value")
    missing <- setdiff(required_cols, names(csv_data))
    if (length(missing) > 0) {
      stop(
        "Thresholds CSV missing required columns: ",
        paste(missing, collapse = ", "), ".\n",
        "Expected columns: severity, metric, value.",
        call. = FALSE
      )
    }

    if (nrow(csv_data) == 0) {
      return(
        Recall(csv = NULL, high = high, moderate = moderate, low = low)
      )
    }

    valid_severities <- c("high", "moderate", "low")
    bad_sev <- setdiff(unique(csv_data$severity), valid_severities)
    if (length(bad_sev) > 0) {
      stop(
        "Thresholds CSV contains invalid severity levels: ",
        paste(bad_sev, collapse = ", "), ".\n",
        "Valid levels: high, moderate, low.",
        call. = FALSE
      )
    }

    if (anyNA(csv_data$value) || !is.numeric(csv_data$value)) {
      stop("Thresholds CSV 'value' column must be numeric with no NAs.",
           call. = FALSE)
    }

    for (sev in valid_severities) {
      rows <- csv_data[csv_data$severity == sev, , drop = FALSE]
      if (nrow(rows) > 0) {
        csv_list <- stats::setNames(as.list(rows$value), rows$metric)
        defaults[[sev]] <- .lnk_merge_lists(defaults[[sev]], csv_list)
      }
    }
  }

  # Inline argument layer (wins over CSV and code defaults)
  if (!is.null(high)) {
    .lnk_validate_threshold_list(high, "high")
    defaults$high <- .lnk_merge_lists(defaults$high, high)
  }
  if (!is.null(moderate)) {
    .lnk_validate_threshold_list(moderate, "moderate")
    defaults$moderate <- .lnk_merge_lists(defaults$moderate, moderate)
  }
  if (!is.null(low)) {
    .lnk_validate_threshold_list(low, "low")
    defaults$low <- .lnk_merge_lists(defaults$low, low)
  }

  defaults
}


#' Merge two named lists (b overwrites a on conflict)
#' @noRd
.lnk_merge_lists <- function(a, b) {
  for (nm in names(b)) {
    a[[nm]] <- b[[nm]]
  }
  a
}


#' Validate a threshold list argument
#' @noRd
.lnk_validate_threshold_list <- function(x, label) {
  if (!is.list(x)) {
    stop("`", label, "` must be a named list, not ", class(x)[1], ".",
         call. = FALSE)
  }
  if (length(x) > 0 && is.null(names(x))) {
    stop("`", label, "` must be a named list (metric names as names).",
         call. = FALSE)
  }
  non_numeric <- !vapply(x, is.numeric, logical(1))
  if (any(non_numeric)) {
    stop(
      "`", label, "` contains non-numeric values for metrics: ",
      paste(names(x)[non_numeric], collapse = ", "), ".",
      call. = FALSE
    )
  }
  non_finite <- !vapply(x, function(v) all(is.finite(v)), logical(1))
  if (any(non_finite)) {
    stop(
      "`", label, "` contains non-finite values (NaN/Inf) for metrics: ",
      paste(names(x)[non_finite], collapse = ", "), ".",
      call. = FALSE
    )
  }
  invisible(x)
}
