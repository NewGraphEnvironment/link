#' Is the discharge a config reads loaded in this database?
#'
#' prepare joins mean annual discharge onto every watershed group's streams,
#' `cw` groups included, from the source the config names
#' (`pipeline: discharge_source`): `fwapg`'s
#' `whse_basemapping.fwa_stream_networks_discharge` by default, or `wet`'s
#' published `discharge.fwa_v1_segment_monthly`. A host without that table
#' fails every group at prepare, so a multi-host run checks each host before
#' it dispatches work there.
#'
#' For `wet` the check is for an annual pick (`scenario = 'historical'`,
#' `month = 0`, `pick`), which is all the pipeline reads. A pipeline host can
#' load just that:
#' `wet::wet_db_load(conn, wet::wet_catalog(), months = 0, pick_only = TRUE)`
#' (about 4.5 M rows, against 103 M for every month and source).
#'
#' @param conn A DBI connection. Not used when `state` is given.
#' @param cfg An `lnk_config` from [lnk_config()].
#' @param state A one-row data frame with `exists` (the table is there),
#'   `valued` (it holds at least one value the pipeline reads) and `comment`
#'   (the table's comment; wet's loader writes its manifest URL, build time
#'   and commit there). Read from `conn` by default; pass one to judge a
#'   state without a database.
#' @param quiet Suppress the human-readable report.
#'
#' @return Invisibly, a list with `ok`, `source`, `table`, `comment` and
#'   `message`.
#'
#' @family preflight
#'
#' @export
#'
#' @examples
#' cfg <- lnk_config("default")
#' cfg$pipeline$discharge_source <- "wet"
#'
#' # Judge a state without touching a database:
#' res <- lnk_preflight_discharge(cfg = cfg, quiet = TRUE,
#'   state = data.frame(exists = FALSE, valued = FALSE, comment = NA))
#' res$ok
#' res$message
lnk_preflight_discharge <- function(conn = NULL, cfg,
                                    state = .lnk_discharge_state(
                                      conn, .lnk_discharge_source(cfg)),
                                    quiet = FALSE) {
  stopifnot(inherits(cfg, "lnk_config") || is.list(cfg),
            is.logical(quiet), length(quiet) == 1L, !is.na(quiet))
  source <- .lnk_discharge_source(cfg)
  stopifnot(is.data.frame(state), nrow(state) == 1L,
            all(c("exists", "valued", "comment") %in% names(state)))
  tbl <- .lnk_discharge_tbl(source)
  ok <- isTRUE(state$exists) && isTRUE(state$valued)
  msg <- if (ok) {
    sprintf("discharge (%s) loaded: %s", source, tbl)
  } else if (!isTRUE(state$exists)) {
    sprintf("discharge (%s): %s does not exist. %s", source, tbl,
            .lnk_discharge_load_hint(source))
  } else {
    sprintf("discharge (%s): %s holds no value the pipeline reads. %s",
            source, tbl, .lnk_discharge_load_hint(source))
  }
  if (!quiet) {
    message(if (ok) "ok   " else "FAIL ", msg)
    if (ok && !is.na(state$comment)) message("     ", state$comment)
  }
  invisible(list(ok = ok, source = source, table = tbl,
                 comment = as.character(state$comment), message = msg))
}

#' How to load a discharge source into a database
#' @noRd
.lnk_discharge_load_hint <- function(source) {
  switch(source,
    wet = paste("Load it with wet::wet_db_load(conn, wet::wet_catalog(),",
                "months = 0, pick_only = TRUE)."),
    fwapg = "It is loaded by fwapg (load.sh).")
}

#' Whether a discharge source's table exists and holds a value, and its comment
#'
#' Cheap: a catalogue lookup and one `LIMIT 1` read through the relation the
#' pipeline reads (wet's goes through its partial index).
#' @noRd
.lnk_discharge_state <- function(conn, source) {
  tbl <- .lnk_discharge_tbl(source)
  oid <- DBI::dbGetQuery(conn, "SELECT to_regclass($1)::oid AS oid",
                         params = list(tbl))$oid
  if (is.na(oid)) {
    return(data.frame(exists = FALSE, valued = FALSE, comment = NA_character_))
  }
  valued <- nrow(DBI::dbGetQuery(conn, sprintf(
    "SELECT 1 FROM %s d WHERE d.mad_m3s IS NOT NULL LIMIT 1",
    .lnk_discharge_rel(source)))) > 0L
  comment <- DBI::dbGetQuery(conn,
    "SELECT obj_description(to_regclass($1), 'pg_class') AS c",
    params = list(tbl))$c
  data.frame(exists = TRUE, valued = valued, comment = as.character(comment))
}
