#!/usr/bin/env bash
# rerun_all.sh — link#409 Phase 2: each group's recompute four times on the
# dispatcher's fresh_default, b1 a1 a2 b2 (b = fresh v0.44.0 from the shared
# library, a = v0.46.0 put first by R_LIBS), so cache warmth favours neither.
# Runs a frozen copy of rerun.R from a worktree at the commit that wrote the
# rows. Before each run it waits (up to WAIT_MIN) for no other active client;
# it records the input tables' write counters before and after; it stops at
# the first run that does not end UNCHANGED.
#   HOST=<dispatcher> WT=<worktree> LIB046=<lib> RERUN=<frozen rerun.R> \
#     OUT=<dir> bash rerun_all.sh SALR LKEL ...
set -uo pipefail
: "${HOST:?}" "${WT:?}" "${LIB046:?}" "${RERUN:?}" "${OUT:?}"
WAIT_MIN=${WAIT_MIN:-60}
[ "$#" -gt 0 ] || { echo "no groups" >&2; exit 2; }
mkdir -p "$OUT"
q() { PGPASSWORD=postgres psql -h "$HOST" -U postgres -d fwapg -X -At -F$'\t' "$@"; }
others() { q -c "SELECT count(*) FROM pg_stat_activity WHERE datname = 'fwapg' AND state <> 'idle'
                 AND backend_type = 'client backend' AND pid <> pg_backend_pid()"; }
counters() { # <tag>
  q -c "SELECT '$1', relname, n_tup_ins, n_tup_upd, n_tup_del FROM pg_stat_user_tables
        WHERE schemaname = 'fresh_default' AND relname IN ('streams', 'barriers') ORDER BY relname" \
    >> "$OUT/input_counters.tsv"
}
counters before
for w in "$@"; do
  for label in b1 a1 a2 b2; do
    waited=0
    until [ "$(others)" = "0" ]; do
      [ "$waited" -ge $((WAIT_MIN * 60)) ] && { echo "$(date -u +%TZ) $w $label not quiet after $WAIT_MIN min; stopping" >> "$OUT/status.txt"; exit 3; }
      sleep 30; waited=$((waited + 30))
    done
    lib=""; [ "${label:0:1}" = a ] && lib="$LIB046"
    t0=$SECONDS
    ( cd "$WT" && LNK_MEASURE_HOST="$HOST" R_LIBS="$lib" Rscript "$RERUN" "$w" "$OUT" "$label" ) > "$OUT/rerun_${w}_${label}.log" 2>&1
    r=$?
    echo "$(date -u +%TZ) $w $label exit $r $((SECONDS - t0)) s waited ${waited} s" >> "$OUT/status.txt"
    grep -q "digests UNCHANGED" "$OUT/rerun_${w}_${label}.log" && [ "$r" -eq 0 ] \
      || { echo "STOP: $w $label did not end UNCHANGED (exit $r)" >> "$OUT/status.txt"; counters stopped; exit 1; }
  done
done
counters after
echo "ALLDONE $(date -u +%FT%TZ)" >> "$OUT/status.txt"
