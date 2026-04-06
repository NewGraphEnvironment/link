#' Load override CSVs into a database table
#'
#' Read one or more correction CSVs, validate their structure, and write
#' them to a PostgreSQL table. This is step one of the override pipeline:
#' **load** -> [lnk_override_validate()] -> [lnk_override_apply()].
#'
#' Override CSVs represent hand-reviewed crossing corrections accumulated
#' across field seasons and imagery review. Each row says "this crossing's
#' attribute should be changed to this value."
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param csv Character. Path to a CSV file, or a vector of paths to load
#'   multiple files into the same table (e.g., one per field season).
#' @param to Character. Schema-qualified destination table name
#'   (e.g., `"working.overrides_modelled"`).
#' @param cols_id Character. Column(s) used as crossing identifier.
#'   System-agnostic — could be `"stream_crossing_id"`,
#'   `"chris_culvert_id"`, or any ID your system uses.
#' @param cols_required Character vector. Columns that must exist in every
#'   CSV. Fails fast with an informative error naming the missing column and
#'   file. `cols_id` is always required and does not need to be repeated here.
#' @param cols_provenance Character vector. Provenance columns to track who
#'   reviewed what and when. Kept when present in the CSV, silently skipped
#'   when absent. Set to `NULL` to disable provenance tracking.
#' @param overwrite Logical. If `TRUE` (default), drop and recreate the
#'   table. If `FALSE`, append to an existing table.
#'
#' @return The destination table name (invisibly), for piping into
#'   [lnk_override_validate()] or [lnk_override_apply()].
#'
#' @details
#' **Fail fast:** structure is validated before any data is written. Missing
#' required columns produce a clear error naming the column and file path.
#'
#' **Multi-file load:** pass a vector of CSV paths to combine overrides from
#' different sources (field seasons, watersheds, reviewers). The first file
#' creates the table; subsequent files append.
#'
#' **Provenance is optional:** teams with mature QA processes track
#' `reviewer`, `review_date`, and `source`. New projects can start without
#' these columns and add them later.
#'
#' @examples
#' # --- What does an override CSV look like? ---
#' csv_path <- system.file("extdata", "overrides_example.csv", package = "link")
#' overrides <- read.csv(csv_path)
#' print(overrides)
#' #   modelled_crossing_id barrier_result_code  reviewer review_date        source
#' # 1                 1001            PASSABLE  J. Smith  2025-08-15 imagery review
#' # 2                 1002             BARRIER  J. Smith  2025-08-15 imagery review
#' # 3                 1003                NONE A. Irvine  2025-09-20   field visit
#' # ...
#' # Each row corrects one crossing. The reviewer and date tell you
#' # who made the call and when — your audit trail.
#'
#' # --- Load into database (the typical workflow) ---
#' \dontrun{
#' conn <- lnk_db_conn()
#'
#' # Single file — most common case
#' lnk_override_load(conn,
#'   csv  = "data/overrides/modelled_xings_fixes.csv",
#'   to   = "working.overrides_modelled",
#'   cols_required = c("barrier_result_code"))
#'
#' # Multiple files from different field seasons
#' lnk_override_load(conn,
#'   csv  = c("data/overrides/2024_field.csv",
#'            "data/overrides/2025_field.csv"),
#'   to   = "working.overrides_modelled")
#'
#' # Then validate and apply:
#' lnk_override_validate(conn, "working.overrides_modelled",
#'   "working.crossings")
#' lnk_override_apply(conn, "working.crossings",
#'   "working.overrides_modelled")
#' }
#'
#' @export
lnk_override_load <- function(conn,
                              csv,
                              to,
                              cols_id = "modelled_crossing_id",
                              cols_required = NULL,
                              cols_provenance = c("reviewer",
                                                  "review_date",
                                                  "source"),
                              overwrite = TRUE) {
  if (!is.character(csv) || length(csv) == 0) {
    stop("`csv` must be a character vector of file paths.", call. = FALSE)
  }

  missing_files <- csv[!file.exists(csv)]
  if (length(missing_files) > 0) {
    stop(
      "Override CSV file(s) not found:\n",
      paste("  -", missing_files, collapse = "\n"),
      call. = FALSE
    )
  }

  .lnk_validate_identifier(to, "destination table")

  all_required <- unique(c(cols_id, cols_required))

  # Phase 1: Read and validate ALL CSVs before touching the database.
  # Prevents partial loads when file 2 of 3 fails validation.
  data_list <- list()
  for (i in seq_along(csv)) {
    path <- csv[i]
    data <- utils::read.csv(path, stringsAsFactors = FALSE)

    if (nrow(data) == 0) {
      warning("Override CSV is empty (header only): '", path, "'.",
              call. = FALSE)
      next
    }

    missing_cols <- setdiff(all_required, names(data))
    if (length(missing_cols) > 0) {
      stop(
        "Override CSV '", basename(path), "' is missing required columns:\n",
        paste("  -", missing_cols, collapse = "\n"), "\n",
        "Columns found: ", paste(names(data), collapse = ", "),
        call. = FALSE
      )
    }

    if (!is.null(cols_provenance) && i == 1) {
      missing_prov <- setdiff(cols_provenance, names(data))
      if (length(missing_prov) > 0) {
        message(
          "Note: provenance columns not found in CSV (this is OK): ",
          paste(missing_prov, collapse = ", ")
        )
      }
    }

    data_list[[length(data_list) + 1]] <- data
  }

  if (length(data_list) == 0) {
    stop("All CSV files were empty -- no overrides to load.", call. = FALSE)
  }

  # Phase 2: Write validated data to database
  parts <- .lnk_parse_table(to)
  tbl_id <- DBI::Id(schema = parts$schema, table = parts$table)

  for (i in seq_along(data_list)) {
    if (i == 1) {
      DBI::dbWriteTable(conn, tbl_id, data_list[[i]], overwrite = overwrite)
    } else {
      DBI::dbWriteTable(conn, tbl_id, data_list[[i]], append = TRUE)
    }
  }

  invisible(to)
}
