#' Are this host's DB primitives fresh enough to model against?
#'
#' `snapshot_bcfp.sh` loads four primitives from public sources into each
#' host's local fwapg. Every cypher reloads them during prep; the
#' dispatcher does not, and nothing checks. On 2026-08-30 the dispatcher's
#' `cabd.dams` was 2026-05-23 and `fresh.modelled_stream_crossings`
#' 2026-05-26 — a run started that day would have modelled one bucket on
#' May inputs and three on August inputs, produced one consolidated table
#' set, and said nothing about it anywhere (link#246).
#'
#' The other seven tables in `.lnk_input_primitives()` are bulk-restored
#' FWA. They are never `ANALYZE`d, so they carry no vintage at all and are
#' not an axis this can measure — including them would mean every host
#' failing forever on data that is not the staleness risk.
#'
#' **Absence is not a pass.** A table missing from the result, and a table
#' present with a NULL timestamp, both fail — in the same direction as a
#' stale one. A query returning nothing must never read as "nothing is
#' stale".
#'
#' `last_analyze` alone is unusable here: measured across all ten
#' primitives it is NULL on every one, and only `last_autoanalyze` is
#' populated. `GREATEST` of the two is the usable signal — in Postgres it
#' ignores NULLs and is NULL only when every argument is.
#'
#' @param conn A [DBI::DBIConnection-class] to the host's local fwapg, or
#'   `NULL` when `vintage` is supplied directly.
#' @param max_age_days Maximum acceptable age of the **oldest** primitive.
#' @param tables Fully-qualified table names to check. Defaults to the
#'   snapshot-loaded set.
#' @param now Reference time. Injectable so tests are not clock-dependent.
#' @param vintage A data frame with `table_name` and `last_analyze`.
#'   Defaults to reading `conn`; pass directly to test, or to judge a
#'   stamp collected on another host.
#' @param quiet Suppress the human-readable report.
#'
#' @return Invisibly, a list with `ok`, `vintage`, `stale`, `missing`,
#'   `oldest_days` and `message`.
#'
#' @family preflight
#'
#' @export
#'
#' @examples
#' # Judge a vintage table without touching a database:
#' now <- as.POSIXct("2026-08-30 12:00:00", tz = "UTC")
#' v <- data.frame(
#'   table_name   = link:::.lnk_vintage_primitives(),
#'   last_analyze = now - c(1, 2, 1, 99) * 86400)
#' res <- lnk_preflight_vintage(vintage = v, now = now, max_age_days = 7,
#'                              quiet = TRUE)
#' res$ok
#' res$stale
lnk_preflight_vintage <- function(conn = NULL,
                                  max_age_days = 7,
                                  tables = .lnk_vintage_primitives(),
                                  now = Sys.time(),
                                  vintage = .lnk_vintage_read(conn, tables),
                                  quiet = FALSE) {
  stopifnot(
    is.numeric(max_age_days), length(max_age_days) == 1L,
    !is.na(max_age_days), max_age_days > 0,
    is.character(tables), length(tables) >= 1L, all(nzchar(tables)),
    inherits(now, "POSIXct"), length(now) == 1L, !is.na(now),
    is.data.frame(vintage),
    all(c("table_name", "last_analyze") %in% names(vintage)),
    is.logical(quiet), length(quiet) == 1L, !is.na(quiet))

  found <- vintage[vintage$table_name %in% tables, , drop = FALSE]

  # Both flavours of "no answer" converge here: a table absent from the
  # result and a table present with no timestamp.
  missing <- sort(union(setdiff(tables, found$table_name),
                        found$table_name[is.na(found$last_analyze)]))

  age <- as.numeric(difftime(now, found$last_analyze, units = "days"))
  stale <- sort(found$table_name[!is.na(age) & age > max_age_days])
  oldest <- if (any(!is.na(age))) max(age, na.rm = TRUE) else NA_real_

  out <- list(ok = length(missing) == 0L && length(stale) == 0L,
              vintage = found, stale = stale, missing = missing,
              oldest_days = oldest,
              message = .lnk_vintage_message(found, stale, missing,
                                             max_age_days, now))
  if (!quiet) message(out$message)
  invisible(out)
}


# The snapshot-loaded primitives, derived from the existing dictionary so
# the set is single-sourced. Everything whose source is not fwapg — the FWA
# tables are bulk-restored and carry no analyze timestamp by construction.
.lnk_vintage_primitives <- function() {
  p <- .lnk_input_primitives()
  sort(p$table_name[!startsWith(p$source, "fwapg/")])
}

.lnk_vintage_read <- function(conn, tables) {
  empty <- data.frame(table_name = character(0),
                      last_analyze = as.POSIXct(character(0)),
                      stringsAsFactors = FALSE)
  if (is.null(conn)) return(empty)

  vals <- paste(sprintf("(%s)", vapply(
    tables, function(t) as.character(DBI::dbQuoteLiteral(conn, t)),
    character(1))), collapse = ", ")

  # LEFT JOIN so a table that does not exist yields a row with a NULL
  # timestamp rather than no row — both are failures, and both should be
  # reported by name rather than inferred from a short result.
  DBI::dbGetQuery(conn, sprintf(
    "SELECT p.tbl AS table_name,
            GREATEST(s.last_analyze, s.last_autoanalyze) AS last_analyze
       FROM (VALUES %s) AS p(tbl)
       LEFT JOIN pg_class c ON c.oid = to_regclass(p.tbl)
       LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid", vals))
}

.lnk_vintage_message <- function(found, stale, missing, max_age_days, now) {
  head <- sprintf("primitive vintage (window %g d)", max_age_days)
  if (length(stale) == 0L && length(missing) == 0L) {
    age <- as.numeric(difftime(now, found$last_analyze, units = "days"))
    return(sprintf("[preflight] %s - OK, oldest %.1f d (%s)",
                   head, max(age),
                   found$table_name[which.max(age)]))
  }
  parts <- character(0)
  if (length(stale)) {
    age <- as.numeric(difftime(now, found$last_analyze, units = "days"))
    names(age) <- found$table_name
    parts <- c(parts, sprintf("  stale: %s",
      paste(sprintf("%s (%.0f d)", stale, age[stale]), collapse = ", ")))
  }
  if (length(missing)) {
    parts <- c(parts, sprintf("  never loaded / absent: %s",
                              paste(missing, collapse = ", ")))
  }
  parts <- c(parts,
    "  fix: bash data-raw/snapshot_bcfp.sh --with-bcfp-views --force")
  paste(c(sprintf("[preflight] %s - FAILED", head), parts), collapse = "\n")
}
