# data-raw/vignette_morr.R
#
# Generate vignette data for Morice (MORR) watershed group.
# Runs against a PostgreSQL database with bcfishpass/fwapg.
# Saves intermediate .rds snapshots to inst/testdata/ for the
# vignette to load (vignette never hits the DB).
#
# Run interactively:
#   source("data-raw/vignette_morr.R")

library(DBI)
library(RPostgres)
library(link)

conn <- lnk_db_conn()

wsg <- "MORR"

# --- 1. Extract raw modelled crossings for MORR ---

morr_crossings_raw <- DBI::dbGetQuery(conn, paste0("
  SELECT
    modelled_crossing_id,
    stream_crossing_id,
    crossing_source,
    pscis_status,
    crossing_type_code,
    crossing_subtype_code,
    barrier_status,
    blue_line_key,
    downstream_route_measure,
    watershed_group_code
  FROM bcfishpass.crossings
  WHERE watershed_group_code = '", wsg, "'
  AND crossing_source = 'MODELLED'
  ORDER BY modelled_crossing_id
"))

saveRDS(morr_crossings_raw,
        "inst/testdata/morr_crossings_raw.rds")
message("Raw crossings: ", nrow(morr_crossings_raw))

# --- 2. Load and apply modelled crossing overrides ---

# Filter bcfishpass override CSV to MORR
fixes_all <- read.csv(
  "~/Projects/repo/bcfishpass/data/user_modelled_crossing_fixes.csv",
  stringsAsFactors = FALSE
)
fixes_morr <- fixes_all[fixes_all$watershed_group_code == wsg, ]
morr_fixes_path <- tempfile(fileext = ".csv")
write.csv(fixes_morr, morr_fixes_path, row.names = FALSE)
message("MORR modelled crossing fixes: ", nrow(fixes_morr))

# Load to DB
DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.morr_crossings")
DBI::dbWriteTable(conn,
                  DBI::Id(schema = "working", table = "morr_crossings"),
                  morr_crossings_raw)

lnk_override_load(conn,
                   csv = morr_fixes_path,
                   to = "working.morr_modelled_fixes",
                   cols_id = "modelled_crossing_id",
                   cols_required = c("structure"),
                   cols_provenance = c("reviewer_name", "review_date", "source"))

morr_overrides_validation <- lnk_override_validate(conn,
  overrides = "working.morr_modelled_fixes",
  crossings = "working.morr_crossings",
  col_id = "modelled_crossing_id")

# The override CSV uses "structure" column — map to crossing_type_code
# for bcfishpass compatibility. NONE = no structure, OBS = open bottom
lnk_override_apply(conn,
  crossings = "working.morr_crossings",
  overrides = "working.morr_modelled_fixes",
  col_id = "modelled_crossing_id",
  cols_update = NULL)  # auto-detect overlapping columns

morr_crossings_overrides <- DBI::dbGetQuery(conn,
  "SELECT * FROM working.morr_crossings ORDER BY modelled_crossing_id")

saveRDS(morr_crossings_overrides,
        "inst/testdata/morr_crossings_overrides.rds")
saveRDS(morr_overrides_validation,
        "inst/testdata/morr_overrides_validation.rds")
saveRDS(fixes_morr,
        "inst/testdata/morr_modelled_fixes.rds")
message("After overrides: ", nrow(morr_crossings_overrides))

# --- 3. Match PSCIS to modelled crossings ---

# Load the xref CSV filtered to MORR
xref_all <- read.csv(
  "~/Projects/repo/bcfishpass/data/pscis_modelledcrossings_streams_xref.csv",
  stringsAsFactors = FALSE
)
xref_morr <- xref_all[xref_all$watershed_group_code == wsg, ]
xref_path <- tempfile(fileext = ".csv")
write.csv(xref_morr, xref_path, row.names = FALSE)
message("MORR xref corrections: ", nrow(xref_morr))

# Get PSCIS assessments for MORR
morr_pscis <- DBI::dbGetQuery(conn, paste0("
  SELECT
    stream_crossing_id,
    assessment_date,
    crossing_type_code,
    crossing_subtype_code,
    barrier_result_code,
    outlet_drop,
    outlet_pool_depth,
    culvert_slope_percent,
    culvert_length_m,
    downstream_channel_width,
    blue_line_key,
    downstream_route_measure
  FROM whse_fish.pscis_assessment_svw
  WHERE watershed_group_code = '", wsg, "'
  ORDER BY stream_crossing_id
"))

# Write PSCIS to working table for matching
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.morr_pscis")
DBI::dbWriteTable(conn,
                  DBI::Id(schema = "working", table = "morr_pscis"),
                  morr_pscis)

lnk_match_pscis(conn,
  crossings = "working.morr_crossings",
  pscis = "working.morr_pscis",
  xref_csv = xref_path,
  to = "working.morr_matched")

morr_matched <- DBI::dbGetQuery(conn,
  "SELECT * FROM working.morr_matched ORDER BY id_a")
saveRDS(morr_matched, "inst/testdata/morr_matched.rds")
saveRDS(morr_pscis, "inst/testdata/morr_pscis.rds")
saveRDS(xref_morr, "inst/testdata/morr_xref.rds")
message("PSCIS matches: ", nrow(morr_matched))

# --- 4. Apply PSCIS barrier status overrides ---

pscis_status_all <- read.csv(
  "~/Projects/repo/bcfishpass/data/user_pscis_barrier_status.csv",
  stringsAsFactors = FALSE
)
pscis_status_morr <- pscis_status_all[
  pscis_status_all$watershed_group_code == wsg, ]

if (nrow(pscis_status_morr) > 0) {
  pscis_status_path <- tempfile(fileext = ".csv")
  write.csv(pscis_status_morr, pscis_status_path, row.names = FALSE)

  lnk_override_load(conn,
    csv = pscis_status_path,
    to = "working.morr_pscis_status_fixes",
    cols_id = "stream_crossing_id",
    cols_provenance = c("reviewer_name", "review_date"))

  # Apply to PSCIS table
  lnk_override_apply(conn,
    crossings = "working.morr_pscis",
    overrides = "working.morr_pscis_status_fixes",
    col_id = "stream_crossing_id",
    cols_update = c("barrier_result_code"),
    cols_provenance = NULL)
}

saveRDS(pscis_status_morr,
        "inst/testdata/morr_pscis_status_fixes.rds")

# --- 5. Score severity ---

# Add measurement columns to crossings from matched PSCIS data
# (join PSCIS measurements onto modelled crossings via match table)
DBI::dbExecute(conn, "
  ALTER TABLE working.morr_crossings
    ADD COLUMN IF NOT EXISTS outlet_drop numeric,
    ADD COLUMN IF NOT EXISTS culvert_slope numeric,
    ADD COLUMN IF NOT EXISTS culvert_length_m numeric,
    ADD COLUMN IF NOT EXISTS downstream_channel_width numeric
")

DBI::dbExecute(conn, "
  UPDATE working.morr_crossings c
  SET outlet_drop = p.outlet_drop,
      culvert_slope = p.culvert_slope_percent / 100.0,
      culvert_length_m = p.culvert_length_m,
      downstream_channel_width = p.downstream_channel_width
  FROM working.morr_matched m
  JOIN working.morr_pscis p ON m.id_a::integer = p.stream_crossing_id
  WHERE c.modelled_crossing_id::text = m.id_b
")

lnk_score_severity(conn, "working.morr_crossings")

morr_crossings_scored <- DBI::dbGetQuery(conn,
  "SELECT * FROM working.morr_crossings ORDER BY modelled_crossing_id")
saveRDS(morr_crossings_scored,
        "inst/testdata/morr_crossings_scored.rds")

# Severity distribution
morr_severity_dist <- DBI::dbGetQuery(conn, "
  SELECT severity, count(*) AS n
  FROM working.morr_crossings
  GROUP BY severity
  ORDER BY CASE severity
    WHEN 'high' THEN 1 WHEN 'moderate' THEN 2 ELSE 3 END
")
saveRDS(morr_severity_dist,
        "inst/testdata/morr_severity_dist.rds")
message("Severity distribution:")
print(morr_severity_dist)

# --- 6. Break source for fresh ---

morr_break_spec <- lnk_break_source(conn, "working.morr_crossings")
saveRDS(morr_break_spec,
        "inst/testdata/morr_break_source.rds")
message("Break source spec ready for frs_habitat()")

# --- Cleanup ---
DBI::dbDisconnect(conn)
unlink(c(morr_fixes_path, xref_path))
if (exists("pscis_status_path")) unlink(pscis_status_path)

message("\nAll MORR vignette data saved to inst/testdata/")
message("Files:")
message("  morr_crossings_raw.rds")
message("  morr_crossings_overrides.rds")
message("  morr_overrides_validation.rds")
message("  morr_modelled_fixes.rds")
message("  morr_crossings_scored.rds")
message("  morr_severity_dist.rds")
message("  morr_matched.rds")
message("  morr_pscis.rds")
message("  morr_xref.rds")
message("  morr_pscis_status_fixes.rds")
message("  morr_break_source.rds")
