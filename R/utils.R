# Internal utilities — not exported
# These are the building blocks every lnk_* function uses.

#' Null-coalescing operator
#' @noRd
`%||%` <- function(x, y) if (is.null(x)) y else x # nolint: object_name_linter.

#' Quote a literal string for SQL (doubles single-quotes)
#' @noRd
.lnk_quote_literal <- function(x) {
  if (!is.character(x) || length(x) != 1L) {
    stop("x must be a single string", call. = FALSE)
  }
  paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
}

#' Execute SQL statement with error context
#' @noRd
.lnk_db_execute <- function(conn, sql) {
  tryCatch(
    DBI::dbExecute(conn, sql),
    error = function(e) {
      stop(
        "SQL execution failed:\n",
        conditionMessage(e), "\n",
        "Statement: ", substr(sql, 1, 200),
        call. = FALSE
      )
    }
  )
}

#' Check if a table exists (schema-aware)
#' @noRd
.lnk_table_exists <- function(conn, table) {
  parts <- .lnk_parse_table(table)
  DBI::dbExistsTable(conn, DBI::Id(schema = parts$schema, table = parts$table))
}

#' Parse schema-qualified table name into schema + table
#' @noRd
.lnk_parse_table <- function(table) {
  parts <- strsplit(table, "\\.")[[1]]
  if (length(parts) == 2) {
    list(schema = parts[1], table = parts[2])
  } else if (length(parts) == 1) {
    list(schema = "public", table = parts[1])
  } else {
    stop("Invalid table name: '", table, "'. Expected 'schema.table' or 'table'.",
         call. = FALSE)
  }
}

#' Validate SQL identifier (guard against injection)
#' Allowlist approach: only alphanumeric, underscores, and dots (for schema.table)
#' @noRd
.lnk_validate_identifier <- function(x, label = "identifier") {
  if (!is.character(x) || length(x) != 1 || nchar(x) == 0) {
    stop(label, " must be a non-empty string.", call. = FALSE)
  }
  if (!grepl("^[a-zA-Z_][a-zA-Z0-9_.]*$", x)) {
    stop(label, " contains disallowed characters: '", x, "'.", call. = FALSE)
  }
  invisible(x)
}

#' Quote a SQL identifier
#' @noRd
.lnk_quote_id <- function(conn, x) {
  DBI::dbQuoteIdentifier(conn, x)
}

#' Quote a schema-qualified table name for SQL interpolation
#' @noRd
.lnk_quote_table <- function(conn, table) {
  parts <- .lnk_parse_table(table)
  id <- DBI::Id(schema = parts$schema, table = parts$table)
  as.character(DBI::dbQuoteIdentifier(conn, id))
}

#' Build WHERE clause from named list of filters
#' Column names are validated and quoted. Requires conn for proper SQL quoting.
#' @noRd
.lnk_build_where <- function(conn, filters) {
  if (is.null(filters) || length(filters) == 0) {
    return("")
  }
  clauses <- vapply(names(filters), function(col) {
    .lnk_validate_identifier(col, "filter column name")
    quoted_col <- DBI::dbQuoteIdentifier(conn, col)
    val <- filters[[col]]
    if (length(val) != 1) {
      stop("Filter for column '", col, "' must be a scalar, not length ",
           length(val), ".", call. = FALSE)
    }
    if (is.character(val)) {
      paste0(quoted_col, " = ", DBI::dbQuoteLiteral(conn, val))
    } else if (is.numeric(val)) {
      if (is.nan(val) || is.infinite(val)) {
        stop("Column '", col, "' has non-finite numeric value.", call. = FALSE)
      }
      paste0(quoted_col, " = ", DBI::dbQuoteLiteral(conn, val))
    } else if (is.logical(val)) {
      paste0(quoted_col, " = ", DBI::dbQuoteLiteral(conn, val))
    } else {
      stop("Unsupported filter type for column '", col, "'.", call. = FALSE)
    }
  }, character(1))
  paste("WHERE", paste(clauses, collapse = " AND "))
}

#' Get column names from a table
#' @noRd
.lnk_table_columns <- function(conn, table) {
  .lnk_validate_identifier(table, "table name")
  parts <- .lnk_parse_table(table)
  id <- DBI::Id(schema = parts$schema, table = parts$table)
  sql <- paste("SELECT * FROM", DBI::dbQuoteIdentifier(conn, id), "LIMIT 0")
  res <- DBI::dbSendQuery(conn, sql)
  on.exit(DBI::dbClearResult(res))
  DBI::dbColumnInfo(res)$name
}


#' Species codes flagged present in a wsg_species_presence row.
#'
#' Treats every column except `watershed_group_code` and `notes` as a
#' species presence flag. Returns uppercased codes for cells equal to
#' the literal string `"t"`.
#'
#' Driven by the CSV header rather than a hardcoded vector so adding a
#' new species column (e.g. `ko`) propagates to every callsite without
#' a code edit. See link#106.
#' @noRd
.lnk_wsg_species_present <- function(row) {
  spp_cols <- setdiff(names(row), c("watershed_group_code", "notes"))
  present <- vapply(spp_cols,
    function(x) identical(row[[x]], "t"), logical(1))
  toupper(spp_cols[present])
}


#' Persistent table names derived from `cfg$pipeline$schema`.
#'
#' Returns a list with the persistent table name for `streams` and a
#' constructor function `habitat_for(species)` that returns the
#' `streams_habitat_<sp>` name for a given species code (lowercased).
#' Per-WSG staging tables use a separate `working_<wsg>` schema and are
#' not surfaced here — this helper only exposes the persistent province-
#' wide targets.
#'
#' @noRd
.lnk_table_names <- function(cfg) {
  if (!inherits(cfg, "lnk_config")) {
    stop("cfg must be an lnk_config object", call. = FALSE)
  }
  schema <- cfg$pipeline$schema
  if (!is.character(schema) || length(schema) != 1L || !nzchar(schema)) {
    stop("cfg$pipeline$schema must be a non-empty string. Add it to ",
         "the bundle's config.yaml under `pipeline:`. See link#112.",
         call. = FALSE)
  }
  list(
    schema      = schema,
    streams     = paste0(schema, ".streams"),
    habitat_for = function(sp) {
      if (!is.character(sp) || length(sp) != 1L || !nzchar(sp)) {
        stop("sp must be a single non-empty species code", call. = FALSE)
      }
      paste0(schema, ".streams_habitat_", tolower(sp))
    }
  )
}


#' Per-WSG working schema name (`working_<wsg>`).
#'
#' Per-WSG staging tables (`working_<wsg>.streams`, `.streams_habitat`,
#' `.streams_breaks`) live here. Keeps each WSG's run-state isolated so
#' parallel workers and re-runs don't collide.
#'
#' @noRd
.lnk_working_schema <- function(aoi) {
  if (!is.character(aoi) || length(aoi) != 1L || !nzchar(aoi)) {
    stop("aoi must be a single non-empty WSG code", call. = FALSE)
  }
  paste0("working_", tolower(aoi))
}
