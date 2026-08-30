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
#   2. pak::local_install link to pick up any package changes. This now
#      also installs `fresh` — see "the image is not load-bearing" below
#   3. record this host's OWN observed git state in ~/.Renviron, so the
#      run log can attribute rows to a commit (link#246)
#   4. assert the installed fresh exports what the pipeline calls
#   5. snapshot_bcfp.sh — load PSCIS / CABD / modelled_crossings / bcfishobs
#      from public sources into the cypher's local fwapg
#   6. lnk_persist_init(force_recreate = TRUE) — DROPs any stale
#      `fresh.streams` table whose DDL has unexpected GENERATED ALWAYS
#      columns (cypher snapshot artifact from when `frs_col_generate()`
#      was previously run on it; link#162 Phase 7 hardening detects this
#      mismatch and the force_recreate flag clears it)
#
# The image is not load-bearing (link#246):
#   `cypher-20260512-warm` bakes link 0.35.0 + fresh 0.31.0, and fresh
#   0.31.0 exports neither `frs_wsg_drainage` nor `frs_wsg_outlets`.
#   link's wsg_run_one.R calls lnk_wsg_downstream_check(), whose `outlets`
#   argument defaults to `fresh::frs_wsg_outlets()`; the resulting error is
#   caught by a tryCatch that does quit(status = 1), and the umbrella's
#   bucket loop logs `[WARN]` and moves on. Net effect: every WSG on the
#   host fails, the host exits 0, and only the dispatcher's WSGs land.
#
#   The fix is a declaration fix, not an install line. `fresh` moved from
#   Suggests to Imports in link's DESCRIPTION, so `pak::local_install`
#   below is now obliged to resolve it, and resolution consults
#   `Remotes: NewGraphEnvironment/fresh@vX`. `upgrade = FALSE` suppresses
#   gratuitous upgrades, not required ones. One pin, in one place, moved by
#   the same PR that starts needing a newer fresh.
#
# Pre-conditions on the cypher:
#   - Docker fresh-db running on localhost:5432 (Postgres + PostGIS)
#   - link cloned at ~/Projects/repo/link
#   - homebrew bcdata, ogr2ogr, libpq psql, R installed
#     (baked into the cypher-<date>-warm snapshot)
#   - link and fresh are INSTALLED BY THIS SCRIPT. Whatever the image
#     happens to carry is overwritten and must never be relied on.
#
# Branch override: set CYPHER_PREP_BRANCH (env var) to use a non-default
# branch. Default is `main` — every host runs released code unless the
# operator explicitly opts into testing a branch.
#
# Stage: CYPHER_PREP_STAGE=all (default) | install
#   `install` stops after the package install + assertion, skipping the
#   snapshot and persist_init. That is the remediation path used by
#   study_area_run.sh --auto-install, where a re-prep costs ~3 min rather
#   than ~20 and the export assertion still gates it.
#
# fresh override: CYPHER_PREP_FRESH_REF installs a specific fresh ref on
# top of the DESCRIPTION pin — for testing an unreleased engine. The ref
# must still satisfy link's Imports floor, or pak will pull it straight
# back. That is deliberate: running an OLDER fresh requires relaxing the
# floor on your branch, where the change is reviewable.
#
# Examples:
#   bash cypher_prep.sh                            # main
#   CYPHER_PREP_BRANCH=feat/foo bash cypher_prep.sh
#   CYPHER_PREP_STAGE=install bash cypher_prep.sh
#   CYPHER_PREP_FRESH_REF=NewGraphEnvironment/fresh@feat/bar bash cypher_prep.sh
#
# The override-aware default protects against the cognitive trap of
# "which branch is everyone on?" — under the default path, all hosts
# converge on main and the orchestrator's preflight version check
# (data-raw/wsgs_dispatch.sh, and study_area_run.sh's preflight_hosts)
# confirms link and fresh agree across hosts.

set -euo pipefail

BRANCH="${CYPHER_PREP_BRANCH:-main}"
STAGE="${CYPHER_PREP_STAGE:-all}"
FRESH_REF="${CYPHER_PREP_FRESH_REF:-}"

case "$STAGE" in
  all|install) ;;
  *) echo "FATAL: CYPHER_PREP_STAGE must be 'all' or 'install' (got '$STAGE')" >&2
     echo "       a typo must not silently skip the snapshot" >&2
     exit 1 ;;
esac

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

# Optional: an unreleased fresh on top of the DESCRIPTION pin. `upgrade =
# TRUE` here because the whole point is to move off whatever pak just
# resolved. See the header for why the Imports floor still applies.
if [ -n "$FRESH_REF" ]; then
  echo "=== fresh override: $FRESH_REF"
  TMP_FRS_PAK=$(mktemp)
  if ! Rscript -e "pak::pkg_install(commandArgs(TRUE)[1], upgrade = TRUE, ask = FALSE)" \
       "$FRESH_REF" > "$TMP_FRS_PAK" 2>&1; then
    echo "FATAL: pak::pkg_install('$FRESH_REF') failed; full log:" >&2
    cat "$TMP_FRS_PAK" >&2
    rm -f "$TMP_FRS_PAK"
    exit 1
  fi
  tail -3 "$TMP_FRS_PAK"
  rm -f "$TMP_FRS_PAK"
fi

# Record THIS host's own observed git state so fresh.log can attribute rows
# to a commit. .lnk_pkg_git_sha() (R/lnk_stamp.R) reads <PKG>_GIT_SHA as its
# first tier and otherwise looks for a .git beside the installed package —
# which a pak install does not have, so every cypher row lands link_sha=NA
# today (link#246 Phase 5).
#
# Deliberately NOT inherited from the dispatcher over ssh. A SHA the
# dispatcher asserts is the dispatcher's claim; a SHA the cypher reads from
# the checkout it just reset is evidence, and it is what makes the
# cross-host parity gate a real comparison instead of a restatement.
LINK_SHA=$(git rev-parse HEAD) || { echo "FATAL: could not resolve link HEAD" >&2; exit 1; }
[ -n "$LINK_SHA" ] || { echo "FATAL: empty link HEAD sha" >&2; exit 1; }
if LINK_PORCELAIN=$(git status --porcelain); then
  [ -z "$LINK_PORCELAIN" ] && LINK_DIRTY=false || LINK_DIRTY=true
else
  echo "FATAL: could not read git status" >&2; exit 1
fi
# A local/source install has no RemoteSha; empty is the honest answer and
# the parity gate reports it as unresolved rather than treating NA == NA as
# agreement.
FRESH_SHA=$(Rscript -e \
  'x <- packageDescription("fresh")$RemoteSha; cat(if (is.null(x) || is.na(x)) "" else x)' \
  2>/dev/null) || FRESH_SHA=""

# Strip only the keys we own, then append — never rewrite wholesale, since
# the image may keep unrelated settings here.
RENV="$HOME/.Renviron"
touch "$RENV"
grep -vE '^(LINK_GIT_SHA|LINK_GIT_DIRTY|FRESH_GIT_SHA)=' "$RENV" > "$RENV.tmp" || true
mv "$RENV.tmp" "$RENV"
{
  printf 'LINK_GIT_SHA=%s\n'   "$LINK_SHA"
  printf 'LINK_GIT_DIRTY=%s\n' "$LINK_DIRTY"
  [ -n "$FRESH_SHA" ] && printf 'FRESH_GIT_SHA=%s\n' "$FRESH_SHA"
} >> "$RENV"
echo "=== provenance: link_sha=${LINK_SHA:0:12} dirty=$LINK_DIRTY fresh_sha=${FRESH_SHA:0:12}"

# Assert the installed fresh actually exports what the pipeline calls.
#
# NOT `$(Rscript ...)`: command substitution discards the exit status under
# set -e, which is the bug the surrounding blocks were already rewritten to
# avoid. Same tempfile + `if !` idiom as the pak and snapshot blocks.
TMP_FRS_LOG=$(mktemp)
if ! Rscript -e 'q(status = if (isTRUE(link::lnk_preflight_fresh()$ok)) 0L else 1L)' \
     > "$TMP_FRS_LOG" 2>&1; then
  echo "FATAL: fresh export assertion failed; full log:" >&2
  cat "$TMP_FRS_LOG" >&2
  rm -f "$TMP_FRS_LOG"
  exit 1
fi
cat "$TMP_FRS_LOG"
rm -f "$TMP_FRS_LOG"
echo "=== link: $(Rscript -e "cat(as.character(packageVersion(\"link\")))") fresh: $(Rscript -e "cat(as.character(packageVersion(\"fresh\")))")"

if [ "$STAGE" = "install" ]; then
  # Distinct sentinel. The umbrella's prep gate greps for an ANCHORED
  # "=== READY", so this cannot be mistaken for a completed full prep.
  echo "=== READY (install stage only; snapshot + persist_init NOT run)"
  exit 0
fi

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
