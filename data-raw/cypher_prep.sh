#!/usr/bin/env bash
# Per-cypher prep: git sync + link install + snapshot_bcfp + DDL fix.
#
# Runs ON each cypher droplet (not on M4). Idempotent — safe to re-run.
# Designed to be invoked via:
#
#   for IP in <cy1_ip> <cy2_ip> <cy3_ip>; do
#     scp -q data-raw/cypher_prep.sh "cypher@$IP:/tmp/cypher_prep.sh"
#     ssh "cypher@$IP" "bash /tmp/cypher_prep.sh" &
#   done
#   wait
#
# What it does:
#   1. git pull/reset the link branch to the orchestrator's current ref
#   2. pak::local_install link to pick up any package changes
#   3. snapshot_bcfp.sh — load PSCIS / CABD / modelled_crossings / bcfishobs
#      from public sources into the cypher's local fwapg
#   4. lnk_persist_init(force_recreate = TRUE) — DROPs any stale
#      `fresh.streams` table whose DDL has unexpected GENERATED ALWAYS
#      columns (cypher snapshot artifact from when `frs_col_generate()`
#      was previously run on it; link#162 Phase 7 hardening detects this
#      mismatch and the force_recreate flag clears it)
#
# Pre-conditions on the cypher:
#   - Docker fresh-db running on localhost:5432 (Postgres + PostGIS)
#   - link cloned at ~/Projects/repo/link
#   - homebrew bcdata, ogr2ogr, libpq psql, R + fresh + link installed
#     (all baked into the cypher-<date>-warm snapshot)
#
# Branch override: set CYPHER_PREP_BRANCH (env var) to use a non-default
# branch. Default is `main` — every host runs released code unless the
# operator explicitly opts into testing a branch.
#
# Examples:
#   bash cypher_prep.sh                            # main
#   CYPHER_PREP_BRANCH=feat/foo bash cypher_prep.sh
#
# The override-aware default protects against the cognitive trap of
# "which branch is everyone on?" — under the default path, all hosts
# converge on main and the orchestrator's preflight version-check
# (data-raw/dispatch_provincial.sh) confirms link versions match.

set -e

BRANCH="${CYPHER_PREP_BRANCH:-main}"

cd ~/Projects/repo/link
git fetch origin
git stash --include-untracked >/dev/null 2>&1 || true
git checkout "$BRANCH" 2>/dev/null || git checkout -B "$BRANCH" "origin/$BRANCH"
git reset --hard "origin/$BRANCH"

Rscript -e "pak::local_install(upgrade = FALSE, ask = FALSE)" 2>&1 | tail -3
echo "=== link: $(Rscript -e "cat(as.character(packageVersion(\"link\")))") fresh: $(Rscript -e "cat(as.character(packageVersion(\"fresh\")))")"

cd data-raw
export PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg
bash snapshot_bcfp.sh 2>&1 | tail -5

# DDL fix: lnk_persist_init detects unexpected GENERATED ALWAYS columns
# in fresh.streams (cypher snapshot artifact) and DROPs the offending
# tables when force_recreate=TRUE. After this, the subsequent
# lnk_pipeline_persist INSERTs succeed because the recreated tables
# have the expected (non-generated) DDL. Without this fix, all WSGs on
# the cypher fail with `cannot insert a non-DEFAULT value into column gradient`
# (the bug that wasted 93 WSGs on the 2026-05-12 provincial run).
Rscript -e '
suppressPackageStartupMessages({library(link); library(DBI); library(RPostgres)})
conn <- DBI::dbConnect(RPostgres::Postgres(),
  host="localhost", port=5432, dbname="fwapg",
  user="postgres", password="postgres")
cfg <- lnk_config("bcfishpass")
loaded <- lnk_load_overrides(cfg)
species <- unique(loaded$parameters_fresh$species_code)
lnk_persist_init(conn, cfg, species, force_recreate = TRUE)
cat("=== lnk_persist_init done\n")
' 2>&1 | tail -10
echo "=== READY"
