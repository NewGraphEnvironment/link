#' Which crossings are human-made barriers, as rules (link#341)
#'
#' A bundle's `parameters_barrier_rules.csv` says which crossings count as
#' human-made barriers: the barrier-below marks of the access walk
#' (`has_barriers_*`, `dam_dnstr_ind`, the mapping code's second token), the
#' anthropogenic rows of the persisted `barriers` table and the per-crossing
#' totals' below-barrier km. A human-made barrier blocks no species: access is
#' decided by natural barriers alone.
#'
#' Rows sharing a `rule_id` are ANDed into one rule, different `rule_id`s are
#' ORed, a NULL value matches only `is_null`, and row order means nothing.
#' `applies_to` scopes a row to crossing sources. `column_name` is read from a
#' source in `.lnk_barrier_rule_sources`: the crossing row itself, or the
#' crossing's PSCIS assessment. `species` accepts only `*` and `outcome` only
#' `barrier`: the columns exist so a later rule that blocks a species adds rows,
#' not a redesign.
#'
#' A bundle that declares no table runs the built-in rule `status`
#' (`barrier_status` in BARRIER, POTENTIAL), what link counted before rules
#' existed; `default` and `bcfishpass` declare it as their one row.
#'
#' @param cfg A config from [lnk_config()].
#' @param loaded Named list from [lnk_load_overrides()].
#' @return The rule rows, checked for shape (no database read), with `value`
#'   as text.
#' @noRd
.lnk_barrier_rules <- function(cfg, loaded) {
  r <- loaded$parameters_barrier_rules
  if (is.null(r)) return(.lnk_barrier_rules_builtin)
  miss <- setdiff(names(.lnk_barrier_rules_builtin), names(r))
  if (length(miss) > 0L) {
    stop("parameters_barrier_rules lacks column(s): ",
         paste(miss, collapse = ", "), call. = FALSE)
  }
  r <- as.data.frame(lapply(r, function(x) trimws(as.character(x))),
                     stringsAsFactors = FALSE)
  r[is.na(r)] <- NA_character_
  if (nrow(r) == 0L) {
    stop("parameters_barrier_rules has no rows: a bundle with no rules ",
         "would count no crossing as a barrier; leave the file out to run ",
         "the built-in rule", call. = FALSE)
  }
  id_ok <- !is.na(r$rule_id) & grepl("^[A-Za-z][A-Za-z0-9_]*$", r$rule_id)
  if (!all(id_ok)) {
    stop("parameters_barrier_rules: rule_id must start with a letter and hold ",
         "letters, digits or '_': ", paste(r$rule_id[!id_ok], collapse = ", "),
         call. = FALSE)
  }
  bad <- function(ok, what, x) {
    if (!all(ok)) {
      stop("parameters_barrier_rules: ", what, ": ",
           paste(unique(x[!ok]), collapse = ", "), call. = FALSE)
    }
  }
  bad(r$source_table %in% names(.lnk_barrier_rule_sources),
      "unknown source_table", r$source_table)
  bad(r$operator %in% .lnk_barrier_rule_operators, "unknown operator",
      r$operator)
  bad(!is.na(r$species) & r$species == "*",
      "species must be '*' (no rule blocks a species yet)", r$species)
  bad(!is.na(r$outcome) & r$outcome == "barrier",
      "outcome must be 'barrier' (no rule blocks a species yet)", r$outcome)
  bad(!is.na(r$column_name) & grepl("^[a-z_][a-z0-9_]*$", r$column_name),
      "column_name must be a lower-case name", r$column_name)
  scope <- strsplit(ifelse(is.na(r$applies_to), "", r$applies_to), ";",
                    fixed = TRUE)
  scope_ok <- vapply(scope, function(v) {
    v <- trimws(v)
    length(v) > 0L && (identical(v, "*") || all(v %in% .lnk_crossing_sources))
  }, logical(1))
  bad(scope_ok, "applies_to must be '*' or of PSCIS, CABD, MODELLED_CROSSINGS",
      r$applies_to)
  needs_value <- !r$operator %in% c("is_null", "not_null")
  bad(!needs_value | (!is.na(r$value) & nzchar(r$value)),
      "a value is needed for operator", r$operator)
  r
}

#' The built-in rule: the source's own status
#' @noRd
.lnk_barrier_rules_builtin <- data.frame(
  rule_id = "status", applies_to = "*", source_table = "crossings",
  column_name = "barrier_status", operator = "in", value = "BARRIER;POTENTIAL",
  species = "*", outcome = "barrier", date = NA_character_,
  source = "link (built in)", notes = NA_character_,
  stringsAsFactors = FALSE)

#' @noRd
.lnk_barrier_rule_operators <- c("in", "=", ">", ">=", "<", "<=", "is_null",
                                 "not_null")

#' @noRd
.lnk_crossing_sources <- c("PSCIS", "CABD", "MODELLED_CROSSINGS")

#' Where a barrier rule reads its column
#'
#' `table` is what the column list is read from (`NULL` for the crossing row);
#' `alias` names it in the rules' query; `join` joins it to the crossings
#' alias `c`; `derived` adds columns computed from it.
#' @noRd
.lnk_barrier_rule_sources <- list(
  crossings = list(table = NULL, alias = "c", join = NULL, derived = NULL),
  pscis_assessment = list(
    table = "whse_fish.pscis_assessment_svw", alias = "pa",
    join = paste0(
      "LEFT JOIN %s pa ON c.crossing_source = 'PSCIS' ",
      "AND c.aggregated_crossings_id = pa.stream_crossing_id::text"),
    # The culvert's slope times its length, as the severity thresholds link
    # shipped until 0.93.0 (`thresholds_default.csv`) computed it.
    derived = c(slope_length = "(pa.culvert_slope * pa.length_or_width)"))
)


#' Write `<schema>.crossings.barrier_rule_id` from the bundle's barrier rules
#'
#' Every rule a crossing matches, sorted in `C` order and joined with `;`;
#' NULL when none. Called by [lnk_pipeline_crossings()] after the per-row
#' corrections and before [lnk_barriers_emit()] for every bundle, so the
#' pipeline's `crossings` always carries the column and the four barrier-set
#' sites read it through `.lnk_sql_barrier_selected()`.
#'
#' A rule's `column_name` is checked against its source's columns, and its value
#' typed by the column (a number for a numeric column) and quoted through DBI,
#' so a value cannot inject SQL. A PSCIS source holding two assessments for one
#' crossing in the table is refused.
#'
#' @param conn DBI connection.
#' @param schema Working schema holding `crossings`.
#' @param rules Rule rows from `.lnk_barrier_rules()`.
#' @param pscis_table The PSCIS assessment view.
#' @return Invisibly, the number of crossings with a rule.
#' @noRd
.lnk_barrier_rules_apply <- function(conn, schema, rules,
                                     pscis_table = "whse_fish.pscis_assessment_svw") {
  .lnk_validate_identifier(schema, "schema")
  .lnk_validate_identifier(pscis_table, "pscis_table")
  used <- unique(rules$source_table)
  types <- list()
  for (src in used) {
    spec <- .lnk_barrier_rule_sources[[src]]
    tbl <- if (is.null(spec$table)) {
      paste0(schema, ".crossings")
    } else if (src == "pscis_assessment") {
      pscis_table
    } else {
      spec$table
    }
    cols <- DBI::dbGetQuery(conn, sprintf(
      "SELECT a.attname AS column_name, format_type(a.atttypid, a.atttypmod) AS type
         FROM pg_attribute a
        WHERE a.attrelid = %s::regclass AND a.attnum > 0 AND NOT a.attisdropped",
      DBI::dbQuoteString(conn, tbl)))
    t <- stats::setNames(cols$type, cols$column_name)
    if (!is.null(spec$derived)) {
      t <- c(t, stats::setNames(rep("numeric", length(spec$derived)),
                                names(spec$derived)))
    }
    types[[src]] <- t
  }
  for (i in seq_len(nrow(rules))) {
    if (!rules$column_name[i] %in% names(types[[rules$source_table[i]]])) {
      stop("parameters_barrier_rules: rule ", rules$rule_id[i], ": ",
           rules$source_table[i], " has no column ", rules$column_name[i],
           call. = FALSE)
    }
  }
  if ("pscis_assessment" %in% used) {
    dup <- DBI::dbGetQuery(conn, sprintf(
      "SELECT pa.stream_crossing_id FROM %s pa
        WHERE pa.stream_crossing_id::text IN (
          SELECT aggregated_crossings_id FROM %s.crossings
           WHERE crossing_source = 'PSCIS')
        GROUP BY 1 HAVING count(*) > 1 LIMIT 1", pscis_table, schema))
    if (nrow(dup) > 0L) {
      stop(pscis_table, " holds more than one assessment for PSCIS crossing ",
           dup[[1]][1], "; a barrier rule cannot tell which to read",
           call. = FALSE)
    }
  }

  cond <- vapply(seq_len(nrow(rules)), function(i) {
    .lnk_sql_barrier_rule_row(conn, rules[i, , drop = FALSE],
                              types[[rules$source_table[i]]])
  }, character(1))
  ids <- sort(unique(rules$rule_id), method = "radix")
  cases <- vapply(ids, function(id) {
    sprintf("CASE WHEN %s THEN %s END",
            paste(sprintf("COALESCE(%s, false)", cond[rules$rule_id == id]),
                  collapse = " AND "),
            DBI::dbQuoteString(conn, id))
  }, character(1))
  joins <- vapply(setdiff(used, "crossings"), function(src) {
    sprintf(.lnk_barrier_rule_sources[[src]]$join,
            if (src == "pscis_assessment") pscis_table else
              .lnk_barrier_rule_sources[[src]]$table)
  }, character(1))

  .lnk_db_execute(conn, sprintf(
    "ALTER TABLE %s.crossings ADD COLUMN IF NOT EXISTS barrier_rule_id text",
    schema))
  .lnk_db_execute(conn, sprintf(
    "UPDATE %1$s.crossings u SET barrier_rule_id = s.ids
       FROM (SELECT c.ctid AS rc,
                    NULLIF(concat_ws(';', %2$s), '') AS ids
               FROM %1$s.crossings c
               %3$s) s
      WHERE u.ctid = s.rc",
    schema, paste(cases, collapse = ", "), paste(joins, collapse = "\n")))
  n <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM %s.crossings WHERE barrier_rule_id IS NOT NULL",
    schema))$n
  invisible(n)
}


#' SQL for one barrier rule row: its scope AND its condition
#' @noRd
.lnk_sql_barrier_rule_row <- function(conn, row, types) {
  spec <- .lnk_barrier_rule_sources[[row$source_table]]
  col <- row$column_name
  expr <- if (!is.null(spec$derived) && col %in% names(spec$derived)) {
    spec$derived[[col]]
  } else {
    paste0(spec$alias, ".", DBI::dbQuoteIdentifier(conn, col))
  }
  numeric <- grepl("^(integer|bigint|smallint|numeric|double precision|real)",
                   types[[col]])
  lit <- function(v) {
    if (numeric) {
      if (!grepl("^-?[0-9]+(\\.[0-9]+)?([eE][-+]?[0-9]+)?$", v)) {
        stop("parameters_barrier_rules: rule ", row$rule_id, ": ", col,
             " is numeric and '", v, "' is not a number", call. = FALSE)
      }
      paste0(DBI::dbQuoteString(conn, v), "::numeric")
    } else {
      as.character(DBI::dbQuoteString(conn, v))
    }
  }
  cond <- switch(row$operator,
    is_null = sprintf("%s IS NULL", expr),
    not_null = sprintf("%s IS NOT NULL", expr),
    `in` = sprintf("%s IN (%s)", expr, paste(vapply(
      trimws(strsplit(row$value, ";", fixed = TRUE)[[1]]), lit, ""),
      collapse = ", ")),
    sprintf("%s %s %s", expr, row$operator, lit(row$value)))
  scope <- trimws(strsplit(row$applies_to, ";", fixed = TRUE)[[1]])
  if (identical(scope, "*")) {
    sprintf("(%s)", cond)
  } else {
    sprintf("(c.crossing_source IN (%s) AND %s)",
            paste(vapply(scope, function(x) {
              as.character(DBI::dbQuoteString(conn, x))
            }, ""), collapse = ", "), cond)
  }
}


#' SQL predicate: is a crossing row a human-made barrier?
#'
#' `barrier_rule_id IS NOT NULL` where `<schema>.crossings` carries the column,
#' which the pipeline always writes (`.lnk_barrier_rules_apply()`). A caller's
#' own crossings table without it falls back to the built-in rule, the
#' source's own status.
#' @param conn DBI connection.
#' @param schema Schema holding `crossings`.
#' @param alias Optional alias of `crossings` in the calling query.
#' @noRd
.lnk_sql_barrier_selected <- function(conn, schema, alias = NULL) {
  p <- if (is.null(alias)) "" else paste0(alias, ".")
  has <- nrow(DBI::dbGetQuery(conn, sprintf(
    "SELECT 1 FROM information_schema.columns
      WHERE table_schema = %s AND table_name = 'crossings'
        AND column_name = 'barrier_rule_id'",
    DBI::dbQuoteString(conn, schema)))) > 0L
  if (has) {
    paste0(p, "barrier_rule_id IS NOT NULL")
  } else {
    paste0(p, "barrier_status IN ('BARRIER', 'POTENTIAL')")
  }
}
