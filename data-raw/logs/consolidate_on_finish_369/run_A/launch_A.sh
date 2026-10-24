#!/usr/bin/env bash
# launch_A.sh — link#369 Run A, exactly as launched: per-host consolidate and
# burn on real droplets. Small groups (2026-10-23 minutes) so job1 (one group)
# ends first, job2 (five) second, and the dispatcher (twelve) last; every group
# passes the downstream-dam guard against an empty schema. Scratch schema, so
# fresh_default is untouched. Run DETACHED from the 369-run worktree:
#
#   nohup /opt/homebrew/bin/bash data-raw/logs/consolidate_on_finish_369/launch_A.sh \
#     > data-raw/logs/consolidate_on_finish_369/run_A.log 2>&1 & disown
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
date -u > data-raw/logs/consolidate_on_finish_369/run_A.started
exec "$BASH" data-raw/study_area_run.sh \
  --cy-workspaces=job1,job2 \
  --buckets-exact \
  --focal=MUSK,LNRS,LSAL,UTRE,SALR,CHES,MIDR,EUCH,EUCL,SAHD,TSEA,UPET \
  --focal=NBNK \
  --focal=MBNK,KEEC,KAKC,PITR,VICT \
  --config=default --schema=fresh_smoke369 \
  --run-label=smoke-369-A
