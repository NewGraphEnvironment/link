# Per-group datasets of the habitat export (#465): the persisted rows another
# group's downstream walk reads.
#
# A group's access is walked downstream through the persist schema's
# province-wide `barriers` (through lnk_barriers_views()) and
# `barrier_overrides` (anti-joined in barriers_<sp>_access), so a one-group
# run on a machine that holds only some groups reads the right access only
# when the rows other groups wrote are there. The export carries them one part
# per group, per config, from the same build its segment parts come from, and
# lnk_downstream_load() puts them back.

# nolint start: indentation_linter
#' The per-group tables the export carries, with their column shape (the one
#' persist definition, `cols_barriers` / `cols_barrier_overrides`) and the
#' order a part's rows are written in (a key, so parts are byte-reproducible).
#' @noRd
.lnk_export_group_tables <- function() {
  list(
    barriers = list(cols = cols_barriers,
                    order = "id_barrier"),
    barrier_overrides = list(cols = cols_barrier_overrides,
                             order = c("blue_line_key",
                                       "downstream_route_measure",
                                       "species_code"))
  )
}

#' Dataset ID of a per-group table.
#' @noRd
.lnk_export_group_dataset <- function(table) paste0("habitat/fwa/v1/", table)

#' How one persist column is written to Parquet and read back.
#'
#' Types Parquet holds as they are pass through; the others are written as
#' text that casts back without loss: `ltree`, `text[]` and `bigint` as their
#' Postgres text forms, geometry as hex WKB (EPSG:3005, the persist SRID).
#' `bigint` is text because RPostgres returns it as `integer64`, whose bits
#' `duckdb::duckdb_register()` read as a double before duckdb 1.5.6
#' (703016261 became 3.5e-315); text is right on every version.
#' @return A list: `select` (SQL for the export query), `parquet` (what the
#'   part holds) and `load` (SQL casting a staged text-or-native column back).
#' @noRd
.lnk_export_group_col <- function(name, type) {
  t <- sub("\\s+NOT NULL$", "", type)
  if (startsWith(t, "geometry")) {
    srid <- sub("^geometry\\([^,]+,\\s*([0-9]+)\\)$", "\\1", t)
    if (!grepl("^[0-9]+$", srid)) {
      stop("geometry column ", name, " has no SRID in its type: ", type,
           call. = FALSE)
    }
    return(list(
      select = sprintf("encode(ST_AsBinary(%s), 'hex') AS %s", name, name),
      parquet = sprintf("string (hex WKB, EPSG:%s)", srid),
      load = sprintf("ST_SetSRID(ST_GeomFromWKB(decode(%s, 'hex')), %s)",
                     name, srid)))
  }
  if (t %in% c("ltree", "text[]", "bigint")) {
    return(list(select = sprintf("%s::text AS %s", name, name),
                parquet = sprintf("string (%s text form)", t),
                load = sprintf("%s::%s", name, t)))
  }
  if (t %in% c("integer", "double precision", "text") ||
      grepl("^varchar\\([0-9]+\\)$", t)) {
    return(list(select = name, parquet = t,
                load = sprintf("%s::%s", name, t)))
  }
  stop("no Parquet mapping for column ", name, " of type ", type,
       call. = FALSE)
}

#' The column contract of a per-group table, for the manifest's `datasets`.
#' @noRd
.lnk_export_group_spec <- function(table) {
  cols <- .lnk_export_group_tables()[[table]]$cols
  lapply(names(cols), function(n) {
    list(name = n, type = cols[[n]],
         parquet = .lnk_export_group_col(n, cols[[n]])$parquet)
  })
}

#' One group's rows of a per-group table, in the part's column order.
#' @noRd
.lnk_export_group_rows <- function(conn, schema, table, wsg) {
  .lnk_validate_identifier(schema, "schema")
  spec <- .lnk_export_group_tables()[[table]]
  if (is.null(spec)) stop("not a per-group export table: ", table, call. = FALSE)
  if (!.lnk_table_exists(conn, paste0(schema, ".", table))) {
    stop(schema, ".", table, " does not exist: every persist schema holds it ",
         "(lnk_persist_init()), and the export cannot say what a downstream ",
         "walk reads without it", call. = FALSE)
  }
  sel <- vapply(names(spec$cols), function(n) {
    .lnk_export_group_col(n, spec$cols[[n]])$select
  }, character(1))
  .lnk_df_plain(DBI::dbGetQuery(conn, sprintf(
    "SELECT %s FROM %s.%s WHERE watershed_group_code = $1",
    paste(sel, collapse = ", "), schema, table), params = list(wsg)))
}

#' Write a group's per-group parts into `stage`.
#'
#' One part per table, written even when the group holds no rows (a reader
#' must tell "none" from "missing").
#' @param run_id The build the parts come from (the group's exported log row).
#' @return A data frame of `group_parts` entries: key, dataset, config, wsg,
#'   run_id, rows, bytes, md5.
#' @noRd
.lnk_export_group_parts <- function(conn, schema, config, wsg, run_id, stage) {
  tabs <- .lnk_export_group_tables()
  do.call(rbind, lapply(names(tabs), function(t) {
    rows <- .lnk_export_group_rows(conn, schema, t, wsg)
    key <- sprintf("%s/config=%s/part-%s.parquet", t, config, wsg)
    .lnk_parquet_write(rows, file.path(stage, key), order_by = tabs[[t]]$order)
    e <- .lnk_file_entry(stage, key)
    data.frame(key = key, dataset = .lnk_export_group_dataset(t),
               config = config, wsg = wsg, run_id = run_id,
               rows = nrow(rows), bytes = e$bytes, md5 = e$md5,
               stringsAsFactors = FALSE)
  }))
}

#' Groups holding rows in a set of persist schemas' `barriers` or
#' `barrier_overrides`: what a downstream walk reads. A group can hold them
#' without a build in `streams` (a build that died between unifying and
#' persisting its barriers), so "held" for the lister means this.
#' @noRd
.lnk_export_barrier_holders <- function(conn, schemas) {
  sort(unique(unlist(lapply(schemas, function(s) {
    .lnk_validate_identifier(s, "schema")
    unlist(lapply(names(.lnk_export_group_tables()), function(t) {
      if (!.lnk_table_exists(conn, paste0(s, ".", t))) return(NULL)
      DBI::dbGetQuery(conn, sprintf(
        "SELECT DISTINCT watershed_group_code::text AS w FROM %s.%s", s, t))$w
    }))
  }))))
}

#' Move a config's staged per-group parts into place, replacing the old ones.
#' @noRd
.lnk_export_group_swap <- function(root, stage, config) {
  for (t in names(.lnk_export_group_tables())) {
    dest <- file.path(root, t, paste0("config=", config))
    unlink(dest, recursive = TRUE)
    src <- file.path(stage, t, paste0("config=", config))
    if (!dir.exists(src)) next
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    if (!file.rename(src, dest)) {
      stop("could not move the staged ", t, " parts of config '", config,
           "' into place", call. = FALSE)
    }
  }
  invisible(root)
}

#' (table, group) pairs a manifest's per-group parts hold for a config.
#' @noRd
.lnk_manifest_group_pairs <- function(group_parts, config) {
  p <- Filter(function(x) identical(x$config[1], config), group_parts)
  # an entry is one part once read, a column list of a config's parts while
  # exporting
  unique(unlist(lapply(p, function(x) {
    paste(x$dataset, x$wsg, sep = ":")
  })))
}

#' The previous manifest's per-group parts for configs not re-exported, each
#' checked on disk against the md5 the manifest records.
#' @noRd
.lnk_manifest_previous_groups <- function(root, m, configs) {
  keep <- Filter(function(p) !p$config %in% configs, m$group_parts)
  if (length(keep) == 0L) return(NULL)
  do.call(rbind, lapply(keep, function(p) {
    f <- file.path(root, p$key)
    if (!file.exists(f) || !identical(unname(tools::md5sum(f)), p$md5)) {
      stop("the manifest in ", root, " lists ", p$key, ", which is ",
           "missing or changed; re-export config '", p$config,
           "' or start from an empty root", call. = FALSE)
    }
    data.frame(key = p$key, dataset = p$dataset, config = p$config,
               wsg = p$wsg, run_id = p$run_id, rows = p$rows,
               bytes = p$bytes, md5 = p$md5, stringsAsFactors = FALSE)
  }))
}
# nolint end: indentation_linter

# nolint start: indentation_linter
#' Identity of the FWA stream table the dependency map is computed from: its
#' whole-table row count and size on the exporting database. Context for a
#' reader, not a guard.
#' @noRd
.lnk_export_fwa_identity <- function(conn) {
  fwa <- "whse_basemapping.fwa_stream_networks_sp"
  id <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::double precision AS rows,
            pg_total_relation_size('%s')::double precision AS bytes
       FROM %s", fwa, fwa))
  list(table = fwa, rows = id$rows, bytes = id$bytes)
}

#' The groups the dependency map must cover: every BC watershed group
#' (`inst/extdata/wsg_regions.csv`, 246). The map is read for any target, so
#' it is computed only from an FWA holding all of them.
#' @noRd
.lnk_export_fwa_required <- function() {
  p <- system.file("extdata", "wsg_regions.csv", package = "link")
  if (!nzchar(p)) stop("link's inst/extdata/wsg_regions.csv is missing",
                       call. = FALSE)
  sort(unique(utils::read.csv(p, stringsAsFactors = FALSE)$watershed_group_code))
}

#' The watershed groups the FWA stream table holds segments of.
#' @noRd
.lnk_export_fwa_groups <- function(conn) {
  DBI::dbGetQuery(conn,
    "SELECT DISTINCT watershed_group_code::text AS w
       FROM whse_basemapping.fwa_stream_networks_sp
      WHERE watershed_group_code IS NOT NULL")$w
}

#' Write the dependency map into `stage`: for each group, every group whose
#' persisted rows its downstream walk can read (the line rule,
#' `.lnk_wsg_deps_line()`), province-wide whatever groups the export names. A
#' one-group machine has no province FWA to compute it from, so the export
#' carries it. Replaced on every export: it follows FWA, not a build.
#'
#' Refused when the exporting database's FWA lacks any BC group, a group the
#' export holds or a group holding barrier rows in an exported schema: the
#' rule would drop every pair through that group's lines, the map is read for
#' every target (configs carried forward included), and a one-group machine,
#' which cannot recompute it, could not tell. The groups it covers are
#' recorded (`groups`), so a reader can refuse a target outside them rather
#' than read it as one with no dependencies.
#' @param groups Groups the export holds, any config.
#' @param schemas The exported persist schemas.
#' @return The manifest's `dependencies` entry.
#' @noRd
.lnk_export_dependencies <- function(conn, stage, groups, schemas) {
  held <- unique(c(.lnk_export_fwa_required(), groups,
                   unlist(lapply(schemas, function(s) {
    .lnk_validate_identifier(s, "schema")
    DBI::dbGetQuery(conn, sprintf(
      "SELECT DISTINCT watershed_group_code::text AS w FROM %s.barriers", s))$w
  }))))
  have <- .lnk_export_fwa_groups(conn)
  missing <- setdiff(held, have)
  if (length(missing) > 0L) {
    stop("this database's FWA holds no segments of ",
         paste(sort(missing), collapse = ", "), " (every BC group, every group ",
         "the export holds and every group holding barriers must be there); ",
         "the dependency map would leave out every pair through them. Export ",
         "from a database with the whole FWA.",
         call. = FALSE)
  }
  d <- .lnk_wsg_deps_line(conn)
  key <- "dependencies/rule=line.parquet"
  .lnk_parquet_write(d, file.path(stage, key), order_by = c("wsg", "dep"))
  e <- .lnk_file_entry(stage, key)
  list(key = key, rule = "line", rows = nrow(d), bytes = e$bytes, md5 = e$md5,
       readers = length(unique(d$wsg)),
       # every group the map answers for, a group with no dependency included
       groups = I(sort(held)),
       fwa = .lnk_export_fwa_identity(conn),
       computed_by = list(
         link_version = as.character(utils::packageVersion("link")),
         link_sha = .lnk_pkg_git_sha("link")))
}

#' Move the staged dependency map into place, replacing the old one.
#' @noRd
.lnk_export_dependencies_swap <- function(root, stage) {
  dest <- file.path(root, "dependencies")
  unlink(dest, recursive = TRUE)
  if (!file.rename(file.path(stage, "dependencies"), dest)) {
    stop("could not move the staged dependency map into place", call. = FALSE)
  }
  invisible(root)
}
# nolint end: indentation_linter
