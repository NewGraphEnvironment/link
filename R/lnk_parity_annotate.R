#' Annotate a parity rollup against the bcfp divergence taxonomy
#'
#' Joins each row of a parity rollup (from [lnk_compare_wsg()] or the
#' `data-raw/compare_bcfishpass_wsg.R` wrapper) to the first taxonomy
#' entry whose `wsg`, `species`, `metric`, `pattern`, and (optional)
#' `diff_range` all match. Unmatched rows with `|diff_pct| >=
#' tolerance` are tagged `class = UNEXPLAINED, status =
#' NEEDS_INVESTIGATION`; smaller residuals become `class =
#' WITHIN_TOLERANCE, status = CLOSED`. Rows with `NA` diff_pct (NA ref
#' value, divide-by-zero) become `class = NOT_APPLICABLE`.
#'
#' First-match-wins: taxonomy entries are evaluated in the order they
#' appear in the YAML file. Put the most specific entries first.
#'
#' @param rollup A tibble with columns `wsg`, `species`, `habitat_type`,
#'   `link_value`, `diff_pct`, plus one of `ref_value` (library shape)
#'   or `bcfishpass_value` (data-raw wrapper shape). Both shapes pass
#'   through — the function normalizes internally.
#' @param taxonomy Path to a YAML file or a parsed list (from
#'   [yaml::read_yaml()]). When a path, the function reads it. When a
#'   parsed list, it must have an `entries` element holding the
#'   per-pattern records.
#' @param to Optional character path. When set, writes the annotated
#'   tibble to a CSV and returns it invisibly.
#' @param tolerance Numeric. Rows with `|diff_pct| < tolerance` and no
#'   taxonomy match are tagged `WITHIN_TOLERANCE` instead of
#'   `UNEXPLAINED`. Default `2` (matching the acceptance bar in #162).
#'
#' @return A tibble extending `rollup` with annotation columns
#'   `taxonomy_id`, `class`, `mechanism`, `status`, `refs`. `refs` is a
#'   semicolon-collapsed string for CSV-friendliness.
#'
#' @examples
#' \dontrun{
#' rollup <- readRDS("data-raw/logs/provincial_parity/ADMS.rds")
#' annotated <- lnk_parity_annotate(
#'   rollup,
#'   taxonomy = "research/bcfp_divergence_taxonomy.yml",
#'   to = "data-raw/logs/provincial_parity/ADMS_annotated.csv"
#' )
#'
#' # Acceptance check
#' unexplained <- annotated[annotated$class == "UNEXPLAINED" &
#'                           abs(annotated$diff_pct) >= 2, ]
#' stopifnot(nrow(unexplained) == 0L)
#' }
#'
#' @family compare
#' @seealso [lnk_compare_wsg()]
#' @export
lnk_parity_annotate <- function(rollup, taxonomy, to = NULL,
                                tolerance = 2) {
  stopifnot(
    is.data.frame(rollup),
    is.numeric(tolerance), length(tolerance) == 1L, tolerance >= 0,
    is.null(to) || (is.character(to) && length(to) == 1L)
  )

  # Normalize column name: data-raw wrapper renames ref_value ->
  # bcfishpass_value for backwards-compat with RDS consumers; the
  # library schema is ref_value. Accept either; convert to ref_value.
  if ("bcfishpass_value" %in% names(rollup) &&
      !("ref_value" %in% names(rollup))) {
    names(rollup)[names(rollup) == "bcfishpass_value"] <- "ref_value"
  }

  required <- c("wsg", "species", "habitat_type",
                "link_value", "ref_value", "diff_pct")
  missing_cols <- setdiff(required, names(rollup))
  if (length(missing_cols) > 0) {
    stop("rollup is missing required columns: ",
         paste(missing_cols, collapse = ", "), call. = FALSE)
  }

  tax <- if (is.character(taxonomy)) {
    stopifnot(length(taxonomy) == 1L, file.exists(taxonomy))
    yaml::read_yaml(taxonomy)
  } else if (is.list(taxonomy)) {
    taxonomy
  } else {
    stop("taxonomy must be a YAML file path or a parsed list",
         call. = FALSE)
  }
  if (is.null(tax$entries) || !is.list(tax$entries)) {
    stop("taxonomy must contain an `entries` list", call. = FALSE)
  }

  annotated <- tibble::as_tibble(rollup)
  annotated$taxonomy_id <- NA_character_
  annotated$class       <- NA_character_
  annotated$mechanism   <- NA_character_
  annotated$status      <- NA_character_
  annotated$refs        <- NA_character_

  for (i in seq_len(nrow(annotated))) {
    row <- annotated[i, ]
    hit <- .lnk_match_taxonomy(row, tax$entries)
    if (!is.null(hit)) {
      # Each optional-field guard prevents a hard crash if a
      # user-extended taxonomy drops one of these fields. The bundled
      # YAML populates all five but we don't enforce that at parse
      # time.
      annotated$taxonomy_id[i] <- hit$id        %||% NA_character_
      annotated$class[i]       <- hit$class     %||% NA_character_
      annotated$mechanism[i]   <- hit$mechanism %||% NA_character_
      annotated$status[i]      <- hit$status    %||% NA_character_
      annotated$refs[i]        <- paste(hit$refs %||% character(),
                                        collapse = "; ")
    } else if (is.na(row$diff_pct)) {
      annotated$class[i]  <- "NOT_APPLICABLE"
      # NA_character_ (not the literal string "NA"): empty in CSV
      # output, distinct from any taxonomy-defined status value.
      annotated$status[i] <- NA_character_
    } else if (abs(row$diff_pct) < tolerance) {
      annotated$class[i]  <- "WITHIN_TOLERANCE"
      annotated$status[i] <- "CLOSED"
    } else {
      annotated$class[i]  <- "UNEXPLAINED"
      annotated$status[i] <- "NEEDS_INVESTIGATION"
    }
  }

  if (!is.null(to)) {
    utils::write.csv(annotated, to, row.names = FALSE, na = "")
    return(invisible(annotated))
  }
  annotated
}


#' Find the first matching taxonomy entry for a rollup row
#'
#' First-match-wins: returns the first entry whose `wsg`, `species`,
#' `metric`, `pattern`, and `diff_range` all match. Returns `NULL` when
#' no entry matches.
#'
#' @noRd
.lnk_match_taxonomy <- function(row, entries) {
  for (entry in entries) {
    if (.lnk_entry_matches(row, entry)) {
      return(entry)
    }
  }
  NULL
}


#' Test whether one rollup row matches one taxonomy entry
#'
#' @noRd
.lnk_entry_matches <- function(row, entry) {
  if (!.lnk_field_matches(row$wsg, entry$wsg)) return(FALSE)
  if (!.lnk_field_matches(row$species, entry$species)) return(FALSE)
  if (!.lnk_field_matches(row$habitat_type, entry$metric)) return(FALSE)
  if (!.lnk_pattern_matches(row, entry$pattern)) return(FALSE)
  if (!is.null(entry$diff_range)) {
    if (is.na(row$diff_pct)) return(FALSE)
    if (length(entry$diff_range) != 2L) {
      stop("diff_range must have length 2 (entry: ", entry$id, ")",
           call. = FALSE)
    }
    abs_diff <- abs(row$diff_pct)
    if (abs_diff < entry$diff_range[1] || abs_diff > entry$diff_range[2]) {
      return(FALSE)
    }
  }
  TRUE
}


#' Wildcard-aware scalar/array membership test
#'
#' `spec = "*"` matches anything. `spec = NULL` (missing field) also
#' matches anything — defensive default. Otherwise `value %in% spec`.
#'
#' @noRd
.lnk_field_matches <- function(value, spec) {
  if (is.null(spec)) return(TRUE)
  if (length(spec) == 1L && identical(spec, "*")) return(TRUE)
  value %in% spec
}


#' Apply one of the four divergence patterns to a rollup row
#'
#' @noRd
.lnk_pattern_matches <- function(row, pattern) {
  if (is.null(pattern) || !is.character(pattern) || length(pattern) != 1L) {
    stop("pattern must be a single character value", call. = FALSE)
  }
  switch(
    pattern,
    "link_gt_bcfp" = !is.na(row$diff_pct) && row$diff_pct > 0,
    "link_lt_bcfp" = !is.na(row$diff_pct) && row$diff_pct < 0,
    "bcfp_only" = !is.na(row$ref_value) && row$ref_value > 0 &&
                  (is.na(row$link_value) || row$link_value == 0),
    "link_only" = !is.na(row$link_value) && row$link_value > 0 &&
                  (is.na(row$ref_value) || row$ref_value == 0),
    stop("Unknown pattern '", pattern,
         "'. Supported: link_gt_bcfp, link_lt_bcfp, bcfp_only, link_only.",
         call. = FALSE)
  )
}