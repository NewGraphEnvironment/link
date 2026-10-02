#' Load a Pipeline Config Bundle (Manifest)
#'
#' Reads a config bundle manifest (`config.yaml`) and returns a single
#' list object describing what a pipeline variant does — paths, file
#' declarations, pipeline knobs, provenance — but **no parsed data**.
#'
#' Tabular data (override CSVs, habitat classifications, parameters)
#' is loaded by [lnk_load_overrides()], which dispatches each declared
#' file through [crate::crt_ingest()] for source-registered entries
#' and falls through to local reads otherwise. This split keeps
#' `lnk_config()` cheap to call (no CSV parsing) and lets
#' provenance-only consumers like [lnk_config_verify()] and
#' [lnk_stamp()] work without touching data.
#'
#' A config bundle is a directory under `inst/extdata/configs/<name>/`
#' (for bundled variants) or an arbitrary directory path (for custom
#' variants) containing `config.yaml` plus the files the manifest
#' references. All file paths in the manifest are resolved relative to
#' the bundle directory.
#'
#' Configs may declare `extends: <parent>` to inherit from another
#' config. The parent is resolved (recursively, if it also extends)
#' and merged shallowly: child entries override parent entries with
#' the same key in `files:`, `pipeline:`, and `provenance:`; top-level
#' scalars (`description`, `rules`, `dimensions`) override directly.
#'
#' @param name_or_path Character. Either a bundled config name
#'   (`"bcfishpass"`, `"default"`) or an absolute path to a config
#'   directory. Bundled names resolve to `system.file("extdata",
#'   "configs", name, package = "link")`.
#'
#' @return An `lnk_config` S3 list with these slots:
#'
#'   - `name` — config name from the manifest
#'   - `dir` — absolute path to the config directory
#'   - `description` — manifest's free-text description (or `NULL`)
#'   - `rules` — absolute path to the rules YAML (consumed by
#'     `fresh::frs_habitat_classify()`)
#'   - `dimensions` — absolute path to the dimensions CSV (input to
#'     [lnk_rules_build()])
#'   - `species` — character vector of species the rules YAML
#'     classifies (parsed from `rules.yaml` top-level keys)
#'   - `files` — named list of file declarations. Each entry is a list
#'     with `path` (resolved absolute path) and optionally `source`
#'     (free-text provenance label) and `canonical_schema`
#'     (`"<source>/<file_name>"` — keys into crate's registry to
#'     dispatch ingest via [crate::crt_ingest()])
#'   - `pipeline` — named list of pipeline knobs
#'     (`apply_habitat_overlay`, `break_order`, `cluster`,
#'     `spawn_connected`)
#'   - `provenance` — named list of per-file provenance metadata,
#'     keyed by file path relative to `dir`. Drift detection against
#'     these checksums lives in [lnk_config_verify()].
#'   - `extends` — character or `NULL`, the parent config name/path
#'     this manifest declared (post-resolution; not used by callers
#'     beyond audit)
#'   - `chain` — character vector of bundle directories along the
#'     `extends:` chain, leaf first (just `dir` when nothing is
#'     extended). Inherited `provenance` entries carry the directory
#'     they are relative to in `.dir`.
#'
#' @export
#'
#' @examples
#' cfg <- lnk_config("bcfishpass")
#' cfg$name
#' cfg$rules
#' names(cfg$files)
#' cfg$files$user_habitat_classification
#' cfg$pipeline$break_order
#'
#' \dontrun{
#' # Custom config: point at any directory containing config.yaml
#' my_cfg <- lnk_config("/path/to/my/variant")
#'
#' # Materialize the data tables declared in the manifest
#' loaded <- lnk_load_overrides(my_cfg)
#' loaded$user_habitat_classification
#' }
lnk_config <- function(name_or_path) {
  if (!is.character(name_or_path) || length(name_or_path) != 1L) {
    stop("name_or_path must be a single string", call. = FALSE)
  }

  resolved <- .lnk_config_resolve(name_or_path, seen = character(0))
  manifest <- resolved$manifest
  dir <- resolved$dir

  required_top <- c("name", "rules", "dimensions", "files")
  missing_top <- setdiff(required_top, names(manifest))
  if (length(missing_top) > 0L) {
    stop("config.yaml missing required keys: ",
         paste(missing_top, collapse = ", "), call. = FALSE)
  }

  rules_path <- if (.lnk_path_is_absolute(manifest$rules)) {
    manifest$rules
  } else {
    file.path(dir, manifest$rules)
  }
  if (!file.exists(rules_path)) {
    stop("config.yaml `rules:` references missing file: ", rules_path,
         call. = FALSE)
  }

  dimensions_path <- if (.lnk_path_is_absolute(manifest$dimensions)) {
    manifest$dimensions
  } else {
    file.path(dir, manifest$dimensions)
  }
  if (!file.exists(dimensions_path)) {
    stop("config.yaml `dimensions:` references missing file: ",
         dimensions_path, call. = FALSE)
  }

  files <- .lnk_config_resolve_files(manifest$files, dir)
  rules_species <- names(yaml::read_yaml(rules_path))

  out <- list(
    name = manifest$name,
    dir = dir,
    description = manifest$description,
    rules = rules_path,
    dimensions = dimensions_path,
    species = rules_species,
    files = files,
    pipeline = manifest$pipeline %||% list(),
    provenance = manifest$provenance,
    extends = manifest$extends,
    chain = resolved$chain
  )
  class(out) <- c("lnk_config", "list")
  out
}

#' @export
print.lnk_config <- function(x, ...) {
  cat("<lnk_config> ", x$name, "\n", sep = "")
  cat("  dir:        ", x$dir, "\n", sep = "")
  cat("  rules:      ", basename(x$rules), "\n", sep = "")
  cat("  dimensions: ", basename(x$dimensions), "\n", sep = "")
  if (!is.null(x$species)) {
    cat("  species:    ", paste(x$species, collapse = ", "), "\n", sep = "")
  }
  if (length(x$files) > 0L) {
    cat("  files:      ", length(x$files), " declared (", sep = "")
    crate_n <- sum(vapply(x$files,
                          function(f) !is.null(f$canonical_schema),
                          logical(1)))
    cat(crate_n, " via crate)\n", sep = "")
  }
  if (length(x$pipeline) > 0L) {
    cat("  pipeline:  ", paste(names(x$pipeline), collapse = ", "),
        "\n", sep = "")
  }
  if (!is.null(x$provenance)) {
    cat("  provenance:", length(x$provenance), "files tracked\n", sep = " ")
  }
  if (!is.null(x$extends)) {
    cat("  extends:   ", x$extends, "\n", sep = "")
  }
  invisible(x)
}

# Resolve manifest YAML, following `extends:` chains. Returns a list
# with `manifest` (merged) and `dir` (the leaf config's directory —
# which is what file paths resolve relative to).
.lnk_config_resolve <- function(name_or_path, seen) {
  dir <- .lnk_config_resolve_dir(name_or_path)
  if (dir %in% seen) {
    stop("Circular `extends:` chain detected: ",
         paste(c(seen, dir), collapse = " -> "), call. = FALSE)
  }

  manifest_path <- file.path(dir, "config.yaml")
  if (!file.exists(manifest_path)) {
    stop("config.yaml not found in ", dir, call. = FALSE)
  }
  manifest <- yaml::read_yaml(manifest_path)

  if (is.null(manifest$extends)) {
    return(list(manifest = manifest, dir = dir, chain = dir))
  }

  # A relative path in `extends:` is relative to this bundle, like every other
  # path in its manifest — not to whatever directory R happens to be in. A bare
  # name (no separator) is still a bundled config.
  parent_ref <- manifest$extends
  if (grepl("[/\\\\]", parent_ref) && !.lnk_path_is_absolute(parent_ref)) {
    parent_ref <- file.path(dir, parent_ref)
  }
  parent <- .lnk_config_resolve(parent_ref, seen = c(seen, dir))
  list(
    manifest = .lnk_config_merge(parent$manifest, manifest, parent$dir, dir),
    dir = dir,
    chain = c(dir, parent$chain)
  )
}

# Merge a child manifest onto a parent. `files:`, `pipeline:`, and
# `provenance:` are shallow-merged (child entries override same-key
# parent entries; parent-only entries kept). Top-level scalars and
# `description` are direct-overridden by child when present. Paths
# inherited from the parent are rewritten to absolute paths against
# the parent dir, so the leaf config's resolver can keep them stable
# regardless of which dir is "current".
.lnk_config_merge <- function(parent, child, parent_dir, child_dir) {
  parent_files <- .lnk_config_absolutize_files(parent$files, parent_dir)
  child_files <- child$files %||% list()
  for (key in names(child_files)) {
    parent_files[[key]] <- child_files[[key]]
  }

  # Provenance keys are paths relative to the bundle that declared them, so an
  # inherited entry keeps the parent's dir (`.dir`) — resolved against the
  # child's dir it names a file that does not exist there. Deeper ancestors
  # already carry theirs.
  parent_prov <- lapply(parent$provenance %||% list(), function(entry) {
    if (is.null(entry[[".dir"]])) entry[[".dir"]] <- parent_dir
    entry
  })
  child_prov <- child$provenance %||% list()
  for (key in names(child_prov)) {
    parent_prov[[key]] <- child_prov[[key]]
  }

  parent_pipe <- parent$pipeline %||% list()
  child_pipe <- child$pipeline %||% list()
  for (key in names(child_pipe)) {
    parent_pipe[[key]] <- child_pipe[[key]]
  }

  list(
    name = child$name %||% parent$name,
    description = child$description %||% parent$description,
    rules = child$rules %||% .lnk_config_absolutize(parent$rules, parent_dir),
    dimensions = child$dimensions %||%
      .lnk_config_absolutize(parent$dimensions, parent_dir),
    files = parent_files,
    pipeline = parent_pipe,
    provenance = parent_prov,
    extends = child$extends
  )
}

# A parent's rules/dimensions are already absolute when the parent itself
# extends something (a chain of three or more); prefixing them again names a
# path that does not exist.
.lnk_config_absolutize <- function(path, dir) {
  if (is.null(path) || .lnk_path_is_absolute(path)) path else file.path(dir, path)
}

# Rewrite `files:` entry paths to absolute (against the given dir).
# Used during extends merge so inherited entries don't get re-resolved
# against the child dir.
.lnk_config_absolutize_files <- function(files, dir) {
  if (is.null(files)) return(list())
  lapply(files, function(entry) {
    if (!is.null(entry$path) && !.lnk_path_is_absolute(entry$path)) {
      entry$path <- file.path(dir, entry$path)
    }
    entry
  })
}

.lnk_path_is_absolute <- function(p) {
  grepl("^([A-Za-z]:)?[/\\\\]", p)
}

# Resolve each `files:` entry's path. Already-absolute paths (e.g.
# inherited via extends) are kept; relative paths are resolved
# against `dir`.
.lnk_config_resolve_files <- function(files, dir) {
  if (is.null(files)) return(list())
  lapply(names(files), function(key) {
    entry <- files[[key]]
    if (is.null(entry$path)) {
      stop("config.yaml `files$", key, "` missing required `path`",
           call. = FALSE)
    }
    if (!.lnk_path_is_absolute(entry$path)) {
      entry$path <- file.path(dir, entry$path)
    }
    if (!file.exists(entry$path)) {
      stop("config.yaml `files$", key, "$path` references missing file: ",
           entry$path, call. = FALSE)
    }
    entry
  }) |> stats::setNames(names(files))
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

# Path to the habitat thresholds CSV a config runs with.
#
# A bundle declares its own under `files: parameters_habitat_thresholds:`
# (#282), so a tuned bundle can move a species' gradient or channel-width
# cutoff without moving the `bcfishpass` parity reference. A config that
# declares none falls back to fresh's shipped copy — the pre-#282 behaviour
# for every bundle — and says so, because that copy is outside the config's
# provenance and changes whenever fresh is upgraded.
.lnk_habitat_thresholds_csv <- function(cfg) {
  path <- cfg$files$parameters_habitat_thresholds$path
  if (!is.null(path)) {
    return(path)
  }
  fresh_path <- system.file("extdata", "parameters_habitat_thresholds.csv",
                            package = "fresh")
  message("config '", cfg$name %||% "<unnamed>", "' declares no ",
          "files$parameters_habitat_thresholds; using fresh's copy: ",
          fresh_path)
  fresh_path
}

# Path to the per-watershed-group habitat model table (`cw` or `mad`) a
# config runs with (#286). Same contract as the thresholds CSV above: the
# bundle's own `files: parameters_habitat_method:`, else fresh's shipped copy
# (all `cw`), with a message because that copy sits outside the config's
# provenance.
.lnk_habitat_method_csv <- function(cfg) {
  path <- cfg$files$parameters_habitat_method$path
  if (!is.null(path)) {
    return(path)
  }
  fresh_path <- system.file("extdata", "parameters_habitat_method.csv",
                            package = "fresh")
  message("config '", cfg$name %||% "<unnamed>", "' declares no ",
          "files$parameters_habitat_method; using fresh's copy: ",
          fresh_path)
  fresh_path
}

# Absolute path of a provenance entry. Keys are relative to the bundle that
# declared them: the leaf for its own entries, `.dir` for inherited ones.
.lnk_provenance_path <- function(cfg, rel) {
  file.path(cfg$provenance[[rel]][[".dir"]] %||% cfg$dir, rel)
}
