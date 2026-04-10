# data-raw/build_habitat_rules_yaml.R
#
# Generate parameters_habitat_rules.yaml from parameters_habitat_dimensions.csv
#
# The dimensions CSV is the human-edited source of truth (which species use
# which habitat types). The rules YAML is a derived artifact consumed by
# fresh::frs_habitat() (fresh#113).
#
# Usage:
#   source("data-raw/build_habitat_rules_yaml.R")
#
# Inputs:
#   - inst/extdata/parameters_habitat_dimensions.csv (link)
#   - parameters_habitat_thresholds.csv (fresh — for species threshold lookup)
#
# Output:
#   - inst/extdata/parameters_habitat_rules.yaml (link)
#
# To sync the YAML to fresh, copy manually after running:
#   file.copy("inst/extdata/parameters_habitat_rules.yaml",
#             "../fresh/inst/extdata/parameters_habitat_rules.yaml",
#             overwrite = TRUE)

stopifnot(requireNamespace("yaml", quietly = TRUE))

# --- Inputs ---

dimensions_path <- "inst/extdata/parameters_habitat_dimensions.csv"
thresholds_path <- system.file("extdata",
  "parameters_habitat_thresholds.csv", package = "fresh")
output_path <- "inst/extdata/parameters_habitat_rules.yaml"

if (!file.exists(dimensions_path)) {
  stop("Missing dimensions CSV: ", dimensions_path)
}
if (thresholds_path == "") {
  stop("fresh package not installed or thresholds CSV missing")
}

dimensions <- utils::read.csv(dimensions_path, stringsAsFactors = FALSE)
thresholds <- utils::read.csv(thresholds_path, stringsAsFactors = FALSE)

# --- Validation ---

required_cols <- c("species", "spawn_lake", "spawn_stream",
                   "rear_lake", "rear_lake_only", "rear_no_fw",
                   "rear_stream", "rear_wetland")
missing <- setdiff(required_cols, names(dimensions))
if (length(missing) > 0) {
  stop("Dimensions CSV missing columns: ", paste(missing, collapse = ", "))
}

# Coerce yes/no to logical
yn_cols <- setdiff(required_cols, "species")
for (col in yn_cols) {
  dimensions[[col]] <- tolower(trimws(dimensions[[col]])) == "yes"
}

# --- Helpers ---

# Look up species in fresh thresholds. Returns NULL if not found.
get_thresholds <- function(species_code) {
  row <- thresholds[thresholds$species_code == species_code, ]
  if (nrow(row) == 0) return(NULL)
  row
}

# Build a single rule (list) from a predicate spec.
# Inheritance: rules inherit thresholds from the species CSV row by default.
# Set inherit_thresholds = FALSE for carve-outs that drop the threshold checks.
make_rule <- function(predicates, inherit_thresholds = TRUE) {
  rule <- predicates
  if (!inherit_thresholds) {
    rule$thresholds <- FALSE
  }
  rule
}

# --- Build rules per species ---

species_rules <- list()

for (i in seq_len(nrow(dimensions))) {
  d <- dimensions[i, ]
  sp <- d$species

  th <- get_thresholds(sp)
  if (is.null(th)) {
    message("Skipping ", sp, ": no thresholds in fresh CSV")
    next
  }

  spawn_rules <- list()
  rear_rules <- list()

  # --- Spawning ---

  if (d$spawn_stream) {
    # Stream/canal rule + waterbody_type=R for river polygons (data fix)
    spawn_rules[[length(spawn_rules) + 1]] <- make_rule(list(
      edge_types = c("stream", "canal")
    ))
    spawn_rules[[length(spawn_rules) + 1]] <- make_rule(list(
      waterbody_type = "R"
    ))
  }

  if (d$spawn_lake) {
    spawn_rules[[length(spawn_rules) + 1]] <- make_rule(list(
      waterbody_type = "L"
    ))
  }

  # --- Rearing (precedence: no_fw > lake_only > additive) ---

  if (d$rear_no_fw) {
    # No freshwater rearing — empty rules list
    rear_rules <- list()
  } else if (d$rear_lake_only) {
    # Lake-only override — drops stream/wetland rules
    lake_rule <- list(waterbody_type = "L")
    if (!is.na(th$rear_lake_ha_min)) {
      lake_rule$lake_ha_min <- th$rear_lake_ha_min
    }
    rear_rules[[length(rear_rules) + 1]] <- lake_rule
  } else {
    # Additive rules
    if (d$rear_stream) {
      rear_rules[[length(rear_rules) + 1]] <- make_rule(list(
        edge_types = c("stream", "canal")
      ))
      rear_rules[[length(rear_rules) + 1]] <- make_rule(list(
        waterbody_type = "R"
      ))
    }
    if (d$rear_wetland) {
      # Wetland-flow carve-out — bcfishpass v0.5.0 includes 1050/1150 with
      # no gradient/cw checks. Use inherit_thresholds = FALSE.
      rear_rules[[length(rear_rules) + 1]] <- make_rule(list(
        edge_types_explicit = c(1050L, 1150L)
      ), inherit_thresholds = FALSE)
    }
    if (d$rear_lake) {
      lake_rule <- list(waterbody_type = "L")
      if (!is.na(th$rear_lake_ha_min)) {
        lake_rule$lake_ha_min <- th$rear_lake_ha_min
      }
      rear_rules[[length(rear_rules) + 1]] <- lake_rule
    }
  }

  species_rules[[sp]] <- list(
    spawn = spawn_rules,
    rear = rear_rules
  )
}

# --- Write YAML ---

# Header comment is added separately because yaml package doesn't write
# comments. Use writeLines to prepend.

header <- c(
  "# Generated from inst/extdata/parameters_habitat_dimensions.csv",
  "# DO NOT EDIT — edit the CSV and re-run data-raw/build_habitat_rules_yaml.R",
  paste0("# Generated: ", format(Sys.Date(), "%Y-%m-%d")),
  "#",
  "# Each species has spawn and rear rule lists. A segment qualifies as",
  "# spawning/rearing if ANY rule matches (rules joined by OR; predicates",
  "# within a rule joined by AND).",
  "#",
  "# Rules inherit gradient/channel_width thresholds from",
  "# parameters_habitat_thresholds.csv unless `thresholds: false` is set.",
  "#",
  "# Predicates:",
  "#   edge_types: list of fresh categories (stream, canal, river, lake, wetland)",
  "#   edge_types_explicit: list of integer FWA edge_type codes",
  "#   waterbody_type: 'L' (lake), 'R' (river polygon), 'W' (wetland)",
  "#   lake_ha_min: minimum lake area for waterbody_type=L rules",
  "#   thresholds: false  — skip CSV threshold inheritance for this rule",
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

writeLines(c(header, yaml_body), output_path)

message("\nWrote ", output_path)
message("Species: ", paste(names(species_rules), collapse = ", "))
message("\nTo sync to fresh:")
message("  file.copy(\"", output_path, "\",")
message("            \"../fresh/inst/extdata/parameters_habitat_rules.yaml\",")
message("            overwrite = TRUE)")
