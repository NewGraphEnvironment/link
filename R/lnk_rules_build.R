#' Build habitat eligibility rules YAML from dimensions CSV
#'
#' Transforms a species habitat dimensions CSV into the rules YAML format
#' consumed by [fresh::frs_habitat()]. The CSV is the human-edited source
#' of truth; the YAML is the derived artifact.
#'
#' @param csv Path to a dimensions CSV with columns: `species`,
#'   `spawn_lake`, `spawn_stream`, `rear_lake`, `rear_lake_only`,
#'   `rear_no_fw`, `rear_stream`, `rear_wetland`. Optional columns:
#'   `river_skip_cw_min` (yes/no — skip channel_width_min on river
#'   polygon segments), `notes`.
#' @param to Path to write the output YAML.
#' @param thresholds Path to the habitat thresholds CSV (from fresh).
#'   Used to look up `rear_lake_ha_min` per species. Default uses the
#'   copy shipped with fresh.
#' @param edge_types Character. How to express stream edge types in rules:
#'   `"categories"` (default) uses fresh categories (`stream`, `canal`).
#'   `"explicit"` uses integer FWA edge_type codes (`1000, 1100, 2000, 2300`).
#'
#' @return Invisible path to the written YAML file.
#'
#' @examples
#' \dontrun{
#' # NGE defaults
#' lnk_rules_build(
#'   csv = system.file("extdata", "parameters_habitat_dimensions.csv", package = "link"),
#'   to = "inst/extdata/parameters_habitat_rules.yaml"
#' )
#'
#' # bcfishpass v0.5.0 comparison
#' lnk_rules_build(
#'   csv = system.file("extdata", "parameters_habitat_dimensions_bcfishpass.csv", package = "link"),
#'   to = "inst/extdata/parameters_habitat_rules_bcfishpass.yaml",
#'   edge_types = "explicit"
#' )
#' }
#'
#' @export
lnk_rules_build <- function(csv,
                             to,
                             thresholds = system.file("extdata",
                               "parameters_habitat_thresholds.csv",
                               package = "fresh"),
                             edge_types = c("categories", "explicit")) {
  stopifnot(requireNamespace("yaml", quietly = TRUE))
  edge_types <- match.arg(edge_types)

  if (!file.exists(csv)) stop("Dimensions CSV not found: ", csv)
  if (thresholds == "") stop("fresh package not installed or thresholds CSV missing")

  dimensions <- utils::read.csv(csv, stringsAsFactors = FALSE)
  thresh_df <- utils::read.csv(thresholds, stringsAsFactors = FALSE)

  # --- Validate ---
  required <- c("species", "spawn_lake", "spawn_stream",
                 "rear_lake", "rear_lake_only", "rear_no_fw",
                 "rear_stream", "rear_wetland")
  missing <- setdiff(required, names(dimensions))
  if (length(missing) > 0) {
    stop("Dimensions CSV missing columns: ", paste(missing, collapse = ", "))
  }

  # Coerce yes/no to logical
  yn_cols <- setdiff(required, "species")
  for (col in yn_cols) {
    dimensions[[col]] <- tolower(trimws(dimensions[[col]])) == "yes"
  }

  # Optional columns
  has_river_skip <- "river_skip_cw_min" %in% names(dimensions)
  if (has_river_skip) {
    dimensions$river_skip_cw_min <-
      tolower(trimws(dimensions$river_skip_cw_min)) == "yes"
  }

  has_all_edges <- "rear_all_edges" %in% names(dimensions)
  if (has_all_edges) {
    dimensions$rear_all_edges <-
      tolower(trimws(dimensions$rear_all_edges)) == "yes"
  }

  # Optional: requires_connected columns (value is the habitat type, not yes/no)
  has_spawn_rc <- "spawn_requires_connected" %in% names(dimensions)
  has_rear_rc <- "rear_requires_connected" %in% names(dimensions)

  # --- Edge type helpers ---
  stream_edges <- if (edge_types == "categories") {
    list(edge_types = c("stream", "canal"))
  } else {
    list(edge_types_explicit = c(1000L, 1100L, 2000L, 2300L))
  }

  # --- Build rules per species ---
  species_rules <- list()

  for (i in seq_len(nrow(dimensions))) {
    d <- dimensions[i, ]
    sp <- d$species

    th <- thresh_df[thresh_df$species_code == sp, ]
    if (nrow(th) == 0) {
      message("Skipping ", sp, ": no thresholds in fresh CSV")
      next
    }

    spawn_rules <- list()
    rear_rules <- list()

    # River polygon rule — optionally skip cw_min
    river_rule <- list(waterbody_type = "R")
    if (has_river_skip && d$river_skip_cw_min) {
      river_rule$channel_width <- c(0, 9999)
    }

    # requires_connected values for this species (empty string or NA = none)
    spawn_rc <- if (has_spawn_rc) trimws(as.character(d$spawn_requires_connected)) else ""
    if (is.na(spawn_rc)) spawn_rc <- ""
    rear_rc <- if (has_rear_rc) trimws(as.character(d$rear_requires_connected)) else ""
    if (is.na(rear_rc)) rear_rc <- ""

    # Helper: annotate rule with requires_connected if non-empty
    add_rc <- function(rule, rc_value) {
      if (nchar(rc_value) > 0) rule$requires_connected <- rc_value
      rule
    }

    # --- Spawning ---
    if (d$spawn_stream) {
      spawn_rules[[length(spawn_rules) + 1]] <- add_rc(stream_edges, spawn_rc)
      spawn_rules[[length(spawn_rules) + 1]] <- add_rc(river_rule, spawn_rc)
    }
    if (d$spawn_lake) {
      spawn_rules[[length(spawn_rules) + 1]] <- add_rc(
        list(waterbody_type = "L"), spawn_rc)
    }

    # --- Rearing (precedence: no_fw > lake_only > additive) ---
    if (d$rear_no_fw) {
      rear_rules <- list()
    } else if (d$rear_lake_only) {
      lake_rule <- list(waterbody_type = "L", thresholds = FALSE)
      if (!is.na(th$rear_lake_ha_min)) {
        lake_rule$lake_ha_min <- th$rear_lake_ha_min
      }
      rear_rules[[1]] <- add_rc(lake_rule, rear_rc)
    } else {
      if (has_all_edges && d$rear_all_edges) {
        rear_rules[[length(rear_rules) + 1]] <- add_rc(list(), rear_rc)
      } else if (d$rear_stream) {
        rear_rules[[length(rear_rules) + 1]] <- add_rc(stream_edges, rear_rc)
        rear_rules[[length(rear_rules) + 1]] <- add_rc(river_rule, rear_rc)
      }
      if (d$rear_wetland) {
        if (edge_types == "categories") {
          rear_rules[[length(rear_rules) + 1]] <- add_rc(list(
            edge_types = c("wetland"), thresholds = FALSE), rear_rc)
        } else {
          rear_rules[[length(rear_rules) + 1]] <- add_rc(list(
            edge_types_explicit = c(1050L, 1150L), thresholds = FALSE), rear_rc)
        }
      }
      if (d$rear_lake) {
        lake_rule <- list(waterbody_type = "L", thresholds = FALSE)
        if (!is.na(th$rear_lake_ha_min)) {
          lake_rule$lake_ha_min <- th$rear_lake_ha_min
        }
        rear_rules[[length(rear_rules) + 1]] <- add_rc(lake_rule, rear_rc)
      }
    }

    species_rules[[sp]] <- list(spawn = spawn_rules, rear = rear_rules)
  }

  # --- Write YAML ---
  header <- c(
    sprintf("# Generated from %s", basename(csv)),
    sprintf("# Generated: %s", format(Sys.Date(), "%Y-%m-%d")),
    sprintf("# Edge types: %s", edge_types),
    "#",
    "# DO NOT EDIT — edit the CSV and re-run lnk_rules_build()",
    ""
  )

  yaml_body <- yaml::as.yaml(species_rules,
    indent = 2,
    handlers = list(
      logical = function(x) {
        v <- ifelse(x, "true", "false")
        class(v) <- "verbatim"
        v
      }
    )
  )

  writeLines(c(header, yaml_body), to)
  message("Wrote ", to, " (", length(species_rules), " species, ", edge_types, " edge types)")
  invisible(to)
}
