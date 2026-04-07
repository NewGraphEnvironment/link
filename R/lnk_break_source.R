#' Produce a fresh-compatible break source list
#'
#' The bridge between link and fresh. Takes scored crossings and returns
#' a list spec that plugs directly into
#' `frs_habitat(break_sources = list(...))`. Zero translation needed —
#' link scores, fresh consumes.
#'
#' @param conn A [DBI::DBIConnection-class] object (used only for
#'   table validation).
#' @param crossings Character. Schema-qualified scored crossings table
#'   (output of [lnk_score_severity()]).
#' @param label Character. Static label for all rows (mutually exclusive
#'   with `label_col`).
#' @param label_col Character. Column to read labels from (default:
#'   `"severity"` — the column [lnk_score_severity()] creates).
#' @param label_map Named character vector. Keys are link severity levels,
#'   values are fresh break labels. Default maps high -> blocked,
#'   moderate -> potential.
#' @param where Character. Optional SQL filter (e.g., only crossings in a
#'   specific watershed). Developer API — raw SQL, must not contain user
#'   input.
#'
#' @return A named list with elements `table`, `label` or `label_col`,
#'   `label_map`, and optionally `where` — exactly the format
#'   `frs_habitat()` expects.
#'
#' @details
#' **Zero-friction bridge:** the return value IS a fresh break source spec.
#' No transformation, no adapter — just pass it through.
#'
#' **`label_map` is the key abstraction:** link thinks in severity
#' (high/moderate/low). fresh thinks in access (blocked/potential/accessible).
#' The map translates between domains.
#'
#' @examples
#' # --- The link -> fresh handoff ---
#' \dontrun{
#' conn <- lnk_db_conn()
#'
#' # Step 1: Score crossings with link
#' lnk_score_severity(conn, "working.crossings")
#'
#' # Step 2: Produce break source
#' src <- lnk_break_source(conn, "working.crossings")
#' # Returns:
#' # list(table = "working.crossings",
#' #      label_col = "severity",
#' #      label_map = c(high = "blocked", moderate = "potential"))
#'
#' # Step 3: Feed to fresh — link's output is fresh's input
#' frs_habitat(conn, "BULK", break_sources = list(src))
#'
#' # --- Combine with other break sources ---
#' frs_habitat(conn, "BULK", break_sources = list(
#'   src,
#'   list(table = "working.falls", label = "blocked"),
#'   list(table = "working.dams", label = "blocked")))
#' # link scored crossings + falls + dams — all as break sources.
#'
#' # --- Custom label_map for a conservative project ---
#' # Only treat high-severity as blocked
#' src_strict <- lnk_break_source(conn, "working.crossings",
#'   label_map = c(high = "blocked"))
#'
#' # --- Static label for all crossings ---
#' src_all <- lnk_break_source(conn, "working.crossings",
#'   label = "potential", label_col = NULL)
#' # Every crossing is a potential barrier — no severity differentiation.
#' }
#'
#' @export
lnk_break_source <- function(conn,
                             crossings,
                             label = NULL,
                             label_col = "severity",
                             label_map = c(high = "blocked",
                                           moderate = "potential"),
                             where = NULL) {
  .lnk_validate_identifier(crossings, "crossings table")

  if (!.lnk_table_exists(conn, crossings)) {
    stop("Crossings table not found: '", crossings, "'.", call. = FALSE)
  }

  if (!is.null(label) && !is.null(label_col)) {
    stop("Specify `label` or `label_col`, not both.", call. = FALSE)
  }
  if (is.null(label) && is.null(label_col)) {
    stop("One of `label` or `label_col` must be provided.", call. = FALSE)
  }

  # Build the spec

  spec <- list(table = crossings)

  if (!is.null(label)) {
    if (!is.character(label) || length(label) != 1) {
      stop("`label` must be a single string.", call. = FALSE)
    }
    spec$label <- label
  }

  if (!is.null(label_col)) {
    .lnk_validate_identifier(label_col, "label_col")
    cols <- .lnk_table_columns(conn, crossings)
    if (!label_col %in% cols) {
      stop("Column '", label_col, "' not found in '", crossings,
           "'. Did you run lnk_score_severity() first?", call. = FALSE)
    }
    spec$label_col <- label_col
    if (!is.null(label_map) && length(label_map) > 0) {
      spec$label_map <- label_map
    }
  }

  if (!is.null(where)) {
    if (!is.character(where) || length(where) != 1) {
      stop("`where` must be a single string.", call. = FALSE)
    }
    spec$where <- where
  }

  spec
}
