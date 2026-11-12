# Input snapshots in the habitat export (#465).
#
# A one-group run that reads its downstream groups' barriers from the export
# can disagree with them about a dam added or reclassified since they were
# built. CABD and PSCIS come from APIs with no version handle, so the export
# carries them, province-wide and keyed by content, for each build whose
# loader-recorded content md5 is what the exporting database holds now. The
# observations and modelled crossings are versioned objects, which each build
# already names by loader version id, so the export cites them.

# nolint start: indentation_linter
#' The `api` primitives the export snapshots (short name -> table), and the
#' object primitives it cites by version.
#' @noRd
.lnk_export_input_tables <- function() {
  list(
    snapshot = c(cabd_dams = "cabd.dams",
                 pscis_assessment = "whse_fish.pscis_assessment_svw"),
    cited = c(observations = "bcfishobs.observations",
              modelled_crossings = "fresh.modelled_stream_crossings")
  )
}

#' A table's rows as text, in the order its content md5 reads them.
#'
#' Every column goes as its Postgres text form (geometry as hex EWKB, which
#' keeps its SRID), so the snapshot holds what the table held whatever its
#' types; the column types are recorded beside it.
#' @return A list: `rows` (data frame of text columns) and `columns`
#'   (data frame of `name`, `type`).
#' @noRd
.lnk_export_table_text <- function(conn, table) {
  p <- .lnk_parse_table(table)
  cols <- DBI::dbGetQuery(conn,
    "SELECT a.attname::text AS name, format_type(a.atttypid, a.atttypmod) AS type
       FROM pg_attribute a
      WHERE a.attrelid = to_regclass($1) AND a.attnum > 0 AND NOT a.attisdropped
      ORDER BY a.attnum", params = list(table))
  if (nrow(cols) == 0L) stop(table, " has no columns", call. = FALSE)
  sel <- vapply(seq_len(nrow(cols)), function(i) {
    n <- DBI::dbQuoteIdentifier(conn, cols$name[i])
    if (startsWith(cols$type[i], "geometry")) {
      sprintf("encode(ST_AsEWKB(t.%s), 'hex') AS %s", n, n)
    } else {
      sprintf("t.%s::text AS %s", n, n)
    }
  }, character(1))
  rows <- DBI::dbGetQuery(conn, sprintf(
    "SELECT %s FROM %s.%s t ORDER BY t::text COLLATE \"C\"",
    paste(sel, collapse = ", "),
    DBI::dbQuoteIdentifier(conn, p$schema),
    DBI::dbQuoteIdentifier(conn, p$table)))
  list(rows = .lnk_df_plain(rows), columns = cols)
}

#' Each exported build's inputs: a snapshot key or the reason it has none, and
#' the versioned objects it read.
#'
#' A snapshot is written (once, at `inputs/<name>/<md5>.parquet`) only when the
#' build's logged content md5 equals the table's content md5 in the exporting
#' database now; a key already in the root is referenced without asking again.
#' Otherwise the reason: `not read` (CABD under `dams = FALSE`), `no content
#' identity at build` (logged before #465, or by a loader that recorded none),
#' `changed since build`.
#' @param runs The config's exported runs (`r_cf`): `run_id`, `schema_export`,
#'   and `arg_dams` where logged.
#' @return A list: `runs` (named by `run_id`, each a list per input) and
#'   `files` (file entries of kind `input`, or NULL).
#' @noRd
.lnk_export_inputs <- function(conn, runs, root) {
  tabs <- .lnk_export_input_tables()
  all_tbl <- c(tabs$snapshot, tabs$cited)
  logged <- do.call(rbind, lapply(unique(runs$schema_export), function(s) {
    li <- paste0(s, ".log_input")
    if (!.lnk_table_exists(conn, li)) return(NULL)
    cols <- .lnk_table_columns(conn, li)
    md5 <- if ("artifact_content_md5" %in% cols) {
      "artifact_content_md5"
    } else {
      "NULL::text"
    }
    DBI::dbGetQuery(conn, sprintf(
      "SELECT run_id, table_name, artifact_url, artifact_version_id,
              artifact_etag, artifact_recorded_by, %s AS content_md5
         FROM %s WHERE run_id = ANY($1) AND table_name = ANY($2)", md5, li),
      params = list(paste0("{", paste(runs$run_id, collapse = ","), "}"),
                    paste0("{", paste(all_tbl, collapse = ","), "}")))
  }))
  now <- vapply(tabs$snapshot, function(t) .lnk_table_content_md5(conn, t),
                character(1))
  files <- list()
  written <- character(0)
  out <- stats::setNames(lapply(seq_len(nrow(runs)), function(i) {
    id <- runs$run_id[i]
    li <- if (is.null(logged)) NULL else logged[logged$run_id == id, , drop = FALSE]
    row_of <- function(t) {
      if (is.null(li)) return(NULL)
      r <- li[li$table_name == t, , drop = FALSE]
      if (nrow(r) == 0L) NULL else r
    }
    snap <- lapply(names(tabs$snapshot), function(nm) {
      t <- tabs$snapshot[[nm]]
      r <- row_of(t)
      m <- if (is.null(r)) NA_character_ else r$content_md5[1]
      if (identical(nm, "cabd_dams") && "arg_dams" %in% names(runs) &&
          isFALSE(as.logical(runs$arg_dams[i]))) {
        return(list(key = NULL, content_md5 = m, reason = "not read"))
      }
      if (is.na(m) || !nzchar(m)) {
        return(list(key = NULL, content_md5 = NULL,
                    reason = "no content identity at build"))
      }
      key <- sprintf("inputs/%s/%s.parquet", nm, m)
      if (!file.exists(file.path(root, key))) {
        if (!identical(m, now[[nm]])) {
          return(list(key = NULL, content_md5 = m,
                      reason = "changed since build"))
        }
        x <- .lnk_export_table_text(conn, t)
        .lnk_write_once(file.path(root, key), function(p) {
          .lnk_parquet_write(x$rows, p)
        }, same = .lnk_parquet_same)
        files[[length(files) + 1L]] <<- local({
          e <- .lnk_file_entry(root, key)
          e$kind <- "input"
          e$run_key <- NA_character_
          e
        })
        written <<- c(written, key)
      } else if (!key %in% written) {
        files[[length(files) + 1L]] <<- local({
          e <- .lnk_file_entry(root, key)
          e$kind <- "input"
          e$run_key <- NA_character_
          e
        })
        written <<- c(written, key)
      }
      list(key = key, content_md5 = m, table = t, reason = NULL)
    })
    names(snap) <- names(tabs$snapshot)
    cited <- lapply(names(tabs$cited), function(nm) {
      r <- row_of(tabs$cited[[nm]])
      if (is.null(r)) return(list(table = tabs$cited[[nm]], url = NULL))
      list(table = tabs$cited[[nm]], url = r$artifact_url[1],
           version_id = r$artifact_version_id[1], etag = r$artifact_etag[1],
           recorded_by = r$artifact_recorded_by[1])
    })
    names(cited) <- names(tabs$cited)
    c(snap, cited)
  }), runs$run_id)
  list(runs = out, files = if (length(files) == 0L) NULL else do.call(rbind, files))
}
# nolint end: indentation_linter
