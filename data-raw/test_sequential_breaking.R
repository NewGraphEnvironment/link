# data-raw/test_sequential_breaking.R
#
# Test: sequential breaking with manual id_segment management.
# Matches bcfishpass break_streams() pipeline exactly:
#   1. observations
#   2. barriers_bt (gradient 25/30 + falls, filtered by obs/habitat)
#   3. barriers_ch_cm_co_pk_sk (gradient 15/20/25/30 + falls, filtered)
#   4. user_habitat_classification_endpoints
#   5. crossings
#
# Requirements:
#   - Local Docker fwapg on port 5432
#   - SSH tunnel to bcfishpass on port 63333
#   - bcfishobs.observations loaded
#   - fresh (>= 0.13.2)

wsg <- "ADMS"
bcfishpass_data <- "~/Projects/repo/bcfishpass/data"

# ===========================================================================
# Connect
# ===========================================================================
conn <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 5432, dbname = "fwapg",
  user = "postgres", password = "postgres")
conn_ref <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 63333, dbname = "bcfishpass", user = "newgraph")
DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")

# ===========================================================================
# Step 1: Load base segments — matching bcfishpass load_streams.sql filters
# ===========================================================================
message("\n=== Step 1: Load base segments ===")
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.streams CASCADE")
DBI::dbExecute(conn, sprintf("
  CREATE TABLE working.streams AS
  SELECT *
  FROM whse_basemapping.fwa_stream_networks_sp
  WHERE watershed_group_code = '%s'
    AND localcode_ltree IS NOT NULL
    AND edge_type != 6010
    AND wscode_ltree <@ '999'::ltree IS FALSE
    AND linear_feature_id NOT IN (832498864, 832474945)", wsg))

n_base <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.streams")[[1]]
message("  Base segments: ", n_base)

n_ref <- DBI::dbGetQuery(conn_ref, sprintf(
  "SELECT count(*) FROM bcfishpass.streams WHERE watershed_group_code = '%s'", wsg))[[1]]
message("  bcfishpass segments: ", n_ref)

# ===========================================================================
# Step 2: GENERATED columns + unique id_segment
# ===========================================================================
message("\n=== Step 2: GENERATED columns + id_segment ===")
fresh::frs_col_generate(conn, "working.streams")

DBI::dbExecute(conn, "ALTER TABLE working.streams ADD COLUMN id_segment integer")
DBI::dbExecute(conn, "
  WITH numbered AS (
    SELECT ctid, row_number() OVER (ORDER BY blue_line_key, downstream_route_measure) AS rn
    FROM working.streams
  )
  UPDATE working.streams s SET id_segment = numbered.rn
  FROM numbered WHERE s.ctid = numbered.ctid")
DBI::dbExecute(conn, "CREATE UNIQUE INDEX ON working.streams (id_segment)")
message("  id_segment unique: ", DBI::dbGetQuery(conn,
  "SELECT count(DISTINCT id_segment) = count(*) FROM working.streams")[[1]])

# ===========================================================================
# Step 3: Gradient barriers (8 classes, same as bcfishpass)
# ===========================================================================
message("\n=== Step 3: Gradient barriers ===")
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.streams_blk")
DBI::dbExecute(conn, sprintf("
  CREATE TABLE working.streams_blk AS
  SELECT DISTINCT blue_line_key FROM whse_basemapping.fwa_stream_networks_sp
  WHERE watershed_group_code = '%s' AND edge_type != 6010", wsg))

fresh::frs_break_find(conn, "working.streams_blk",
  attribute = "gradient",
  classes = c("500" = 0.05, "700" = 0.07, "1000" = 0.10, "1200" = 0.12,
              "1500" = 0.15, "2000" = 0.20, "2500" = 0.25, "3000" = 0.30),
  to = "working.gradient_barriers")

# Enrich with ltree for fwa_upstream joins
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.gradient_barriers_enriched")
DBI::dbExecute(conn, "
  CREATE TABLE working.gradient_barriers_enriched AS
  SELECT g.blue_line_key, g.downstream_route_measure,
    'GRADIENT_' || lpad(g.gradient_class::text, 4, '0') AS barrier_type,
    s.wscode_ltree, s.localcode_ltree
  FROM working.gradient_barriers g
  JOIN whse_basemapping.fwa_stream_networks_sp s
    ON g.blue_line_key = s.blue_line_key
    AND g.downstream_route_measure >= s.downstream_route_measure
    AND g.downstream_route_measure < s.upstream_route_measure")
DBI::dbExecute(conn, "CREATE INDEX ON working.gradient_barriers_enriched (blue_line_key)")
DBI::dbExecute(conn, "CREATE INDEX ON working.gradient_barriers_enriched USING gist (wscode_ltree)")
DBI::dbExecute(conn, "CREATE INDEX ON working.gradient_barriers_enriched USING btree (wscode_ltree)")
DBI::dbExecute(conn, "CREATE INDEX ON working.gradient_barriers_enriched USING gist (localcode_ltree)")
DBI::dbExecute(conn, "CREATE INDEX ON working.gradient_barriers_enriched USING btree (localcode_ltree)")

n_grad <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.gradient_barriers_enriched")[[1]]
message("  Gradient barriers (enriched): ", n_grad)

# ===========================================================================
# Step 4: Falls
# ===========================================================================
message("\n=== Step 4: Falls ===")
falls_all <- read.csv(system.file("extdata", "falls.csv", package = "fresh"),
  stringsAsFactors = FALSE)
falls <- falls_all[falls_all$watershed_group_code == wsg & falls_all$barrier_ind == TRUE, ]
DBI::dbWriteTable(conn, DBI::Id(schema = "working", table = "falls"),
  falls, overwrite = TRUE)

# Enrich falls with ltree
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.falls_enriched")
DBI::dbExecute(conn, "
  CREATE TABLE working.falls_enriched AS
  SELECT f.blue_line_key, f.downstream_route_measure,
    'FALLS' AS barrier_type,
    s.wscode_ltree, s.localcode_ltree
  FROM working.falls f
  JOIN whse_basemapping.fwa_stream_networks_sp s
    ON f.blue_line_key = s.blue_line_key
    AND f.downstream_route_measure >= s.downstream_route_measure
    AND f.downstream_route_measure < s.upstream_route_measure")
message("  Falls: ", nrow(falls))

# ===========================================================================
# Step 5: Build FILTERED per-model barrier tables (matching bcfishpass)
# ===========================================================================
message("\n=== Step 5: Per-model barrier tables (filtered) ===")

# --- Helper: remove non-minimal barriers ---
# bcfishpass keeps only the most-downstream barrier on each path.
# A barrier is "non-minimal" if another barrier in the same table is
# downstream of it. Delete non-minimal barriers using fwa_upstream self-join.
remove_non_minimal <- function(conn, table) {
  n_before <- DBI::dbGetQuery(conn, sprintf("SELECT count(*) FROM %s", table))[[1]]
  # Delete barrier A if there exists barrier B downstream of A (A upstream of B)
  DBI::dbExecute(conn, sprintf("
    DELETE FROM %s a
    WHERE EXISTS (
      SELECT 1 FROM %s b
      WHERE b.ctid != a.ctid
        AND fwa_upstream(
          b.blue_line_key, b.downstream_route_measure,
          b.wscode_ltree, b.localcode_ltree,
          a.blue_line_key, a.downstream_route_measure,
          a.wscode_ltree, a.localcode_ltree,
          false, 1)
    )", table, table))
  n_after <- DBI::dbGetQuery(conn, sprintf("SELECT count(*) FROM %s", table))[[1]]
  message("    Removed ", n_before - n_after, " non-minimal (", n_before, " -> ", n_after, ")")
}

# --- barriers_bt: gradient 25/30 + falls + subsurface, obs-filtered, minimal ---
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.barriers_bt")
DBI::dbExecute(conn, "
  CREATE TABLE working.barriers_bt AS
  WITH barriers AS (
    SELECT blue_line_key, downstream_route_measure, barrier_type,
           wscode_ltree, localcode_ltree
    FROM working.gradient_barriers_enriched
    WHERE barrier_type IN ('GRADIENT_2500', 'GRADIENT_3000')
    UNION ALL
    SELECT blue_line_key, downstream_route_measure, barrier_type,
           wscode_ltree, localcode_ltree
    FROM working.falls_enriched
  ),
  obs_upstr_n AS (
    SELECT b.blue_line_key AS b_blk, b.downstream_route_measure AS b_drm,
           count(o.observation_key) AS n_obs
    FROM barriers b
    INNER JOIN bcfishobs.observations o
      ON fwa_upstream(
        b.blue_line_key, b.downstream_route_measure,
        b.wscode_ltree, b.localcode_ltree,
        o.blue_line_key, o.downstream_route_measure,
        o.wscode, o.localcode,
        false, 20)
    WHERE o.species_code IN ('BT','CH','CM','CO','PK','SK','ST')
    GROUP BY b.blue_line_key, b.downstream_route_measure
  )
  SELECT b.blue_line_key, b.downstream_route_measure,
         b.wscode_ltree, b.localcode_ltree
  FROM barriers b
  LEFT JOIN obs_upstr_n o
    ON b.blue_line_key = o.b_blk
    AND b.downstream_route_measure = o.b_drm
  WHERE (o.n_obs IS NULL OR o.n_obs < 1)")
DBI::dbExecute(conn, "CREATE INDEX ON working.barriers_bt (blue_line_key)")
DBI::dbExecute(conn, "CREATE INDEX ON working.barriers_bt USING gist (wscode_ltree)")
DBI::dbExecute(conn, "CREATE INDEX ON working.barriers_bt USING btree (wscode_ltree)")
DBI::dbExecute(conn, "CREATE INDEX ON working.barriers_bt USING gist (localcode_ltree)")
DBI::dbExecute(conn, "CREATE INDEX ON working.barriers_bt USING btree (localcode_ltree)")
n_bt_pre <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.barriers_bt")[[1]]
message("  barriers_bt (before minimal): ", n_bt_pre)
remove_non_minimal(conn, "working.barriers_bt")
n_bt <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.barriers_bt")[[1]]
message("  barriers_bt (minimal): ", n_bt, "  (bcfishpass: 1250)")

# --- barriers_ch_cm_co_pk_sk: gradient 15/20/25/30 + falls, >=5 post-1990, minimal ---
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.barriers_ch_cm_co_pk_sk")
DBI::dbExecute(conn, "
  CREATE TABLE working.barriers_ch_cm_co_pk_sk AS
  WITH barriers AS (
    SELECT blue_line_key, downstream_route_measure, barrier_type,
           wscode_ltree, localcode_ltree
    FROM working.gradient_barriers_enriched
    WHERE barrier_type IN ('GRADIENT_1500', 'GRADIENT_2000', 'GRADIENT_2500', 'GRADIENT_3000')
    UNION ALL
    SELECT blue_line_key, downstream_route_measure, barrier_type,
           wscode_ltree, localcode_ltree
    FROM working.falls_enriched
  ),
  obs_upstr_n AS (
    SELECT b.blue_line_key AS b_blk, b.downstream_route_measure AS b_drm,
           count(o.observation_key) AS n_obs
    FROM barriers b
    INNER JOIN bcfishobs.observations o
      ON fwa_upstream(
        b.blue_line_key, b.downstream_route_measure,
        b.wscode_ltree, b.localcode_ltree,
        o.blue_line_key, o.downstream_route_measure,
        o.wscode, o.localcode,
        false, 20)
    WHERE o.species_code IN ('CH','CM','CO','PK','SK')
      AND o.observation_date > '1990-01-01'::date
    GROUP BY b.blue_line_key, b.downstream_route_measure
  )
  SELECT b.blue_line_key, b.downstream_route_measure,
         b.wscode_ltree, b.localcode_ltree
  FROM barriers b
  LEFT JOIN obs_upstr_n o
    ON b.blue_line_key = o.b_blk
    AND b.downstream_route_measure = o.b_drm
  WHERE (o.n_obs IS NULL OR o.n_obs < 5)")
DBI::dbExecute(conn, "CREATE INDEX ON working.barriers_ch_cm_co_pk_sk (blue_line_key)")
DBI::dbExecute(conn, "CREATE INDEX ON working.barriers_ch_cm_co_pk_sk USING gist (wscode_ltree)")
DBI::dbExecute(conn, "CREATE INDEX ON working.barriers_ch_cm_co_pk_sk USING btree (wscode_ltree)")
DBI::dbExecute(conn, "CREATE INDEX ON working.barriers_ch_cm_co_pk_sk USING gist (localcode_ltree)")
DBI::dbExecute(conn, "CREATE INDEX ON working.barriers_ch_cm_co_pk_sk USING btree (localcode_ltree)")
n_sal_pre <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.barriers_ch_cm_co_pk_sk")[[1]]
message("  barriers_ch_cm_co_pk_sk (before minimal): ", n_sal_pre)
remove_non_minimal(conn, "working.barriers_ch_cm_co_pk_sk")
n_sal <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.barriers_ch_cm_co_pk_sk")[[1]]
message("  barriers_ch_cm_co_pk_sk (minimal): ", n_sal)

# --- Observations as break source ---
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.observations_breaks")
DBI::dbExecute(conn, sprintf("
  CREATE TABLE working.observations_breaks AS
  SELECT DISTINCT blue_line_key, round(downstream_route_measure) AS downstream_route_measure
  FROM bcfishobs.observations
  WHERE watershed_group_code = '%s'", wsg))
n_obs <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.observations_breaks")[[1]]
message("  Observations: ", n_obs)

# --- Habitat endpoints ---
# Load user_habitat_classification
link::lnk_load(conn,
  csv = file.path(bcfishpass_data, "user_habitat_classification.csv"),
  to = "working.user_habitat_classification",
  cols_id = "blue_line_key",
  cols_required = c("species_code", "upstream_route_measure", "habitat_ind"))
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.habitat_endpoints")
DBI::dbExecute(conn, sprintf("
  CREATE TABLE working.habitat_endpoints AS
  SELECT DISTINCT blue_line_key, round(upstream_route_measure) AS downstream_route_measure
  FROM working.user_habitat_classification
  WHERE watershed_group_code = '%s'", wsg))
n_hab <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.habitat_endpoints")[[1]]
message("  Habitat endpoints: ", n_hab, "  (bcfishpass: 145)")

# --- Crossings ---
crossings_all <- read.csv(system.file("extdata", "crossings.csv", package = "fresh"),
  stringsAsFactors = FALSE)
crossings <- crossings_all[crossings_all$watershed_group_code == wsg, ]
crossings$aggregated_crossings_id <- as.character(crossings$aggregated_crossings_id)
DBI::dbWriteTable(conn, DBI::Id(schema = "working", table = "crossings"),
  crossings, overwrite = TRUE)
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.crossings_breaks")
DBI::dbExecute(conn, "
  CREATE TABLE working.crossings_breaks AS
  SELECT blue_line_key, round(downstream_route_measure) AS downstream_route_measure
  FROM working.crossings")
n_cross <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.crossings_breaks")[[1]]
message("  Crossings: ", n_cross)

# ===========================================================================
# Helper: reassign unique id_segment after each break round
# ===========================================================================
reassign_id <- function(conn) {
  DBI::dbExecute(conn, "DROP INDEX IF EXISTS working.streams_id_segment_idx")
  DBI::dbExecute(conn, "
    WITH numbered AS (
      SELECT ctid, row_number() OVER (ORDER BY blue_line_key, downstream_route_measure) AS rn
      FROM working.streams
    )
    UPDATE working.streams s SET id_segment = numbered.rn
    FROM numbered WHERE s.ctid = numbered.ctid")
  DBI::dbExecute(conn, "CREATE UNIQUE INDEX streams_id_segment_idx ON working.streams (id_segment)")
}

# ===========================================================================
# Step 6: Sequential breaking — bcfishpass order
# ===========================================================================
message("\n=== Step 6: Sequential breaking ===")

break_sources <- list(
  list(name = "observations",            table = "working.observations_breaks"),
  list(name = "barriers_bt",             table = "working.barriers_bt"),
  list(name = "barriers_ch_cm_co_pk_sk", table = "working.barriers_ch_cm_co_pk_sk"),
  list(name = "habitat_endpoints",       table = "working.habitat_endpoints"),
  list(name = "crossings",               table = "working.crossings_breaks")
)

for (src in break_sources) {
  n_before <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.streams")[[1]]

  # Diagnostic: how many breaks would the 1m guard allow?
  n_would_break <- DBI::dbGetQuery(conn, sprintf("
    WITH breakpoints AS (
      SELECT DISTINCT blue_line_key,
        round(downstream_route_measure::numeric, 0) AS downstream_route_measure
      FROM %s
    ),
    to_break AS (
      SELECT s.id_segment AS seg_id, b.downstream_route_measure AS meas_event
      FROM working.streams s
      INNER JOIN breakpoints b ON s.blue_line_key = b.blue_line_key
        AND (b.downstream_route_measure - s.downstream_route_measure) > 1
        AND (s.upstream_route_measure - b.downstream_route_measure) > 1
    )
    SELECT count(*) FROM to_break", src$table))[[1]]
  message(sprintf("  %-30s: %s breaks would apply (1m guard)", src$name, n_would_break))

  fresh::frs_break_apply(conn,
    table = "working.streams",
    breaks = src$table,
    segment_id = "id_segment",
    measure_precision = 0L)

  n_after <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.streams")[[1]]
  n_new <- n_after - n_before

  message(sprintf("  After %-30s: %s segments (+%s new)", src$name, n_after, n_new))

  # Reassign unique id_segment for next round
  reassign_id(conn)
}

# ===========================================================================
# Step 7: Compare segment counts
# ===========================================================================
message("\n=== Step 7: Compare ===")
n_final <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.streams")[[1]]
message("  Our segments:        ", n_final)
message("  bcfishpass segments: ", n_ref)
message("  Difference:          ", n_final - n_ref,
  " (", round(100 * (n_final - n_ref) / n_ref, 1), "%)")

our_km <- DBI::dbGetQuery(conn, "SELECT round(sum(length_metre)::numeric / 1000, 2) FROM working.streams")[[1]]
ref_km <- DBI::dbGetQuery(conn_ref, sprintf("
  SELECT round(sum(length_metre)::numeric / 1000, 2) FROM bcfishpass.streams
  WHERE watershed_group_code = '%s'", wsg))[[1]]
message("  Our total km:        ", our_km)
message("  bcfishpass total km: ", ref_km)

DBI::dbDisconnect(conn_ref)
DBI::dbDisconnect(conn)
message("\nDone.")
