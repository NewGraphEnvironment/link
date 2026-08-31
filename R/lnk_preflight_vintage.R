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
#' **Absence is not a pass**, but absence and ignorance are different
#' failures and are reported as such. A table that does not exist is
#' `absent`; one that exists but yields no usable timestamp is `unknown`.
#' Both fail, in the same direction as a stale one — a query returning
#' nothing must never read as "nothing is stale" — but they send an operator
#' to different places. Conflating them cost a pilot run, which reported
#' `never loaded / absent` for a table that was present and healthy.
#'
#' Two statistics quirks make this fiddlier than it looks. `last_analyze`
#' alone is unusable: measured across all ten primitives it is NULL on every
#' one and only `last_autoanalyze` is populated, so the query takes
#' `GREATEST` of the pair (in Postgres that ignores NULLs and is NULL only
#' when every argument is). And on a **freshly restored** database neither is
#' set — statistics are collected by (auto)analyze, so a table that was just
#' loaded has rows and no stats at all. The query therefore falls back to the
#' relation file's mtime, which exists for any real table. That fallback is
#' why `unknown` should be unreachable in practice.
#'
#' @param conn A [DBI::DBIConnection-class] to the host's local fwapg, or
#'   `NULL` when `vintage` is supplied directly.
#' @param max_age_days Maximum acceptable age of the **oldest** primitive.
#' @param tables Fully-qualified table names to check. Defaults to the
#'   snapshot-loaded set.
#' @param now Reference time. Injectable so tests are not clock-dependent.
#' @param vintage A data frame with `table_name` and `last_analyze`, and
#'   optionally `table_exists`. Defaults to reading `conn`; pass directly to
#'   test, or to judge a stamp collected on another host. Rows in a frame
#'   without `table_exists` are taken to exist.
#' @param quiet Suppress the human-readable report.
#'
#' @return Invisibly, a list with `ok`, `vintage`, `stale`, `absent`,
#'   `unknown`, `missing` (the union of the last two, kept for callers that
#'   only care that something was wrong), `oldest_days` and `message`.
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

  # "No answer" is two different states and they need different words.
  #
  #   absent  — the table does not exist. Always a failure.
  #   unknown — it exists but carries no usable timestamp.
  #
  # Conflating them cost a pilot run: on a freshly restored database a table
  # has rows but has never been ANALYZEd, so the statistics views are NULL and
  # the gate reported `never loaded / absent: bcfishobs.observations` for a
  # table that was present and fine. `.lnk_vintage_read()` now falls back to
  # the relation file's mtime, which exists for any real table, so `unknown`
  # should be unreachable in practice — it is kept as a distinct state rather
  # than folded back in, because a gate that cannot name what it saw sends
  # people to the wrong place.
  #
  # `table_exists` is optional so a caller can still hand in a bare
  # (table_name, last_analyze) frame; rows present in such a frame are taken
  # to exist.
  exists_col <- if ("table_exists" %in% names(found)) {
    as.logical(found$table_exists)
  } else {
    rep(TRUE, nrow(found))
  }
  absent <- sort(union(setdiff(tables, found$table_name),
                       found$table_name[!is.na(exists_col) & !exists_col]))
  unknown <- sort(setdiff(found$table_name[is.na(found$last_analyze)], absent))
  missing <- sort(union(absent, unknown))

  age <- as.numeric(difftime(now, found$last_analyze, units = "days"))
  stale <- sort(found$table_name[!is.na(age) & age > max_age_days])
  oldest <- if (any(!is.na(age))) max(age, na.rm = TRUE) else NA_real_

  out <- list(ok = length(missing) == 0L && length(stale) == 0L,
              vintage = found, stale = stale, missing = missing,
              absent = absent, unknown = unknown,
              oldest_days = oldest,
              message = .lnk_vintage_message(found, stale, absent, unknown,
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
                      table_exists = logical(0),
                      last_analyze = as.POSIXct(character(0)),
                      stringsAsFactors = FALSE)
  if (is.null(conn)) return(empty)

  vals <- paste(sprintf("(%s)", vapply(
    tables, function(t) as.character(DBI::dbQuoteLiteral(conn, t)),
    character(1))), collapse = ", ")

  # LEFT JOIN so a table that does not exist yields a row rather than no row —
  # its absence is reported by name instead of inferred from a short result.
  #
  # `table_exists` is carried separately from the timestamp because the two
  # answer different questions, and the gate reports them differently.
  #
  # The COALESCE fallback to the relation file's mtime is what makes this
  # usable on a freshly restored database: statistics are collected by
  # (auto)analyze, so a table that was just loaded has rows and NULL stats.
  # Measured on m1 — stats and mtime agree to within ~90s on every primitive,
  # and mtime is populated where stats are not. `pg_relation_filepath` and
  # `pg_stat_file` are both strict, so a non-existent table yields NULL rather
  # than an error; verified against a deliberately missing table.
  DBI::dbGetQuery(conn, sprintf(
    "SELECT p.tbl AS table_name,
            (to_regclass(p.tbl) IS NOT NULL) AS table_exists,
            COALESCE(
              GREATEST(s.last_analyze, s.last_autoanalyze),
              (pg_stat_file(pg_relation_filepath(c.oid))).modification
            ) AS last_analyze
       FROM (VALUES %s) AS p(tbl)
       LEFT JOIN pg_class c ON c.oid = to_regclass(p.tbl)
       LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid", vals))
}

.lnk_vintage_message <- function(found, stale, absent, unknown, max_age_days, now) {
  head <- sprintf("primitive vintage (window %g d)", max_age_days)
  if (length(stale) == 0L && length(absent) == 0L && length(unknown) == 0L) {
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
  if (length(absent)) {
    parts <- c(parts, sprintf("  table does not exist: %s",
                              paste(absent, collapse = ", ")))
  }
  if (length(unknown)) {
    parts <- c(parts, sprintf(
      "  exists but no timestamp (stats not collected AND no file mtime): %s",
      paste(unknown, collapse = ", ")))
  }
  parts <- c(parts,
    "  fix: bash data-raw/snapshot_bcfp.sh --with-bcfp-views --force")
  paste(c(sprintf("[preflight] %s - FAILED", head), parts), collapse = "\n")
}
