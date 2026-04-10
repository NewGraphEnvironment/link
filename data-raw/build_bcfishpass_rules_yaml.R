# data-raw/build_bcfishpass_rules_yaml.R
#
# Generate a rules YAML that matches bcfishpass v0.5.0 exactly.
# This is NOT our NGE defaults (those are in build_habitat_rules_yaml.R).
# This is for the comparison script (compare_adms.R) to validate that
# fresh+link can reproduce bcfishpass outputs.
#
# BOTH builders read from the same CSV source of truth:
#   inst/extdata/parameters_habitat_dimensions.csv
#
# Key differences from NGE defaults:
#   - edge_types_explicit [1000, 1100, 2000, 2300] (not categories)
#   - waterbody_type=R: channel_width [0, 9999] (bcfishpass skips cw_min)
#   - Wetland-flow carve-out: only species with rear_wetland=yes
#   - BT rear: no edge filter (bcfishpass has none — empty rule)
#
# Usage:
#   source("data-raw/build_bcfishpass_rules_yaml.R")

stopifnot(requireNamespace("yaml", quietly = TRUE))

# --- Inputs ---

dimensions_path <- "inst/extdata/parameters_habitat_dimensions.csv"
thresholds_path <- system.file("extdata",
  "parameters_habitat_thresholds.csv", package = "fresh")
output_path <- "inst/extdata/parameters_habitat_rules_bcfishpass.yaml"

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

# Only build rules for species that bcfishpass models (have thresholds)
get_thresholds <- function(species_code) {
  row <- thresholds[thresholds$species_code == species_code, ]
  if (nrow(row) == 0) return(NULL)
  row
}

# --- bcfishpass deviations from NGE biological defaults ---
# The dimensions CSV is NGE truth. bcfishpass v0.5.0 is more restrictive
# on some species. These overrides replicate what bcfishpass actually does.
# Verified from bcfishpass SQL: load_habitat_linear_*.sql
bcfp_overrides <- list(
  CH = list(rear_wetland = FALSE, rear_lake = FALSE),
  CO = list(rear_lake = FALSE),
  SK = list(spawn_lake = FALSE),
  ST = list(rear_wetland = FALSE, rear_lake = FALSE),
  WCT = list(rear_wetland = FALSE, rear_lake = FALSE),
  RB = list(rear_wetland = FALSE, rear_lake = FALSE),
  GR = list(rear_wetland = FALSE, rear_lake = FALSE)
)

# --- bcfishpass-specific constants ---

# bcfishpass spawning: edge_type IN (1000, 1100, 2000, 2300) — excludes 1050/1150
bcfp_stream_edges <- c(1000L, 1100L, 2000L, 2300L)

# bcfishpass river polygon: waterbody_type=R skips cw_min (channel_width [0, 9999])
bcfp_river_rule <- list(
  waterbody_type = "R",
  channel_width = c(0, 9999)
)

# bcfishpass wetland-flow carve-out: edge_types 1050/1150 with no thresholds
bcfp_wetland_rule <- list(
  edge_types_explicit = c(1050L, 1150L),
  thresholds = FALSE
)

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

  # Apply bcfishpass-specific overrides
  if (sp %in% names(bcfp_overrides)) {
    for (nm in names(bcfp_overrides[[sp]])) {
      d[[nm]] <- bcfp_overrides[[sp]][[nm]]
    }
  }

  spawn_rules <- list()
  rear_rules <- list()

  # --- Spawning ---
  # bcfishpass: all species use edge_types_explicit + waterbody_type=R
  if (d$spawn_stream) {
    spawn_rules[[length(spawn_rules) + 1]] <- list(
      edge_types_explicit = bcfp_stream_edges
    )
    spawn_rules[[length(spawn_rules) + 1]] <- bcfp_river_rule
  }
  if (d$spawn_lake) {
    spawn_rules[[length(spawn_rules) + 1]] <- list(waterbody_type = "L")
  }

  # --- Rearing (precedence: no_fw > lake_only > additive) ---
  if (d$rear_no_fw) {
    rear_rules <- list()
  } else if (d$rear_lake_only) {
    lake_rule <- list(waterbody_type = "L")
    if (!is.na(th$rear_lake_ha_min)) {
      lake_rule$lake_ha_min <- th$rear_lake_ha_min
    }
    rear_rules[[1]] <- lake_rule
  } else {
    # bcfishpass rearing SQL: wb.waterbody_type = 'R' OR
    #   (wb.waterbody_type IS NULL AND edge_type IN (1000,1100,2000,2300))
    # BT is special: no edge_type filter (empty rule matches all)
    if (d$rear_stream) {
      if (sp == "BT") {
        # BT rearing in bcfishpass: no edge_type filter at all
        rear_rules[[length(rear_rules) + 1]] <- list()
      } else {
        rear_rules[[length(rear_rules) + 1]] <- list(
          edge_types_explicit = bcfp_stream_edges
        )
      }
      rear_rules[[length(rear_rules) + 1]] <- bcfp_river_rule
    }
    if (d$rear_wetland) {
      # CO wetland carve-out: 1050/1150 no thresholds
      # bcfishpass only has this for CO explicitly, but we derive from CSV
      rear_rules[[length(rear_rules) + 1]] <- bcfp_wetland_rule
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

header <- c(
  "# bcfishpass v0.5.0 matching rules",
  "# Generated from inst/extdata/parameters_habitat_dimensions.csv",
  "# DO NOT EDIT — edit the CSV and re-run data-raw/build_bcfishpass_rules_yaml.R",
  paste0("# Generated: ", format(Sys.Date(), "%Y-%m-%d")),
  "#",
  "# These rules replicate bcfishpass v0.5.0 habitat_linear SQL.",
  "# For NGE saner defaults, use parameters_habitat_rules.yaml instead.",
  "#",
  "# Key bcfishpass conventions replicated here:",
  "#   - Spawning only on edge_type 1000/1100/2000/2300 (excludes 1050/1150)",
  "#   - waterbody_type=R segments skip channel_width_min (channel_width: [0, 9999])",
  "#   - Wetland-flow 1050/1150 rearing only for species with rear_wetland=yes",
  "#   - BT rearing has no edge_type filter (empty rule)",
  "#   - SK/KO rearing is lake-only (from rear_lake_only=yes in CSV)",
  "#   - CM/PK have no freshwater rearing (from rear_no_fw=yes in CSV)",
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
message("Wrote ", output_path)
message("Species: ", paste(names(species_rules), collapse = ", "))
