# Experiment: extra network breaks at per-species spawn / rear gradient
# ceilings, on top of the existing access-driven break network.
#
# Hypothesis: locally-steep "ceiling" sub-segments (the steep bits inside
# generally-flat reaches) get broken out of their parent segment, and
# their stand-alone gradient may flip per-segment classification when
# the rules / fresh predicates depend on it. Spawn ceilings are tighter
# than rear, so spawn is more sensitive.
#
# Compares against the default-bundle ADMS rollup from the 2026-05-03
# provincial run (data-raw/logs/provincial_default/ADMS.rds).
#
# Run: Rscript data-raw/exp_gradient_extra_breaks.R

suppressPackageStartupMessages({
  library(link); library(fresh); library(dplyr); library(DBI); library(RPostgres)
})
setwd("/Users/airvine/Projects/repo/link/data-raw")

WSG <- "ADMS"
EXP_SCHEMA <- "fresh_default_extrabreaks"
schema <- paste0("working_", tolower(WSG))

# --- Connections (mirrors compare_bcfishpass_wsg.R exactly) -----------------
conn <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 5432, dbname = "fwapg",
  user = "postgres", password = "postgres")
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

tunnel_pass <- Sys.getenv("PG_PASS_SHARE", "")
conn_ref <- if (nzchar(tunnel_pass)) {
  DBI::dbConnect(RPostgres::Postgres(),
    host = "localhost", port = 63333, dbname = "bcfishpass",
    user = Sys.getenv("PG_USER_SHARE", "newgraph"),
    password = tunnel_pass)
} else {
  message("PG_PASS_SHARE not set — running without dams pull from bcfp tunnel")
  NULL
}
if (!is.null(conn_ref)) {
  on.exit(try(DBI::dbDisconnect(conn_ref), silent = TRUE), add = TRUE)
}

# --- Per-species spawn / rear gradient ceilings (the experimental knob) -----
thresholds_csv <- system.file("extdata", "parameters_habitat_thresholds.csv",
                              package = "fresh")
thr <- utils::read.csv(thresholds_csv, stringsAsFactors = FALSE)
extra_thresholds <- sort(unique(c(thr$spawn_gradient_max, thr$rear_gradient_max)))
extra_thresholds <- extra_thresholds[!is.na(extra_thresholds) & extra_thresholds > 0]
extra_classes <- setNames(extra_thresholds,
                          sprintf("%04d", round(extra_thresholds * 10000)))
cat("Extra breaks at:\n")
print(extra_classes)

# --- Default config + experimental persist schema --------------------------
cfg <- lnk_config("default")
cfg$pipeline$schema <- EXP_SCHEMA
loaded <- lnk_load_overrides(cfg)

cat("\n=== Run start ", format(Sys.time(), "%H:%M:%S"), " ===\n", sep = "")
t0 <- Sys.time()

# Defensive reset of per-WSG staging.
DBI::dbExecute(conn, sprintf(
  "DROP TABLE IF EXISTS %1$s.streams, %1$s.streams_habitat,
   %1$s.streams_breaks CASCADE", schema))

# Standard pipeline through break.
link::lnk_pipeline_setup(conn, schema, overwrite = TRUE)
link::lnk_pipeline_load(conn, aoi = WSG, cfg = cfg, loaded = loaded,
                        schema = schema)
link::lnk_pipeline_prepare(conn, aoi = WSG, cfg = cfg, loaded = loaded,
                           schema = schema, conn_tunnel = conn_ref)
link::lnk_pipeline_break(conn, aoi = WSG, cfg = cfg, loaded = loaded,
                         schema = schema)

# --- Extra breaks: detect spawn/rear-ceiling positions, apply as breaks ----
# These split segments without becoming access barriers (no entry in
# streams_breaks). Pure segmentation refinement.
extra_tbl <- paste0(schema, ".gradient_barriers_extra")
fresh::frs_break_find(conn,
                      paste0(schema, ".streams_blk"),
                      attribute = "gradient",
                      classes = extra_classes,
                      to = extra_tbl)
n_extra <- as.numeric(DBI::dbGetQuery(conn,
  sprintf("SELECT count(*)::int AS n FROM %s", extra_tbl))$n)
cat(sprintf("\nExtra-break positions detected: %.0f\n", n_extra))

n_segs_pre <- as.numeric(DBI::dbGetQuery(conn,
  sprintf("SELECT count(*)::int AS n FROM %s.streams", schema))$n)

fresh::frs_break_apply(conn,
                       table = paste0(schema, ".streams"),
                       breaks = extra_tbl,
                       segment_id = "id_segment",
                       measure_precision = 0L)

# Re-assign id_segment so downstream phases see contiguous IDs.
link:::.lnk_pipeline_break_reassign_id(conn, schema)

n_segs_post <- as.numeric(DBI::dbGetQuery(conn,
  sprintf("SELECT count(*)::int AS n FROM %s.streams", schema))$n)
cat(sprintf("Segment count: pre=%.0f  post=%.0f  delta=%+.0f\n",
            n_segs_pre, n_segs_post, n_segs_post - n_segs_pre))

# --- Continue pipeline -----------------------------------------------------
link::lnk_pipeline_classify(conn, aoi = WSG, cfg = cfg, loaded = loaded,
                            schema = schema)
link::lnk_pipeline_connect(conn, aoi = WSG, cfg = cfg, loaded = loaded,
                           schema = schema)

active <- link::lnk_pipeline_species(cfg, loaded, WSG)
link::lnk_persist_init(conn, cfg, species = active)
link::lnk_pipeline_persist(conn, aoi = WSG, cfg = cfg,
                           species = active, schema = schema)

# --- Rollup (link-side only — same shape as compare_bcfishpass_wsg) --------
species_sql <- paste(
  vapply(active,
    function(s) as.character(DBI::dbQuoteLiteral(conn, s)),
    character(1)),
  collapse = ", ")
et_stream_sql  <- "(1000, 1050, 1100, 1150, 2000, 2100, 2300)"
et_lake_sql    <- "(1500, 1525)"
et_wetland_sql <- "(1700)"

ours_km <- DBI::dbGetQuery(conn, sprintf("
  SELECT h.species_code,
    round(SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric / 1000, 2) AS spawning_km,
    round(SUM(CASE WHEN h.rearing  THEN s.length_metre ELSE 0 END)::numeric / 1000, 2) AS rearing_km,
    round(SUM(CASE WHEN h.rearing AND s.edge_type IN %s THEN s.length_metre ELSE 0 END)::numeric / 1000, 2) AS rearing_stream_km,
    round(SUM(CASE WHEN h.rearing AND s.edge_type IN %s THEN s.length_metre ELSE 0 END)::numeric / 1000, 2) AS rearing_lake_centerline_km,
    round(SUM(CASE WHEN h.rearing AND s.edge_type IN %s THEN s.length_metre ELSE 0 END)::numeric / 1000, 2) AS rearing_wetland_centerline_km
  FROM %s.streams s JOIN %s.streams_habitat h
    ON s.id_segment = h.id_segment
   AND s.watershed_group_code = h.watershed_group_code
  WHERE h.species_code IN (%s) AND h.accessible
  GROUP BY h.species_code",
  et_stream_sql, et_lake_sql, et_wetland_sql,
  schema, schema, species_sql))

elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat("\n=== Done in ", round(elapsed, 1), "s ===\n", sep = "")

ts <- format(Sys.time(), "%Y%m%d_%H%M")
out_rds <- sprintf("logs/%s_ADMS_extrabreaks.rds", ts)
saveRDS(list(rollup_km = ours_km,
             extra_classes = extra_classes,
             n_segs_pre = n_segs_pre,
             n_segs_post = n_segs_post,
             extra_break_positions = n_extra),
        out_rds)
cat("Saved:", out_rds, "\n")

cat("\n--- Experiment rollup (default + extra breaks) ---\n")
print(ours_km)

# --- Compare to default-bundle baseline ------------------------------------
baseline <- readRDS("logs/provincial_default/ADMS.rds")

# Reshape baseline (long: wsg/species/habitat_type/unit/link_value) to a
# species-wise wide view matching ours_km columns where they overlap.
base_wide <- reshape(
  baseline[baseline$unit == "km", c("species", "habitat_type", "link_value")],
  idvar = "species", timevar = "habitat_type", direction = "wide")
names(base_wide) <- sub("^link_value\\.", "", names(base_wide))

cat("\n--- Default-bundle baseline (km only) ---\n")
print(base_wide)

cat("\n--- Side-by-side (km) ---\n")
sbs <- merge(
  ours_km[, c("species_code", "spawning_km", "rearing_km")],
  base_wide[, c("species", "spawning", "rearing")],
  by.x = "species_code", by.y = "species", all = TRUE)
names(sbs) <- c("sp", "spawn_extra", "rear_extra", "spawn_default", "rear_default")
sbs$spawn_d <- round(sbs$spawn_extra - sbs$spawn_default, 2)
sbs$rear_d  <- round(sbs$rear_extra  - sbs$rear_default,  2)
print(sbs[, c("sp", "spawn_default", "spawn_extra", "spawn_d",
              "rear_default", "rear_extra", "rear_d")])
