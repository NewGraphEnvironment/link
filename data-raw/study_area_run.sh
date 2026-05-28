#!/usr/bin/env bash
# study_area_run.sh — tunnel-free, M1-dispatch study-area mapping_code parity.
#
# Productionizes the proven smoke flow (cypher_up -> cypher_prep ->
# lnk_pipeline_run(mapping_code=TRUE) per WSG -> schema_consolidate ->
# wsg_compare_mapping_code -> cypher_down). NOT a refactor of the old
# M4-centric wsgs_run_pipeline.sh — it reuses the simple local flow the
# 3-WSG smoke validated (link#175).
#
# Host model: the local machine is the dispatcher (M1) and the consolidate
# destination; cyphers are the remote workers. No M4, no `ssh m1`, no bcfp
# tunnel (`:63333`/PG_PASS_SHARE) — the compare reference is the LOCAL bcfp
# snapshot fresh.streams_vw_bcfp (snapshot_bcfp.sh --with-bcfp-views).
#
# Cross-WSG `;DAM` correctness WITHOUT a post-consolidate recompute: each
# host gets a DRAINAGE-CLOSED bucket (focal WSGs + every WSG they drain
# through, via study_area_wsgs.R / public.wsg_outlet) run DOWNSTREAM-FIRST,
# so a WSG's downstream dam barriers are persisted before its access /
# mapping_code is computed. One study area (closed) per host.
#
# Usage:
#   bash data-raw/study_area_run.sh \
#     --cy-workspaces=job1,job2 \
#     --focal=<dispatcher focal csv> \
#     --focal=<cy1 focal csv> \
#     --focal=<cy2 focal csv> \
#     [--config=bcfishpass] [--schema=<persist-schema>] [--keep-cyphers]
#
# The number of --focal flags MUST equal 1 (dispatcher) + N cyphers, in
# order: first --focal -> dispatcher, the rest -> cyphers in --cy-workspaces
# order. Put the LARGEST area on the dispatcher (first --focal): it is the
# fast, free local host, while cyphers are slower + paid — give them the
# smaller areas so they finish + burn sooner. Cyphers burn right after
# consolidate (minimise idle); a trap EXIT is the safety net.

set -euo pipefail

# --- args ---
CY_WS=""
CONFIG="bcfishpass"
SCHEMA_OVERRIDE=""
KEEP_CYPHERS=0
FOCAL_ARR=()
for arg in "$@"; do
  case "$arg" in
    --cy-workspaces=*) CY_WS="${arg#--cy-workspaces=}" ;;
    --config=*)        CONFIG="${arg#--config=}" ;;
    --schema=*)        SCHEMA_OVERRIDE="${arg#--schema=}"
                       [ -n "$SCHEMA_OVERRIDE" ] || { echo "FATAL: --schema= requires a non-empty value" >&2; exit 1; } ;;
    --focal=*)         FOCAL_ARR+=("${arg#--focal=}") ;;
    --keep-cyphers)    KEEP_CYPHERS=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

IFS=',' read -ra CY_WS_ARR <<< "$CY_WS"
[ -n "$CY_WS" ] || CY_WS_ARR=()
N_CY=${#CY_WS_ARR[@]}
N_FOCAL=${#FOCAL_ARR[@]}
EXPECT=$((N_CY + 1))
if [ "$N_FOCAL" -ne "$EXPECT" ]; then
  echo "FATAL: need exactly $EXPECT --focal flags (1 dispatcher + $N_CY cyphers); got $N_FOCAL" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TS="$(date -u +%Y%m%d_%H%M%S)"
LOG_DIR="$REPO_ROOT/data-raw/logs/study_area_run"
mkdir -p "$LOG_DIR"
CYPHER_DIR="$HOME/Projects/repo/rtj/scripts/cypher"
CYPHER_TF="$HOME/Projects/repo/rtj/env/do/dev/cypher"
# Cyphers must run the SAME git ref as the dispatcher so they carry these
# driver scripts (wsg_run_one.R etc.) + a matching link install. cypher_prep
# reads CYPHER_PREP_BRANCH (default main, which lacks these scripts); pass the
# dispatcher's current branch. The branch MUST be pushed to origin first —
# cypher_prep does `git fetch origin && git reset --hard origin/$BRANCH`.
LINK_BRANCH="$(git -C "$REPO_ROOT" branch --show-current)"

# Resolve persist schema: --schema= overrides the config's YAML default
# (e.g. for side-by-side bundle compares: --config=default --schema=fresh_default
# keeps the bcfp-config run intact in `fresh`). All R scripts read LNK_SCHEMA
# below and override `cfg$pipeline$schema` if it is non-empty.
if [ -n "$SCHEMA_OVERRIDE" ]; then
  SCHEMA="$SCHEMA_OVERRIDE"
else
  SCHEMA=$(cd "$REPO_ROOT" && Rscript -e \
    'cat(link::lnk_config(commandArgs(TRUE)[1])$pipeline$schema)' "$CONFIG" 2>/dev/null || true)
fi
[ -n "$SCHEMA" ] || { echo "FATAL: could not resolve persist schema for --config=$CONFIG"; exit 1; }
export LNK_SCHEMA="$SCHEMA"

echo "=== study_area_run $TS ==="
echo "  config:       $CONFIG"
echo "  branch:       $LINK_BRANCH (cyphers run this ref)"
echo "  persist:      $SCHEMA"
echo "  cyphers:      ${CY_WS_ARR[*]:-<none>} ($N_CY)"
echo "  log dir:      $LOG_DIR"

# --- trap: burn cyphers on exit (safety net; explicit burn after consolidate) ---
CYPHERS_UP=0
burn_cyphers() {
  local rc=$?
  if [ "$CYPHERS_UP" = "0" ]; then return $rc; fi
  if [ "$KEEP_CYPHERS" = "1" ]; then
    echo "=== trap EXIT: --keep-cyphers; NOT burning (${CY_WS_ARR[*]}) ==="
    return $rc
  fi
  echo "=== BURN CYPHERS (trap EXIT) ==="
  ( cd "$CYPHER_DIR"
    for WS in "${CY_WS_ARR[@]}"; do
      ./cypher_down.sh --workspace "$WS" > "$LOG_DIR/${TS}_burn_$WS.log" 2>&1 &
    done
    wait )
  local clean=1
  for WS in "${CY_WS_ARR[@]}"; do
    local n
    # `|| n="?"` so a tofu hiccup (pipefail) can't abort the verification
    # loop when burn_cyphers runs via the EXIT trap (set -e active there).
    n=$(cd "$CYPHER_TF" && TF_WORKSPACE="$WS" tofu state list 2>/dev/null | wc -l | tr -d ' ') || n="?"
    echo "  cy[$WS]: $n tofu resources (expect 0)"; [ "$n" = "0" ] || clean=0
  done
  if doctl compute droplet list --no-header 2>/dev/null | grep -qi cypher; then
    echo "  ✗ doctl still shows cypher droplets"; clean=0
  else echo "  ✓ doctl: no cypher droplets"; fi
  [ "$clean" = "1" ] && echo "  ✓ burn clean" || echo "  ✗ BURN INCOMPLETE — investigate"
  CYPHERS_UP=0
  return $rc
}
trap burn_cyphers EXIT

# --- pre-flight (tunnel-free) ---
echo "=== pre-flight ==="
fail=0
pg_isready -h localhost -p 5432 >/dev/null 2>&1 || { echo "  ✗ local fwapg down (:5432)"; fail=1; }
# bcfp reference view is a constant (fresh.streams_vw_bcfp) — it lives in
# its own schema independent of $SCHEMA (the persist target). All compare
# code paths (R/lnk_compare_mapping_code.R:78 default) read it from `fresh`.
HAS_VW=$(PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres -d fwapg -t -A -c \
  "SELECT 1 FROM information_schema.tables WHERE table_schema='fresh' AND table_name='streams_vw_bcfp'" 2>/dev/null || true)
[ "$HAS_VW" = "1" ] || { echo "  ✗ fresh.streams_vw_bcfp missing (run snapshot_bcfp.sh --with-bcfp-views)"; fail=1; }
if [ "$N_CY" -gt 0 ]; then
  doctl compute droplet list --no-header >/dev/null 2>&1 || { echo "  ✗ doctl not authed"; fail=1; }
  (cd "$CYPHER_TF" && tofu workspace list >/dev/null 2>&1) || { echo "  ✗ tofu workspace list failed"; fail=1; }
fi
[ "$fail" = "0" ] || { echo "FATAL: pre-flight failed; aborting before spend"; exit 1; }
echo "  ✓ pre-flight clean (tunnel-free)"

# --- resolve drainage-closed DS-first buckets ---
echo "=== resolve drainage-closed DS-first buckets ==="
DISP_BUCKET=$(cd "$REPO_ROOT" && Rscript data-raw/study_area_wsgs.R "${FOCAL_ARR[0]}")
DISP_BUCKET=$(echo "$DISP_BUCKET" | tr -d '[:space:]')
echo "  dispatcher (focal=${FOCAL_ARR[0]}): $DISP_BUCKET"
declare -A CY_BUCKET
for i in "${!CY_WS_ARR[@]}"; do
  WS="${CY_WS_ARR[$i]}"
  B=$(cd "$REPO_ROOT" && Rscript data-raw/study_area_wsgs.R "${FOCAL_ARR[$((i+1))]}")
  CY_BUCKET[$WS]=$(echo "$B" | tr -d '[:space:]')
  echo "  cy[$WS] (focal=${FOCAL_ARR[$((i+1))]}): ${CY_BUCKET[$WS]}"
done

# Non-fatal: warn if buckets overlap. A WSG in two hosts' closures is
# computed on both and consolidate is last-writer-wins. Harmless when focal
# sets are drainage-independent (Peace/Fraser/Skeena are distinct roots), but
# surface an accidental overlap so it's visible rather than silent.
DUP=$( { echo "$DISP_BUCKET" | tr ',' '\n'
  for WS in "${CY_WS_ARR[@]}"; do echo "${CY_BUCKET[$WS]}" | tr ',' '\n'; done
} | grep -v '^$' | sort | uniq -d | paste -sd, - )
[ -z "$DUP" ] || echo "  WARN: buckets overlap on: $DUP (computed on multiple hosts; consolidate last-writer-wins)"

# --- spin + prep cyphers ---
declare -A CY_IP
if [ "$N_CY" -gt 0 ]; then
  echo "=== spin cyphers: ${CY_WS_ARR[*]} ==="
  ( cd "$CYPHER_DIR"
    for WS in "${CY_WS_ARR[@]}"; do
      ./cypher_up.sh --workspace "$WS" > "$LOG_DIR/${TS}_up_$WS.log" 2>&1 &
    done
    wait )
  for WS in "${CY_WS_ARR[@]}"; do
    IP=$(cd "$CYPHER_TF" && TF_WORKSPACE="$WS" tofu output -raw droplet_ip 2>/dev/null) \
      || { echo "FATAL: tofu droplet_ip failed for $WS"; exit 1; }
    [ -n "$IP" ] || { echo "FATAL: empty droplet_ip for $WS"; exit 1; }
    CY_IP[$WS]="$IP"; echo "  cy[$WS] = $IP"
  done
  CYPHERS_UP=1

  echo "=== prep cyphers (cypher_prep.sh) ==="
  for WS in "${CY_WS_ARR[@]}"; do
    IP="${CY_IP[$WS]}"
    ( # Wait for the fresh droplet's sshd before scp — cypher_up returns as
      # soon as the IP is assigned, often before SSH is up, which races scp
      # into "Connection closed". Poll up to ~150s, accept the new host key.
      for _ in $(seq 1 30); do
        ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
          "cypher@$IP" 'true' 2>/dev/null && break
        sleep 5
      done
      scp -q "$REPO_ROOT/data-raw/cypher_prep.sh" "cypher@$IP:/tmp/cypher_prep.sh" \
        && ssh "cypher@$IP" "CYPHER_PREP_BRANCH='$LINK_BRANCH' bash /tmp/cypher_prep.sh" ) > "$LOG_DIR/${TS}_prep_$WS.log" 2>&1 &
  done
  wait
  for WS in "${CY_WS_ARR[@]}"; do
    grep -q "snapshot_bcfp.sh: complete" "$LOG_DIR/${TS}_prep_$WS.log" 2>/dev/null \
      || { echo "FATAL: cypher[$WS] prep failed; see $LOG_DIR/${TS}_prep_$WS.log"; exit 1; }
  done
  echo "  ✓ cyphers prepped"
fi

# --- run buckets DS-first (dispatcher local + cyphers, parallel) ---
# Per-WSG SOFT-FAIL (mirrors wsgs_run_host.R resume-safe behaviour): a single
# WSG error logs a warning and the loop CONTINUES. It must NEVER abort the host
# and trip the trap-burn before consolidate — that lost a whole run + the
# cyphers' data on 2026-05-25 (one species-less WSG -> exit 1 -> FATAL -> burn).
# Missing WSGs surface as gaps in the final compare, not as data loss.
echo "=== run buckets (DS-first) ==="
( cd "$REPO_ROOT"
  for w in $(echo "$DISP_BUCKET" | tr ',' ' '); do
    LNK_LOAD=loadall Rscript data-raw/wsg_run_one.R "$w" "$CONFIG" \
      || echo "[WARN] dispatcher WSG $w failed (continuing)"
  done ) > "$LOG_DIR/${TS}_run_local.log" 2>&1 &
LOCAL_PID=$!
declare -A CY_PID
for WS in "${CY_WS_ARR[@]}"; do
  IP="${CY_IP[$WS]}"; B_SPACE=$(echo "${CY_BUCKET[$WS]}" | tr ',' ' ')
  ssh "cypher@$IP" "cd ~/Projects/repo/link && export LNK_SCHEMA='$SCHEMA' && for w in $B_SPACE; do Rscript data-raw/wsg_run_one.R \$w '$CONFIG' || echo \"[WARN] cy WSG \$w failed\"; done" \
    > "$LOG_DIR/${TS}_run_$WS.log" 2>&1 &
  CY_PID[$WS]=$!
done
# A non-zero host exit (e.g. ssh dropped) is logged, NOT fatal — we still
# consolidate whatever each host persisted so a late failure can't lose the
# other hosts' work.
wait $LOCAL_PID || echo "  WARN: dispatcher run returned non-zero; see $LOG_DIR/${TS}_run_local.log"
for WS in "${CY_WS_ARR[@]}"; do
  wait "${CY_PID[$WS]}" || echo "  WARN: cy[$WS] run returned non-zero; see $LOG_DIR/${TS}_run_$WS.log"
done
echo "  ✓ host runs finished (per-WSG soft-fail; gaps surface in compare)"

# --- consolidate cyphers -> dispatcher ---
if [ "$N_CY" -gt 0 ]; then
  echo "=== consolidate cyphers -> dispatcher ($SCHEMA) ==="
  SRC_R="list("
  first=1
  for WS in "${CY_WS_ARR[@]}"; do
    IP="${CY_IP[$WS]}"
    bucket_r=$(echo "${CY_BUCKET[$WS]}" | tr ',' '\n' | grep -v '^$' | sed "s/.*/'&'/" | paste -sd, -)
    [ "$first" = "1" ] || SRC_R="$SRC_R, "
    SRC_R="$SRC_R list(host = 'cypher@$IP', via = 'docker', bucket = c($bucket_r))"
    first=0
  done
  SRC_R="$SRC_R)"
  ( cd "$REPO_ROOT" && Rscript -e "
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
source('data-raw/schema_consolidate.R')
res <- schema_consolidate(schema = '$SCHEMA', sources = $SRC_R, backup = TRUE)
print(res)
ok <- all(vapply(res\$sources, function(s) isTRUE(s\$ok), logical(1)))
quit(status = if (ok) 0 else 1)
" ) > "$LOG_DIR/${TS}_consolidate.log" 2>&1 \
    || { echo "  ✗ consolidate failed; see $LOG_DIR/${TS}_consolidate.log"; exit 1; }
  echo "  ✓ consolidated (see $LOG_DIR/${TS}_consolidate.log)"
fi

# --- burn cyphers now (work is consolidated; minimise idle) ---
burn_cyphers || true

# WSG set across all hosts.
ALL_WSGS=$( { echo "$DISP_BUCKET" | tr ',' '\n'
  for WS in "${CY_WS_ARR[@]}"; do echo "${CY_BUCKET[$WS]}" | tr ',' '\n'; done
} | grep -v '^$' | sort -u | paste -sd, - )
COMPARE_CSV="$LOG_DIR/${TS}_compare.csv"

# --- post-consolidate recompute: settle cross-WSG access (link#205) ---
# Drainage-closed + DS-first per-host is NOT sufficient: a WSG's downstream
# barriers can be cross-bucket or arrive late in DS-first order, so its access
# (hence token1/token2) is computed against an incomplete barrier set.
# Caught 2026-05-25: FINA 75% / PARA 69% per-host -> both 99% only after
# re-modelling on the full consolidated barrier set. The recompute is the
# correctness guarantee REGARDLESS of bucketing. We use lnk_access(merge=TRUE)
# — the cheap access-only recompute that reuses the persisted streams /
# habitat / barriers / barrier_overrides (link#205, ~10 s/WSG vs ~1.5 min for
# a full pipeline rebuild). Because it is cheap, we recompute ALL run WSGs
# unconditionally rather than threshold-filtering by parity — bucketing is
# now a speed knob, not a correctness lever.
echo "=== post-consolidate recompute (lnk_access, all WSGs) ==="
( cd "$REPO_ROOT"
  for w in $(echo "$ALL_WSGS" | tr ',' ' '); do
    LNK_LOAD=loadall Rscript data-raw/wsg_recompute_one.R "$w" "$CONFIG" \
      || echo "[WARN] recompute WSG $w failed (continuing)"
  done ) > "$LOG_DIR/${TS}_recompute.log" 2>&1
echo "  ✓ recompute done"

# --- compare (tunnel-free) -> CSV ---
echo "=== compare (tunnel-free) ==="
( cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript data-raw/study_area_compare.R \
    "$COMPARE_CSV" "$ALL_WSGS" "$CONFIG" ) > "$LOG_DIR/${TS}_compare.log" 2>&1 \
  || { echo "  ✗ compare failed; see $LOG_DIR/${TS}_compare.log"; exit 1; }
echo "  ✓ compare CSV: $COMPARE_CSV"

# --- report ---
echo "=== summary ==="
echo "  run WSGs: $ALL_WSGS"
echo "  compare CSV: $COMPARE_CSV"
tail -40 "$LOG_DIR/${TS}_compare.log" || true
echo "=== study_area_run done ==="
