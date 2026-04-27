#' Load a Pipeline Config Bundle
#'
#' Reads a config bundle manifest (`config.yaml`) and returns a single
#' list object containing everything a pipeline needs to classify
#' habitat for a given interpretation variant — rules YAML, parameters,
#' overrides, observation exclusions, habitat confirmations, and
#' pipeline knobs (break order, cluster params, spawn_connected rules).
#'
#' A config bundle is a directory under `inst/extdata/configs/<name>/`
#' (for bundled variants) or an arbitrary directory path (for custom
#' variants) containing `config.yaml` plus the files the manifest
#' references. All file paths in the manifest are resolved relative to
#' the bundle directory.
#'
#' The returned list is the single object passed around the pipeline
#' (e.g. into `_targets.R`), so pipeline variants become a config
#' authoring exercise, not a code fork.
#'
#' @param name_or_path Character. Either a bundled config name
#'   (`"bcfishpass"`, `"default"`) or an absolute path to a config
#'   directory. Bundled names resolve to `system.file("extdata",
#'   "configs", name, package = "link")`.
#'
#' @return An `lnk_config` S3 list with these slots:
#'
#'   - `name` — config name (from `name_or_path` or the manifest)
#'   - `dir` — absolute path to the config directory
#'   - `rules_yaml` — absolute path to the rules YAML (consumed by
#'     `fresh::frs_habitat_classify()`)
#'   - `dimensions_csv` — absolute path to the dimensions CSV (source
#'     of `rules_yaml` via `lnk_rules_build()`)
#'   - `parameters_fresh` — data frame of per-species fresh overrides
#'   - `habitat_classification` — data frame of expert-confirmed
#'     habitat endpoints (or `NULL` if the manifest does not reference
#'     one)
#'   - `observation_exclusions` — data frame of observation IDs to
#'     skip (or `NULL`)
#'   - `wsg_species` — data frame of species per watershed group (or
#'     `NULL`)
#'   - `overrides` — named list of data frames, one per override CSV
#'     listed in the manifest
#'   - `pipeline` — named list of pipeline knobs from the manifest
#'     (`break_order`, `cluster`, `spawn_connected`)
#'   - `provenance` — named list of per-file provenance metadata parsed
#'     from the manifest's `provenance:` block (or `NULL` when the
#'     bundle does not declare it). Each entry is keyed by the file's
#'     path relative to `dir` and carries metadata fields such as
#'     `source`, `upstream_sha`, `synced`, `checksum`, plus
#'     generator-specific keys (`generated_from`, `generated_by`,
#'     `generator_sha`) for files produced by tooling. Drift detection
#'     against the recorded checksums is in [lnk_config_verify()].
#'
#' @export
#'
#' @examples
#' # Load the bundled bcfishpass variant
#' cfg <- lnk_config("bcfishpass")
#'
#' # Inspect
#' cfg$name
#' cfg$dir
#' file.exists(cfg$rules_yaml)
#' head(cfg$parameters_fresh)
#' names(cfg$overrides)
#' cfg$pipeline$break_order
#'
#' \dontrun{
#' # Custom config: point at any directory containing config.yaml
#' my_cfg <- lnk_config("/path/to/my/variant")
#'
#' # Feed into the pipeline
#' fresh::frs_habitat_classify(conn, ...,
#'   rules = cfg$rules_yaml,
#'   params = cfg$parameters_fresh)
#' }
lnk_config <- function(name_or_path) {
  if (!is.character(name_or_path) || length(name_or_path) != 1L) {
    stop("name_or_path must be a single string", call. = FALSE)
  }

  dir <- .lnk_config_resolve_dir(name_or_path)

  manifest_path <- file.path(dir, "config.yaml")
  if (!file.exists(manifest_path)) {
    stop("config.yaml not found in ", dir, call. = FALSE)
  }
  manifest <- yaml::read_yaml(manifest_path)

  required_top <- c("name", "files")
  missing_top <- setdiff(required_top, names(manifest))
  if (length(missing_top) > 0L) {
    stop("config.yaml missing required keys: ",
         paste(missing_top, collapse = ", "), call. = FALSE)
  }

  files <- manifest$files %||% list()
  required_files <- c("rules_yaml", "dimensions_csv", "parameters_fresh")
  missing_files <- setdiff(required_files, names(files))
  if (length(missing_files) > 0L) {
    stop("config.yaml `files:` missing required entries: ",
         paste(missing_files, collapse = ", "), call. = FALSE)
  }

  resolve <- function(rel) {
    if (is.null(rel)) return(NULL)
    file.path(dir, rel)
  }

  resolve_required <- function(key) {
    p <- resolve(files[[key]])
    if (!file.exists(p)) {
      stop("config.yaml `files$", key, "` references missing file: ", p,
           call. = FALSE)
    }
    p
  }

  read_csv_optional <- function(key) {
    rel <- files[[key]]
    if (is.null(rel)) return(NULL)
    p <- resolve(rel)
    if (!file.exists(p)) {
      stop("config.yaml `files$", key, "` references missing file: ", p,
           call. = FALSE)
    }
    utils::read.csv(p, stringsAsFactors = FALSE)
  }

  overrides <- lapply(manifest$overrides %||% list(), function(rel) {
    p <- resolve(rel)
    if (!file.exists(p)) {
      stop("config.yaml `overrides:` references missing file: ", p,
           call. = FALSE)
    }
    utils::read.csv(p, stringsAsFactors = FALSE)
  })

  rules_yaml_path <- resolve_required("rules_yaml")
  rules_species <- names(yaml::read_yaml(rules_yaml_path))

  out <- list(
    name = manifest$name,
    dir = dir,
    rules_yaml = rules_yaml_path,
    dimensions_csv = resolve_required("dimensions_csv"),
    species = rules_species,
    parameters_fresh = utils::read.csv(resolve_required("parameters_fresh"),
                                       stringsAsFactors = FALSE),
    habitat_classification = read_csv_optional("habitat_classification"),
    observation_exclusions = read_csv_optional("observation_exclusions"),
    wsg_species = read_csv_optional("wsg_species"),
    overrides = overrides,
    pipeline = manifest$pipeline %||% list(),
    provenance = manifest$provenance
  )
  class(out) <- c("lnk_config", "list")
  out
}

#' @export
print.lnk_config <- function(x, ...) {
  cat("<lnk_config> ", x$name, "\n", sep = "")
  cat("  dir:        ", x$dir, "\n", sep = "")
  cat("  rules:      ", basename(x$rules_yaml), "\n", sep = "")
  cat("  dimensions: ", basename(x$dimensions_csv), "\n", sep = "")
  cat("  parameters_fresh: ", nrow(x$parameters_fresh), " rows\n", sep = "")
  if (length(x$overrides) > 0L) {
    cat("  overrides: ", paste(names(x$overrides), collapse = ", "),
        "\n", sep = "")
  }
  if (length(x$pipeline) > 0L) {
    cat("  pipeline:  ", paste(names(x$pipeline), collapse = ", "),
        "\n", sep = "")
  }
  if (!is.null(x$provenance)) {
    cat("  provenance:", length(x$provenance), "files tracked\n", sep = " ")
  }
  invisible(x)
}

.lnk_config_resolve_dir <- function(name_or_path) {
  # Heuristic: inputs containing a path separator are treated as
  # filesystem paths; bare identifiers are looked up as bundled names
  # first. Without this, a `bcfishpass/` directory in the current
  # working directory would silently shadow the bundled config.
  looks_like_path <- grepl("[/\\\\]", name_or_path)

  if (looks_like_path) {
    if (!dir.exists(name_or_path)) {
      stop("No config directory found at path: ", name_or_path,
           call. = FALSE)
    }
    return(normalizePath(name_or_path, mustWork = TRUE))
  }

  bundled <- system.file("extdata", "configs", name_or_path, package = "link")
  if (nzchar(bundled) && dir.exists(bundled)) {
    return(normalizePath(bundled, mustWork = TRUE))
  }

  stop("No config bundle found for name: ", name_or_path,
       "\n  Bundled configs are in: ",
       system.file("extdata", "configs", package = "link"),
       "\n  To load a custom config, pass an absolute or relative path",
       " (must contain '/').",
       call. = FALSE)
}
