# The stall sampler (link#487). While a group's statement runs past a
# threshold, a second connection records what that backend, its parallel
# workers and the sessions blocking any of them are doing, one tagged line per
# backend per check, into the group's own log. data-raw/wsg_stall_sample.R runs
# `.lnk_stall_watch()` beside each group; the driver splits the lines into
# `<TS>_stall_<WSG>.tsv` (data-raw/study_area_finish.sh, run_stalls).

#' Columns of a stall sample, in file order
#' @noRd
.lnk_stall_cols <- c(
  "sampled_utc", "wsg", "role", "pid", "leader_pid", "blocks_pid", "state",
  "wait_event_type", "wait_event", "query_start", "query",
  "load1", "load5", "load15", "n_active"
)

#' Snapshot a backend that has been on one statement longer than `after_s`
#'
#' One query over `pg_stat_activity`: the backend (`leader`), its parallel
#' workers (`leader_pid`), and each session `pg_blocking_pids()` names for
#' any of them (`blocker`, with `blocks_pid` the one it blocks). Nothing is
#' returned while the backend is idle or has been on its statement for
#' `after_s` seconds or less. Times are UTC text; `query` is the first 200
#' characters, whitespace squished, for the leader and blockers only.
#'
#' @param conn A DBI connection other than the backend's own.
#' @param pid The watched backend's pid.
#' @param after_s Seconds on one statement before it is sampled.
#' @return A data frame with `.lnk_stall_cols` less `wsg` and the load
#'   columns; zero rows when the backend is not stalled.
#' @noRd
.lnk_stall_snapshot <- function(conn, pid, after_s) {
  stopifnot(length(pid) == 1L, !is.na(pid), length(after_s) == 1L,
            is.finite(after_s), after_s >= 0)
  sql <- "
WITH lead AS (
  SELECT a.* FROM pg_stat_activity a
  WHERE a.pid = $1 AND a.state = 'active'
    AND clock_timestamp() - a.query_start > make_interval(secs => $2)
), grp AS (
  SELECT 1 AS ord, 'leader' AS role, l.pid, l.leader_pid, NULL::int AS blocks_pid,
         l.state, l.wait_event_type, l.wait_event, l.query_start, l.query
  FROM lead l
  UNION ALL
  SELECT 2, 'worker', w.pid, w.leader_pid, NULL::int,
         w.state, w.wait_event_type, w.wait_event, w.query_start, NULL::text
  FROM pg_stat_activity w JOIN lead l ON w.leader_pid = l.pid AND w.pid <> l.pid
), blk AS (
  SELECT DISTINCT 3 AS ord, 'blocker' AS role, b.pid, b.leader_pid, g.pid AS blocks_pid,
         b.state, b.wait_event_type, b.wait_event, b.query_start, b.query
  FROM grp g
  CROSS JOIN LATERAL unnest(pg_blocking_pids(g.pid)) AS bp(pid)
  JOIN pg_stat_activity b ON b.pid = bp.pid
), s AS (
  SELECT * FROM grp UNION ALL SELECT * FROM blk
)
SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS sampled_utc,
       role, pid, leader_pid, blocks_pid, state, wait_event_type, wait_event,
       to_char(query_start AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') AS query_start,
       left(regexp_replace(query, '\\s+', ' ', 'g'), 200) AS query,
       (SELECT count(*)::int FROM pg_stat_activity
        WHERE datname = current_database() AND state = 'active'
          AND pid <> pg_backend_pid()) AS n_active
FROM s
ORDER BY ord, blocks_pid NULLS FIRST, pid"
  DBI::dbGetQuery(conn, sql, params = list(as.integer(pid), as.numeric(after_s)))
}

#' Format stall rows as tagged log lines
#'
#' @param df A frame from `.lnk_stall_snapshot()`.
#' @param wsg The group code, in the tag and the `wsg` column.
#' @param load The host's 1, 5 and 15 minute load averages.
#' @param header Write the column names first.
#' @return `[wsg_stall] <WSG>\t<fields>` lines; NA is an empty field, no
#'   field holds a tab, carriage return or newline, and none holds `[wsg_` or
#'   `__LNK_`, which the driver's log readers match.
#' @noRd
.lnk_stall_lines <- function(df, wsg, load, header = FALSE) {
  tag <- paste0("[wsg_stall] ", wsg, "\t")
  rows <- character(0)
  if (nrow(df) > 0L) {
    df$wsg <- wsg
    df$load1 <- load[1]
    df$load5 <- load[2]
    df$load15 <- load[3]
    cells <- lapply(.lnk_stall_cols, function(col) {
      v <- as.character(df[[col]])
      v[is.na(v)] <- ""
      v <- gsub("[\t\r\n]+", " ", v)
      # Host logs are grepped unanchored for `[wsg_run_one] <WSG> done` and
      # `__LNK_LEG_END__`: a blocker's query text must not read as either.
      v <- gsub("[wsg_", "[wsg-", v, fixed = TRUE)
      v <- gsub("__LNK_", "--LNK_", v, fixed = TRUE)
      if (identical(col, "query")) v <- substr(v, 1L, 200L)
      v
    })
    rows <- paste0(tag, do.call(paste, c(cells, sep = "\t")))
  }
  if (header) rows <- c(paste0(tag, paste(.lnk_stall_cols, collapse = "\t")), rows)
  rows
}

#' Read the first three numbers of a load-average string
#'
#' Reads `/proc/loadavg` (`0.52 0.58 0.59 1/389 12345`) and macOS's
#' `sysctl -n vm.loadavg` (`{ 2.10 1.98 1.85 }`) alike.
#' @noRd
.lnk_loadavg_parse <- function(txt) {
  txt <- paste(txt, collapse = " ")
  hits <- regmatches(txt, gregexpr("[0-9]+(\\.[0-9]+)?", txt))[[1]]
  n <- suppressWarnings(as.numeric(hits))
  if (length(n) < 3L) return(rep(NA_real_, 3))
  n[1:3]
}

#' The host's 1, 5 and 15 minute load averages, NA when unreadable
#' @noRd
.lnk_loadavg <- function() {
  txt <- tryCatch({
    if (file.exists("/proc/loadavg")) {
      readLines("/proc/loadavg", n = 1L, warn = FALSE)
    } else {
      suppressWarnings(system2("sysctl", c("-n", "vm.loadavg"),
                               stdout = TRUE, stderr = FALSE))
    }
  }, error = function(e) character(0))
  .lnk_loadavg_parse(txt)
}

#' Watch one backend and write a stall sample at each check
#'
#' Checks `parent_pid` every `poll_s` seconds and returns once it has
#' exited, so the watch ends with its group. Every `every_s` seconds it
#' returns if the backend is gone, and otherwise writes the backend's
#' snapshot (`.lnk_stall_snapshot()`) to stdout, with the header before the
#' first row. Any error is written as one `[wsg_stall_error] <WSG>` line and
#' ends the watch: it never raises, so it cannot fail the group.
#'
#' @param conn The watch's own connection.
#' @param pid The group's backend pid.
#' @param parent_pid The group's R process.
#' @param wsg Group code.
#' @param after_s Seconds on one statement before it is sampled.
#' @param every_s Seconds between checks.
#' @param poll_s Seconds between checks of `parent_pid`.
#' @return `"parent_gone"`, `"backend_gone"` or `"error"`, invisibly.
#' @noRd
.lnk_stall_watch <- function(conn, pid, parent_pid, wsg, after_s = 600,
                             every_s = 60, poll_s = 2) {
  header_done <- FALSE
  next_at <- Sys.time() + every_s
  repeat {
    if (!isTRUE(tools::pskill(parent_pid, 0L))) return(invisible("parent_gone"))
    if (Sys.time() >= next_at) {
      next_at <- next_at + every_s
      res <- tryCatch({
        here <- DBI::dbGetQuery(
          conn, "SELECT count(*)::int AS n FROM pg_stat_activity WHERE pid = $1",
          params = list(as.integer(pid))
        )$n
        if (identical(here, 0L)) {
          "backend_gone"
        } else {
          df <- .lnk_stall_snapshot(conn, pid, after_s)
          if (nrow(df) > 0L) {
            cat(.lnk_stall_lines(df, wsg, .lnk_loadavg(), header = !header_done),
                sep = "\n")
            # A redirected stdout is block-buffered: flush, so the log holds
            # each check as it happens, not at exit.
            flush(stdout())
            header_done <- TRUE
          }
          "ok"
        }
      }, error = function(e) {
        # The print itself can fail (a dropped ssh link): still no condition.
        try({
          cat(sprintf("[wsg_stall_error] %s %s\n", wsg,
                      gsub("[[:space:]]+", " ", conditionMessage(e))))
          flush(stdout())
        }, silent = TRUE)
        "error"
      })
      if (!identical(res, "ok")) return(invisible(res))
    }
    Sys.sleep(poll_s)
  }
}
