# A one-group run on a machine that holds only some groups (#465).
#
# A group's access is walked downstream through every group's persisted
# `barriers` and `barrier_overrides`. lnk_downstream_files() reads, from a
# habitat export, which groups' rows a target's walk can read (the export's
# line-rule dependency map) and the parts that hold them;
# lnk_downstream_load() puts those rows into a persist schema, so a
# lnk_pipeline_run() of the target there reads what the provincial run read.

# nolint start: indentation_linter
#' Which export files a one-group run needs from the groups downstream of it
#'
#' A group's access is classified by walking downstream through the barriers
#' and barrier overrides that every other group persisted. On a machine that
#' holds only some groups, those rows come from the habitat export: this lists,
#' for a target group, every group whose rows its walk can read (the export's
#' dependency map, which errs wide) and the per-group parts holding them.
#'
#' Each dependency is one of:
#' - `exported`: its `barriers` and `barrier_overrides` parts are listed, with
#'   the build they came from;
#' - `skipped`: the export asked for it and had no finished build of the
#'   config; its rows are not available, and [lnk_downstream_load()] refuses
#'   unless told to go on without them;
#' - `not_held`: the export took every group its schemas held and this one was
#'   not among them, so the provincial walk read no rows of it either;
#' - `not_exported`: the export named its groups and left this one out.
#'
#' The target's own rows are not listed: its run writes them. `fwa_url` names
#' the dependency's FWA stream object, which a machine needs loaded for the
#' downstream check ([lnk_wsg_downstream_check()]) and for the target's own
#' gradient search, which runs along whole lines.
#'
#' @param manifest Path or URL (`s3://`, `https://`) of an export's
#'   `manifest.json`.
#' @param wsg The target watershed group.
#' @param config The config whose parts to list, as the export names it.
#' @param cache_dir Where the downloaded dependency map is kept.
#' @return A data frame, one row per dependency and table (one row for a
#'   dependency with nothing to fetch): `target`, `config`, `wsg`, `class`,
#'   `reason`, `table`, `key`, `href`, `rows`, `bytes`, `md5`, `run_id`,
#'   `config_hash`, `link_version`, `link_sha`, `fwa_url`.
#' @family export
#' @export
#' @examples
#' \dontrun{
#' f <- lnk_downstream_files("s3://fresh-bc/habitat/fwa/v1/manifest.json",
#'                           wsg = "PARS", config = "default")
#' f[, c("wsg", "class", "table", "rows")]
#' }
lnk_downstream_files <- function(manifest, wsg, config,
                                 cache_dir = tools::R_user_dir("link",
                                                               "cache")) {
  stopifnot(is.character(manifest), length(manifest) == 1L, nzchar(manifest),
            is.character(wsg), length(wsg) == 1L, grepl("^[A-Z]{4}$", wsg),
            is.character(config), length(config) == 1L, nzchar(config))
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("lnk_downstream_files() needs the duckdb package", call. = FALSE)
  }
  m <- jsonlite::fromJSON(.lnk_fetch_text(manifest), simplifyVector = FALSE)
  if (!identical(as.integer(m$manifest_version), 1L)) {
    stop("unsupported manifest_version in ", manifest, call. = FALSE)
  }
  base <- .lnk_manifest_base(manifest)
  d <- m$dependencies
  if (is.null(d)) {
    stop(manifest, " carries no dependency map: it was exported by a link ",
         "from before #465. Re-export it.", call. = FALSE)
  }
  entry <- Filter(function(x) identical(x$config, config), m$configs)
  if (length(entry) == 0L) {
    stop(manifest, " exports no config '", config, "'", call. = FALSE)
  }
  entry <- entry[[1]]

  map_file <- .lnk_part_fetch(data.frame(
    key = d$key, href = paste0(base, "/", d$key), bytes = d$bytes,
    md5 = d$md5, stringsAsFactors = FALSE), cache_dir)
  duck <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(duck, shutdown = TRUE), add = TRUE)
  deps <- DBI::dbGetQuery(duck, sprintf(
    "SELECT dep FROM read_parquet(%s, hive_partitioning = false)
      WHERE wsg = $1 ORDER BY dep", DBI::dbQuoteString(duck, map_file)),
    params = list(wsg))$dep

  gp <- Filter(function(x) identical(x$config, config), m$group_parts)
  runs <- entry$runs
  run_of <- function(w) {
    r <- Filter(function(x) identical(x$watershed_group_code, w), runs)
    if (length(r) == 0L) NULL else r[[1]]
  }
  fwa <- .lnk_input_primitives()
  fwa_tmpl <- fwa$url[fwa$table_name == "whse_basemapping.fwa_stream_networks_sp"]
  tables <- names(.lnk_export_group_tables())
  skipped <- entry$skipped %||% list()
  scope <- entry$scope %||% "named"

  rows <- lapply(deps, function(w) {
    base_row <- data.frame(
      target = wsg, config = config, wsg = w, class = NA_character_,
      reason = NA_character_, table = NA_character_, key = NA_character_,
      href = NA_character_, rows = NA_real_, bytes = NA_real_,
      md5 = NA_character_, run_id = NA_character_,
      config_hash = NA_character_, link_version = NA_character_,
      link_sha = NA_character_, fwa_url = gsub("{wsg}", w, fwa_tmpl,
                                                fixed = TRUE),
      stringsAsFactors = FALSE)
    mine <- Filter(function(x) identical(x$wsg, w), gp)
    if (length(mine) > 0L) {
      have <- vapply(mine, function(x) x$dataset, character(1))
      want <- .lnk_export_group_dataset(tables)
      if (!setequal(have, want)) {
        stop(manifest, " lists ", paste(have, collapse = ", "), " for ", w,
             " but not every per-group table (", paste(want, collapse = ", "),
             ")", call. = FALSE)
      }
      r <- run_of(w)
      out <- do.call(rbind, lapply(mine, function(x) {
        b <- base_row
        b$class <- "exported"
        b$table <- sub("^habitat/fwa/v1/", "", x$dataset)
        b$key <- x$key
        b$href <- paste0(base, "/", x$key)
        b$rows <- as.numeric(x$rows)
        b$bytes <- as.numeric(x$bytes)
        b$md5 <- x$md5
        b$run_id <- x$run_id
        b$config_hash <- r$config_hash %||% NA_character_
        b$link_version <- r$link_version %||% NA_character_
        b$link_sha <- r$link_sha %||% NA_character_
        b
      }))
      return(out[order(out$table, method = "radix"), , drop = FALSE])
    }
    if (!is.null(skipped[[w]])) {
      base_row$class <- "skipped"
      base_row$reason <- paste("no finished build of the config:",
                               skipped[[w]])
    } else if (identical(scope, "held")) {
      base_row$class <- "not_held"
      base_row$reason <- paste("the exported schemas held no build of it,",
                               "so no walk read rows of it")
    } else {
      base_row$class <- "not_exported"
      base_row$reason <- paste("the export named its groups and left this",
                               "one out; export it, or every held group")
    }
    base_row
  })
  out <- if (length(rows) == 0L) {
    data.frame(target = character(0), config = character(0),
               wsg = character(0), class = character(0),
               reason = character(0), table = character(0), key = character(0),
               href = character(0), rows = numeric(0), bytes = numeric(0),
               md5 = character(0), run_id = character(0),
               config_hash = character(0), link_version = character(0),
               link_sha = character(0), fwa_url = character(0),
               stringsAsFactors = FALSE)
  } else {
    do.call(rbind, rows)
  }
  rownames(out) <- NULL
  attr(out, "manifest") <- manifest
  attr(out, "built") <- m$built
  out
}

#' Column shape of `<schema>.log_downstream_load`: one row per group and
#' table, the rows a schema holds that came from an export, not a build here.
#' @noRd
cols_log_downstream_load <- c(
  watershed_group_code = "varchar(4) NOT NULL",
  table_name           = "text NOT NULL",
  config               = "text NOT NULL",
  run_id               = "text NOT NULL",
  config_hash          = "text",
  link_version         = "text",
  link_sha             = "text",
  part_key             = "text NOT NULL",
  part_md5             = "text NOT NULL",
  rows                 = "bigint NOT NULL",
  manifest             = "text NOT NULL",
  manifest_built       = "text",
  loaded_at            = "timestamptz NOT NULL",
  loaded_by_link_sha   = "text"
)

#' Load the downstream groups' barriers into a persist schema
#'
#' Puts the `barriers` and `barrier_overrides` rows that
#' [lnk_downstream_files()] lists into the persist schema `cfg` names
#' (`cfg$pipeline$schema`, set as the run will set it), so a
#' [lnk_pipeline_run()] of the target there walks downstream through the rows
#' the provincial run's walk read. Each part is fetched and checked for size
#' and md5 before the database is touched; every group is then replaced in one
#' transaction, with each part's row count checked, and recorded in
#' `<schema>.log_downstream_load`.
#'
#' It refuses, before writing, when a dependency's rows are not in the export
#' (`skipped` or `not_exported`, unless `allow_missing`), and when the schema
#' holds rows of a dependency group that did not come from an earlier load:
#' a build of the group here (a finished `<schema>.log` row), or rows of
#' unknown origin (unless `replace`).
#'
#' It reports, without refusing, each dependency build whose `config_hash`
#' differs from `cfg`'s bundle: the rows were built under other rules than the
#' target will be. The target's own inputs on this machine (observations above
#' all) still decide its own barriers and lifts.
#'
#' @param conn DBI connection to the target database.
#' @param files The data frame [lnk_downstream_files()] returns, for one
#'   target and config.
#' @param cfg The `lnk_config` the target will be modelled with, its
#'   `pipeline$schema` set to the persist schema the run writes.
#' @param replace Replace a dependency group's rows even when this schema built
#'   them, or holds them from no recorded load.
#' @param allow_missing Load what the export has even when some dependencies'
#'   rows are not in it.
#' @param cache_dir Where downloaded parts are kept.
#' @return Invisibly, a data frame per dependency loaded: `wsg`, `run_id`,
#'   `barriers`, `barrier_overrides` (rows), `config_hash`, `config_same`.
#' @family export
#' @export
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
#'                     user = "postgres", password = "postgres")
#' cfg <- lnk_config("default")
#' cfg$pipeline$schema <- "fresh_default"
#' f <- lnk_downstream_files("s3://fresh-bc/habitat/fwa/v1/manifest.json",
#'                           wsg = "PARS", config = "default")
#' lnk_downstream_load(conn, f, cfg)
#' }
lnk_downstream_load <- function(conn, files, cfg, replace = FALSE,
                                allow_missing = FALSE,
                                cache_dir = tools::R_user_dir("link",
                                                              "cache")) {
  stopifnot(inherits(conn, "DBIConnection"), is.data.frame(files),
            inherits(cfg, "lnk_config"),
            is.logical(replace), length(replace) == 1L,
            is.logical(allow_missing), length(allow_missing) == 1L)
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("lnk_downstream_load() needs the duckdb package", call. = FALSE)
  }
  need <- c("target", "config", "wsg", "class", "table", "key", "href",
            "rows", "bytes", "md5", "run_id", "config_hash", "link_version",
            "link_sha")
  if (!all(need %in% names(files))) {
    stop("files lacks ", paste(setdiff(need, names(files)), collapse = ", "),
         "; list them with lnk_downstream_files()", call. = FALSE)
  }
  if (nrow(files) > 0L &&
      (length(unique(files$target)) != 1L ||
       length(unique(files$config)) != 1L)) {
    stop("files must list one target and one config", call. = FALSE)
  }
  miss <- files[files$class %in% c("skipped", "not_exported"), , drop = FALSE]
  if (nrow(miss) > 0L && !allow_missing) {
    stop("the export lacks the rows of ", nrow(miss), " group(s) the target's ",
         "walk can read: ", paste(sprintf("%s (%s)", miss$wsg, miss$reason),
                                  collapse = "; "),
         ". Re-export, or pass allow_missing = TRUE.", call. = FALSE)
  }
  ex <- files[files$class == "exported", , drop = FALSE]
  if (nrow(ex) == 0L) {
    message("no downstream group's rows to load")
    return(invisible(data.frame(wsg = character(0))))
  }
  # every part fetched and checked before the database is touched
  local <- vapply(seq_len(nrow(ex)), function(i) {
    .lnk_part_fetch(ex[i, , drop = FALSE], cache_dir)
  }, character(1))

  tn <- .lnk_table_names(cfg)
  schema <- tn$schema
  .lnk_validate_identifier(schema, "schema")
  lnk_persist_init(conn, cfg, species = cfg$species)
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE IF NOT EXISTS %s.log_downstream_load (\n  %s\n)", schema,
    .lnk_cols_clause(cols_log_downstream_load,
                     c("watershed_group_code", "table_name"))))

  # a dependency's rows here must be absent or from an earlier load
  groups <- sort(unique(ex$wsg))
  arr <- paste0("{", paste(groups, collapse = ","), "}")
  built_here <- if (.lnk_table_exists(conn, paste0(schema, ".log"))) {
    DBI::dbGetQuery(conn, sprintf(
      "SELECT DISTINCT watershed_group_code::text AS w FROM %s.log
        WHERE date_end IS NOT NULL AND watershed_group_code = ANY($1)",
      schema), params = list(arr))$w
  } else {
    character(0)
  }
  held <- unique(unlist(lapply(names(.lnk_export_group_tables()), function(t) {
    DBI::dbGetQuery(conn, sprintf(
      "SELECT DISTINCT watershed_group_code::text AS w FROM %s.%s
        WHERE watershed_group_code = ANY($1)", schema, t),
      params = list(arr))$w
  })))
  loaded_before <- DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT watershed_group_code::text AS w
       FROM %s.log_downstream_load", schema))$w
  unknown <- setdiff(held, c(built_here, loaded_before))
  if (!replace && length(c(built_here, unknown)) > 0L) {
    stop(schema, " holds rows of ",
         paste(c(if (length(built_here) > 0L) paste0(
                   paste(built_here, collapse = ", "), " (built here)"),
                 if (length(unknown) > 0L) paste0(
                   paste(unknown, collapse = ", "), " (no recorded load)")),
               collapse = " and "),
         ". Pass replace = TRUE to replace them with the export's.",
         call. = FALSE)
  }

  tabs <- .lnk_export_group_tables()
  duck <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(duck, shutdown = TRUE), add = TRUE)
  link_sha <- .lnk_pkg_git_sha("link")
  n_loaded <- stats::setNames(rep(NA_real_, nrow(ex)), ex$key)
  DBI::dbWithTransaction(conn, {
    for (i in seq_len(nrow(ex))) {
      t <- ex$table[i]
      w <- ex$wsg[i]
      if (!t %in% names(tabs)) {
        stop("not a per-group table: ", t, call. = FALSE)
      }
      cols <- tabs[[t]]$cols
      df <- DBI::dbGetQuery(duck, sprintf(
        "SELECT * FROM read_parquet(%s, hive_partitioning = false)",
        DBI::dbQuoteString(duck, local[i])))
      if (!identical(names(df), names(cols))) {
        stop(ex$key[i], " does not hold ", t, "'s columns", call. = FALSE)
      }
      if (nrow(df) != ex$rows[i]) {
        stop(sprintf("%s: read %d rows, the manifest says %d", ex$key[i],
                     nrow(df), ex$rows[i]), call. = FALSE)
      }
      if (any(df$watershed_group_code != w)) {
        stop(ex$key[i], " holds rows of another group", call. = FALSE)
      }
      DBI::dbExecute(conn, sprintf(
        "DELETE FROM %s.%s WHERE watershed_group_code = $1", schema, t),
        params = list(w))
      n <- 0
      if (nrow(df) > 0L) {
        DBI::dbWriteTable(conn, "lnk_downstream_stage", .lnk_df_plain(df),
                          temporary = TRUE, overwrite = TRUE)
        load <- vapply(names(cols), function(n) {
          .lnk_export_group_col(n, cols[[n]])$load
        }, character(1))
        n <- DBI::dbExecute(conn, sprintf(
          "INSERT INTO %s.%s (%s) SELECT %s FROM lnk_downstream_stage",
          schema, t, paste(names(cols), collapse = ", "),
          paste(load, collapse = ", ")))
        DBI::dbExecute(conn, "DROP TABLE lnk_downstream_stage")
      }
      if (n != ex$rows[i]) {
        stop(sprintf("%s: wrote %d rows, the manifest says %d", ex$key[i], n,
                     ex$rows[i]), call. = FALSE)
      }
      n_loaded[[i]] <- n
      DBI::dbExecute(conn, sprintf(
        "INSERT INTO %s.log_downstream_load (%s)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, now(), $13)
         ON CONFLICT (watershed_group_code, table_name) DO UPDATE SET
           config = EXCLUDED.config, run_id = EXCLUDED.run_id,
           config_hash = EXCLUDED.config_hash,
           link_version = EXCLUDED.link_version,
           link_sha = EXCLUDED.link_sha, part_key = EXCLUDED.part_key,
           part_md5 = EXCLUDED.part_md5, rows = EXCLUDED.rows,
           manifest = EXCLUDED.manifest,
           manifest_built = EXCLUDED.manifest_built,
           loaded_at = EXCLUDED.loaded_at,
           loaded_by_link_sha = EXCLUDED.loaded_by_link_sha",
        schema, paste(names(cols_log_downstream_load), collapse = ", ")),
        params = list(w, t, ex$config[i], ex$run_id[i], ex$config_hash[i],
                      ex$link_version[i], ex$link_sha[i], ex$key[i],
                      ex$md5[i], n,
                      attr(files, "manifest") %||% NA_character_,
                      attr(files, "built") %||% NA_character_,
                      link_sha %||% NA_character_))
    }
  })
  for (t in names(tabs)) {
    DBI::dbExecute(conn, sprintf("ANALYZE %s.%s", schema, t))
  }

  hash_here <- .lnk_config_hash(cfg)
  rep <- do.call(rbind, lapply(groups, function(w) {
    x <- ex[ex$wsg == w, , drop = FALSE]
    data.frame(wsg = w, run_id = x$run_id[1],
               barriers = n_loaded[[x$key[x$table == "barriers"]]],
               barrier_overrides =
                 n_loaded[[x$key[x$table == "barrier_overrides"]]],
               config_hash = x$config_hash[1],
               config_same = identical(x$config_hash[1], hash_here),
               stringsAsFactors = FALSE)
  }))
  other <- rep$wsg[!rep$config_same]
  if (length(other) > 0L) {
    message("built under another bundle than this cfg's (", hash_here, "): ",
            paste(sprintf("%s (%s)", other, rep$config_hash[!rep$config_same]),
                  collapse = ", "))
  }
  invisible(rep)
}
# nolint end: indentation_linter
