#!/usr/bin/env bash
# pretest_history_load.sh — copy a host's <schema>.log into a named local schema,
# for a pre-run gate that borrows history (--history-schema, RUNBOOK §8d, "The
# pre-run gate"). The history a provincial run leaves sits on the host that
# consolidated it, and the gate runs on the dispatcher of the next run, which may
# be another machine.
#
#   bash data-raw/pretest_history_load.sh --host=<ssh target> --from=fresh_default \
#     --to=fresh_default_history [--container=fresh-db]
#
# pg_dump -t, so the table's primary key and indexes come with it. The target holds
# only this table: a schema holding anything else is refused, so a real build's log
# cannot be replaced. Exit 0 loaded, 1 the copy failed, 2 refused.
#
# ssh's exit status says nothing here: Tailscale SSH to a Mac exits 0 whatever ran.
# So the dump must end on pg_dump's own trailer, and hold the row count the host
# reports, before anything local changes.
set -euo pipefail

HOST="" FROM="" TO="" CONTAINER="fresh-db"
for arg in "$@"; do
  case "$arg" in
    --host=*)      HOST="${arg#*=}" ;;
    --from=*)      FROM="${arg#*=}" ;;
    --to=*)        TO="${arg#*=}" ;;
    --container=*) CONTAINER="${arg#*=}" ;;
    *) echo "REFUSED: unknown argument $arg" >&2; exit 2 ;;
  esac
done
[ -n "$HOST" ] && [ -n "$FROM" ] && [ -n "$TO" ] \
  || { echo "REFUSED: --host=, --from= and --to= are required" >&2; exit 2; }
for s in "$FROM" "$TO"; do
  [[ "$s" =~ ^[a-z_][a-z0-9_]*$ ]] || { echo "REFUSED: bad schema name '$s'" >&2; exit 2; }
done
[[ "$CONTAINER" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "REFUSED: bad --container '$CONTAINER'" >&2; exit 2; }
[ "$FROM" != "$TO" ] || { echo "REFUSED: --from and --to name one schema; a borrowed history has its own" >&2; exit 2; }

psql_q() { PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres -d fwapg -X -q -v ON_ERROR_STOP=1 -t -A "$@"; }

others=$(psql_q -c "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = '$TO' AND c.relkind IN ('r', 'p', 'v', 'm', 'f') AND c.relname <> 'log'")
[[ "$others" =~ ^[0-9]+$ ]] || { echo "REFUSED: could not read local schema $TO" >&2; exit 2; }
[ "$others" -eq 0 ] || { echo "REFUSED: $TO holds $others other table(s) or view(s): it is not a history schema" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pretest_history.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

n_host=$(ssh "$HOST" "docker exec $CONTAINER psql -U postgres -d fwapg -XAtc 'SELECT count(*) FROM $FROM.log'" 2>"$TMP/count.err") || true
[[ "$n_host" =~ ^[0-9]+$ ]] && [ "$n_host" -gt 0 ] \
  || { echo "FAILED: $HOST did not report rows in $FROM.log (got '$n_host'): $(cat "$TMP/count.err")" >&2; exit 1; }

ssh "$HOST" "docker exec $CONTAINER pg_dump -U postgres -d fwapg -t $FROM.log --no-owner --no-privileges" \
  >"$TMP/dump.sql" 2>"$TMP/dump.err" || true
grep -q '^-- PostgreSQL database dump complete' "$TMP/dump.sql" \
  || { echo "FAILED: the dump from $HOST did not complete: $(cat "$TMP/dump.err")" >&2; exit 1; }

# The schema is renamed everywhere but in the rows, whose notes may quote it.
awk -v from="$FROM" -v to="$TO" -v rows="$TMP/rows" '
  in_copy { if ($0 == "\\.") { in_copy = 0; print; next } n++; print; next }
  { gsub(from "\\.", to "."); print }
  /^COPY / { in_copy = 1 }
  END { print n + 0 > rows }
' "$TMP/dump.sql" >"$TMP/load.sql"
n_dump=$(cat "$TMP/rows")
[ "$n_dump" -eq "$n_host" ] \
  || { echo "FAILED: the dump holds $n_dump rows; $HOST reports $n_host" >&2; exit 1; }

{
  echo "CREATE SCHEMA IF NOT EXISTS $TO;"
  echo "DROP TABLE IF EXISTS $TO.log;"
  cat "$TMP/load.sql"
  echo "COMMENT ON SCHEMA $TO IS 'history only: $FROM.log copied from another host by pretest_history_load.sh, $(date -u +%Y-%m-%dT%H:%MZ)';"
} >"$TMP/all.sql"
psql_q -1 -f "$TMP/all.sql" >/dev/null

n_local=$(psql_q -c "SELECT count(*) FROM $TO.log")
[ "$n_local" -eq "$n_host" ] \
  || { echo "FAILED: $TO.log holds $n_local rows; $HOST reports $n_host" >&2; exit 1; }
echo "=== $TO.log: $n_local rows copied from $FROM.log on $HOST"
psql_q -F ' ' -c "SELECT count(DISTINCT watershed_group_code) || ' groups, ' || count(DISTINCT host) || ' hosts, '
                         || count(DISTINCT link_sha) || ' link shas' FROM $TO.log"
