#!/usr/bin/env bash
# Proves each guard of #442 fires: every case runs on the code as committed (the
# guard refuses) and with that guard removed (it does not). Uses a temporary
# worktree and two scratch schemas, removed at the end. Read-only otherwise.
set -uo pipefail
REPO="$(git rev-parse --show-toplevel)"; FRESH_REPO="${FRESH_REPO:-$REPO/../fresh}"; FRESH_REPO="$(cd "$FRESH_REPO" && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/mut442.XXXXXX")"; WT="$T/wt"; git -C "$REPO" worktree add -q --detach "$WT" HEAD
export PGPASSWORD=postgres; q() { psql -h localhost -U postgres -d fwapg -X -q -v ON_ERROR_STOP=1 -Atc "$1"; }
cleanup() { git -C "$REPO" worktree remove --force "$WT"; q "DROP SCHEMA IF EXISTS zz442_dirty CASCADE; DROP SCHEMA IF EXISTS zz442_rec CASCADE"; }
trap cleanup EXIT
FRESH_SHA=$(Rscript -e 'cat(packageDescription("fresh")$RemoteSha)')
q "DROP SCHEMA IF EXISTS zz442_dirty CASCADE; CREATE SCHEMA zz442_dirty;
   CREATE TABLE zz442_dirty.log AS SELECT * FROM fresh_default_history.log;
   UPDATE zz442_dirty.log SET link_dirty = NULL WHERE watershed_group_code = 'ADMS'"
pick() { (cd "$WT" && /opt/homebrew/bin/bash data-raw/pretest_run.sh --config=default_minimal --schema=zz442_none \
    --history-schema="$1" --history-config=default --pick-only --fresh-repo="$FRESH_REPO" --out="$T/pick" ${2:+--since="$2"} 2>&1) | grep -E '^REFUSED|^WARN|^pick only|pick exited' | sed "s#$T/##" | cut -c1-150; }
check() { # the launch check, on a pass record that borrowed the 4-group history
  q "DROP SCHEMA IF EXISTS zz442_rec CASCADE; CREATE SCHEMA zz442_rec;
     CREATE TABLE zz442_rec.log_pretest (run_at timestamptz DEFAULT now(), config_name text, link_sha text, link_dirty boolean,
       fresh_sha text, since_sha text, until_sha text, scratch text, k numeric, floor_min numeric, per_input int, groups text,
       verdict text, notes text, history_schema text, history_config text);
     INSERT INTO zz442_rec.log_pretest (config_name, link_sha, link_dirty, fresh_sha, since_sha, until_sha, verdict, history_schema, history_config)
       VALUES ('default_minimal', '$(git -C "$WT" rev-parse HEAD)', false, '$FRESH_SHA', '$(git -C "$WT" rev-parse HEAD)', '$(git -C "$WT" rev-parse HEAD)', 'pass', 'fresh_default', 'default')"
  (cd "$WT" && Rscript data-raw/pretest_check.R --config=default_minimal --schema=zz442_rec --head="$(git rev-parse HEAD)" --fresh-sha="$FRESH_SHA" 2>&1; echo "exit $?") | cut -c1-150; }
mutate() { # commit, since pretest_check.R refuses a dirty checkout first
  python3 - "$WT/$1" "$2" <<'PY'
import sys
p, old = sys.argv[1:]; s = open(p).read(); assert old in s, old; open(p, 'w').write(s.replace(old, '', 1))
PY
  git -C "$WT" -c user.email=m -c user.name=m commit -qam mutation; }
restore() { git -C "$WT" reset -q --hard "$(git -C "$REPO" rev-parse HEAD)"; }
echo "## short history in the pick"; echo "as committed:"; pick fresh_default
mutate data-raw/pretest_pick.R '  if (nzchar(short)) refuse(short)'; echo "guard removed:"; pick fresh_default; restore
echo; echo "## a history no range can cover, in --pick-only"; echo "as committed:"; pick zz442_dirty 1d00c04c
mutate data-raw/pretest_pick.R 'if (nzchar(bad_history)) refuse(bad_history, "; a gate on it cannot clear a run")'; echo "guard removed:"; pick zz442_dirty 1d00c04c; restore
echo; echo "## short history in the launch check"; echo "as committed:"; check
mutate data-raw/pretest_check.R 'if (nzchar(short)) stop("the gate borrowed a short history: ", short)'; echo "guard removed:"; check; restore
