#!/bin/bash
# data-raw/snapshot_bcfp.sh
#
# Manual snapshot of bcfp dependencies into a local Postgres (fwapg) so
# lnk_pipeline_crossings() (link#138) and parity comparisons can run
# without a tunnel. Pulls only from public sources -- no SSH, no DB
# pg_dump, no AWS auth.
#
# Loads (in order):
#   1. BCDC PSCIS via Python `bcdata bc2pg` -> whse_fish.pscis_*
#   2. CABD dams via ogr2ogr (GeoJSON API) -> cabd.dams
#   3. bchamp modelled crossings (gpkg.zip) -> fresh.modelled_stream_crossings
#   4. bchamp observations (parquet) -> bcfishobs.observations
#      (matches bcfp's jobs/load_observations -- the canonical source)
#   5. (--with-bcfp-views) Simon's bcfp output views from s3://newgraph
#      -> fresh.crossings_bcfp / fresh.streams_bcfp (parity comparison)
#   6. Stamp data-raw/logs/bcfp_baselines.csv with the bcfp build identifier
#      from s3://fresh-bc/bcfishpass/log.json (link#117 ledger).
#
# Prereqs:
#   - Local Postgres with PostGIS. Connection via PG* env vars or ~/.pgpass.
#   - Python `bcdata` CLI (`uv tool install bcdata==0.16.0.post1`).
#   - GDAL `ogr2ogr` with Parquet driver (macOS: Homebrew GDAL;
#     Ubuntu/cypher: conda-forge GDAL via micromamba).
#   - `curl`, `unzip`.
#   - `aws` CLI (only for --with-bcfp-views).
#   - R with link package installed (for the baseline-stamp step).
#
# Install paths by host:
#   M4/m1: kdot install_geo.sh (Homebrew GDAL + uv + bcdata)
#   cypher: rtj cloud-init (micromamba conda-forge GDAL + uv + bcdata)
#
# Required env (or pgpass):
#   PGUSER, PGPASSWORD, PGHOST, PGPORT, PGDATABASE
#   OR a single DATABASE_URL (postgres://user:pass@host:port/dbname)
#
# Usage:
#   bash data-raw/snapshot_bcfp.sh                     # primitives only
#   bash data-raw/snapshot_bcfp.sh --with-bcfp-views   # + comparison views
#
# Runtime: ~5 min for primitives; +2-3 min with --with-bcfp-views.

# Note: `set -x` (xtrace) is intentionally OFF. The script sources
# `~/.config/snapshot-bcfp.env` which may carry DB credentials, and the
# launchd / cron path writes stderr to log files on disk. xtrace would
# echo `+ PGPASSWORD=...` and `+ DATABASE_URL=postgresql://user:pass@...`
# into those logs. Keep -e -u -o pipefail; rely on explicit echos for
# diagnostics.
set -euo pipefail

# Anchor cwd at the repo root so the default ledger path
# `data-raw/logs/bcfp_baselines.csv` resolves correctly regardless of
# how the script was invoked. cron jobs default to $HOME; without this
# the skip-guard returns FALSE and the stamp-write lands at
# $HOME/data-raw/logs/... -- silently bypassing the real ledger.
cd "$(dirname "$0")/.."

WITH_BCFP_VIEWS=0
for arg in "$@"; do
  case "$arg" in
    --with-bcfp-views) WITH_BCFP_VIEWS=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

# -----------------------------------------
# Fail-fast prereq checks
# -----------------------------------------
MISSING=""
for cmd in bcdata ogr2ogr psql curl unzip; do
  command -v "$cmd" >/dev/null 2>&1 || MISSING="$MISSING $cmd"
done
if [ "$WITH_BCFP_VIEWS" = "1" ]; then
  command -v aws >/dev/null 2>&1 || MISSING="$MISSING aws"
fi
if [ -n "$MISSING" ]; then
  echo "FATAL: missing required tools:$MISSING" >&2
  echo "See data-raw/README.md for install instructions per host." >&2
  exit 1
fi
if ! ogr2ogr --formats 2>/dev/null | grep -qi parquet; then
  echo "FATAL: ogr2ogr lacks Parquet driver. Need conda-forge or Homebrew GDAL." >&2
  exit 1
fi

# Skip-if-current guard runs FIRST -- before any DB-credential resolution.
# Reads `data-raw/logs/bcfp_baselines.csv` + the s3 log.json via httr; no
# Postgres needed. If this host's most-recent ledger row already matches
# the upstream bcfp build identifier, exit 0. Per-host scoped via
# lnk_baseline_current; each host populates its own local fwapg.
# A host with a stale/missing env file can skip cleanly when this week's
# ledger already matches, instead of aborting on PG* unbound-variable.
# Default behaviour on R failure (e.g. R not on PATH): proceed with the
# snapshot (rely on later DB-credential resolution to fail loud).
CURRENT=$(Rscript -e "cat(link::lnk_baseline_current(link::lnk_bucket_log()))" 2>/dev/null || echo "FALSE")
if [ "$CURRENT" = "TRUE" ]; then
  echo "snapshot_bcfp: ledger row for $(hostname) already at this upstream SHA; skipping."
  exit 0
fi

# Source per-host env file if present. data-raw/scheduler/README.md
# documents the format -- DATABASE_URL or PG* vars. Keeps secrets out
# of the launchd plist / cron template that ships in the repo.
# shellcheck disable=SC1091
[ -f "${HOME}/.config/snapshot-bcfp.env" ] && source "${HOME}/.config/snapshot-bcfp.env"

# Resolve DATABASE_URL from PG* env if not already set.
if [ -z "${DATABASE_URL:-}" ]; then
  DATABASE_URL="postgresql://${PGUSER:?}:${PGPASSWORD:?}@${PGHOST:-localhost}:${PGPORT:-5432}/${PGDATABASE:?}"
fi
PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"

# Ensure required schemas exist.
$PSQL -c "CREATE SCHEMA IF NOT EXISTS whse_fish;"
$PSQL -c "CREATE SCHEMA IF NOT EXISTS cabd;"
$PSQL -c "CREATE SCHEMA IF NOT EXISTS fresh;"
$PSQL -c "CREATE SCHEMA IF NOT EXISTS bcfishobs;"

# -----------------------------------------
# 1. BCDC PSCIS
# -----------------------------------------
# Drop the table first so the load is fresh on every run. `bcdata bc2pg
# --refresh` requires the target table to already exist (truncates it);
# DROP+create-from-scratch is simpler for our snapshot use case.
for tbl in pscis_assessment_svw \
          pscis_design_proposal_svw \
          pscis_habitat_confirmation_svw \
          pscis_remediation_svw; do
  $PSQL -c "DROP TABLE IF EXISTS whse_fish.${tbl};"
  bcdata bc2pg "whse_fish.${tbl}" --db_url "$DATABASE_URL"
done

# -----------------------------------------
# 2. CABD dams (public API; same URL as bcfp's jobs/load_weekly)
# -----------------------------------------
ogr2ogr -f PostgreSQL \
  "PG:$DATABASE_URL" \
  -overwrite \
  --config OGR_TRUNCATE=YES \
  --config PG_USE_COPY=YES \
  -nln cabd.dams \
  -lco GEOMETRY_NAME=geom \
  "https://cabd-web.azurewebsites.net/cabd-api/features/dams?filter=province_territory_code:eq:bc&filter=use_analysis:eq:true" \
  OGRGeoJSON

# -----------------------------------------
# 3. bchamp modelled_stream_crossings (gpkg.zip)
# -----------------------------------------
TMPDIR_MSC=$(mktemp -d)
trap "rm -rf $TMPDIR_MSC" EXIT

curl -fsSL \
  -o "$TMPDIR_MSC/modelled_stream_crossings.gpkg.zip" \
  https://nrs.objectstore.gov.bc.ca/bchamp/modelled_stream_crossings.gpkg.zip

unzip -qun "$TMPDIR_MSC/modelled_stream_crossings.gpkg.zip" -d "$TMPDIR_MSC"

ogr2ogr -f PostgreSQL \
  "PG:$DATABASE_URL" \
  -overwrite \
  --config PG_USE_COPY=YES \
  -nln fresh.modelled_stream_crossings \
  "$TMPDIR_MSC/modelled_stream_crossings.gpkg" \
  modelled_stream_crossings

# -----------------------------------------
# 4. bchamp observations (parquet) -- matches bcfp's jobs/load_observations
# -----------------------------------------
# observation_key is a string FID in the parquet; ogr2ogr -overwrite rejects
# string FIDs on table creation. bcfp's load_observations uses -append into a
# pre-existing table. We mirror that: DROP + CREATE (text PK) + -append.
$PSQL -c "DROP TABLE IF EXISTS bcfishobs.observations;"
$PSQL -c "CREATE TABLE bcfishobs.observations (
  observation_key text NOT NULL PRIMARY KEY,
  fish_observation_point_id numeric,
  wbody_id numeric,
  species_code varchar(6),
  agency_id numeric,
  point_type_code varchar(20),
  observation_date date,
  agency_name varchar(60),
  source varchar(1000),
  source_ref varchar(4000),
  utm_zone integer,
  utm_easting integer,
  utm_northing integer,
  activity_code varchar(100),
  activity varchar(300),
  life_stage_code varchar(100),
  life_stage varchar(300),
  species_name varchar(60),
  waterbody_identifier varchar(9),
  waterbody_type varchar(20),
  gazetted_name varchar(30),
  new_watershed_code varchar(56),
  trimmed_watershed_code varchar(56),
  acat_report_url varchar(254),
  feature_code varchar(10),
  linear_feature_id bigint,
  wscode ltree,
  localcode ltree,
  blue_line_key integer,
  watershed_group_code varchar(4),
  downstream_route_measure double precision,
  match_type text,
  distance_to_stream double precision,
  geom geometry(PointZ, 3005)
);"
ogr2ogr -f PostgreSQL \
  "PG:$DATABASE_URL" \
  -append \
  --config OGR_TRUNCATE=YES \
  --config PG_USE_COPY=YES \
  -nln bcfishobs.observations \
  /vsicurl/https://nrs.objectstore.gov.bc.ca/bchamp/bcfishobs/observations.parquet \
  observations

# -----------------------------------------
# 5. (optional) Simon's bcfp output views for parity comparison
# -----------------------------------------
if [ "$WITH_BCFP_VIEWS" = "1" ]; then
  for view in bcfishpass.crossings_vw bcfishpass.streams_vw; do
    target="fresh.${view#bcfishpass.}_bcfp"

    ogr2ogr -f PostgreSQL \
      "PG:$DATABASE_URL" \
      -overwrite \
      --config PG_USE_COPY=YES \
      -nln "$target" \
      "/vsizip//vsicurl/https://newgraph.s3.us-west-2.amazonaws.com/${view}.fgb.zip" \
      "${view}"
  done
fi

# -----------------------------------------
# 6. Stamp the baseline ledger with the bcfp build identifier
# -----------------------------------------
RUN_LABEL="snapshot-$(date -u +%Y%m%d)"
NOTES="manual snapshot via data-raw/snapshot_bcfp.sh"
if [ "$WITH_BCFP_VIEWS" = "1" ]; then
  NOTES="$NOTES; --with-bcfp-views"
fi

Rscript -e "
suppressMessages(library(link))
log <- lnk_bucket_log()
lnk_baseline_append(log,
  run_label = '$RUN_LABEL',
  notes     = paste0('$NOTES; head_sha=', substr(log\$head_sha, 1, 7))
)
cat(sprintf('Stamped %s with bcfp build %s (head_sha=%s)\\n',
            'data-raw/logs/bcfp_baselines.csv',
            log\$model_version,
            substr(log\$head_sha, 1, 7)))
" || {
  echo "WARNING: baseline stamp failed (link package may not be installed). Snapshot completed."
  exit 0
}

echo "snapshot_bcfp.sh: complete."
