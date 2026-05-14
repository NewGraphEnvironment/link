#!/usr/bin/env bash
# province_clean.sh — wipe link-pipeline state on all hosts to a known-clean
# baseline. Idempotent. Runs in <5 min wall on a healthy cluster.
#
# What it cleans:
#   1. Kills any in-flight dispatch (Rscript / cypher_run.sh / ssh tunnels)
#   2. Drops all `working_<wsg>` schemas everywhere (orphans from killed runs)
#   3. Drops all `fresh_<bundle>` schemas (legacy bundle outputs like
#      `fresh_default`, `fresh_default_extrabreaks`)
#   4. DROP SCHEMA fresh CASCADE — pipeline output + modelled_stream_crossings
#   5. Re-runs `snapshot_bcfp.sh --force` to reload fresh.modelled_stream_crossings
#      (and re-stamps the bcfp baseline ledger)
#
# What it preserves:
#   - whse_basemapping (the expensive fwa dump)
#   - bcfishobs, cabd, whse_fish (today's loaded primitives — refreshed by
#     snapshot_bcfp.sh on its next run anyway)
#   - bcfishpass_ref (reference data; not pipeline output)
#
# Usage:
#   bash data-raw/province_clean.sh [--cy-workspaces=job1,job2,job3] [--skip-m1] [--skip-cy]
#
# Honors /tmp/cy_ips.env if present (set by trifecta_provincial.sh dispatch
# wrapper). Otherwise derives cypher IPs from tofu state.
#
# Expected wall: ~2-3 min (parallel across all hosts).

set -euo pipefail

CY_WORKSPACES="job1,job2,job3"
SKIP_M1=0
SKIP_CY=0
for arg in "$@"; do
  case "$arg" in
    --cy-workspaces=*) CY_WORKSPACES="${arg#--cy-workspaces=}" ;;
    --skip-m1)         SKIP_M1=1 ;;
    --skip-cy)         SKIP_CY=1 ;;
    *) echo "FATAL: unknown arg: $arg" >&2; exit 1 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Resolve cypher IPs ---
declare -A CY_IPS
if [ "$SKIP_CY" = "0" ]; then
  IFS=',' read -ra WS_ARR <<< "$CY_WORKSPACES"
  for WS in "${WS_ARR[@]}"; do
    IP=$(cd ~/Projects/repo/rtj/env/do/dev/cypher && TF_WORKSPACE="$WS" tofu output -raw droplet_ip 2>/dev/null) || {
      echo "WARN: no cypher in workspace $WS — skipping"
      continue
    }
    CY_IPS[$WS]="$IP"
  done
fi

echo "=== province_clean.sh starting $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo "  hosts: M4 + $([ "$SKIP_M1" = "0" ] && echo "M1 + ")$([ "$SKIP_CY" = "0" ] && echo "${#CY_IPS[@]} cyphers" || echo "no cyphers")"

# --- Step 1: kill in-flight processes ---
echo "--- step 1: kill in-flight dispatch ---"
ps -ef | grep -E "trifecta_provincial|cypher_run|run_provincial_parity|ssh.*cypher@|ssh.*-R.*m1|consolidate_schema" \
  | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true
sleep 2
[ "$SKIP_M1" = "0" ] && ssh m1 'pkill -9 -f "Rscript.*run_provincial" 2>/dev/null' 2>&1 || true
if [ "$SKIP_CY" = "0" ]; then
  for WS in "${!CY_IPS[@]}"; do
    IP="${CY_IPS[$WS]}"
    ssh "cypher@$IP" 'pkill -9 -f Rscript 2>/dev/null; pkill -9 -f "ssh.*db_newgraph" 2>/dev/null' 2>&1 || true
  done
fi
echo "  ✓ killed"

# --- Step 2-4: drop stale schemas + fresh, parallel across hosts ---
# Combined DROP block: drops working_*, fresh_<bundle>*, AND fresh itself.
DROP_SQL="SELECT 'DROP SCHEMA \"' || schema_name || '\" CASCADE' FROM information_schema.schemata WHERE (schema_name LIKE 'working%' OR schema_name LIKE 'fresh_%' OR schema_name = 'fresh') AND schema_name NOT IN ('bcfishpass_ref') \\gexec
CREATE SCHEMA fresh;"

echo "--- step 2-4: drop stale schemas + recreate fresh, parallel ---"

(
  PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres -d fwapg <<EOF > "/tmp/clean_m4.log" 2>&1
$DROP_SQL
EOF
) &

if [ "$SKIP_M1" = "0" ]; then
  (
    ssh m1 'docker exec -i fresh-db psql -U postgres -d fwapg' <<EOF > "/tmp/clean_m1.log" 2>&1
$DROP_SQL
EOF
  ) &
fi

if [ "$SKIP_CY" = "0" ]; then
  for WS in "${!CY_IPS[@]}"; do
    IP="${CY_IPS[$WS]}"
    (
      ssh "cypher@$IP" 'docker exec -i fresh-db psql -U postgres -d fwapg' <<EOF > "/tmp/clean_$WS.log" 2>&1
$DROP_SQL
EOF
    ) &
  done
fi

wait
echo "  ✓ schemas dropped + fresh recreated empty"

# --- Step 5: reload modelled_stream_crossings via snapshot_bcfp.sh --force ---
echo "--- step 5: snapshot_bcfp.sh --force on all hosts ---"

(
  cd "$REPO_ROOT" && PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg \
    bash data-raw/snapshot_bcfp.sh --force > "/tmp/snap_m4.log" 2>&1
) &

if [ "$SKIP_M1" = "0" ]; then
  (
    ssh m1 'export PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg && \
            cd ~/Projects/repo/link && bash data-raw/snapshot_bcfp.sh --force' > "/tmp/snap_m1.log" 2>&1
  ) &
fi

if [ "$SKIP_CY" = "0" ]; then
  for WS in "${!CY_IPS[@]}"; do
    IP="${CY_IPS[$WS]}"
    (
      ssh "cypher@$IP" "cd ~/Projects/repo/link && \
        export PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg && \
        bash data-raw/snapshot_bcfp.sh --force" > "/tmp/snap_$WS.log" 2>&1
    ) &
  done
fi

wait
echo "  ✓ snapshot reloaded"

# --- Verify ---
echo "--- verify: fresh.modelled_stream_crossings + zero stale schemas ---"

verify_host() {
  local label="$1" cmd="$2"
  local n_msc=$(eval "$cmd -At -c \"SELECT count(*) FROM fresh.modelled_stream_crossings\"" 2>/dev/null)
  local n_stale=$(eval "$cmd -At -c \"SELECT count(*) FROM information_schema.schemata WHERE schema_name LIKE 'working%' OR schema_name LIKE 'fresh_%' AND schema_name NOT IN ('fresh','bcfishpass_ref')\"" 2>/dev/null)
  printf "  %-12s msc=%-8s stale_schemas=%s\n" "$label" "$n_msc" "$n_stale"
}

verify_host "M4" "PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres -d fwapg"
[ "$SKIP_M1" = "0" ] && verify_host "M1" "ssh m1 docker exec fresh-db psql -U postgres -d fwapg"
if [ "$SKIP_CY" = "0" ]; then
  for WS in "${!CY_IPS[@]}"; do
    IP="${CY_IPS[$WS]}"
    verify_host "cy[$WS]" "ssh cypher@$IP docker exec fresh-db psql -U postgres -d fwapg"
  done
fi

echo "=== province_clean.sh complete $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
