# nolint start: indentation_linter
#' Load a habitat export into PostgreSQL
#'
#' Fetches the parts a catalog lists, checks each one's size and md5 against
#' the manifest before reading it, and writes their rows to one table, keyed
#' `(config, species, blue_line_key, downstream_route_measure)`. Join it to
#' `whse_basemapping.fwa_stream_networks_sp` by `blue_line_key` and measure to
#' cut each segment's line.
#'
#' Everything runs in one transaction: a part that fails its md5, a column
#' mismatch, a duplicate key or a short read leaves the table as it was.
#' Loading a config replaces that config's rows (all species), so a reload
#' never mixes two builds of one config. Other configs' rows are untouched.
#'
#' @param conn A DBI connection to PostgreSQL.
#' @param catalog A catalog from [lnk_catalog()], optionally filtered to some
#'   of its parts. A config is loaded from the parts given for it, so filter by
#'   config rather than by species when reloading.
#' @param configs Configs to load, or `NULL` for every config in `catalog`.
#' @param table Target table, `schema.table`. Defaults to the name the dataset
#'   ID gives, `habitat.fwa_v1_segment`.
#' @param cache_dir Where downloaded parts are kept. A cached part is reused
#'   while its md5 still matches the manifest. Local parts are read in place.
#' @return Invisibly, a data frame of `key` and `rows` loaded.
#' @family export
#' @export
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
#'                     user = "postgres", password = "postgres")
#' cat <- lnk_catalog("s3://fresh-bc/habitat/fwa/v1/manifest.json")
#' lnk_db_load(conn, cat, configs = "default")
#'
#' DBI::dbGetQuery(conn, "
#'   SELECT species, round(sum(length_metre) / 1000) AS rearing_km
#'     FROM habitat.fwa_v1_segment
#'    WHERE config = 'default' AND rearing
#'    GROUP BY species")
#' }
lnk_db_load <- function(conn, catalog, configs = NULL,
                        table = "habitat.fwa_v1_segment",
                        cache_dir = tools::R_user_dir("link", "cache")) {
  stopifnot(inherits(conn, "DBIConnection"), is.data.frame(catalog),
            is.null(configs) || is.character(configs))
  .lnk_validate_identifier(table, "table")
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("lnk_db_load() needs the duckdb package", call. = FALSE)
  }
  need <- c("config", "species", "key", "href", "rows", "bytes", "md5")
  if (!all(need %in% names(catalog))) {
    stop("catalog lacks ", paste(setdiff(need, names(catalog)), collapse = ", "),
         "; read it with lnk_catalog()", call. = FALSE)
  }
  if (!is.null(configs)) {
    unknown <- setdiff(configs, catalog$config)
    if (length(unknown) > 0L) {
      stop("catalog has no config ", paste(unknown, collapse = ", "),
           call. = FALSE)
    }
    catalog <- catalog[catalog$config %in% configs, , drop = FALSE]
  }
  if (nrow(catalog) == 0L) stop("nothing to load", call. = FALSE)

  # every part is fetched and checked before the database is touched
  local <- vapply(seq_len(nrow(catalog)), function(i) {
    .lnk_part_fetch(catalog[i, ], cache_dir)
  }, character(1))

  cols <- .lnk_export_cols()
  pg_type <- c(integer = "integer", double = "double precision",
               string = "text", logical = "boolean")
  ddl <- c(config = "text NOT NULL", species = "text NOT NULL",
           stats::setNames(pg_type[cols], names(cols)))
  parts <- .lnk_parse_table(table)
  tq <- .lnk_quote_table(conn, table)

  duck <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(duck, shutdown = TRUE), add = TRUE)

  loaded <- data.frame(key = catalog$key, rows = 0, stringsAsFactors = FALSE)
  created <- FALSE
  DBI::dbWithTransaction(conn, {
    DBI::dbExecute(conn, sprintf("CREATE SCHEMA IF NOT EXISTS %s",
                                 DBI::dbQuoteIdentifier(conn, parts$schema)))
    if (.lnk_table_exists(conn, table)) {
      have <- .lnk_table_columns(conn, table)
      if (!identical(have, names(ddl))) {
        stop(table, " has other columns than this export. A new column ",
             "contract belongs in a new table (a new dataset version).",
             call. = FALSE)
      }
    } else {
      DBI::dbExecute(conn, sprintf(
        "CREATE TABLE %s (%s)", tq,
        paste(sprintf("%s %s", names(ddl), ddl), collapse = ", ")))
      created <- TRUE
    }
    DBI::dbExecute(conn, sprintf("DELETE FROM %s WHERE config = ANY($1)", tq),
                   params = list(paste0("{", paste(unique(catalog$config),
                                                   collapse = ","), "}")))
    for (i in seq_len(nrow(catalog))) {
      res <- DBI::dbSendQuery(duck, sprintf(
        "SELECT * FROM read_parquet(%s, hive_partitioning = false)",
        DBI::dbQuoteString(duck, local[i])))
      n <- 0
      while (!DBI::dbHasCompleted(res)) {
        chunk <- DBI::dbFetch(res, n = 1e6)
        if (nrow(chunk) == 0L) next
        if (!identical(names(chunk), names(cols))) {
          DBI::dbClearResult(res)
          stop(catalog$key[i], " does not hold the export's columns",
               call. = FALSE)
        }
        chunk <- cbind(data.frame(config = catalog$config[i],
                                  species = catalog$species[i],
                                  stringsAsFactors = FALSE), chunk)
        DBI::dbAppendTable(conn, DBI::Id(schema = parts$schema,
                                         table = parts$table), chunk)
        n <- n + nrow(chunk)
      }
      DBI::dbClearResult(res)
      if (n != catalog$rows[i]) {
        stop(sprintf("%s: read %d rows, the manifest says %d",
                     catalog$key[i], n, catalog$rows[i]), call. = FALSE)
      }
      loaded$rows[i] <- n
    }
    if (created) {
      DBI::dbExecute(conn, sprintf(
        "ALTER TABLE %s ADD PRIMARY KEY (config, species, blue_line_key,
                                         downstream_route_measure)", tq))
      DBI::dbExecute(conn, sprintf(
        "CREATE INDEX ON %s (blue_line_key)", tq))
      DBI::dbExecute(conn, sprintf(
        "CREATE INDEX ON %s (watershed_group_code)", tq))
    }
    DBI::dbExecute(conn, sprintf(
      "COMMENT ON TABLE %s IS %s", tq, DBI::dbQuoteLiteral(conn, sprintf(
        "link habitat export, dataset %s, from %s (built %s); last load: %s",
        .lnk_export_dataset(),
        attr(catalog, "manifest") %||% "<catalog without a manifest path>",
        attr(catalog, "built") %||% "?",
        paste(sort(unique(catalog$config)), collapse = ", ")))))
  })
  DBI::dbExecute(conn, sprintf("ANALYZE %s", tq))
  invisible(loaded)
}

#' A part as a verified local file.
#'
#' A local href is checked in place. A remote one is downloaded to
#' `<cache>/<key>.part`, checked for size and md5, and only then renamed to its
#' key, so a cached file is always one that passed; a cached file whose md5 no
#' longer matches (the build moved) is fetched again.
#' @noRd
.lnk_part_fetch <- function(part, cache_dir) {
  href <- part$href[[1]]
  check <- function(f) {
    isTRUE(file.exists(f)) &&
      identical(as.numeric(file.size(f)), as.numeric(part$bytes[[1]])) &&
      identical(unname(tools::md5sum(f)), part$md5[[1]])
  }
  if (!startsWith(href, "s3://") && !grepl("^https?://", href)) {
    if (!check(href)) {
      stop(part$key[[1]], " (", href, ") does not match the manifest's ",
           "size and md5", call. = FALSE)
    }
    return(href)
  }
  dest <- file.path(cache_dir, part$key[[1]])
  if (check(dest)) return(dest)
  tmp <- paste0(dest, ".part")
  on.exit(unlink(tmp), add = TRUE)
  .lnk_fetch_file(href, tmp)
  if (!check(tmp)) {
    stop(part$key[[1]], " from ", href, " does not match the manifest's ",
         "size and md5", call. = FALSE)
  }
  if (!file.rename(tmp, dest)) stop("could not move ", tmp, call. = FALSE)
  dest
}
# nolint end: indentation_linter
