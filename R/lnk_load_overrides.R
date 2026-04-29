#' Materialize the Tabular Data Files Declared in a Config Bundle
#'
#' Walks `cfg$files` and returns a named list of tibbles, one per
#' entry. Entries with a `canonical_schema` field dispatch through
#' [crate::crt_ingest()] (which handles canonicalization across
#' upstream variants). Entries without `canonical_schema` fall through
#' to a local read dispatched on the path's extension (`.csv` today;
#' more formats can be added without schema changes).
#'
#' Returned list keys match the entry keys in `cfg$files` exactly
#' (filename-stem convention — see `inst/extdata/configs/<name>/config.yaml`).
#'
#' @param cfg An `lnk_config` object returned by [lnk_config()], or a
#'   character (config name or path) — for ergonomic call.
#'
#' @return Named list of tibbles. Order matches `cfg$files`.
#'
#' @export
#'
#' @examples
#' cfg <- lnk_config("bcfishpass")
#' loaded <- lnk_load_overrides(cfg)
#' names(loaded)
#' head(loaded$user_habitat_classification)
#' head(loaded$parameters_fresh)
#'
#' \dontrun{
#' # Same call shape with a project-experimental config that extends default
#' loaded_proj <- lnk_load_overrides("/path/to/project/config")
#' }
lnk_load_overrides <- function(cfg) {
  if (is.character(cfg)) {
    cfg <- lnk_config(cfg)
  }
  if (!inherits(cfg, "lnk_config")) {
    stop("cfg must be an lnk_config or a config name/path", call. = FALSE)
  }

  out <- lapply(names(cfg$files), function(key) {
    entry <- cfg$files[[key]]
    .lnk_load_entry(key, entry)
  })
  stats::setNames(out, names(cfg$files))
}

# Dispatch a single file entry. canonical_schema -> crate; else local.
.lnk_load_entry <- function(key, entry) {
  if (!is.null(entry$canonical_schema)) {
    parts <- strsplit(entry$canonical_schema, "/", fixed = TRUE)[[1]]
    if (length(parts) != 2L) {
      stop("`files$", key, "$canonical_schema` must be '<source>/<file_name>': ",
           entry$canonical_schema, call. = FALSE)
    }
    return(crate::crt_ingest(
      source = parts[1],
      file_name = parts[2],
      path = entry$path
    ))
  }
  .lnk_load_local(key, entry$path)
}

# Local-read fallback. Dispatch on extension. Add cases here as new
# formats arrive (parquet, geojson, sqlite, ...). Keep scope minimal
# until a real consumer needs more.
.lnk_load_local <- function(key, path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "csv") {
    df <- utils::read.csv(path, stringsAsFactors = FALSE)
    return(tibble::as_tibble(df))
  }
  stop("Unsupported file extension '", ext, "' for entry '", key,
       "' (path: ", path, "). Add an explicit `canonical_schema` ",
       "to dispatch via crate, or extend .lnk_load_local() for new ",
       "local formats.", call. = FALSE)
}
