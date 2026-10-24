#!/usr/bin/env bash
# launch_B.sh — link#369 Run B, exactly as launched: the negative case. One
# cypher (job1: MILL, LPET) into its own scratch schema, fresh_smoke369b, where
# a future-dated log row for MILL was seeded before launch (run_id seed369b),
# so its consolidate is refused (dest_log_newer). Expected: job1 KEPT and
# listed in <TS>_kept_hosts.tsv with its burn command, the dispatcher's LNRS
# still recomputed, and a non-zero exit. Run DETACHED from the 369-run worktree:
#
#   nohup /opt/homebrew/bin/bash data-raw/logs/consolidate_on_finish_369/launch_B.sh \
#     > data-raw/logs/consolidate_on_finish_369/run_B.log 2>&1 & disown
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
date -u > data-raw/logs/consolidate_on_finish_369/run_B.started
exec "$BASH" data-raw/study_area_run.sh \
  --cy-workspaces=job1 \
  --buckets-exact \
  --focal=LNRS \
  --focal=MILL,LPET \
  --config=default --schema=fresh_smoke369b \
  --run-label=smoke-369-B
