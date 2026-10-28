#!/usr/bin/env bash
# run.sh — the #406 measurement: one variants build per width, each followed by
# its digests. Run from the repo root; builds run from the worktree $WT.
#   bash data-raw/logs/variants_parallel_406/run.sh <worktree>
set -euo pipefail
WT="${1:?usage: run.sh <worktree>}"
REPO="$(pwd)"
D="$REPO/data-raw/logs/variants_parallel_406"
B="$REPO/data-raw/logs/variant_cost_404"
[ -f "$WT/data-raw/habitat_variants_build.R" ] || { echo "no build script under $WT"; exit 1; }
state() {
  {
    echo "== $1 $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    uptime
    psql "postgresql://postgres:postgres@localhost:5432/fwapg" -At -c \
      "SELECT pid, application_name, state FROM pg_stat_activity
        WHERE backend_type = 'client backend' AND pid <> pg_backend_pid()"
    echo "(end of list)"
  } >> "$D/launch_state.txt"
}
for j in 1 2 4 8; do
  out="$D/j$j"
  mkdir -p "$out"
  cp "$B/base_habitat_digest.csv" "$B/closure.txt" "$out/"
  state "launch --jobs=$j"
  ( cd "$WT" && Rscript data-raw/habitat_variants_build.R --step=variants \
      --prefix=score404_ --variants=data-raw/habitat_score/variants_331.csv \
      --roles=data-raw/habitat_score/wsg_roles_331.csv --only=bt_rear_wet_p10 \
      --out="$out" --jobs="$j" ) > "$out/build.log" 2>&1
  state "exited --jobs=$j"
  Rscript "$D/digest.R" "$D/digests_j$j.csv"
done
state "end"
echo "RUN406 DONE"
