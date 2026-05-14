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
#   bash data-raw/province_clean.sh [flags]
#
# Flags:
#   --cy-workspaces=A,B,C  cypher workspaces to clean (default: job1,job2,job3)
#   --skip-m1              skip M1
#   --skip-cy              skip all cyphers
#   --schemas=A,B,C        SCOPED MODE — drop ONLY these exact schemas.
#                          Skips the working*/fresh_*/fresh heuristic AND
#                          skips the snapshot_bcfp.sh re-run (canonical state
#                          not touched). Use for per-bundle pre-cleans like
#                          `--schemas=fresh_default` before subset dispatches.
#
# Honors /tmp/cy_ips.env if present (set by trifecta_provincial.sh dispatch
# wrapper). Otherwise derives cypher IPs from tofu state.
#
# Expected wall:
#   Full mode (default):  ~2-3 min (drop + snapshot reload, parallel)
#   Scoped (--schemas=):  ~10-20 s   (drop only)

set -euo pipefail

CY_WORKSPACES="job1,job2,job3"
SKIP_M1=0
SKIP_CY=0
SCOPED_SCHEMAS=""
SAW_SCHEMAS=0
for arg in "$@"; do
  case "$arg" in
    --cy-workspaces=*) CY_WORKSPACES="${arg#--cy-workspaces=}" ;;
    --skip-m1)         SKIP_M1=1 ;;
    --skip-cy)         SKIP_CY=1 ;;
    --schemas=*)       SCOPED_SCHEMAS="${arg#--schemas=}"; SAW_SCHEMAS=1 ;;
    *) echo "FATAL: unknown arg: $arg" >&2; exit 1 ;;
  esac
done

# Guard against empty `--schemas=` falling through to the destructive
# heuristic full-wipe. Callers that build the arg dynamically and end
# up with an empty value need to know — silently wiping `fresh` is the
# wrong default for "the operator forgot to populate $VAR".
if [ "$SAW_SCHEMAS" = "1" ] && [ -z "$SCOPED_SCHEMAS" ]; then
  echo "FATAL: --schemas= requires at least one schema (got empty value)." >&2
  echo "       Omit --schemas= entirely to invoke the heuristic full-wipe mode." >&2
  exit 1
fi

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

# --- Step 2-4: drop stale schemas, parallel across hosts ---
# Default (heuristic) mode: drops working_*, fresh_<bundle>*, AND fresh
# itself; recreates empty `fresh`.
#
# Scoped mode (--schemas=A,B,C): drops ONLY the listed exact schemas;
# does NOT recreate `fresh`. Use for per-bundle pre-cleans before subset
# dispatches (e.g. --schemas=fresh_default).
if [ -n "$SCOPED_SCHEMAS" ]; then
  # Build a literal IN-list of schema names, double-quoted for safety.
  SCOPED_IN=$(echo "$SCOPED_SCHEMAS" | awk -F',' '{
    for(i=1;i<=NF;i++) {
      gsub(/^[ \t]+|[ \t]+$/, "", $i)
      printf("%s\047%s\047", (i==1?"":","), $i)
    }
  }')
  DROP_SQL="SELECT 'DROP SCHEMA \"' || schema_name || '\" CASCADE' FROM information_schema.schemata WHERE schema_name IN ($SCOPED_IN) \\gexec"
  echo "--- step 2-4 (scoped): drop schemas [$SCOPED_SCHEMAS], parallel ---"
else
  DROP_SQL="SELECT 'DROP SCHEMA \"' || schema_name || '\" CASCADE' FROM information_schema.schemata WHERE (schema_name LIKE 'working%' OR schema_name LIKE 'fresh_%' OR schema_name = 'fresh') AND schema_name NOT IN ('bcfishpass_ref') \\gexec
CREATE SCHEMA fresh;"
  echo "--- step 2-4: drop stale schemas + recreate fresh, parallel ---"
fi

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
# Skipped under --schemas= (scoped mode): canonical fresh schema wasn't
# touched, so modelled_stream_crossings is still present.
if [ -n "$SCOPED_SCHEMAS" ]; then
  echo "--- step 5: SKIPPED (scoped mode — canonical fresh untouched) ---"
  echo
  echo "=== province_clean.sh complete (scoped: [$SCOPED_SCHEMAS]) $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
  exit 0
fi

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
