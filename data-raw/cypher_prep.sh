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

set -euo pipefail

BRANCH="${CYPHER_PREP_BRANCH:-main}"

cd ~/Projects/repo/link
git fetch origin
git stash --include-untracked >/dev/null 2>&1 || true
git checkout "$BRANCH" 2>/dev/null || git checkout -B "$BRANCH" "origin/$BRANCH"
git reset --hard "origin/$BRANCH"

# pak::local_install — same tempfile + exit-check pattern as snapshot
# and persist_init below. A pak failure (network blip, dep resolution
# issue) was previously masked by `| tail -3` and only surfaced via
# the version-mismatch check downstream.
TMP_PAK_LOG=$(mktemp)
if ! Rscript -e "pak::local_install(upgrade = FALSE, ask = FALSE)" > "$TMP_PAK_LOG" 2>&1; then
  echo "FATAL: pak::local_install failed; full log:" >&2
  cat "$TMP_PAK_LOG" >&2
  rm -f "$TMP_PAK_LOG"
  exit 1
fi
tail -3 "$TMP_PAK_LOG"
rm -f "$TMP_PAK_LOG"
echo "=== link: $(Rscript -e "cat(as.character(packageVersion(\"link\")))") fresh: $(Rscript -e "cat(as.character(packageVersion(\"fresh\")))")"

cd data-raw
export PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg

# snapshot_bcfp.sh — capture full log to tempfile so a failure dumps the
# whole log to stderr (operator-debuggable on the cypher itself) instead
# of being masked by `| tail -5` (set -e doesn't propagate exit codes
# through pipelines). On success, tail-5 to stdout preserves the
# umbrella's downstream `grep -q "snapshot_bcfp.sh: complete"` check
# (data-raw/wsgs_run_pipeline.sh:264). Bug class documented in CLAUDE.md
# "Shell Scripts → pipefail with ssh+tee"; sibling fix in rtj#163.
TMP_SNAP_LOG=$(mktemp)
if ! bash snapshot_bcfp.sh > "$TMP_SNAP_LOG" 2>&1; then
  echo "FATAL: snapshot_bcfp.sh failed; full log:" >&2
  cat "$TMP_SNAP_LOG" >&2
  rm -f "$TMP_SNAP_LOG"
  exit 1
fi
tail -5 "$TMP_SNAP_LOG"
rm -f "$TMP_SNAP_LOG"

# DDL fix: lnk_persist_init detects unexpected GENERATED ALWAYS columns
# in fresh.streams (cypher snapshot artifact) and DROPs the offending
# tables when force_recreate=TRUE. After this, the subsequent
# lnk_pipeline_persist INSERTs succeed because the recreated tables
# have the expected (non-generated) DDL. Without this fix, all WSGs on
# the cypher fail with `cannot insert a non-DEFAULT value into column gradient`
# (the bug that wasted 93 WSGs on the 2026-05-12 provincial run).
#
# Same tempfile + exit-check pattern as snapshot above — without it,
# `| tail -10` would mask R-side failures (e.g. fresh schema state
# unexpected, conn refused) and the script would print "=== READY"
# while leaving the cypher half-prepped.
TMP_INIT_LOG=$(mktemp)
if ! Rscript -e '
suppressPackageStartupMessages({library(link); library(DBI); library(RPostgres)})
conn <- DBI::dbConnect(RPostgres::Postgres(),
  host="localhost", port=5432, dbname="fwapg",
  user="postgres", password="postgres")
cfg <- lnk_config("bcfishpass")
loaded <- lnk_load_overrides(cfg)
# Persist species set MUST match lnk_pipeline_run (R/lnk_pipeline_run.R:
# `lnk_persist_init(conn, cfg, species = cfg$species)`). The wide per-
# species tables (streams_access, streams_mapping_code) carry one column
# per species, so a cypher seeding from parameters_fresh (11 sp: adds
# CT/DV/RB) while the dispatcher uses cfg$species (8 sp) produces a
# column-set mismatch that breaks the cross-host COPY-consolidate.
# Caught 2026-05-25 in the 3-WSG smoke (link#175). Mirror cfg$species,
# with the same parameters_fresh fallback lnk_pipeline_species uses.
species <- if (!is.null(cfg$species)) cfg$species else unique(loaded$parameters_fresh$species_code)
lnk_persist_init(conn, cfg, species, force_recreate = TRUE)
cat("=== lnk_persist_init done\n")
' > "$TMP_INIT_LOG" 2>&1; then
  echo "FATAL: lnk_persist_init failed; full log:" >&2
  cat "$TMP_INIT_LOG" >&2
  rm -f "$TMP_INIT_LOG"
  exit 1
fi
tail -10 "$TMP_INIT_LOG"
rm -f "$TMP_INIT_LOG"
echo "=== READY"
