#!/usr/bin/env bash
# wsgs_run_pipeline.sh — top-level wrapper for the full provincial parity run.
#
# Orchestrates the 10-step sequence documented in
# research/post_compact_provincial_handoff.md:
#   pre-flight  → fail loud before any spend
#   1+2.        snapshot_bcfp.sh on M4 + M1 (parallel)
#   3.          cypher_up.sh job1/job2/job3 (parallel)
#   4.          cypher_prep.sh on each cypher (parallel)
#   5.          runs_archive.sh on all 5 hosts (parallel)
#   6.          SMOKE — fail-fast
#   7.          FULL DISPATCH
#   8.          acceptance bar check (UNEXPLAINED at |diff_pct|>=2% == 0)
#   9.          consolidate fresh schema → M4
#   10.         BURN CYPHERS — fires via trap EXIT
#
# Cypher burn is `trap EXIT` so it fires regardless of failure mode in
# steps 6-9. Steps 1-3 set CYPHERS_UP=1 once cyphers exist, so the trap
# only attempts burn when there's something to burn.
#
# Usage:
#   bash data-raw/wsgs_run_pipeline.sh [flags]
#
# Flags:
#   --wsgs=A,B,C       restrict to a WSG subset (full bundle if omitted)
#   --config=<name>    bundle name (default: bcfishpass)
#   --schema=<name>    override cfg$pipeline$schema (default: bundle default)
#   --no-cyphers       M4+M1 only — skip cypher spin/prep/burn entirely
#   --cy-workspaces=A,B,C  cypher tofu workspaces to spin (default: job1,job2,job3).
#                          Pass a subset like `--cy-workspaces=job1` for Tier 1
#                          integration tests, or `--cy-workspaces=job1,job2` for Tier 2.
#                          Mutually exclusive with --no-cyphers.
#   --force            forward --force to per-host Rscript (bypass resume gates)
#   --skip-smoke       skip the smoke pre-check
#   --no-mapping-code  drop the mapping_code lens
#   --keep-cyphers     don't burn cyphers on exit (debug)
#
# Total wall:
#   ~95-110 min for full provincial (3 cyphers)
#   ~30-40 min for --wsgs=<16-WSG-set> --no-cyphers (M4+M1 only)
# Cypher cost: ~$1-2 per full provincial; $0 with --no-cyphers.

set -euo pipefail

# --- args ---
SKIP_SMOKE=0
NO_MAPPING=0
KEEP_CYPHERS=0
WSGS_FILTER=""
CONFIG_NAME="bcfishpass"
SCHEMA=""
NO_CYPHERS=0
FORCE_FLAG=""
CY_WORKSPACES="job1,job2,job3"
for arg in "$@"; do
  case "$arg" in
    --skip-smoke)      SKIP_SMOKE=1 ;;
    --with-mapping-code) ;;  # default-on; accept explicitly for symmetry with --no-mapping-code
    --no-mapping-code) NO_MAPPING=1 ;;
    --keep-cyphers)    KEEP_CYPHERS=1 ;;
    --wsgs=*)          WSGS_FILTER="${arg#--wsgs=}" ;;
    --config=*)        CONFIG_NAME="${arg#--config=}" ;;
    --schema=*)        SCHEMA="${arg#--schema=}" ;;
    --no-cyphers)      NO_CYPHERS=1 ;;
    --cy-workspaces=*) CY_WORKSPACES="${arg#--cy-workspaces=}" ;;
    --force)           FORCE_FLAG="--force" ;;
    *) echo "FATAL: unknown arg: $arg" >&2; exit 1 ;;
  esac
done

# Parse cypher workspace list into array. Empty CY_WS_ARR when --no-cyphers
# is set so downstream `for WS in "${CY_WS_ARR[@]}"` loops become no-ops.
if [ "$NO_CYPHERS" = "1" ] || [ -z "$CY_WORKSPACES" ]; then
  CY_WS_ARR=()
else
  IFS=',' read -r -a CY_WS_ARR <<< "$CY_WORKSPACES"
fi
N_CY=${#CY_WS_ARR[@]}

MAPPING_FLAG="--with-mapping-code"
[ "$NO_MAPPING" = "1" ] && MAPPING_FLAG=""

# Build the passthrough flag string for wsgs_dispatch.sh + trifecta_smoke.sh.
DISPATCH_FLAGS=""
[ -n "$WSGS_FILTER" ] && DISPATCH_FLAGS="$DISPATCH_FLAGS --wsgs=$WSGS_FILTER"
[ -n "$CONFIG_NAME" ] && DISPATCH_FLAGS="$DISPATCH_FLAGS --config=$CONFIG_NAME"
[ -n "$SCHEMA" ]      && DISPATCH_FLAGS="$DISPATCH_FLAGS --schema=$SCHEMA"
[ "$NO_CYPHERS" = "1" ] && DISPATCH_FLAGS="$DISPATCH_FLAGS --no-cyphers"
[ -n "$FORCE_FLAG" ]  && DISPATCH_FLAGS="$DISPATCH_FLAGS $FORCE_FLAG"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
TS="$(date -u +%Y%m%d_%H%M%S)"
LOG_DIR="$REPO_ROOT/data-raw/logs/wsgs_run_pipeline"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/${TS}_wsgs_run_pipeline.log"
exec > >(tee -a "$LOG") 2>&1

START_EPOCH=$(date +%s)
echo "=== wsgs_run_pipeline.sh $TS ==="
echo "  log:         $LOG"
echo "  config:      $CONFIG_NAME"
[ -n "$SCHEMA" ]      && echo "  schema:      $SCHEMA"
[ -n "$WSGS_FILTER" ] && echo "  wsgs:        $WSGS_FILTER"
echo "  no-cyphers:  $([ "$NO_CYPHERS" = "0" ] && echo no || echo YES)"
echo "  force:       $([ -n "$FORCE_FLAG" ] && echo YES || echo no)"
echo "  mapping:     $([ "$NO_MAPPING" = "0" ] && echo with || echo without)"
echo "  smoke:       $([ "$SKIP_SMOKE" = "0" ] && echo on || echo SKIPPED)"
echo "  keep-cy:     $([ "$KEEP_CYPHERS" = "0" ] && echo no || echo YES)"

# Auto-skip smoke when the smoke harness's preconditions are not met.
# trifecta_smoke.sh assumes 3 cypher workspaces (job1/job2/job3) and a
# fixed per-host WSG triplet; all break under --no-cyphers, --wsgs, or
# a non-default --cy-workspaces (e.g. Tier 1 / Tier 2 integration tests
# with 1 or 2 cyphers). Setting SKIP_SMOKE here (after the log redirect)
# keeps the notice in the log for post-hoc inspection.
if [ "$SKIP_SMOKE" = "0" ] && \
   { [ "$NO_CYPHERS" = "1" ] || [ -n "$WSGS_FILTER" ] || \
     [ "$CY_WORKSPACES" != "job1,job2,job3" ]; }; then
  echo "[auto-skip-smoke] one of {--no-cyphers, --wsgs, non-default"
  echo "                   --cy-workspaces} is set; trifecta_smoke.sh"
  echo "                   assumptions don't hold — skipping Step 6."
  SKIP_SMOKE=1
fi

# --- trap: burn cyphers on exit, but only if we ever spun them ---
CYPHERS_UP=0
burn_cyphers() {
  local rc=$?
  if [ "$CYPHERS_UP" = "0" ]; then
    echo "=== trap EXIT: no cyphers spun, nothing to burn ==="
    return $rc
  fi
  if [ "$KEEP_CYPHERS" = "1" ]; then
    echo "=== trap EXIT: --keep-cyphers given; NOT burning ==="
    echo "  manually: cd ~/Projects/repo/rtj/scripts/cypher && \\"
    echo "    for WS in ${CY_WS_ARR[*]}; do ./cypher_down.sh --workspace \$WS & done; wait"
    return $rc
  fi
  echo "=== Step 10: BURN CYPHERS (trap EXIT, mandatory) ==="
  cd ~/Projects/repo/rtj/scripts/cypher
  for WS in "${CY_WS_ARR[@]}"; do
    ./cypher_down.sh --workspace "$WS" > "$LOG_DIR/${TS}_burn_$WS.log" 2>&1 &
  done
  wait
  echo "--- destruction verification ---"
  local clean=1
  for WS in "${CY_WS_ARR[@]}"; do
    local n
    n=$(cd ~/Projects/repo/rtj/env/do/dev/cypher && TF_WORKSPACE="$WS" tofu state list 2>/dev/null | wc -l | tr -d ' ')
    echo "  cy[$WS]: $n tofu resources (expect 0)"
    [ "$n" = "0" ] || clean=0
  done
  if doctl compute droplet list --no-header 2>/dev/null | grep -qi cypher; then
    echo "  ✗ doctl still shows cypher droplets:"
    doctl compute droplet list --no-header 2>/dev/null | grep -i cypher
    clean=0
  else
    echo "  ✓ doctl: no cypher droplets"
  fi
  [ "$clean" = "1" ] && echo "  ✓ burn clean" || echo "  ✗ BURN INCOMPLETE — investigate before next run"
  return $rc
}
trap burn_cyphers EXIT

# --- pre-flight ---
echo "=== pre-flight ==="
fail=0
pg_isready -h localhost -p 63333 >/dev/null 2>&1 || { echo "  ✗ bcfp tunnel down (:63333)"; fail=1; }
pg_isready -h localhost -p 5432  >/dev/null 2>&1 || { echo "  ✗ local fwapg down (:5432)";  fail=1; }
Rscript -e 'q(status = if (nchar(Sys.getenv("PG_PASS_SHARE")) > 0) 0 else 1)' >/dev/null 2>&1 \
  || { echo "  ✗ PG_PASS_SHARE not visible to R (check ~/.Renviron)"; fail=1; }
ssh -o ConnectTimeout=3 m1 'hostname' >/dev/null 2>&1 || { echo "  ✗ m1 ssh failed"; fail=1; }
doctl compute droplet list --no-header >/dev/null 2>&1 || { echo "  ✗ doctl not authed"; fail=1; }
( cd ~/Projects/repo/rtj/env/do/dev/cypher && tofu workspace list >/dev/null 2>&1 ) \
  || { echo "  ✗ tofu workspace list failed"; fail=1; }
[ "$fail" = "0" ] || { echo "FATAL: pre-flight failed; aborting before spend"; exit 1; }
echo "  ✓ pre-flight clean"

# --- Step 0: pre-clean target schema (when --schema= is set) ---
# Drops $SCHEMA on every host before dispatch so the per-WSG pipeline
# writes land into a clean slate AND so consolidate's pg_dump source
# contains only the current run's bucket (no leftover WSGs from prior
# runs colliding with destination data). Uses state_clean.sh in
# scoped mode (--schemas=...) which skips the canonical-fresh wipe and
# the snapshot_bcfp.sh reload.
#
# Skipped when --schema is empty (writes go to the bundle's default
# schema, typically the canonical `fresh` — which Step 1+2's snapshot
# already handles).
if [ -n "$SCHEMA" ]; then
  echo "=== Step 0: pre-clean target schema [$SCHEMA] ==="
  CLEAN_ARGS="--schemas=$SCHEMA"
  [ "$NO_CYPHERS" = "1" ] && CLEAN_ARGS="$CLEAN_ARGS --skip-cy"
  bash data-raw/state_clean.sh $CLEAN_ARGS > "$LOG_DIR/${TS}_preclean.log" 2>&1 || {
    echo "FATAL: pre-clean failed; see $LOG_DIR/${TS}_preclean.log"
    exit 1
  }
  echo "  ✓ pre-cleaned"
fi

# --- Step 1+2: snapshot_bcfp.sh on M4 + M1 (parallel) ---
echo "=== Step 1+2: snapshot_bcfp.sh --force on M4 + M1 ==="
( PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg \
    bash data-raw/snapshot_bcfp.sh --force > "$LOG_DIR/${TS}_snapshot_m4.log" 2>&1 ) &
M4_PID=$!
( ssh m1 'export PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg && \
          cd ~/Projects/repo/link && bash data-raw/snapshot_bcfp.sh --force' \
    > "$LOG_DIR/${TS}_snapshot_m1.log" 2>&1 ) &
M1_PID=$!
wait $M4_PID || { echo "FATAL: M4 snapshot failed; see $LOG_DIR/${TS}_snapshot_m4.log"; exit 1; }
wait $M1_PID || { echo "FATAL: M1 snapshot failed; see $LOG_DIR/${TS}_snapshot_m1.log"; exit 1; }
echo "  ✓ snapshots done"

# --- Step 3: spin N cyphers (parallel) — N = ${#CY_WS_ARR[@]} ---
declare -A CY_IP
if [ "$N_CY" -gt 0 ]; then
  echo "=== Step 3: cypher_up.sh ${CY_WS_ARR[*]} ($N_CY cypher$([ $N_CY -eq 1 ] || echo s)) ==="
  cd ~/Projects/repo/rtj/scripts/cypher
  for WS in "${CY_WS_ARR[@]}"; do
    ./cypher_up.sh --workspace "$WS" > "$LOG_DIR/${TS}_up_$WS.log" 2>&1 &
  done
  wait
  cd "$REPO_ROOT"
  for WS in "${CY_WS_ARR[@]}"; do
    IP=$(cd ~/Projects/repo/rtj/env/do/dev/cypher && TF_WORKSPACE="$WS" tofu output -raw droplet_ip 2>/dev/null) || {
      echo "FATAL: tofu output droplet_ip failed for $WS; see $LOG_DIR/${TS}_up_$WS.log"
      exit 1
    }
    [ -n "$IP" ] || { echo "FATAL: empty droplet_ip for $WS"; exit 1; }
    CY_IP[$WS]="$IP"
    echo "  cy[$WS] = $IP"
  done
  CYPHERS_UP=1   # trap EXIT will now attempt burn

  # --- Step 4: per-cypher prep (parallel) ---
  echo "=== Step 4: cypher_prep.sh on $N_CY cypher$([ $N_CY -eq 1 ] || echo s) ==="
  for WS in "${CY_WS_ARR[@]}"; do
    IP="${CY_IP[$WS]}"
    ( scp -q data-raw/cypher_prep.sh "cypher@$IP:/tmp/cypher_prep.sh" && \
      ssh "cypher@$IP" "bash /tmp/cypher_prep.sh" ) > "$LOG_DIR/${TS}_prep_$WS.log" 2>&1 &
  done
  wait
  for WS in "${CY_WS_ARR[@]}"; do
    if ! grep -q "snapshot_bcfp.sh: complete" "$LOG_DIR/${TS}_prep_$WS.log" 2>/dev/null; then
      echo "FATAL: cypher[$WS] prep failed; see $LOG_DIR/${TS}_prep_$WS.log"
      exit 1
    fi
  done
  echo "  ✓ cyphers prepped"
else
  echo "=== Step 3+4: SKIPPED (--no-cyphers) ==="
fi

# --- Step 5: archive prior RDS — M4+M1 always, cyphers only when up ---
echo "=== Step 5: runs_archive.sh on all hosts ==="
bash data-raw/runs_archive.sh > "$LOG_DIR/${TS}_archive_m4.log" 2>&1 &
ssh m1 'cd ~/Projects/repo/link/data-raw && ./runs_archive.sh' \
  > "$LOG_DIR/${TS}_archive_m1.log" 2>&1 &
for WS in "${CY_WS_ARR[@]}"; do
  IP="${CY_IP[$WS]}"
  ssh "cypher@$IP" 'cd ~/Projects/repo/link/data-raw && ./runs_archive.sh' \
    > "$LOG_DIR/${TS}_archive_$WS.log" 2>&1 &
done
wait
echo "  ✓ archived"

# --- Step 6: SMOKE (fail-fast) ---
if [ "$SKIP_SMOKE" = "0" ]; then
  echo "=== Step 6: SMOKE ==="
  cd "$REPO_ROOT/data-raw"
  if ! bash trifecta_smoke.sh --cy-workspaces=job1,job2,job3 $MAPPING_FLAG \
       > "$LOG_DIR/${TS}_smoke.log" 2>&1; then
    echo "FATAL: smoke FAILED; see $LOG_DIR/${TS}_smoke.log"
    grep -E "smoke.*FAILED|smoke.*ERROR|SMOKE_ERR:" "$LOG_DIR/${TS}_smoke.log" | head -10 || true
    exit 1
  fi
  echo "  ✓ smoke clean"
  cd "$REPO_ROOT"
fi

# --- Step 7: FULL DISPATCH ---
# Cypher workspaces flow through verbatim from the umbrella's
# --cy-workspaces=. When --no-cyphers is set, $N_CY=0 and the arg
# is omitted (dispatcher then sees no cypher hosts).
if [ "$N_CY" -gt 0 ]; then
  TRIFECTA_CY_ARG="--cy-workspaces=$CY_WORKSPACES"
  echo "=== Step 7: dispatch ($N_CY cypher$([ $N_CY -eq 1 ] || echo s)) ==="
else
  TRIFECTA_CY_ARG=""
  echo "=== Step 7: dispatch (M4+M1 only) ==="
fi
echo "  DISPATCH_FLAGS=$DISPATCH_FLAGS $TRIFECTA_CY_ARG"
cd "$REPO_ROOT/data-raw"
if ! bash wsgs_dispatch.sh $TRIFECTA_CY_ARG $DISPATCH_FLAGS $MAPPING_FLAG \
     > "$LOG_DIR/${TS}_full.log" 2>&1; then
  echo "WARNING: wsgs_dispatch.sh exited non-zero; partial result may exist"
  # don't exit — let acceptance + consolidate inspect what landed
fi
echo "--- full dispatch tail ---"
tail -15 "$LOG_DIR/${TS}_full.log"
cd "$REPO_ROOT"

# --- Step 8: acceptance bar ---
# RDS dir is config-aware: bcfishpass → provincial_parity (legacy
# name, kept for back-compat); any other bundle → provincial_<config>.
echo "=== Step 8: acceptance bar ==="
if [ "$CONFIG_NAME" = "bcfishpass" ]; then
  RDS_DIR_NAME="provincial_parity"
else
  RDS_DIR_NAME="provincial_${CONFIG_NAME}"
fi
ANN_CSV=$(ls -1t "data-raw/logs/$RDS_DIR_NAME"/*_annotated.csv 2>/dev/null | head -1 || true)
if [ -z "$ANN_CSV" ]; then
  echo "  ✗ no annotated.csv found — dispatch likely failed before annotation"
  exit 1
fi
N_UNEXP=$(Rscript -e "
ann <- read.csv('$ANN_CSV', stringsAsFactors=FALSE)
cat(nrow(ann[ann\$class == 'UNEXPLAINED' & abs(ann\$diff_pct) >= 2, ]))
")
echo "  annotated: $ANN_CSV"
echo "  UNEXPLAINED at |diff_pct|>=2%: $N_UNEXP"
if [ "$N_UNEXP" -gt 0 ]; then
  echo "  WARNING: $N_UNEXP UNEXPLAINED rows — surface to user; consolidate still proceeds"
fi

# --- Step 9: consolidate target schema → M4 ---
# Target schema: --schema= if provided, else cfg$pipeline$schema for
# the bundle (best-effort lookup via Rscript). Sources list is built
# dynamically — M1 always present; cyphers only when --no-cyphers
# wasn't set.
echo "=== Step 9: consolidate target schema ==="
ORCH_LOG=$(ls -1t data-raw/logs/*_wsgs_dispatch_orchestrator.txt 2>/dev/null | head -1 || true)
if [ -z "$ORCH_LOG" ]; then
  echo "  ✗ no orchestrator log found — cannot extract per-host buckets"
  exit 1
fi
M1_BUCKET=$(grep '^  m1     bucket:' "$ORCH_LOG" | sed 's/.*bucket: //' || true)
if [ -z "$M1_BUCKET" ]; then
  echo "  ✗ failed to extract m1 bucket from $ORCH_LOG"
  exit 1
fi
declare -A CY_BUCKETS
for WS in "${CY_WS_ARR[@]}"; do
  B=$(grep "^  cypher\\[$WS\\] bucket:" "$ORCH_LOG" | sed 's/.*bucket: //' || true)
  if [ -z "$B" ]; then
    echo "  ✗ failed to extract cypher[$WS] bucket from $ORCH_LOG"
    exit 1
  fi
  CY_BUCKETS[$WS]="$B"
done

# Resolve target schema name: explicit --schema wins, else look up
# cfg$pipeline$schema for the bundle. Explicit guards rather than a
# silent "fresh" fallback so a misconfigured --config= surfaces loud.
if [ -n "$SCHEMA" ]; then
  TARGET_SCHEMA="$SCHEMA"
else
  TARGET_SCHEMA=$(Rscript -e "
    cfg <- link::lnk_config('$CONFIG_NAME')
    s <- cfg\$pipeline\$schema
    if (is.null(s) || !nzchar(s)) stop('cfg\$pipeline\$schema missing for bundle \"$CONFIG_NAME\"')
    cat(s)
  ") || {
    echo "  ✗ failed to resolve target schema for --config=$CONFIG_NAME" >&2
    echo "    (lnk_config may be missing the bundle, or cfg\$pipeline\$schema is unset)" >&2
    exit 1
  }
  if [ -z "$TARGET_SCHEMA" ] || [ "$TARGET_SCHEMA" = "NULL" ]; then
    echo "  ✗ lnk_config('$CONFIG_NAME')\$pipeline\$schema returned empty/NULL" >&2
    exit 1
  fi
fi
echo "  target schema: $TARGET_SCHEMA"

cd "$REPO_ROOT/data-raw"

# Build SOURCES_R as a list literal dynamically. M1 always present;
# any cyphers in CY_WS_ARR get their own entry with IP + bucket. The
# R-side `eval(parse(text=...))` materializes the list. Each cypher
# bucket is passed via env var CY_BUCKET_<WS>; each cypher IP via
# CY_IP_<WS>. The R snippet reads these by Sys.getenv() to avoid
# quoting hazards across the shell↔R boundary.
SOURCES_R_LINES="list(\n    list(host = 'm1', via = 'docker', bucket = strsplit(Sys.getenv('M1_BUCKET'), ',')[[1]])"
ENV_PREFIX="M1_BUCKET=\"$M1_BUCKET\""
for WS in "${CY_WS_ARR[@]}"; do
  SOURCES_R_LINES="${SOURCES_R_LINES},\n    list(host = paste0('cypher@', Sys.getenv('CY_IP_${WS}')), via = 'docker', bucket = strsplit(Sys.getenv('CY_BUCKET_${WS}'), ',')[[1]])"
  ENV_PREFIX="$ENV_PREFIX CY_BUCKET_${WS}=\"${CY_BUCKETS[$WS]}\" CY_IP_${WS}=\"${CY_IP[$WS]}\""
done
SOURCES_R="$(printf '%b\n  )' "$SOURCES_R_LINES")"

eval "$ENV_PREFIX TARGET_SCHEMA=\"$TARGET_SCHEMA\" SOURCES_R=\"\$SOURCES_R\" Rscript -e '
suppressPackageStartupMessages({library(link)})
source(\"schema_consolidate.R\")
sources <- eval(parse(text = Sys.getenv(\"SOURCES_R\")))
result <- schema_consolidate(schema = Sys.getenv(\"TARGET_SCHEMA\"),
                              sources = sources, backup = TRUE)
print(result)
saveRDS(result, \"/tmp/consolidate_result.rds\")
'" > "$LOG_DIR/${TS}_consolidate.log" 2>&1 || {
  echo "  ✗ schema_consolidate.R failed; see $LOG_DIR/${TS}_consolidate.log"
  exit 1
}
echo "  ✓ consolidated (see $LOG_DIR/${TS}_consolidate.log)"
cd "$REPO_ROOT"

# --- summary ---
END_EPOCH=$(date +%s)
WALL=$(( END_EPOCH - START_EPOCH ))
echo
echo "=== wsgs_run_pipeline.sh complete in ${WALL}s (~$((WALL/60))m) ==="
echo "  annotated CSV:  $ANN_CSV"
echo "  UNEXPLAINED ≥2%: $N_UNEXP"
echo "  trap EXIT will now burn cyphers (unless --keep-cyphers)"
