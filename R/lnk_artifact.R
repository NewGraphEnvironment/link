# Source-artifact identity for the DB primitives (link#265).
#
# The primitives are loaded from a versioned object store
# (nrs.objectstore.gov.bc.ca/bchamp). A HEAD returns three identity handles
# free -- x-amz-version-id, ETag, Last-Modified -- and `?versionId=` re-fetches
# an exact version. But `?versions` and prefix listing are AccessDenied, so a
# version nobody wrote down at load time cannot be recovered later. This table
# is where it gets written down.
#
# One table per host DATABASE, not per persist schema: it describes what is
# loaded in this Postgres, which every persist schema in it reads. Each run
# copies the rows it read into `<schema>.log_input` (.lnk_log_inputs()), which
# is what carries the identity home from a cypher before the cypher is burned.
#
# `recorded_by` is the strength of the evidence, recorded rather than inferred
# (the `bcfp_pin_source` pattern, link#262):
#
#   loader  written by the thing that did the load. A record.
#   probe   a HEAD after the fact. "This version is current now", not "this is
#           what was loaded". Weaker, labelled weaker, and never allowed to
#           overwrite a loader row.

cols_source_artifact <- c(
  host                   = "text NOT NULL",
  table_name             = "text NOT NULL",
  url                    = "text NOT NULL",
  kind                   = "text NOT NULL CHECK (kind IN ('object', 'api', 'derived'))",
  version_id             = "text",
  etag                   = "text",
  last_modified          = "timestamptz",
  n_rows                 = "bigint",
  loaded_at              = "timestamptz",
  recorded_at            = "timestamptz NOT NULL",
  recorded_by            = "text NOT NULL CHECK (recorded_by IN ('loader', 'probe'))",
  notes                  = "text"
)

# Where the table lives. One function rather than an argument: the gate, the
# run log and the loader must all read the same table, and a per-call schema is
# a way for them to disagree. Everything that names the table goes through
# here, so moving it is a one-line change.
.lnk_artifact_location <- function() {
  list(schema = "fresh", table = "log_source_artifact")
}
.lnk_artifact_table <- function() {
  l <- .lnk_artifact_location()
  paste(l$schema, l$table, sep = ".")
}


#' Create `fresh.log_source_artifact`. Idempotent.
#'
#' Same shape discipline as [.lnk_log_create_tables()]: DDL from
#' `cols_source_artifact`, then `ADD COLUMN IF NOT EXISTS` so a table created
#' by an older link gains new columns.
#'
#' @noRd
.lnk_artifact_create <- function(conn) {
  loc <- .lnk_artifact_location()
  .lnk_db_execute(conn, sprintf("CREATE SCHEMA IF NOT EXISTS %s", loc$schema))
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE IF NOT EXISTS %s (\n  %s\n)",
    .lnk_artifact_table(),
    .lnk_cols_clause(cols_source_artifact, c("host", "table_name", "url"))))
  # CHECK constraints cannot ride along on ADD COLUMN IF NOT EXISTS against a
  # table that already holds rows, and every column here exists since the
  # first version, so only the types are aligned.
  cols <- sub("\\s+CHECK .*$", "", cols_source_artifact)
  names(cols) <- names(cols_source_artifact)
  .lnk_log_align_columns(conn, loc$schema, loc$table, cols)
  invisible(conn)
}


#' Expand a primitive's URL template into the artifacts it is read from.
#'
#' `{wsg}` expands once per group in `wsg`. Templates without it pass through.
#'
#' @noRd
.lnk_artifact_expand <- function(prims, wsg = character(0)) {
  rows <- lapply(seq_len(nrow(prims)), function(i) {
    u <- prims$url[i]
    if (grepl("{wsg}", u, fixed = TRUE)) {
      if (length(wsg) == 0L) return(NULL)
      data.frame(table_name = prims$table_name[i], kind = prims$kind[i],
                 url = vapply(wsg, function(w) sub("{wsg}", w, u, fixed = TRUE),
                              character(1), USE.NAMES = FALSE),
                 stringsAsFactors = FALSE)
    } else {
      data.frame(table_name = prims$table_name[i], kind = prims$kind[i],
                 url = u, stringsAsFactors = FALSE)
    }
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) {
    out <- data.frame(table_name = character(0), kind = character(0),
                      url = character(0), stringsAsFactors = FALSE)
  }
  out
}


#' HEAD one object and read its identity handles.
#'
#' Never errors. An unreachable host, a timeout or a non-200 returns NA
#' identity and says why in `notes` — an honest NULL, not a failed run.
#'
#' @return A one-row data.frame: `version_id`, `etag`, `last_modified`,
#'   `status`, `notes`.
#' @noRd
.lnk_artifact_head <- function(url, timeout = 20) {
  na_row <- function(status, why) {
    data.frame(version_id = NA_character_, etag = NA_character_,
               last_modified = as.POSIXct(NA, tz = "UTC"),
               status = status, notes = why, stringsAsFactors = FALSE)
  }
  r <- tryCatch(httr::HEAD(url, httr::timeout(timeout),
                           httr::config(connecttimeout = 10)),
                error = function(e) e)
  if (inherits(r, "error")) {
    return(na_row(NA_integer_,
                  paste0("HEAD failed: ", conditionMessage(r))))
  }
  status <- as.integer(httr::status_code(r))
  if (status != 200L) {
    return(na_row(status, sprintf("HEAD returned HTTP %d", status)))
  }
  h <- httr::headers(r)
  hv <- function(nm) {
    v <- h[[nm]]
    if (is.null(v) || !nzchar(v)) NA_character_ else as.character(v)
  }
  etag <- hv("etag")
  lm <- hv("last-modified")
  data.frame(
    version_id    = hv("x-amz-version-id"),
    etag          = .lnk_etag_normalise(etag),
    last_modified = .lnk_http_date(lm),
    status        = status,
    notes         = NA_character_,
    stringsAsFactors = FALSE)
}


#' Record source-artifact identity for DB primitives
#'
#' Upserts rows into `fresh.log_source_artifact`, the table that says which
#' version of which object each primitive in this database was loaded from
#' (link#265). The bchamp object store is versioned but cannot be listed, so a
#' version id not recorded at load time is gone for good; this is where it is
#' recorded.
#'
#' `recorded_by` is the strength of the evidence. `"loader"` rows come from the
#' thing that did the load (`data-raw/snapshot_bcfp.sh` pins each fetch to the
#' version it records). `"probe"` rows come from a `HEAD` after the fact and
#' say only that the version is current now. **A probe never overwrites a
#' loader row**, so weaker evidence cannot replace stronger.
#'
#' Every `url` must be one [lnk_artifact_record()] knows for that table — the
#' primitives dictionary's URL, with `{wsg}` expanded. A loader that fetches
#' from somewhere else stops here rather than recording an identity for an
#' object the rest of link does not know about.
#'
#' `n_rows` is counted from the database at record time: exactly, per
#' watershed group for the per-group stream objects. A table that does not
#' exist records `n_rows` NULL and says so in `notes`.
#'
#' @param conn A [DBI::DBIConnection-class] to the database the primitives
#'   live in.
#' @param artifacts A data frame with `table_name` and `url`, and optionally
#'   `version_id`, `etag`, `last_modified`, `loaded_at` and `notes`. `kind`
#'   is taken from the dictionary. `last_modified` may be POSIXct or the raw
#'   HTTP header string (`"Thu, 16 Apr 2026 02:22:39 GMT"`).
#' @param recorded_by `"loader"` or `"probe"`.
#' @param host Host label. Defaults to `LNK_HOST_ALIAS`, else the node name —
#'   the same label the run log uses.
#'
#' @return Invisibly, the rows as recorded (before the probe-vs-loader rule is
#'   applied by the database).
#'
#' @family provenance
#' @export
#'
#' @examples
#' # Which artifacts the dictionary knows, without touching a database:
#' prims <- link:::.lnk_input_primitives()
#' prims[, c("table_name", "kind")]
#'
#' \dontrun{
#' conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
#'                     user = "postgres", password = "postgres")
#' lnk_artifact_record(conn, data.frame(
#'   table_name = "cabd.dams",
#'   url = prims$url[prims$table_name == "cabd.dams"],
#'   loaded_at = Sys.time()), recorded_by = "loader")
#' }
lnk_artifact_record <- function(conn, artifacts,
                                recorded_by = c("loader", "probe"),
                                host = .lnk_host()) {
  recorded_by <- match.arg(recorded_by)
  stopifnot(is.data.frame(artifacts),
            all(c("table_name", "url") %in% names(artifacts)),
            is.character(host), length(host) == 1L, nzchar(host))
  if (nrow(artifacts) == 0L) return(invisible(artifacts))

  prims <- .lnk_input_primitives()
  unknown_tbl <- setdiff(artifacts$table_name, prims$table_name)
  if (length(unknown_tbl)) {
    stop("not a primitive in .lnk_input_primitives(): ",
         paste(unknown_tbl, collapse = ", "), call. = FALSE)
  }
  ok_url <- vapply(seq_len(nrow(artifacts)), function(i) {
    tmpl <- prims$url[prims$table_name == artifacts$table_name[i]]
    rx <- paste0("^", gsub("\\{wsg\\}", "[A-Z]{4}", .lnk_regex_escape(tmpl),
                           fixed = TRUE), "$")
    grepl(rx, artifacts$url[i])
  }, logical(1))
  if (!all(ok_url)) {
    bad <- artifacts[!ok_url, c("table_name", "url"), drop = FALSE]
    stop("artifact URL does not match the primitives dictionary ",
         "(.lnk_input_primitives()):\n",
         paste(sprintf("  %s: %s", bad$table_name, bad$url), collapse = "\n"),
         call. = FALSE)
  }

  fill <- function(nm, na) {
    if (nm %in% names(artifacts)) artifacts[[nm]] else rep(na, nrow(artifacts))
  }
  a <- data.frame(
    table_name    = artifacts$table_name,
    url           = artifacts$url,
    kind          = prims$kind[match(artifacts$table_name, prims$table_name)],
    version_id    = as.character(fill("version_id", NA_character_)),
    etag          = as.character(fill("etag", NA_character_)),
    last_modified = .lnk_http_date(fill("last_modified", NA)),
    loaded_at     = as.POSIXct(fill("loaded_at", NA), tz = "UTC"),
    notes         = as.character(fill("notes", NA_character_)),
    stringsAsFactors = FALSE)
  # An empty string is not an identity.
  for (nm in c("version_id", "etag", "notes")) {
    a[[nm]][!is.na(a[[nm]]) & !nzchar(a[[nm]])] <- NA_character_
  }
  # One spelling of an ETag, whichever writer supplied it, or a loader's
  # and a probe's ETag for the same bytes would never compare equal.
  a$etag <- .lnk_etag_normalise(a$etag)

  a$n_rows <- .lnk_artifact_count(conn, a)
  tbls <- unique(a$table_name)
  missing_tbl <- tbls[!.lnk_artifact_exists(conn, tbls)]
  absent <- a$table_name %in% missing_tbl
  a$notes[absent] <- vapply(a$notes[absent], function(n) {
    paste(stats::na.omit(c(n, "table absent at record time")), collapse = "; ")
  }, character(1))

  .lnk_artifact_create(conn)

  lit <- function(x) {
    if (inherits(x, "POSIXct")) {
      x <- ifelse(is.na(x), NA_character_,
                  format(x, "%Y-%m-%d %H:%M:%OS3+00", tz = "UTC"))
    } else if (is.numeric(x)) {
      # as.character(1234567) is "1234567" but 1e6 prints as "1e+06".
      x <- ifelse(is.na(x), NA_character_, sprintf("%.0f", x))
    }
    vapply(x, function(v) {
      if (is.na(v)) "NULL" else as.character(DBI::dbQuoteLiteral(conn, as.character(v)))
    }, character(1), USE.NAMES = FALSE)
  }
  values <- paste(sprintf(
    "(%s, %s, %s, %s, %s, %s, %s::timestamptz, %s::bigint, %s::timestamptz, now(), %s, %s)",
    lit(rep(host, nrow(a))), lit(a$table_name), lit(a$url), lit(a$kind),
    lit(a$version_id), lit(a$etag), lit(a$last_modified), lit(a$n_rows),
    lit(a$loaded_at), lit(rep(recorded_by, nrow(a))), lit(a$notes)),
    collapse = ",\n  ")

  tbl <- .lnk_artifact_table()
  set_cols <- c("kind", "version_id", "etag", "last_modified", "n_rows",
                "loaded_at", "recorded_at", "recorded_by", "notes")
  .lnk_db_execute(conn, sprintf(
    "INSERT INTO %s
       (host, table_name, url, kind, version_id, etag, last_modified, n_rows,
        loaded_at, recorded_at, recorded_by, notes)
     VALUES
       %s
     ON CONFLICT (host, table_name, url) DO UPDATE SET %s
     WHERE %s.recorded_by = 'probe'
        OR EXCLUDED.recorded_by = 'loader'",
    tbl, values,
    paste(sprintf("%s = EXCLUDED.%s", set_cols, set_cols), collapse = ", "),
    .lnk_artifact_location()$table))

  invisible(a)
}


#' Probe the FWA primitives' artifacts and record what is current now
#'
#' `HEAD`s the object-store artifact behind each FWA primitive in this
#' database and records the answer with `recorded_by = "probe"` (link#265).
#' This is the weaker kind of record: it says which version is current
#' **now**, not which one was loaded. It exists because fwapg's `load.sh`
#' records nothing, and a version that is not written down before the store
#' moves on can never be named (link#270 is the loader-side record). A probe
#' never overwrites a `loader` row. A probe row is **not a baseline**: anything
#' that compares a recorded ETag against the store to decide whether a source
#' changed (link#273) must read `loader` rows only, because a probe's ETag is by
#' construction whatever the store held when the probe ran.
#'
#' The stream network is one object per watershed group. The groups probed
#' are the ones **loaded in this database**, not a copy of `load.sh`'s
#' discovery query, so the probe cannot drift from what is actually here.
#' The derived `fwa_stream_networks_order_parent` gets a `derived` row with no
#' identity, which is correct and permanent.
#'
#' @param conn A [DBI::DBIConnection-class] to the database the primitives
#'   live in.
#' @param tables Primitives to probe. Defaults to every FWA primitive (those
#'   loaded by fwapg).
#' @param host Host label; see [lnk_artifact_record()].
#' @param max_fail Stop sending `HEAD`s after this many consecutive failures
#'   (no response at all); the rest are recorded with no identity and a note.
#'
#' @return Invisibly, the probed rows, with the HTTP `status` of each `HEAD`.
#'
#' @family provenance
#' @export
#'
#' @examples
#' # The FWA artifacts a probe would HEAD for two watershed groups:
#' prims <- link:::.lnk_input_primitives()
#' fwa <- prims[startsWith(prims$source, "fwapg/"), ]
#' link:::.lnk_artifact_expand(fwa, wsg = c("BULK", "MORR"))[, c("kind", "url")]
#'
#' \dontrun{
#' conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
#'                     user = "postgres", password = "postgres")
#' lnk_artifact_probe(conn)
#' }
lnk_artifact_probe <- function(conn, tables = NULL, host = .lnk_host(),
                               max_fail = 5L) {
  prims <- .lnk_input_primitives()
  if (is.null(tables)) {
    tables <- prims$table_name[startsWith(prims$source, "fwapg/")]
  }
  stopifnot(all(tables %in% prims$table_name))
  prims <- prims[prims$table_name %in% tables, , drop = FALSE]

  wsg <- character(0)
  if (any(grepl("{wsg}", prims$url, fixed = TRUE))) {
    wsg <- .lnk_artifact_wsgs(conn)
  }
  a <- .lnk_artifact_expand(prims, wsg)

  # Sequential HEADs, so a store that black-holes requests would cost
  # n x timeout. Stop asking after `max_fail` consecutive failures and record
  # the rest as not probed -- an honest NULL, with the reason.
  heads <- vector("list", nrow(a))
  fails <- 0L
  for (i in seq_len(nrow(a))) {
    if (a$kind[i] != "object") {
      heads[[i]] <- .lnk_artifact_head_na()
    } else if (fails >= max_fail) {
      heads[[i]] <- .lnk_artifact_head_na(sprintf(
        "not probed: %d consecutive HEAD failures before it", max_fail))
    } else {
      heads[[i]] <- .lnk_artifact_head(a$url[i])
      fails <- if (is.na(heads[[i]]$status)) fails + 1L else 0L
    }
  }
  a <- cbind(a, do.call(rbind, heads))
  lnk_artifact_record(conn, a, recorded_by = "probe", host = host)
  n_bad <- sum(a$kind == "object" & is.na(a$version_id))
  message(sprintf("[artifact] probed %d artifacts (%d without a version id)",
                  sum(a$kind == "object"), n_bad))
  invisible(a)
}


#' Read the recorded source artifacts, one row per expected artifact
#'
#' Reports every primitive this host should have a record for, with
#' `status = "missing"` where it has none — a missing record is reported, not
#' silently left out. The stream network expands to one expected artifact per
#' watershed group loaded in this database.
#'
#' @param conn A [DBI::DBIConnection-class].
#' @param host Host label; see [lnk_artifact_record()].
#'
#' @return A data frame: the recorded columns plus `status`
#'   (`"recorded"` / `"missing"`).
#'
#' @family provenance
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
#'                     user = "postgres", password = "postgres")
#' a <- lnk_artifact_read(conn)
#' table(a$table_name, a$status)
#' }
lnk_artifact_read <- function(conn, host = .lnk_host()) {
  prims <- .lnk_input_primitives()
  expected <- .lnk_artifact_expand(prims, .lnk_artifact_wsgs(conn))
  have <- if (.lnk_artifact_exists(conn, .lnk_artifact_table())) {
    DBI::dbGetQuery(conn, sprintf(
      "SELECT table_name, url, version_id, etag, last_modified, n_rows,
              loaded_at, recorded_at, recorded_by, notes
         FROM %s WHERE host = %s",
      .lnk_artifact_table(), DBI::dbQuoteLiteral(conn, host)))
  } else {
    NULL
  }
  if (is.null(have) || nrow(have) == 0L) {
    out <- expected
    for (nm in c("version_id", "etag", "recorded_by", "notes")) {
      out[[nm]] <- rep(NA_character_, nrow(out))
    }
    out$status <- rep("missing", nrow(out))
    return(out)
  }
  out <- merge(expected, have, by = c("table_name", "url"), all.x = TRUE,
               sort = FALSE)
  out$status <- ifelse(is.na(out$recorded_by), "missing", "recorded")
  out[order(out$table_name, out$url), , drop = FALSE]
}


# --- internals --------------------------------------------------------------

.lnk_artifact_head_na <- function(notes = NA_character_) {
  data.frame(version_id = NA_character_, etag = NA_character_,
             last_modified = as.POSIXct(NA, tz = "UTC"),
             status = NA_integer_, notes = notes,
             stringsAsFactors = FALSE)
}

# HTTP dates, element by element. httr::parse_http_date() is all-or-nothing:
# one NA or unparseable element makes it return NA for EVERY element, which
# silently blanked last_modified on both loader rows of the first live
# snapshot (the api rows carry none). POSIXct input passes through.
.lnk_http_date <- function(x) {
  if (inherits(x, "POSIXct")) return(as.POSIXct(x, tz = "UTC"))
  out <- rep(as.POSIXct(NA, tz = "UTC"), length(x))
  x <- as.character(x)
  ok <- !is.na(x) & nzchar(x)
  for (i in which(ok)) {
    out[i] <- as.POSIXct(httr::parse_http_date(x[i]), tz = "UTC")
  }
  out
}

# ETags arrive quoted from HTTP ("abc-18") and unquoted from a shell that
# stripped them. Store one form.
.lnk_etag_normalise <- function(x) {
  x <- gsub('"', "", x, fixed = TRUE)
  x[!is.na(x) & !nzchar(x)] <- NA_character_
  x
}

# Watershed groups whose stream network is loaded here.
.lnk_artifact_wsgs <- function(conn) {
  if (!.lnk_artifact_exists(conn, "whse_basemapping.fwa_stream_networks_sp")) {
    return(character(0))
  }
  sort(DBI::dbGetQuery(conn,
    "SELECT DISTINCT watershed_group_code AS w
       FROM whse_basemapping.fwa_stream_networks_sp
      WHERE watershed_group_code IS NOT NULL")$w)
}

.lnk_artifact_exists <- function(conn, tables) {
  vapply(tables, function(t) {
    r <- DBI::dbGetQuery(conn, sprintf(
      "SELECT to_regclass(%s) IS NOT NULL AS e", DBI::dbQuoteLiteral(conn, t)))
    nrow(r) == 1L && isTRUE(r$e[1])
  }, logical(1), USE.NAMES = FALSE)
}

# Exact row counts per artifact: per watershed group for a `{wsg}` artifact,
# the whole table otherwise. NA where the table does not exist.
.lnk_artifact_count <- function(conn, a) {
  prims <- .lnk_input_primitives()
  n <- rep(NA_real_, nrow(a))
  for (tbl in unique(a$table_name)) {
    i <- which(a$table_name == tbl)
    if (!.lnk_artifact_exists(conn, tbl)) next
    tmpl <- prims$url[prims$table_name == tbl]
    if (grepl("{wsg}", tmpl, fixed = TRUE)) {
      w <- sub("^.*/([A-Z]{4})\\.parquet$", "\\1", a$url[i])
      cnt <- DBI::dbGetQuery(conn, sprintf(
        "SELECT watershed_group_code AS w, count(*)::float8 AS n
           FROM %s WHERE watershed_group_code IN (%s)
          GROUP BY 1", tbl,
        paste(vapply(unique(w), function(x)
          as.character(DBI::dbQuoteLiteral(conn, x)), character(1)),
          collapse = ", ")))
      n[i] <- cnt$n[match(w, cnt$w)]
      n[i][is.na(n[i])] <- 0
    } else {
      n[i] <- DBI::dbGetQuery(conn, sprintf(
        "SELECT count(*)::float8 AS n FROM %s", tbl))$n[1]
    }
  }
  n
}

