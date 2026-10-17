# data-raw/study_area_hosts.sh — what each host finished, and which hosts may
# be burned (link#347). Sourced by study_area_run.sh and by
# tests/testthat/test-study_area_hosts.R; defines functions only, so sourcing
# it has no side effects.
#
# Rules, learned the expensive way in run 20261017_004619-3f4c713b:
#
#   1. A host's finished set comes from its DATABASE, not from its log text.
#      R writes warnings into the same stream, and a warning flushed without a
#      newline put `[wsg_run_one] FIRE done` mid-line, where the old anchored
#      match could not see it: 18 finished groups were hidden that way. The
#      log is still read, unanchored. It can only ADD to the set consolidate
#      takes, never remove from it: `done` prints after persist, while the
#      log row's date_end is set by a soft UPDATE that can fail
#      (.lnk_log_run_finish) and its run_uid depends on LNK_RUN_UID crossing
#      ssh. SKIP comes from the log alone; it writes no row.
#
#   2. A host that may hold unconsolidated work is never burned. Every cypher
#      is HELD from the moment its bucket is dispatched. It is released only
#      when its dispatch session exited 0, and AFTER consolidate its database
#      answers that no `streams` rows are left for any group it finished or
#      was asked to run. consolidate deletes what it copied from the source,
#      so what is left is what was not consolidated, measured rather than
#      assumed, and without trusting run_uid or date_end.
#
#   3. A held host is kept on every exit path, including an abort, and written
#      to ${TS}_kept_hosts.tsv with its groups and the commands that recover
#      and burn it. A burn that fails is listed the same way.
#
# Globals read (set by the driver, or by the test):
#   SCHEMA RUN_UID TS LOG_DIR CYPHER_DIR CYPHER_TF KEEP_CYPHERS CYPHERS_UP
#   CY_WS_ARR (array); CY_IP CY_RUN_RC (assoc, keyed by workspace)
# Globals written:
#   ACC_STATE ACC_FINISHED ACC_DONE_LOG ACC_SKIP (assoc, keyed by host key)
#   CY_HOLD CY_BURNED CY_UNCONS CY_WHY (assoc, keyed by workspace)
#   CYPHERS_UP KEPT_N
# Every assoc array must be declared at the caller's TOP LEVEL before the
# EXIT trap can fire: under `set -u` an undeclared one kills the trap, and a
# `declare -A` inside a function is local to it.
#
# Needs bash >= 4 (assoc arrays), as the driver does.

# psql script: groups in <table> matching <condition>, framed by sentinels. A
# persist with no such table yet holds no groups, and says so (begin and end
# with nothing between) rather than erroring into "unknown".
.hosts_wsg_sql() {   # $1 = table, $2 = SQL condition
  printf '%s\n' \
    '\echo __LNK_BEGIN__' \
    "SELECT to_regclass('${SCHEMA}.$1') IS NOT NULL AS lnk_has_table \\gset" \
    '\if :lnk_has_table' \
    "SELECT DISTINCT watershed_group_code FROM ${SCHEMA}.$1 WHERE $2 ORDER BY 1;" \
    '\endif' \
    '\echo __LNK_END__'
}

# .hosts_query <local|ip> <table> <condition>: prints the groups, one per line.
# Returns 0 when the database answered, 1 when it did not.
#
# Judged on the output, never on the exit status: ssh to a host on the tailnet
# can exit 0 whatever the remote command returned, and an empty answer from a
# host that could not be reached would otherwise read as "nothing there",
# which is the one answer that lets it be burned. Both sentinels and nothing
# but group codes between them, or it is unknown. The remote route is the one
# schema_consolidate.R uses (docker exec into fresh-db).
.hosts_query() {
  local where="$1" out
  if [ "$where" = "local" ]; then
    out=$(.hosts_wsg_sql "$2" "$3" | PGPASSWORD=postgres psql -h localhost -p 5432 \
      -U postgres -d fwapg -X -q -t -A -v ON_ERROR_STOP=1 2>/dev/null) || true
  else
    out=$(.hosts_wsg_sql "$2" "$3" | ssh -o ConnectTimeout=20 -o BatchMode=yes \
      "cypher@$where" \
      'docker exec -i fresh-db psql -U postgres -d fwapg -X -q -t -A -v ON_ERROR_STOP=1' \
      2>/dev/null) || true
  fi
  printf '%s\n' "$out" | awk '
    $0 == "__LNK_BEGIN__" { if (begun) bad = 1; begun = 1; next }
    $0 == "__LNK_END__"   { if (!begun || ended) bad = 1; ended = 1; next }
    $0 == ""              { next }
    begun && !ended && $0 ~ /^[A-Z][A-Z][A-Z][A-Z]$/ { rows[++n] = $0; next }
    { bad = 1 }
    END {
      if (!begun || !ended || bad) exit 1
      for (i = 1; i <= n; i++) print rows[i]
    }'
}

# host_finished <local|ip>: groups whose log row for this run is closed.
host_finished() {
  .hosts_query "$1" log "run_uid = '${RUN_UID}' AND date_end IS NOT NULL"
}

# host_remaining <local|ip> <csv>: which of these groups still have streams
# rows on the host. Independent of run_uid and date_end.
host_remaining() {
  local in
  in=$(.hosts_lines "$2" | sed "s/.*/'&'/" | paste -sd, -)
  .hosts_query "$1" streams "watershed_group_code IN (${in:-NULL})"
}

# host_log_reported <logfile> <done|SKIP>: groups the log text names with that
# marker, ANYWHERE on a line. An unreadable log reports nothing: `grep` on a
# missing file must not abort a `set -e` caller into the EXIT trap.
host_log_reported() {
  [ -r "$1" ] || return 0
  { grep -oE "\[wsg_run_one\] [A-Z]{4} $2" "$1" || true; } \
    | awk '{ print $2 }' | sort -u
}

# Set helpers over CSV lists. `sed` deleting every line still exits 0, where
# `grep -v '^$'` exits 1 and would abort a `set -e` caller.
.hosts_lines() { printf '%s\n' "${1:-}" | tr ',' '\n' | sed '/^[[:space:]]*$/d' | sort -u; }
.hosts_csv()   { tr ',' '\n' | sed '/^[[:space:]]*$/d' | sort -u | paste -sd, -; }
.hosts_n()     { .hosts_lines "${1:-}" | wc -l | tr -d ' '; }
.hosts_union() { printf '%s\n' "$@" | .hosts_csv; }
# Members of $1 not in $2, as CSV.
.hosts_minus() { comm -23 <(.hosts_lines "$1") <(.hosts_lines "$2") | .hosts_csv; }

# host_account <key> <local|ip> <logfile> <expected csv>
# <key> is `dispatcher` or a cypher's workspace; ACC_* are keyed by it (plain
# keys: a subscript holding brackets is fragile). Records the database's
# finished set, the log's done and SKIP sets, prints one line, and returns 0
# only when the database answered and every expected group is finished or
# SKIPped. Log/database disagreement is printed; the log only ever adds.
host_account() {
  local key="$1" where="$2" log="$3" expected="$4" label fin
  local acc missing extra hidden phantom exp_n acc_n
  if [ "$key" = "dispatcher" ]; then label="dispatcher"; else label="cy[$key]"; fi
  if fin=$(host_finished "$where"); then
    ACC_STATE[$key]=known
  else
    ACC_STATE[$key]=unknown
    fin=""
  fi
  ACC_FINISHED[$key]=$(printf '%s\n' "$fin" | .hosts_csv)
  ACC_SKIP[$key]=$(host_log_reported "$log" SKIP | .hosts_csv)
  ACC_DONE_LOG[$key]=$(host_log_reported "$log" done | .hosts_csv)
  [ "$key" = "dispatcher" ] || \
    CY_UNCONS[$key]=$(.hosts_union "${ACC_FINISHED[$key]}" "${ACC_DONE_LOG[$key]}")

  if [ "${ACC_STATE[$key]}" = "unknown" ]; then
    echo "  ✗ $label: database did not answer — finished set UNKNOWN; the log names $(.hosts_n "${ACC_DONE_LOG[$key]}") done (see $log)"
    return 1
  fi

  acc=$(.hosts_union "${ACC_FINISHED[$key]}" "${ACC_SKIP[$key]}")
  missing=$(.hosts_minus "$expected" "$acc")
  extra=$(.hosts_minus "${ACC_FINISHED[$key]}" "$expected")
  hidden=$(.hosts_minus "${ACC_FINISHED[$key]}" "${ACC_DONE_LOG[$key]}")
  phantom=$(.hosts_minus "${ACC_DONE_LOG[$key]}" "${ACC_FINISHED[$key]}")
  exp_n=$(.hosts_n "$expected")
  acc_n=$(( exp_n - $(.hosts_n "$missing") ))

  [ -z "$hidden" ]  || echo "    note: $label: finished in the database, no done marker in the log: $hidden"
  [ -z "$phantom" ] || echo "    note: $label: done in the log, not closed in the database (consolidated anyway): $phantom"
  [ -z "$extra" ]   || echo "    note: $label: finished groups outside its bucket (consolidated anyway): $extra"
  if [ -z "$missing" ]; then
    echo "  ✓ $label: $acc_n/$exp_n WSGs accounted for ($(.hosts_n "${ACC_FINISHED[$key]}") finished, $(.hosts_n "${ACC_SKIP[$key]}") SKIP; database)"
    return 0
  fi
  echo "  ✗ $label: only $acc_n/$exp_n WSGs accounted for; not finished: $missing (see $log)"
  return 1
}

# host_consolidate_bucket <ws>: what consolidate should take from a cypher.
# Database ∪ log done for a host whose database answered; nothing for one
# that did not, because consolidate reads the same database over the same
# route and its failure would sink every other host's consolidate. That host
# stays HELD.
host_consolidate_bucket() {
  if [ "${ACC_STATE[$1]:-unknown}" = "known" ]; then
    .hosts_union "${ACC_FINISHED[$1]}" "${ACC_DONE_LOG[$1]}"
  fi
}

# host_release <ws> <expected csv>: call only after consolidate returned
# success. Releases the hold only when the dispatch session exited 0 and the
# host's database answers that no streams rows are left for anything it
# finished or was asked to run. Anything else keeps it, with the reason in
# CY_WHY and the groups in CY_UNCONS.
host_release() {
  local ws="$1" expected="$2" check left
  if [ "${ACC_STATE[$ws]:-unknown}" != "known" ]; then
    CY_WHY[$ws]="database did not answer at accounting; finished set unknown"
  elif [ "${CY_RUN_RC[$ws]:-1}" != "0" ]; then
    CY_WHY[$ws]="dispatch session exited ${CY_RUN_RC[$ws]:-?}; groups may still be running there"
  else
    check=$(.hosts_union "$expected" "${CY_UNCONS[$ws]:-}")
    if ! left=$(host_remaining "${CY_IP[$ws]}" "$check"); then
      CY_WHY[$ws]="database did not answer after consolidate"
    elif [ -n "$left" ]; then
      CY_UNCONS[$ws]=$(printf '%s\n' "$left" | .hosts_csv)
      CY_WHY[$ws]="streams rows left after consolidate"
    else
      CY_HOLD[$ws]=0
      CY_UNCONS[$ws]=""
      echo "  ✓ cy[$ws]: nothing left on the host after consolidate — may be burned"
      return 0
    fi
  fi
  echo "  ✗ cy[$ws]: ${CY_WHY[$ws]} — KEEPING it${CY_UNCONS[$ws]:+ (groups: ${CY_UNCONS[$ws]})}"
  return 0
}

# Droplet name for a tofu workspace (rtj env/do/dev/cypher/main.tf:25-26).
host_droplet_name() {
  if [ "$1" = "default" ]; then echo "cypher"; else echo "cypher-${1//_/-}"; fi
}

# hosts_preflight_droplets <droplet names, one per line>: before a spin, a
# cypher already up is most likely one an earlier run KEPT. In one of this
# run's workspaces cypher_up would adopt it and this run could burn or
# overwrite what it holds, so that returns 1. Another cypher only warns,
# except the long-lived default `cypher`, which is not a run's host.
hosts_preflight_droplets() {
  local d ws hit rc=0
  for d in $(printf '%s\n' "$1" | awk '$1 ~ /^cypher(-|$)/ { print $1 }'); do
    hit=""
    for ws in ${CY_WS_ARR[@]+"${CY_WS_ARR[@]}"}; do
      [ "$(host_droplet_name "$ws")" = "$d" ] && hit="$ws"
    done
    if [ -n "$hit" ]; then
      echo "  ✗ droplet $d (workspace $hit) is already up — kept by an earlier run?"
      echo "    See data-raw/logs/study_area_run/*_kept_hosts.tsv; consolidate what it"
      echo "    holds, then: cd $CYPHER_DIR && ./cypher_down.sh --workspace $hit"
      rc=1
    elif [ "$d" != "cypher" ]; then
      echo "  WARN: droplet $d is up and billing (not one of this run's workspaces)"
    fi
  done
  return $rc
}

# Why a host is kept, for the TSV and the banner.
.hosts_keep_reason() {
  local ws="$1"
  if [ "$KEEP_CYPHERS" = "1" ]; then echo "--keep-cyphers"; return; fi
  if [ -n "${CY_WHY[$ws]:-}" ]; then echo "${CY_WHY[$ws]}"; return; fi
  echo "run stopped before consolidate released it; may hold finished groups"
}

# burn_cyphers: burn every cypher that is neither held nor already burned, and
# record every other one. Idempotent; runs explicitly after consolidate and
# again from the EXIT trap. The caller's status is passed through.
burn_cyphers() {
  local rc=$?
  [ "${CYPHERS_UP:-0}" = "1" ] || return $rc
  local ws burn=() keep=() clean=1 n dl name doctl_ok why
  for ws in "${CY_WS_ARR[@]}"; do
    [ "${CY_BURNED[$ws]:-0}" = "1" ] && continue
    if [ "$KEEP_CYPHERS" = "1" ] || [ "${CY_HOLD[$ws]:-0}" = "1" ]; then
      keep+=("$ws")
    else
      burn+=("$ws")
    fi
  done

  if [ "${#burn[@]}" -gt 0 ]; then
    echo "=== BURN CYPHERS: ${burn[*]} ==="
    ( cd "$CYPHER_DIR" || exit 1
      for ws in "${burn[@]}"; do
        ./cypher_down.sh --workspace "$ws" > "$LOG_DIR/${TS}_burn_$ws.log" 2>&1 &
      done
      wait ) || true
    dl=""
    doctl_ok=1
    dl=$(doctl compute droplet list --no-header --format Name 2>/dev/null) || doctl_ok=0
    for ws in "${burn[@]}"; do
      # `|| n="?"` so a tofu hiccup (pipefail) cannot abort the loop when this
      # runs from the EXIT trap with set -e active.
      n=$(cd "$CYPHER_TF" && TF_WORKSPACE="$ws" tofu state list 2>/dev/null | wc -l | tr -d ' ') || n="?"
      name=$(host_droplet_name "$ws")
      echo "  cy[$ws]: $n tofu resources (expect 0)"
      why=""
      [ "$n" = "0" ] || why="$n tofu resources left"
      if [ "$doctl_ok" != "1" ]; then
        why="${why:+$why; }doctl did not answer"
      elif printf '%s\n' "$dl" | awk -v n="$name" '$1 == n { f = 1 } END { exit !f }'; then
        echo "  ✗ doctl still shows $name"
        why="${why:+$why; }doctl still shows $name"
      fi
      if [ -z "$why" ]; then
        CY_BURNED[$ws]=1
      else
        # Not marked burned: the trap tries again, and until then it is
        # listed as kept, so a droplet left billing cannot go unreported.
        clean=0
        CY_WHY[$ws]="burn did not complete ($why); see $LOG_DIR/${TS}_burn_$ws.log"
        keep+=("$ws")
      fi
    done
    [ "$doctl_ok" = "1" ] || echo "  ✗ could not query doctl — droplet state UNKNOWN, check manually"
    [ "$clean" = "1" ] && echo "  ✓ burn clean" || echo "  ✗ BURN INCOMPLETE — investigate"
  fi

  hosts_kept_report ${keep[@]+"${keep[@]}"}
  return $rc
}

# hosts_kept_report <ws...>: write ${TS}_kept_hosts.tsv and print the banner.
# Rewritten on every call, so the file states the current set; removed when
# nothing is kept. No IP in it: redact_log_addresses rewrites every ${TS}_*
# file, so it names the command that prints one. Sets KEPT_N.
hosts_kept_report() {
  local tsv="$LOG_DIR/${TS}_kept_hosts.tsv" ws
  KEPT_N=$#
  if [ "$#" -eq 0 ]; then
    rm -f "$tsv"
    return 0
  fi
  printf 'workspace\tdroplet\treason\trun_uid\tschema\tgroups\tip_command\tburn_command\n' > "$tsv"
  echo "=== HOSTS KEPT ($#) — still running and billed ==="
  for ws in "$@"; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ws" "$(host_droplet_name "$ws")" \
      "$(.hosts_keep_reason "$ws")" "$RUN_UID" "$SCHEMA" "${CY_UNCONS[$ws]:-}" \
      "cd $CYPHER_TF && TF_WORKSPACE=$ws tofu output -raw droplet_ip" \
      "cd $CYPHER_DIR && ./cypher_down.sh --workspace $ws" >> "$tsv"
    echo "  cy[$ws] ($(host_droplet_name "$ws")): $(.hosts_keep_reason "$ws")"
    [ -z "${CY_UNCONS[$ws]:-}" ] || echo "    groups: ${CY_UNCONS[$ws]}"
  done
  echo "  To recover: get each host's address (ip_command), consolidate its groups"
  echo "  with data-raw/schema_consolidate.R (schema = '$SCHEMA', one source"
  echo "  list(host = 'cypher@<ip>', via = 'docker', bucket = <groups>)), then burn:"
  for ws in "$@"; do echo "    cd $CYPHER_DIR && ./cypher_down.sh --workspace $ws"; done
  echo "  Recorded in $tsv"
  return 0
}
