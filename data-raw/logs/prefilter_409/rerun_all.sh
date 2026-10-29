#!/usr/bin/env bash
# rerun_all.sh — link#409 Phase 2: each group's recompute four times on the
# dispatcher's fresh_default, b1 a1 a2 b2 (b = fresh v0.44.0 from the shared
# library, or from LIB044 when set; a = v0.46.0 put first by R_LIBS), so cache
# warmth favours neither.
# Runs a frozen copy of rerun.R from a worktree at the commit that wrote the
# rows. Before each run it waits (up to WAIT_MIN) for QUIET_S seconds with no
# other active client and no other lock in fresh_default;
# it records the input tables' write counters before and after; it stops at
# the first run that does not end UNCHANGED.
#   HOST=<dispatcher> WT=<worktree> LIB046=<lib> RERUN=<frozen rerun.R> \
#     OUT=<dir> [LIB044=<lib holding fresh 0.44.0>] [RESUME=<WSG>:<label>] \
#     bash rerun_all.sh SALR LKEL ...
set -uo pipefail
: "${HOST:?}" "${WT:?}" "${LIB046:?}" "${RERUN:?}" "${OUT:?}"
WAIT_MIN=${WAIT_MIN:-60}
QUIET_S=${QUIET_S:-300}
[ "$#" -gt 0 ] || { echo "no groups" >&2; exit 2; }
mkdir -p "$OUT"
q() { PGPASSWORD=postgres psql -h "$HOST" -U postgres -d fwapg -X -At -F$'\t' "$@"; }
# Quiet means no other active client and no other backend holding a lock in
# fresh_default: autovacuum, set off by these runs' own rewrites, is not a
# client but rerun.R refuses on its lock, and its I/O would land in a timing.
others() { q -c "SELECT (SELECT count(*) FROM pg_stat_activity WHERE datname = 'fwapg' AND state <> 'idle'
                   AND backend_type = 'client backend' AND pid <> pg_backend_pid())
               + (SELECT count(*) FROM pg_locks l JOIN pg_class c ON c.oid = l.relation
                   JOIN pg_namespace s ON s.oid = c.relnamespace
                   WHERE s.nspname = 'fresh_default' AND l.pid <> pg_backend_pid())"; }
counters() { # <tag>
  q -c "SELECT '$1', relname, n_tup_ins, n_tup_upd, n_tup_del FROM pg_stat_user_tables
        WHERE schemaname = 'fresh_default' AND relname IN ('streams', 'barriers') ORDER BY relname" \
    >> "$OUT/input_counters.tsv"
}
# RESUME=<WSG>:<label> skips every run before that one (a restart after a
# refusal keeps the runs that finished).
RESUME=${RESUME:-}
counters before
for w in "$@"; do
  for label in b1 a1 a2 b2; do
    if [ -n "$RESUME" ]; then
      [ "$w:$label" = "$RESUME" ] || continue
      RESUME=""
    fi
    # Quiet for QUIET_S seconds running, sampled every 15 s: a session that
    # runs walks back to back leaves gaps of seconds, and a run started in one
    # was refused at its own lock check (SETN a2, 2026-10-29).
    waited=0; quiet=0
    while [ "$quiet" -lt "$QUIET_S" ]; do
      [ "$waited" -ge $((WAIT_MIN * 60)) ] && { echo "$(date -u +%TZ) $w $label not quiet after $WAIT_MIN min; stopping" >> "$OUT/status.txt"; exit 3; }
      if [ "$(others)" = "0" ]; then quiet=$((quiet + 15)); else quiet=0; fi
      sleep 15; waited=$((waited + 15))
    done
    lib="${LIB044:-}"; [ "${label:0:1}" = a ] && lib="$LIB046"
    # Keep an earlier attempt's log (a refusal) rather than overwrite it.
    log="$OUT/rerun_${w}_${label}.log"
    n=1; while [ -e "$log" ] && [ -e "$OUT/rerun_${w}_${label}_refused${n}.log" ]; do n=$((n + 1)); done
    [ -e "$log" ] && mv "$log" "$OUT/rerun_${w}_${label}_refused${n}.log"
    t0=$SECONDS
    ( cd "$WT" && LNK_MEASURE_HOST="$HOST" R_LIBS="$lib" Rscript "$RERUN" "$w" "$OUT" "$label" ) > "$log" 2>&1
    r=$?
    echo "$(date -u +%TZ) $w $label exit $r $((SECONDS - t0)) s waited ${waited} s" >> "$OUT/status.txt"
    grep -q "digests UNCHANGED" "$log" && [ "$r" -eq 0 ] \
      || { echo "STOP: $w $label did not end UNCHANGED (exit $r)" >> "$OUT/status.txt"; counters stopped; exit 1; }
  done
done
# A RESUME that matched no run skipped everything: say so rather than ALLDONE.
[ -z "$RESUME" ] || { echo "RESUME=$RESUME matched no run; nothing ran" >> "$OUT/status.txt"; exit 2; }
counters after
echo "ALLDONE $(date -u +%FT%TZ)" >> "$OUT/status.txt"
