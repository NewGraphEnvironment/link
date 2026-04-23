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
