# Habitat export: per-config Parquet + manifest, keyed by FWA position (#308).
#
# Mirrors NewGraphEnvironment/wet#7's discharge publish: long-form rows, one
# part per FWA top-level drainage, Hive keys in the path (config, species), a
# manifest.json carrying each part's md5 and the link log rows that produced
# it. Readers go through the manifest (lnk_catalog()), and lnk_db_load() puts
# the rows in fwapg.

# nolint start: indentation_linter
#' Dataset ID of the habitat segment export.
#' @noRd
.lnk_export_dataset <- function() "habitat/fwa/v1/segment"

#' The column contract of the export, in crate's schema shape.
#'
#' Kept in link (`inst/extdata/schemas/habitat_fwa_v1_segment.yaml`) until it
#' is registered in crate; the shape is crate's, so the move is a copy.
#' @return The parsed YAML.
#' @noRd
.lnk_export_spec <- function() {
  p <- system.file("extdata", "schemas", "habitat_fwa_v1_segment.yaml",
                   package = "link")
  if (!nzchar(p)) {
    stop("link's inst/extdata/schemas/habitat_fwa_v1_segment.yaml is missing",
         call. = FALSE)
  }
  yaml::read_yaml(p)
}

#' Column names and types of the export, in file order.
#' @noRd
.lnk_export_cols <- function(spec = .lnk_export_spec()) {
  cols <- spec$canonical$cols
  stats::setNames(vapply(cols, function(x) x$type, character(1)),
                  vapply(cols, function(x) x$name, character(1)))
}

#' Check a part's rows against the contract: exact names, order and types.
#'
#' A check, not a repair: a column the query returns with the wrong type is a
#' defect in the query, and coercing it here would hide that.
#' @noRd
.lnk_export_conform <- function(df, cols = .lnk_export_cols()) {
  if (!identical(names(df), names(cols))) {
    stop("export rows do not match the column contract.\n",
         "  expected: ", paste(names(cols), collapse = ", "), "\n",
         "  got:      ", paste(names(df), collapse = ", "), call. = FALSE)
  }
  is_type <- list(
    integer = is.integer, double = is.double,
    string = is.character, logical = is.logical
  )
  bad <- names(cols)[!vapply(names(cols), function(n) {
    isTRUE(is_type[[cols[[n]]]](df[[n]]))
  }, logical(1))]
  if (length(bad) > 0L) {
    stop("export columns of the wrong type: ",
         paste(sprintf("%s (want %s, got %s)", bad, cols[bad],
                       vapply(df[bad], function(x) class(x)[1], character(1))),
               collapse = "; "), call. = FALSE)
  }
  key_na <- vapply(c("blue_line_key", "downstream_route_measure",
                     "upstream_route_measure", "watershed_group_code"),
                   function(n) anyNA(df[[n]]), logical(1))
  if (any(key_na)) {
    stop("export key columns hold NA: ",
         paste(names(key_na)[key_na], collapse = ", "), call. = FALSE)
  }
  flags <- c("accessible", "spawning", "rearing", "lake_rearing",
             "wetland_rearing")
  flag_na <- vapply(flags, function(n) anyNA(df[[n]]), logical(1))
  if (any(flag_na)) {
    stop("export flags hold NA (a species with no habitat must read FALSE): ",
         paste(flags[flag_na], collapse = ", "), call. = FALSE)
  }
  invisible(df)
}

#' Drop RPostgres' `pq_*` classes so a frame writes as plain R types.
#' @noRd
.lnk_df_plain <- function(df) {
  for (n in names(df)) {
    cl <- class(df[[n]])
    if (any(startsWith(cl, "pq_"))) {
      df[[n]] <- unclass(df[[n]])
      attr(df[[n]], "class") <- setdiff(cl, cl[startsWith(cl, "pq_")])
      if (length(class(df[[n]])) == 0L || identical(class(df[[n]]), "")) {
        df[[n]] <- as.vector(df[[n]])
      }
    }
  }
  df
}

#' Threshold casts from the logged text snapshot: blank and NA read NULL.
#' @noRd
.lnk_export_num <- function(col) {
  sprintf("nullif(btrim(%s), '')::double precision", col)
}

#' The export rows of one species in one watershed group.
#'
#' One query: `streams` LEFT JOIN `streams_habitat_<sp>` and `streams_access`
#' on the full persist key, so a group sharing an `id_segment` with another
#' cannot fan out (#203). The species must be one the build modelled: a
#' habitat table with no rows for the group stops, rather than reading FALSE
#' for a species that was never classified there. Discharge is the
#' subquery the run classified on, with the run's logged fill. Ratios use the
#' thresholds the run logged at its `config_hash`, so they agree with the
#' flags; where the run logged none (builds before #282), they are NA.
#'
#' @param conn DBI connection.
#' @param schema Persist schema.
#' @param wsg One watershed group code.
#' @param sp One species code.
#' @param run One row of `<schema>.log` (a list or one-row data frame) with
#'   `config_hash` and `discharge_fill`.
#' @return A data frame in the column contract's order, sorted by
#'   `blue_line_key`, `downstream_route_measure`.
#' @noRd
.lnk_export_rows <- function(conn, schema, wsg, sp, run) {
  .lnk_validate_identifier(schema, "schema")
  if (!grepl("^[A-Z]{4}$", wsg)) stop("wsg must be a 4-letter code", call. = FALSE)
  if (!grepl("^[A-Z]{2,3}$", sp)) stop("sp must be a species code", call. = FALSE)

  hab <- sprintf("%s.streams_habitat_%s", schema, tolower(sp))
  if (!.lnk_table_exists(conn, hab) || nrow(DBI::dbGetQuery(conn, sprintf(
    "SELECT 1 FROM %s WHERE watershed_group_code = $1 LIMIT 1", hab),
    params = list(wsg))) == 0L) {
    stop(sprintf("%s %s: the build logged %s but %s has no rows for it",
                 schema, wsg, sp, hab), call. = FALSE)
  }
  acc_tbl <- paste0(schema, ".streams_access")
  acc_col <- sprintf("has_barriers_%s_dnstr", tolower(sp))
  has_acc <- .lnk_table_exists(conn, acc_tbl) &&
    acc_col %in% .lnk_table_columns(conn, acc_tbl)
  has_thr <- .lnk_table_exists(
    conn, paste0(schema, ".log_parameters_habitat_thresholds"))
  has_fresh <- .lnk_table_exists(conn, paste0(schema, ".log_parameters_fresh"))

  hash <- DBI::dbQuoteLiteral(conn, as.character(run$config_hash[[1]]))
  spq <- DBI::dbQuoteLiteral(conn, sp)
  thr_cols <- c("spawn_gradient_max", "spawn_channel_width_min",
                "spawn_mad_min", "rear_gradient_max",
                "rear_channel_width_min", "rear_mad_min")
  thr <- if (has_thr) {
    sprintf("SELECT %s FROM %s.log_parameters_habitat_thresholds
              WHERE config_hash = %s AND species_code = %s",
            paste(sprintf("%s AS %s", .lnk_export_num(thr_cols), thr_cols),
                  collapse = ", "),
            schema, hash, spq)
  } else {
    sprintf("SELECT %s",
            paste(sprintf("NULL::double precision AS %s", thr_cols),
                  collapse = ", "))
  }
  acc <- if (has_fresh) {
    sprintf("SELECT %s AS access_gradient_max FROM %s.log_parameters_fresh
              WHERE config_hash = %s AND species_code = %s",
            .lnk_export_num("access_gradient_max"), schema, hash, spq)
  } else {
    "SELECT NULL::double precision AS access_gradient_max"
  }
  flag <- function(f) sprintf("coalesce(h.%s, false) AS %s", f, f)
  ratio <- function(num, den, as) {
    sprintf("%s / nullif(%s, 0) AS %s", num, den, as)
  }
  fill <- isTRUE(as.logical(run$discharge_fill[[1]]))

  sql <- sprintf(
    "WITH thr AS (%s), acc AS (%s)
     SELECT s.blue_line_key::integer AS blue_line_key,
            s.downstream_route_measure::double precision
              AS downstream_route_measure,
            s.upstream_route_measure::double precision
              AS upstream_route_measure,
            s.linear_feature_id::integer AS linear_feature_id,
            s.watershed_group_code::text AS watershed_group_code,
            s.stream_order::integer AS stream_order,
            s.edge_type::integer AS edge_type,
            s.length_metre::double precision AS length_metre,
            s.gradient::double precision AS gradient,
            s.channel_width::double precision AS channel_width,
            s.channel_width_source::text AS channel_width_source,
            d.mad_m3s::double precision AS mad_m3s,
            d.mad_m3s_source::text AS mad_m3s_source,
            %s, %s, %s, %s, %s,
            %s AS has_barriers_dnstr,
            %s,
            %s, %s, %s,
            %s, %s, %s
       FROM %s.streams s
       LEFT JOIN %s h ON h.id_segment = s.id_segment
        AND h.watershed_group_code = s.watershed_group_code
       %s
       LEFT JOIN %s d ON d.linear_feature_id = s.linear_feature_id
       LEFT JOIN thr ON true
       LEFT JOIN acc ON true
      WHERE s.watershed_group_code = %s
      ORDER BY s.blue_line_key, s.downstream_route_measure",
    thr, acc,
    flag("accessible"), flag("spawning"), flag("rearing"),
    flag("lake_rearing"), flag("wetland_rearing"),
    if (has_acc) paste0("a.", acc_col) else "NULL::boolean",
    ratio("s.gradient", "acc.access_gradient_max", "accessible_ratio_gradient"),
    ratio("s.channel_width", "thr.spawn_channel_width_min", "spawning_ratio_cw"),
    ratio("d.mad_m3s", "thr.spawn_mad_min", "spawning_ratio_mad"),
    ratio("s.gradient", "thr.spawn_gradient_max", "spawning_ratio_gradient"),
    ratio("s.channel_width", "thr.rear_channel_width_min", "rearing_ratio_cw"),
    ratio("d.mad_m3s", "thr.rear_mad_min", "rearing_ratio_mad"),
    ratio("s.gradient", "thr.rear_gradient_max", "rearing_ratio_gradient"),
    schema, hab,
    if (has_acc) {
      sprintf("LEFT JOIN %s a ON a.id_segment = s.id_segment
                AND a.watershed_group_code = s.watershed_group_code", acc_tbl)
    } else {
      ""
    },
    .lnk_discharge_sql(wsg = wsg, fill = fill),
    DBI::dbQuoteLiteral(conn, wsg))

  out <- .lnk_df_plain(DBI::dbGetQuery(conn, sql))
  n <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::integer AS n FROM %s.streams
      WHERE watershed_group_code = %s",
    schema, DBI::dbQuoteLiteral(conn, wsg)))$n
  if (nrow(out) != n) {
    stop(sprintf(
      "%s %s %s: %d export rows for %d segments (a join fanned out)",
      schema, wsg, sp, nrow(out), n), call. = FALSE)
  }
  .lnk_export_conform(out)
}

#' Parse a Postgres text[] as RPostgres returns it (`"{BT,CH}"`).
#' @noRd
.lnk_pg_array <- function(x) {
  x <- as.character(x)
  if (length(x) == 0L || is.na(x) || !nzchar(x) || identical(x, "{}")) {
    return(character(0))
  }
  v <- strsplit(gsub("^\\{|\\}$", "", x), ",", fixed = TRUE)[[1]]
  gsub('^"|"$', "", v)
}

#' The log row each exported group was built by.
#'
#' The latest row per group (`date_start`, then `run_id`) is the build the
#' persist holds. A group is exportable only when that row names `config` and
#' finished (`date_end` set): without it there is no `config_hash`, so no
#' record of the thresholds or the bundle that produced the flags. A NULL
#' `run_uid` (a single-group run outside a dispatch) is accepted.
#'
#' @param wsgs `NULL` for every exportable group the schema holds (others are
#'   named in a message), or the groups to export (any that fails stops).
#' @return The log rows, one per group, sorted by group.
#' @noRd
.lnk_export_runs <- function(conn, schema, config, wsgs = NULL) {
  .lnk_validate_identifier(schema, "schema")
  if (!.lnk_table_exists(conn, paste0(schema, ".log"))) {
    stop(schema, " has no log table: nothing records which build it holds",
         call. = FALSE)
  }
  held <- DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT watershed_group_code::text AS wsg FROM %s.streams",
    schema))$wsg
  log <- .lnk_df_plain(DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT ON (watershed_group_code) *
       FROM %s.log
      ORDER BY watershed_group_code, date_start DESC, run_id DESC", schema)))
  log$watershed_group_code <- as.character(log$watershed_group_code)
  # A log written before a column existed (e.g. `discharge_fill`, #305) reads
  # it as NA, which is what an older build means by it.
  for (n in setdiff(names(cols_log), names(log))) log[[n]] <- rep(NA, nrow(log))

  why <- vapply(held, function(w) {
    r <- log[log$watershed_group_code == w, , drop = FALSE]
    if (nrow(r) == 0L) return("no log row")
    if (!identical(r$config_name[[1]], config)) {
      return(sprintf("latest build is config '%s'", r$config_name[[1]]))
    }
    if (is.na(r$date_end[[1]])) return("latest build did not finish")
    if (is.na(r$config_hash[[1]])) return("latest build logged no config_hash")
    sp <- r$schema_persist[[1]]
    if (!is.null(sp) && !is.na(sp) && !identical(sp, schema)) {
      return(sprintf("latest build logged schema '%s'", sp))
    }
    ""
  }, character(1))

  if (is.null(wsgs)) {
    skip <- why[nzchar(why)]
    if (length(skip) > 0L) {
      message(sprintf(
        "%s: %d of %d groups not exported (%s)", schema, length(skip),
        length(held),
        paste(sprintf("%s: %s", names(skip), skip)[seq_len(min(5L, length(skip)))],
              collapse = "; ")),
        if (length(skip) > 5L) "; ..." else "")
    }
    wsgs <- names(why)[!nzchar(why)]
  } else {
    absent <- setdiff(wsgs, held)
    bad <- why[intersect(wsgs, held)]
    bad <- bad[nzchar(bad)]
    if (length(absent) > 0L || length(bad) > 0L) {
      stop(schema, ": cannot export ",
           paste(c(sprintf("%s (not in streams)", absent),
                   sprintf("%s (%s)", names(bad), bad)), collapse = ", "),
           call. = FALSE)
    }
  }
  if (length(wsgs) == 0L) {
    stop(schema, ": no group has a finished build of config '", config, "'",
         call. = FALSE)
  }
  out <- log[log$watershed_group_code %in% wsgs, , drop = FALSE]
  out <- out[order(out$watershed_group_code), , drop = FALSE]
  skip <- why[nzchar(why) & !names(why) %in% wsgs]
  attr(out, "skipped") <- as.list(skip)
  attr(out, "recompute") <- .lnk_export_recompute(conn, schema, out)
  out
}

#' Finished recomputes of each group after its build.
#'
#' The cross-group recompute rewrites `streams_access`, which is where
#' `has_barriers_dnstr` comes from, so it is part of what the export reads.
#' @return `<schema>.log_recompute` rows, or NULL where the table is absent.
#' @noRd
.lnk_export_recompute <- function(conn, schema, runs) {
  if (!.lnk_table_exists(conn, paste0(schema, ".log_recompute"))) return(NULL)
  rc <- .lnk_df_plain(DBI::dbGetQuery(conn, sprintf(
    "SELECT * FROM %s.log_recompute
      WHERE watershed_group_code = ANY($1) AND date_end IS NOT NULL
      ORDER BY watershed_group_code, date_start", schema),
    params = list(paste0("{", paste(runs$watershed_group_code,
                                    collapse = ","), "}"))))
  rc$watershed_group_code <- as.character(rc$watershed_group_code)
  after <- vapply(seq_len(nrow(rc)), function(i) {
    w <- runs$date_start[runs$watershed_group_code == rc$watershed_group_code[i]]
    length(w) == 1L && rc$date_start[i] > w
  }, logical(1))
  rc[after, , drop = FALSE]
}

#' FWA top-level drainage of each group: the first field of its outlet's
#' watershed code, labelled by region (`inst/extdata/wsg_regions.csv`).
#' @noRd
.lnk_wsg_drainage <- function(wsgs) {
  r <- utils::read.csv(.lnk_wsg_regions_path(), stringsAsFactors = FALSE,
                       colClasses = "character")
  missing <- setdiff(wsgs, r$watershed_group_code)
  if (length(missing) > 0L) {
    stop("no outlet in wsg_regions.csv for: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  r <- r[match(wsgs, r$watershed_group_code), , drop = FALSE]
  data.frame(watershed_group_code = wsgs,
             code = sub("\\..*$", "", r$wscode_outlet),
             drainage = r$region, stringsAsFactors = FALSE)
}

#' Write a data frame to Parquet through duckdb: zstd, one thread (so the bytes
#' are reproducible), to a temporary file renamed into place.
#' @noRd
.lnk_parquet_write <- function(df, path, order_by = NULL) {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("writing Parquet needs the duckdb package", call. = FALSE)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "SET threads = 1")
  duckdb::duckdb_register(con, "lnk_df", .lnk_df_plain(df))
  tmp <- paste0(path, ".tmp")
  ord <- ""
  if (length(order_by) > 0L) {
    ord <- paste(" ORDER BY", paste(order_by, collapse = ", "))
  }
  DBI::dbExecute(con, sprintf(
    "COPY (SELECT * FROM lnk_df%s) TO %s (FORMAT parquet, COMPRESSION zstd)",
    ord, DBI::dbQuoteString(con, tmp)))
  if (!file.rename(tmp, path)) {
    stop("could not move ", tmp, " into place", call. = FALSE)
  }
  invisible(path)
}

#' Size and md5 of files under `root`, keyed by their path relative to it.
#' @noRd
.lnk_file_entry <- function(root, key) {
  p <- file.path(root, key)
  data.frame(key = key, bytes = as.numeric(file.size(p)),
             md5 = unname(tools::md5sum(p)), stringsAsFactors = FALSE)
}

#' Write once: a file that exists must already hold these bytes.
#'
#' Provenance and bundle files are evidence and are never overwritten. A new
#' copy is written beside the old, compared, and dropped when identical.
#' @noRd
.lnk_write_once <- function(path, write) {
  if (!file.exists(path)) {
    write(path)
    return(invisible(path))
  }
  tmp <- paste0(path, ".new")
  on.exit(unlink(tmp), add = TRUE)
  write(tmp)
  if (!identical(unname(tools::md5sum(tmp)), unname(tools::md5sum(path)))) {
    stop(path, " is already written with different content. Provenance is ",
         "written once; a changed record means a changed build, which needs ",
         "its own run.", call. = FALSE)
  }
  invisible(path)
}

#' Provenance key of a run: `run_uid=<uid>`, or `run_id=<id>` for a run that
#' belonged to no dispatch.
#' @noRd
.lnk_run_key <- function(run) {
  uid <- as.character(run$run_uid[[1]])
  k <- if (is.na(uid) || !nzchar(uid)) {
    paste0("run_id=", run$run_id[[1]])
  } else {
    paste0("run_uid=", uid)
  }
  if (!grepl("^run_(uid|id)=[A-Za-z0-9_.:+-]+$", k)) {
    stop("run identifier not usable in a path: ", k, call. = FALSE)
  }
  k
}

#' Write each run's evidence under `provenance/<run key>/`.
#'
#' A dispatch's rows come whole (every group of that `run_uid` in the schema's
#' log, not only the exported ones), with its `log_input`, the threshold and
#' `parameters_fresh` snapshots at its config hashes, and the
#' `provenance.source_artifact` rows of its hosts.
#' @return A data frame of written files: `key`, `kind`, `run_key`, `bytes`,
#'   `md5`.
#' @noRd
.lnk_export_provenance <- function(conn, schema, runs, root) {
  keys <- vapply(seq_len(nrow(runs)), function(i) .lnk_run_key(runs[i, ]),
                 character(1))
  out <- list()
  for (k in unique(keys)) {
    field <- sub("=.*$", "", k)
    val <- sub("^[^=]*=", "", k)
    log <- .lnk_df_plain(DBI::dbGetQuery(conn, sprintf(
      "SELECT * FROM %s.log WHERE %s = $1 ORDER BY watershed_group_code, run_id",
      schema, field), params = list(val)))
    tabs <- list(log = log)
    tabs$log_input <- .lnk_df_plain(DBI::dbGetQuery(conn, sprintf(
      "SELECT * FROM %s.log_input WHERE run_id = ANY($1)
        ORDER BY run_id, table_name", schema),
      params = list(paste0("{", paste(log$run_id, collapse = ","), "}"))))
    hashes <- paste0("{", paste(unique(stats::na.omit(log$config_hash)),
                                collapse = ","), "}")
    for (t in c("log_parameters_habitat_thresholds", "log_parameters_fresh")) {
      if (.lnk_table_exists(conn, paste0(schema, ".", t))) {
        tabs[[t]] <- .lnk_df_plain(DBI::dbGetQuery(conn, sprintf(
          "SELECT * FROM %s.%s WHERE config_hash = ANY($1)
            ORDER BY config_hash, species_code", schema, t),
          params = list(hashes)))
      }
    }
    sa <- .lnk_artifact_table()
    if (.lnk_table_exists(conn, sa)) {
      hosts <- paste0("{", paste(unique(stats::na.omit(log$host)),
                                 collapse = ","), "}")
      tabs$source_artifact <- .lnk_df_plain(DBI::dbGetQuery(conn, sprintf(
        "SELECT * FROM %s WHERE host = ANY($1) ORDER BY host, table_name, url",
        sa), params = list(hosts)))
    }
    for (t in names(tabs)) {
      key <- sprintf("provenance/%s/%s.parquet", k, t)
      .lnk_write_once(file.path(root, key), function(p) {
        .lnk_parquet_write(tabs[[t]], p)
      })
      e <- .lnk_file_entry(root, key)
      e$kind <- "provenance"
      e$run_key <- k
      out[[length(out) + 1L]] <- e
    }
  }
  do.call(rbind, out)
}

#' Publish the files a logged `config_hash` was computed over.
#'
#' Possible only where today's bundle hashes the same: the files are then the
#' bytes the run read. Otherwise the bundle moved since the build, and the
#' manifest says so instead of publishing files the run never saw.
#' @return A list: `bundles` (one entry per hash) and `files` (data frame of
#'   written files).
#' @noRd
.lnk_export_bundle <- function(config, hashes, root) {
  cfg <- tryCatch(suppressMessages(lnk_config(config)), error = function(e) NULL)
  current <- if (is.null(cfg)) NA_character_ else .lnk_config_hash(cfg)
  bundles <- list()
  files <- list()
  for (h in hashes) {
    if (is.null(cfg)) {
      bundles[[length(bundles) + 1L]] <- list(
        config_hash = h, prefix = NULL,
        reason = sprintf("link ships no config named '%s'", config))
      next
    }
    if (!identical(h, current)) {
      bundles[[length(bundles) + 1L]] <- list(
        config_hash = h, prefix = NULL,
        reason = sprintf("bundle has changed since the build (now %s)", current))
      next
    }
    prefix <- paste0("config/", sub("^sha256:", "sha256-", h))
    f <- .lnk_config_files(cfg)
    f <- f[f$digest != "MISSING", , drop = FALSE]
    f <- f[order(f$rel, method = "radix"), , drop = FALSE]
    rel_key <- sub("^(extends|fresh|link):", "\\1/", f$rel)
    for (i in seq_len(nrow(f))) {
      key <- paste0(prefix, "/", rel_key[i])
      .lnk_write_once(file.path(root, key), function(p) {
        dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
        if (!file.copy(f$path[i], p, overwrite = TRUE)) {
          stop("could not copy ", f$path[i], call. = FALSE)
        }
      })
      e <- .lnk_file_entry(root, key)
      e$kind <- "bundle"
      e$run_key <- NA_character_
      files[[length(files) + 1L]] <- e
    }
    bundles[[length(bundles) + 1L]] <- list(
      config_hash = h, prefix = prefix,
      files = lapply(seq_len(nrow(f)), function(i) {
        list(name = f$rel[i], key = paste0(prefix, "/", rel_key[i]),
             sha256 = f$digest[i])
      }))
  }
  list(bundles = bundles, files = do.call(rbind, files))
}

#' Timestamps as ISO 8601 UTC strings, for JSON.
#' @noRd
.lnk_json_rows <- function(df) {
  for (n in names(df)) {
    if (inherits(df[[n]], "POSIXt")) {
      df[[n]] <- ifelse(is.na(df[[n]]), NA_character_,
                        format(df[[n]], "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"))
    }
  }
  df
}

#' Write `manifest.json` under `root`, atomically.
#' @noRd
.lnk_manifest_write <- function(root, parts, files, configs,
                                built = Sys.time()) {
  m <- list(
    manifest_version = 1L,
    id = sub("/segment$", "", .lnk_export_dataset()),
    built = format(as.POSIXct(built), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    provenance = list(
      link_version = as.character(utils::packageVersion("link")),
      link_sha = .lnk_pkg_git_sha("link"),
      link_dirty = .lnk_pkg_git_dirty("link")
    ),
    datasets = list(list(
      dataset = .lnk_export_dataset(),
      schema = list(package = "link",
                    file = "inst/extdata/schemas/habitat_fwa_v1_segment.yaml",
                    cols = .lnk_export_spec()$canonical$cols)
    )),
    configs = configs,
    parts = parts,
    files = files
  )
  path <- file.path(root, "manifest.json")
  tmp <- tempfile(tmpdir = root, fileext = ".json")
  jsonlite::write_json(m, tmp, auto_unbox = TRUE, pretty = TRUE, digits = NA,
                       null = "null", na = "null", dataframe = "rows")
  if (!file.rename(tmp, path)) {
    unlink(tmp)
    stop("could not move the manifest into place", call. = FALSE)
  }
  invisible(path)
}

#' Publish link's habitat flags per config as Parquet + manifest
#'
#' Writes a local tree, the layout of `s3://fresh-bc/habitat/fwa/v1/`, from
#' persisted link runs: one long-form row per stream segment, config and
#' species, keyed by FWA position, with the flags, the size and gradient
#' values the run tested, and their ratios to the run's thresholds. A
#' `manifest.json` names each part's md5 and the log rows of the builds that
#' produced it; [lnk_catalog()] reads it and [lnk_db_load()] loads the parts
#' into PostgreSQL.
#'
#' ```
#' <root>/manifest.json
#' <root>/segment/config=<config>/species=<sp>/part-<code>.parquet
#' <root>/provenance/run_uid=<uid>/{log,log_input,...}.parquet
#' <root>/config/sha256-<hex>/<bundle files>
#' ```
#'
#' Rules the export holds to:
#' - **Key.** `(blue_line_key, downstream_route_measure,
#'   upstream_route_measure)`. Break points differ by config, so neither
#'   `linear_feature_id` nor link's per-group `id_segment` is a key; cut a
#'   segment's line from the FWA blue line at its measures.
#' - **Which groups.** A group is exported only when its latest log row is a
#'   finished build of the config; there is no other record of the thresholds
#'   or bundle behind its flags. A build outside a dispatch (`run_uid` NULL)
#'   is kept under `provenance/run_id=<run_id>/`.
#' - **Species.** Every segment has a row for every species the config models
#'   in the exported groups; a species with no habitat in a group reads FALSE.
#' - **Discharge.** `mad_m3s` is the discharge the run classified on, with its
#'   logged fill, so `*_ratio_mad` agrees with the flags.
#' - **Ratios.** Use the thresholds the run logged at its `config_hash`. A build
#'   that logged none (before link's #282) has NA ratios for spawning and
#'   rearing.
#' - **Bundle files.** Published under `config/` only when today's bundle
#'   hashes the same as the build; otherwise the manifest records why not.
#' - **Provenance.** Written once: a provenance file that already exists with
#'   different bytes stops the export.
#'
#' @param conn A DBI connection to the database holding the persist schemas.
#' @param configs Named character: names are link config names (as logged in
#'   `<schema>.log.config_name`), values the persist schema holding each. A
#'   config may name several schemas holding different groups.
#' @param root Directory to write. `segment/` and `manifest.json` are replaced;
#'   `provenance/` and `config/` accumulate.
#' @param wsgs Watershed groups to export, or `NULL` for every group with a
#'   finished build of its config (the others are named in a message).
#' @param species Species codes, or `NULL` for every species the config
#'   modelled in the exported groups.
#' @param shared_segmentation If `TRUE`, stop unless every schema exported
#'   holds the same segmentation in the groups they share. Set it when the
#'   configs are variants meant to be compared segment for segment.
#' @return The manifest path, invisibly.
#' @family export
#' @export
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
#'                     user = "postgres", password = "postgres")
#' root <- file.path(tempdir(), "habitat", "fwa", "v1")
#' lnk_scenario_export(conn, c(default = "fresh_default"), root,
#'                     wsgs = "DUNC", species = c("BT", "RB"))
#' cat <- lnk_catalog(file.path(root, "manifest.json"))
#' cat[, c("config", "species", "code", "rows", "md5")]
#' }
lnk_scenario_export <- function(conn, configs, root, wsgs = NULL,
                                species = NULL, shared_segmentation = FALSE) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(configs), length(configs) > 0L,
    !is.null(names(configs)), all(nzchar(names(configs))),
    is.character(root), length(root) == 1L, nzchar(root),
    is.null(wsgs) || is.character(wsgs),
    is.null(species) || is.character(species),
    is.logical(shared_segmentation), length(shared_segmentation) == 1L
  )
  for (s in configs) .lnk_validate_identifier(s, "schema")
  if (!is.null(species)) species <- toupper(species)
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("lnk_scenario_export() needs the duckdb package", call. = FALSE)
  }

  # one finished build per group, per schema
  runs <- lapply(seq_along(configs), function(i) {
    r <- .lnk_export_runs(conn, configs[[i]], names(configs)[i], wsgs)
    r$schema_export <- configs[[i]]
    r$config_export <- names(configs)[i]
    r
  })
  # a group comes from one schema per config
  for (cf in unique(names(configs))) {
    w <- unlist(lapply(runs[names(configs) == cf],
                       function(r) r$watershed_group_code))
    dup <- unique(w[duplicated(w)])
    if (length(dup) > 0L) {
      stop("config '", cf, "': ", paste(dup, collapse = ", "),
           " held by more than one schema", call. = FALSE)
    }
  }
  # a dispatch belongs to one config
  uid <- do.call(rbind, lapply(runs, function(r) {
    unique(r[!is.na(r$run_uid), c("run_uid", "config_export"), drop = FALSE])
  }))
  if (!is.null(uid) && anyDuplicated(uid$run_uid) > 0L) {
    stop("run_uid shared across configs: ",
         paste(unique(uid$run_uid[duplicated(uid$run_uid)]), collapse = ", "),
         call. = FALSE)
  }
  if (isTRUE(shared_segmentation) && length(unique(configs)) > 1L) {
    common <- Reduce(intersect, lapply(runs, function(r) r$watershed_group_code))
    if (length(common) == 0L) {
      stop("shared_segmentation: the schemas share no group", call. = FALSE)
    }
    .lnk_hvb_check_segmentation(conn, unique(unname(configs)), common)
  }

  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  prev <- .lnk_manifest_previous(root, unique(names(configs)))
  for (cf in unique(names(configs))) {
    unlink(file.path(root, "segment", paste0("config=", cf)), recursive = TRUE)
  }

  parts <- list(prev$parts)
  files <- list(prev$files)
  cfg_entries <- prev$configs
  for (cf in unique(names(configs))) {
    r_set <- runs[names(configs) == cf]
    r_cf <- do.call(rbind, r_set)
    rc_cf <- do.call(rbind, lapply(r_set, attr, "recompute"))
    skipped <- do.call(c, lapply(r_set, attr, "skipped"))
    sp_wsg <- lapply(r_cf$species, .lnk_pg_array)
    if (!is.null(species)) sp_wsg <- lapply(sp_wsg, intersect, species)
    names(sp_wsg) <- r_cf$watershed_group_code
    sp_cf <- sort(unique(unlist(sp_wsg)))
    if (length(sp_cf) == 0L) {
      stop("config '", cf, "': the exported builds modelled none of the ",
           "species asked for", call. = FALSE)
    }
    dr <- .lnk_wsg_drainage(r_cf$watershed_group_code)
    for (sp in sp_cf) {
      for (code in sort(unique(dr$code))) {
        w_code <- sort(dr$watershed_group_code[dr$code == code])
        w_code <- w_code[vapply(w_code, function(w) sp %in% sp_wsg[[w]],
                                logical(1))]
        if (length(w_code) == 0L) next
        rows <- do.call(rbind, lapply(w_code, function(w) {
          run <- r_cf[r_cf$watershed_group_code == w, , drop = FALSE]
          .lnk_export_rows(conn, run$schema_export[[1]], w, sp, run)
        }))
        key <- sprintf("segment/config=%s/species=%s/part-%s.parquet",
                       cf, sp, code)
        .lnk_parquet_write(rows, file.path(root, key),
                           order_by = c("watershed_group_code",
                                        "blue_line_key",
                                        "downstream_route_measure"))
        e <- .lnk_file_entry(root, key)
        parts[[length(parts) + 1L]] <- data.frame(
          key = key, dataset = .lnk_export_dataset(), config = cf,
          species = sp, code = code,
          drainage = paste(unique(dr$drainage[dr$code == code]),
                           collapse = "; "),
          wsgs = paste(w_code, collapse = ","),
          rows = nrow(rows), bytes = e$bytes, md5 = e$md5,
          stringsAsFactors = FALSE)
      }
    }

    prov <- do.call(rbind, lapply(unique(r_cf$schema_export), function(s) {
      .lnk_export_provenance(conn, s, r_cf[r_cf$schema_export == s, ,
                                           drop = FALSE], root)
    }))
    rc_files <- .lnk_export_recompute_files(rc_cf, root)
    hashes <- unique(r_cf$config_hash)
    bnd <- .lnk_export_bundle(cf, hashes, root)
    files[[length(files) + 1L]] <- rbind(prov, rc_files, bnd$files)

    thr_logged <- vapply(hashes, function(h) {
      any(vapply(unique(r_cf$schema_export), function(s) {
        t <- paste0(s, ".log_parameters_habitat_thresholds")
        .lnk_table_exists(conn, t) && nrow(DBI::dbGetQuery(conn, sprintf(
          "SELECT 1 FROM %s WHERE config_hash = $1 LIMIT 1", t),
          params = list(h))) > 0L
      }, logical(1)))
    }, logical(1))

    dtbl <- .lnk_hv_discharge_tbl()
    sa <- .lnk_artifact_table()
    d_art <- if (.lnk_table_exists(conn, sa)) {
      .lnk_json_rows(.lnk_df_plain(DBI::dbGetQuery(conn, sprintf(
        "SELECT * FROM %s WHERE table_name = $1 ORDER BY host, url", sa),
        params = list(dtbl))))
    }
    keep <- setdiff(names(r_cf), c("schema_export", "config_export"))
    run_rows <- .lnk_json_rows(r_cf[, keep, drop = FALSE])
    run_rows$species <- lapply(r_cf$species, .lnk_pg_array)
    run_rows$wsg_upstream <- lapply(r_cf$wsg_upstream, .lnk_pg_array)
    run_rows$model <- .lnk_export_model(cf, r_cf)
    run_rows$provenance_key <- vapply(seq_len(nrow(r_cf)), function(i) {
      paste0("provenance/", .lnk_run_key(r_cf[i, ]))
    }, character(1))
    run_rows$recompute_keys <- lapply(r_cf$watershed_group_code, function(w) {
      ids <- if (is.null(rc_cf)) character(0) else
        rc_cf$recompute_id[rc_cf$watershed_group_code == w]
      if (length(ids) == 0L) character(0) else
        paste0("provenance/recompute_id=", ids)
    })
    cfg_entries[[cf]] <- list(
      config = cf,
      schema_persist = unique(r_cf$schema_export),
      wsgs = r_cf$watershed_group_code,
      species = sp_cf,
      skipped = skipped,
      run_uids = sort(unique(stats::na.omit(r_cf$run_uid))),
      config_hashes = hashes,
      thresholds_logged = as.list(thr_logged),
      discharge = list(
        table = dtbl,
        fill = stats::setNames(as.list(as.logical(r_cf$discharge_fill)),
                               r_cf$watershed_group_code),
        source_artifact = d_art,
        source_artifact_scope = paste(
          "provenance.source_artifact rows of the exporting database at",
          "export time, not a record of the hosts the builds ran on")),
      bundles = bnd$bundles,
      runs = run_rows
    )
  }

  parts <- do.call(rbind, parts)
  parts <- parts[order(parts$key, method = "radix"), , drop = FALSE]
  files <- do.call(rbind, files)
  files <- files[!duplicated(files$key), , drop = FALSE]
  files <- files[order(files$key, method = "radix"), , drop = FALSE]
  cfg_entries <- unname(cfg_entries[order(names(cfg_entries), method = "radix")])
  invisible(.lnk_manifest_write(root, parts, files, cfg_entries))
}

#' The habitat model (`cw` or `mad`) each build classified on.
#'
#' Not logged per group; resolvable from the bundle's method table only when
#' today's bundle is the one the build hashed, so NA otherwise.
#' @noRd
.lnk_export_model <- function(config, runs) {
  cfg <- tryCatch(suppressMessages(lnk_config(config)),
                  error = function(e) NULL)
  out <- rep(NA_character_, nrow(runs))
  if (is.null(cfg)) return(out)
  ok <- runs$config_hash == .lnk_config_hash(cfg)
  if (any(ok)) {
    method <- .lnk_habitat_method_read(
      suppressMessages(.lnk_habitat_method_csv(cfg)))
    out[ok] <- .lnk_wsg_model(method, runs$watershed_group_code[ok])
  }
  out
}

#' Write each recompute's log row under `provenance/recompute_id=<id>/`.
#' @noRd
.lnk_export_recompute_files <- function(rc, root) {
  if (is.null(rc) || nrow(rc) == 0L) return(NULL)
  do.call(rbind, lapply(seq_len(nrow(rc)), function(i) {
    id <- rc$recompute_id[i]
    if (!grepl("^[A-Za-z0-9_.:+-]+$", id)) {
      stop("recompute_id not usable in a path: ", id, call. = FALSE)
    }
    k <- paste0("recompute_id=", id)
    key <- sprintf("provenance/%s/log_recompute.parquet", k)
    .lnk_write_once(file.path(root, key), function(p) {
      .lnk_parquet_write(rc[i, , drop = FALSE], p)
    })
    e <- .lnk_file_entry(root, key)
    e$kind <- "provenance"
    e$run_key <- k
    e
  }))
}

#' What an existing manifest in `root` keeps for the configs not re-exported.
#'
#' A tree holds every config published to it, and an export replaces only the
#' configs it names. So the previous manifest's parts and entries for the
#' others are carried forward, after checking each part is still on disk with
#' the md5 the manifest records. Provenance and bundle files are kept for all
#' configs: they are written once and never removed.
#' @noRd
.lnk_manifest_previous <- function(root, configs) {
  path <- file.path(root, "manifest.json")
  empty <- list(parts = NULL, files = NULL, configs = list())
  if (!file.exists(path)) return(empty)
  m <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  keep_parts <- Filter(function(p) !p$config %in% configs, m$parts)
  parts <- if (length(keep_parts) > 0L) {
    do.call(rbind, lapply(keep_parts, function(p) {
      f <- file.path(root, p$key)
      if (!file.exists(f) || !identical(unname(tools::md5sum(f)), p$md5)) {
        stop("the manifest in ", root, " lists ", p$key, ", which is ",
             "missing or changed; re-export config '", p$config,
             "' or start from an empty root", call. = FALSE)
      }
      data.frame(key = p$key, dataset = p$dataset, config = p$config,
                 species = p$species, code = p$code,
                 drainage = p$drainage %||% NA_character_,
                 wsgs = p$wsgs %||% NA_character_, rows = p$rows,
                 bytes = p$bytes, md5 = p$md5, stringsAsFactors = FALSE)
    }))
  }
  files <- if (length(m$files) > 0L) {
    do.call(rbind, lapply(m$files, function(f) {
      data.frame(key = f$key, bytes = f$bytes, md5 = f$md5, kind = f$kind,
                 run_key = f$run_key %||% NA_character_,
                 stringsAsFactors = FALSE)
    }))
  }
  keep_cfg <- Filter(function(x) !x$config %in% configs, m$configs)
  names(keep_cfg) <- vapply(keep_cfg, function(x) x$config, character(1))
  list(parts = parts, files = files, configs = keep_cfg)
}
# nolint end: indentation_linter
