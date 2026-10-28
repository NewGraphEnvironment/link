#!/usr/bin/env bash
# pretest_run.sh — the pre-run gate (link#372). Run on the dispatcher before a
# provincial run: it models the groups that stress each input the code changed
# since the last run drives, and refuses the launch when one fails or takes
# more than k times its last-run minutes. study_area_run.sh's pre-flight reads
# the record it writes (RUNBOOK §8d, "The pre-run gate").
#
#   bash data-raw/pretest_run.sh --config=default --schema=fresh_default \
#     [--since=<sha>] [--until=HEAD] [--per-input=2] [--k=3] [--floor-min=5] \
#     [--statement-timeout=30] [--minutes-schema=<schema>] \
#     [--minutes-exclude=KTSU,...] [--fresh-repo=<fresh checkout>] \
#     [--out=<dir>] [--pick-only] [--only=<WSG>,...]
#
# --only=<WSG>,... models only those of the picks (a smoke test of the
# machinery, or a re-check of one group); its record is never a pass.
#
# What it does, in order:
#   1. pretest_pick.R: the changed files (link since..until, fresh between the
#      two DESCRIPTION pins), the input each one drives (pretest_inputs.csv),
#      the groups at each input's extreme, each group's bound. An unmapped
#      changed file refuses (exit 2). --pick-only stops here, writing nothing
#      to the database.
#   2. A scratch schema, fresh_pretest_<config>, dropped and rebuilt with the
#      persist schema's tables (columns, defaults, indexes, primary keys) and
#      no rows, so the run's DDL meets the tables as they exist rather than
#      creating them fresh.
#   3. Each pick modelled one at a time through wsg_run_one.R, as a run's
#      dispatcher leg would (LNK_LOAD=loadall, LNK_GUARD_DOWNSTREAM=warn,
#      LNK_HABITAT_GATE=0), under a statement bound and a wall-clock bound,
#      both from the group's bound. A group past its wall-clock bound is
#      killed and its backends terminated.
#   4. pretest_verdict.R: each group's minutes from the scratch log, the
#      verdict table, one row in <schema>.log_pretest.
#
# Exit 0 pass, 1 a group failed or breached its bound, 2 refused.
#
# It is not a parity or correctness test (the variants harness and
# habitat_validate.R keep that job), and it does not run the recompute or the
# consolidate: a changed file on those paths is named as unexercised.
set -euo pipefail

if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 5 ] ||
   { [ "${BASH_VERSINFO[0]}" -eq 5 ] && [ "${BASH_VERSINFO[1]}" -lt 1 ]; }; then
  echo "REFUSED: bash >= 5.1 required (this is ${BASH_VERSION:-unknown})" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="" SCHEMA="" SINCE="" UNTIL="HEAD" PER_INPUT=2 K=3 FLOOR_MIN=5 STMT=30
MINUTES_SCHEMA="" MINUTES_EXCLUDE="" FRESH_REPO="" OUT="" PICK_ONLY=0 ONLY=""
for arg in "$@"; do
  case "$arg" in
    --config=*)            CONFIG="${arg#*=}" ;;
    --schema=*)            SCHEMA="${arg#*=}" ;;
    --since=*)             SINCE="${arg#*=}" ;;
    --until=*)             UNTIL="${arg#*=}" ;;
    --per-input=*)         PER_INPUT="${arg#*=}" ;;
    --k=*)                 K="${arg#*=}" ;;
    --floor-min=*)         FLOOR_MIN="${arg#*=}" ;;
    --statement-timeout=*) STMT="${arg#*=}" ;;
    --minutes-schema=*)    MINUTES_SCHEMA="${arg#*=}" ;;
    --minutes-exclude=*)   MINUTES_EXCLUDE="${arg#*=}" ;;
    --fresh-repo=*)        FRESH_REPO="${arg#*=}" ;;
    --out=*)               OUT="${arg#*=}" ;;
    --pick-only)           PICK_ONLY=1 ;;
    --only=*)              ONLY="${arg#*=}" ;;
    *) echo "REFUSED: unknown argument $arg" >&2; exit 2 ;;
  esac
done
[ -n "$CONFIG" ] && [ -n "$SCHEMA" ] || { echo "REFUSED: --config= and --schema= are required (no defaults: state the run's)" >&2; exit 2; }
[[ "$CONFIG" =~ ^[a-z][a-z0-9_]*$ ]] || { echo "REFUSED: bad --config '$CONFIG'" >&2; exit 2; }
[[ "$SCHEMA" =~ ^[a-z_][a-z0-9_]*$ ]] || { echo "REFUSED: bad --schema '$SCHEMA'" >&2; exit 2; }
SCRATCH="fresh_pretest_${CONFIG}"
[ "$SCRATCH" != "$SCHEMA" ] || { echo "REFUSED: --schema is the scratch schema $SCRATCH" >&2; exit 2; }
[ -n "$MINUTES_SCHEMA" ] || MINUTES_SCHEMA="$SCHEMA"
TS="$(date -u +%Y%m%d_%H%M%S)"
[ -n "$OUT" ] || OUT="$REPO_ROOT/data-raw/logs/pretest/${TS}_${CONFIG}"
mkdir -p "$OUT"

psql_q() { PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres -d fwapg -X -q -v ON_ERROR_STOP=1 -t -A "$@"; }

echo "=== pre-run gate (link#372) ==="
echo "  config:          $CONFIG"
echo "  history schema:  $SCHEMA (minutes from $MINUTES_SCHEMA${MINUTES_EXCLUDE:+, excluding $MINUTES_EXCLUDE})"
echo "  scratch schema:  $SCRATCH (dropped and rebuilt)"
echo "  range:           ${SINCE:-<earliest newest build in $SCHEMA.log>}..$UNTIL"
echo "  bound:           ${K} x last minutes, floor ${FLOOR_MIN} min; statements <= ${STMT} min"
echo "  out:             $OUT"
[ "$PICK_ONLY" = 1 ] && echo "  mode:            pick only (nothing modelled, nothing recorded)"
[ -z "$ONLY" ] || echo "  SUBSET:          only $ONLY of the picks; the record cannot pass"
[ -z "${LNK_TEST_STALL_WSG:-}" ] || echo "  TEST HOOK:       LNK_TEST_STALL_WSG=$LNK_TEST_STALL_WSG"

if [ "$PICK_ONLY" = 0 ]; then
  # The record states the code a run will use, so the tree must be what was
  # committed (data-raw/logs excluded, as study_area_run.sh does: the gate
  # writes its own output there).
  dirty=$(git -C "$REPO_ROOT" status --porcelain -- ':(top,exclude)data-raw/logs') \
    || { echo "REFUSED: git status failed" >&2; exit 2; }
  [ -z "$dirty" ] || { echo "REFUSED: the checkout is dirty; commit first (or --pick-only)" >&2; printf '%s\n' "$dirty" >&2; exit 2; }
  pg_isready -h localhost -p 5432 >/dev/null 2>&1 || { echo "REFUSED: local fwapg down" >&2; exit 2; }
fi

pick_args=(--config="$CONFIG" --schema="$SCHEMA" --out="$OUT" --until="$UNTIL"
           --per-input="$PER_INPUT" --k="$K" --floor-min="$FLOOR_MIN"
           --statement-timeout="$STMT" --minutes-schema="$MINUTES_SCHEMA")
[ -z "$SINCE" ] || pick_args+=(--since="$SINCE")
[ -z "$MINUTES_EXCLUDE" ] || pick_args+=(--minutes-exclude="$MINUTES_EXCLUDE")
[ -z "$FRESH_REPO" ] || pick_args+=(--fresh-repo="$FRESH_REPO")
prc=0
(cd "$REPO_ROOT" && Rscript data-raw/pretest_pick.R "${pick_args[@]}") || prc=$?
[ "$prc" = 0 ] || { echo "pick exited $prc"; exit "$prc"; }
[ "$PICK_ONLY" = 0 ] || { echo "pick only: $OUT/pretest.md"; exit 0; }

# The record must describe the code being modelled.
until_sha=$(sed -n 2p "$OUT/range.txt")
head_sha=$(git -C "$REPO_ROOT" rev-parse HEAD)
[ "$until_sha" = "$head_sha" ] || {
  echo "REFUSED: --until resolves to ${until_sha:0:12}, but HEAD (what would be modelled) is ${head_sha:0:12}; use --pick-only for another range" >&2
  exit 2
}

# Picks as rows: wsg inputs minutes host bound statement_min
mapfile -t PICKS < <(tail -n +2 "$OUT/picks.tsv")
if [ -n "$ONLY" ]; then
  [[ "$ONLY" =~ ^[A-Z]{4}(,[A-Z]{4})*$ ]] || { echo "REFUSED: --only takes group codes" >&2; exit 2; }
  kept=()
  for row in "${PICKS[@]}"; do
    case ",$ONLY," in *",${row%%$'\t'*},"*) kept+=("$row") ;; esac
  done
  [ "${#kept[@]}" -gt 0 ] || { echo "REFUSED: none of --only=$ONLY was picked" >&2; exit 2; }
  PICKS=("${kept[@]}")
  { head -1 "$OUT/picks.tsv"; printf '%s\n' "${PICKS[@]}"; } > "$OUT/picks.tsv.only"
  mv "$OUT/picks.tsv.only" "$OUT/picks.tsv"
fi

# A run or recompute in flight would share working_<wsg> and the database
# with the gate: refuse rather than corrupt it or time against it.
busy=$(psql_q -c "SELECT count(*) FROM pg_stat_activity
                   WHERE pid <> pg_backend_pid() AND state <> 'idle'
                     AND (query ILIKE '%${SCHEMA}.%' OR query ILIKE '%working\\_%')")
[ "$busy" = 0 ] || { echo "REFUSED: $busy active session(s) on $SCHEMA or a working schema; a run looks live" >&2; exit 2; }

if [ "${#PICKS[@]}" -gt 0 ]; then
  echo "=== scratch schema $SCRATCH (tables of $SCHEMA, no rows) ==="
  psql_q <<SQL
DROP SCHEMA IF EXISTS ${SCRATCH} CASCADE;
CREATE SCHEMA ${SCRATCH};
DO \$\$
DECLARE t record; i record;
BEGIN
  FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = '${SCHEMA}' AND c.relkind = 'r' AND c.relname <> 'log_pretest' LOOP
    EXECUTE format('CREATE TABLE ${SCRATCH}.%I (LIKE ${SCHEMA}.%I INCLUDING DEFAULTS INCLUDING GENERATED INCLUDING IDENTITY)',
                   t.relname, t.relname);
  END LOOP;
  -- Indexes under their own names (persist_init and the log find them by
  -- name), and primary keys rebuilt on theirs.
  FOR i IN SELECT ix.indexrelid, ic.relname AS idx, tc.relname AS tbl, pg_get_indexdef(ix.indexrelid) AS def,
                  con.conname, con.contype
             FROM pg_index ix
             JOIN pg_class ic ON ic.oid = ix.indexrelid
             JOIN pg_class tc ON tc.oid = ix.indrelid
             JOIN pg_namespace n ON n.oid = tc.relnamespace
             LEFT JOIN pg_constraint con ON con.conindid = ix.indexrelid AND con.contype IN ('p', 'u')
            WHERE n.nspname = '${SCHEMA}' AND tc.relkind = 'r' AND tc.relname <> 'log_pretest' LOOP
    EXECUTE replace(i.def, ' ON ${SCHEMA}.', ' ON ${SCRATCH}.');
    IF i.contype = 'p' THEN
      EXECUTE format('ALTER TABLE ${SCRATCH}.%I ADD CONSTRAINT %I PRIMARY KEY USING INDEX %I', i.tbl, i.conname, i.idx);
    ELSIF i.contype = 'u' THEN
      EXECUTE format('ALTER TABLE ${SCRATCH}.%I ADD CONSTRAINT %I UNIQUE USING INDEX %I', i.tbl, i.conname, i.idx);
    END IF;
  END LOOP;
END
\$\$;
SQL
  echo "  $(psql_q -c "SELECT count(*) FROM pg_tables WHERE schemaname = '${SCRATCH}'") tables, $(psql_q -c "SELECT count(*) FROM pg_indexes WHERE schemaname = '${SCRATCH}'") indexes"
fi

: > "$OUT/exits.tsv"
for row in "${PICKS[@]}"; do
  IFS=$'\t' read -r wsg inputs minutes host bound smin <<<"$row"
  bound_s=$(awk -v b="$bound" 'BEGIN { printf "%d", (b * 60 == int(b * 60)) ? b * 60 : int(b * 60) + 1 }')
  app="pretest_${wsg}"
  echo "=== $wsg [$inputs] last ${minutes} min on $host; bound ${bound} min, statements ${smin} min ==="
  (
    cd "$REPO_ROOT"
    PGOPTIONS="${PGOPTIONS:-} -c statement_timeout=${smin}min" \
    LNK_STATEMENT_TIMEOUT_MIN="$smin" PGAPPNAME="$app" \
    LNK_SCHEMA="$SCRATCH" LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=warn LNK_HABITAT_GATE=0 \
    LNK_RUN_LABEL="pretest" exec Rscript data-raw/wsg_run_one.R "$wsg" "$CONFIG"
  ) > "$OUT/${wsg}.log" 2>&1 &
  pid=$!
  t0=$(date +%s)
  killed=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ $(( $(date +%s) - t0 )) -ge "$bound_s" ]; then
      echo "  past ${bound} min: killing $wsg"
      kill "$pid" 2>/dev/null || true
      # Killing R leaves its backend running; end it by its application name.
      psql_q -c "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE application_name = '${app}'" >/dev/null || true
      killed=1
      break
    fi
    sleep 2
  done
  rc=0
  wait "$pid" || rc=$?
  [ "$killed" = 0 ] || rc=124
  printf '%s\t%s\n' "$wsg" "$rc" >> "$OUT/exits.tsv"
  LC_ALL=C grep -aE "TIMEOUT|done in|Error" "$OUT/${wsg}.log" | tail -3 | sed 's/^/  /' || true
  echo "  exit $rc after $(( $(date +%s) - t0 )) s"
done

notes=""
if [ -s "$OUT/unexercised.txt" ]; then
  notes="${notes:+$notes; }unexercised: $(paste -sd, "$OUT/unexercised.txt")"
fi
vrc=0
(cd "$REPO_ROOT" && Rscript data-raw/pretest_verdict.R --out="$OUT" --schema="$SCHEMA" \
   --scratch="$SCRATCH" --config="$CONFIG" --k="$K" --floor-min="$FLOOR_MIN" \
   --per-input="$PER_INPUT" --notes="$notes" ${ONLY:+--subset}) || vrc=$?
echo "report: $OUT/pretest.md"
exit "$vrc"
