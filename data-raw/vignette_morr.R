# data-raw/vignette_morr.R
#
# Generate vignette data for Morice (MORR) watershed group.
#
# Data sources (no DB required):
#   - Crossings: fresh::system.file("extdata", "crossings.csv")
#   - PSCIS assessments: bcdata::bcdc_get_data() from BC Data Catalogue
#   - Override CSVs: bcfishpass/data/ directory
#
# Run interactively:
#   source("data-raw/vignette_morr.R")
#
# Requires: fresh, bcdata installed

wsg <- "MORR"
bcfishpass_data <- "~/Projects/repo/bcfishpass/data"

# --- 1. Extract MORR crossings from fresh CSV ---

message("--- 1. Loading crossings from fresh CSV ---")
crossings_csv <- system.file("extdata", "crossings.csv", package = "fresh")
if (crossings_csv == "") stop("fresh package not installed or crossings.csv not found")

crossings_all <- read.csv(crossings_csv, stringsAsFactors = FALSE)
morr_crossings_raw <- crossings_all[crossings_all$watershed_group_code == wsg, ]

saveRDS(morr_crossings_raw, "inst/testdata/morr_crossings_raw.rds")
message("Raw crossings: ", nrow(morr_crossings_raw))
message("  By source: ")
print(table(morr_crossings_raw$crossing_source))

# --- 2. Load override CSVs filtered to MORR ---

message("\n--- 2. Loading override CSVs ---")

# Modelled crossing fixes
fixes_all <- read.csv(
  file.path(bcfishpass_data, "user_modelled_crossing_fixes.csv"),
  stringsAsFactors = FALSE
)
morr_fixes <- fixes_all[fixes_all$watershed_group_code == wsg, ]
saveRDS(morr_fixes, "inst/testdata/morr_modelled_fixes.rds")
message("Modelled crossing fixes: ", nrow(morr_fixes))
message("  Structures: ")
print(table(morr_fixes$structure))

# PSCIS-to-modelled xref
xref_all <- read.csv(
  file.path(bcfishpass_data, "pscis_modelledcrossings_streams_xref.csv"),
  stringsAsFactors = FALSE
)
morr_xref <- xref_all[xref_all$watershed_group_code == wsg, ]
saveRDS(morr_xref, "inst/testdata/morr_xref.rds")
message("PSCIS-modelled xref corrections: ", nrow(morr_xref))

# PSCIS barrier status overrides
pscis_status_all <- read.csv(
  file.path(bcfishpass_data, "user_pscis_barrier_status.csv"),
  stringsAsFactors = FALSE
)
morr_pscis_status <- pscis_status_all[
  pscis_status_all$watershed_group_code == wsg, ]
saveRDS(morr_pscis_status, "inst/testdata/morr_pscis_status_fixes.rds")
message("PSCIS barrier status overrides: ", nrow(morr_pscis_status))

# --- 3. Get PSCIS assessments from BC Data Catalogue ---

message("\n--- 3. Fetching PSCIS assessments from bcdata ---")
library(bcdata)

# Get MORR PSCIS crossing IDs from the crossings table
morr_pscis_ids <- morr_crossings_raw$aggregated_crossings_id[
  morr_crossings_raw$crossing_source == "PSCIS"
]
# aggregated_crossings_id for PSCIS source = stream_crossing_id
morr_pscis_ids <- as.integer(morr_pscis_ids)

# Fetch from BC Data Catalogue
# PSCIS Assessments: 7ecfafa6-5e18-48cd-8d9b-eae5b5ea2881
morr_pscis_sf <- bcdc_query_geodata("7ecfafa6-5e18-48cd-8d9b-eae5b5ea2881") |>
  filter(STREAM_CROSSING_ID %in% morr_pscis_ids) |>
  collect()

# Convert to plain data frame with columns we need
morr_pscis <- data.frame(
  stream_crossing_id = morr_pscis_sf$STREAM_CROSSING_ID,
  assessment_date = morr_pscis_sf$ASSESSMENT_DATE,
  crossing_type_code = morr_pscis_sf$CROSSING_TYPE_CODE,
  crossing_subtype_code = morr_pscis_sf$CROSSING_SUBTYPE_CODE,
  barrier_result_code = morr_pscis_sf$BARRIER_RESULT_CODE,
  outlet_drop = morr_pscis_sf$OUTLET_DROP,
  outlet_pool_depth = morr_pscis_sf$OUTLET_POOL_DEPTH,
  culvert_slope = morr_pscis_sf$CULVERT_SLOPE,
  culvert_length_m = as.numeric(morr_pscis_sf$CULVERT_LENGTH_SCORE),
  downstream_channel_width = morr_pscis_sf$DOWNSTREAM_CHANNEL_WIDTH,
  stringsAsFactors = FALSE
)

# Add network position from the crossings table
pscis_crossings <- morr_crossings_raw[
  morr_crossings_raw$crossing_source == "PSCIS",
  c("aggregated_crossings_id", "blue_line_key", "downstream_route_measure")
]
pscis_crossings$stream_crossing_id <- as.integer(
  pscis_crossings$aggregated_crossings_id)

morr_pscis <- merge(morr_pscis, pscis_crossings[,
  c("stream_crossing_id", "blue_line_key", "downstream_route_measure")],
  by = "stream_crossing_id", all.x = TRUE)

saveRDS(morr_pscis, "inst/testdata/morr_pscis.rds")
message("PSCIS assessments: ", nrow(morr_pscis))
message("  With network position: ",
        sum(!is.na(morr_pscis$blue_line_key)))

# --- 4. Build summary tables for vignette display ---

message("\n--- 4. Building summary tables ---")

# Barrier status before overrides
barrier_before <- table(morr_crossings_raw$barrier_status)
saveRDS(barrier_before, "inst/testdata/morr_barrier_before.rds")

# PSCIS measurement summary (crossings with field data)
pscis_with_measurements <- morr_pscis[!is.na(morr_pscis$outlet_drop), ]
saveRDS(pscis_with_measurements, "inst/testdata/morr_pscis_measured.rds")
message("PSCIS with outlet_drop: ", nrow(pscis_with_measurements))

# Example scored crossings (simulate severity from PSCIS measurements)
# This shows what lnk_score_severity would produce
th <- link::lnk_thresholds()
morr_pscis$severity <- ifelse(
  !is.na(morr_pscis$outlet_drop) & morr_pscis$outlet_drop >= th$high$outlet_drop,
  "high",
  ifelse(
    !is.na(morr_pscis$outlet_drop) & morr_pscis$outlet_drop >= th$moderate$outlet_drop,
    "moderate",
    ifelse(!is.na(morr_pscis$outlet_drop), "low", NA_character_)
  )
)
saveRDS(morr_pscis, "inst/testdata/morr_pscis_scored.rds")

severity_dist <- table(morr_pscis$severity, useNA = "ifany")
saveRDS(severity_dist, "inst/testdata/morr_severity_dist.rds")
message("Severity distribution (PSCIS with measurements):")
print(severity_dist)

# Break source spec (what link would produce)
morr_break_spec <- list(
  table = "working.morr_crossings",
  label_col = "severity",
  label_map = c(high = "blocked", moderate = "potential")
)
saveRDS(morr_break_spec, "inst/testdata/morr_break_source.rds")

message("\n--- Done ---")
message("All MORR vignette data saved to inst/testdata/")
message("Files:")
for (f in list.files("inst/testdata", pattern = "\\.rds$")) {
  sz <- file.size(file.path("inst/testdata", f))
  message(sprintf("  %-40s %s", f, format(sz, big.mark = ",")))
}
