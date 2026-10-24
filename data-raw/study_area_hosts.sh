# data-raw/study_area_hosts.sh — what each host finished, and which hosts may
# be burned (link#347). Sourced by study_area_run.sh and by
# tests/testthat/test-study_area_hosts.R. Sourcing defines functions and
# declares the empty maps they use, nothing else.
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
#   HOST_ARR (array); CY_IP HOST_SSH HOST_BUCKET HOST_RUN_RC (assoc, keyed by
#   workspace; HOST_SSH is the ssh target, cypher@<ip> for a cloud host)
#   HOST_CONS_FAIL (assoc: the stage at which consolidate failed for a source,
#   set by consolidate_outcomes in study_area_finish.sh, link#358)
# Globals written:
#   ACC_STATE ACC_FINISHED ACC_DONE_LOG ACC_SKIP (assoc, keyed by host key)
#   HOST_HOLD CY_BURNED HOST_UNCONS HOST_PARTIAL HOST_WHY HOST_PRE HOST_PRE_STATE
#   (assoc, keyed by workspace)
# Read with a default: RECOMPUTE_RAN (1 once the driver's recompute pool ran),
# CONSOLIDATING (the workspace schema_consolidate is copying from, empty
# otherwise; one host at a time since link#369), HOST_LEG_DONE (assoc: 1 once a
# host's leg has ended, read by `burn_cyphers ended`).
#   CYPHERS_UP KEPT_N KEPT_CAUSE_N
# Every map is declared below, ONCE, so a caller cannot forget one: under
# `set -u` an undeclared map kills the EXIT trap and leaks the droplets. Source
# this file at the TOP LEVEL, before installing the trap; sourced from inside
# a function the `declare -A` would be local to it. Re-declaring a map that
# already exists keeps its contents.
#
# Needs bash >= 4 (assoc arrays), as the driver does.

declare -A CY_IP HOST_SSH HOST_KIND HOST_BUCKET HOST_RUN_RC HOST_HOLD CY_BURNED HOST_UNCONS HOST_PARTIAL HOST_WHY
declare -A HOST_PRE HOST_PRE_STATE HOST_DOUBT HOST_CONS_FAIL HOST_LEG_DONE HOST_CONS_STATE HOST_BUCKET_DONE
declare -A ACC_STATE ACC_FINISHED ACC_DONE_LOG ACC_SKIP

# psql script: groups in <table> matching <condition>, framed by sentinels. A
# missing table (or schema: to_regclass is NULL for both) prints
# __LNK_NOTABLE__ instead of erroring, so the caller decides what it means.
.hosts_wsg_sql() {   # $1 = table, $2 = SQL condition
  printf '%s\n' \
    '\echo __LNK_BEGIN__' \
    "SELECT to_regclass('${SCHEMA}.$1') IS NOT NULL AS lnk_has_table \\gset" \
    '\if :lnk_has_table' \
    "SELECT DISTINCT watershed_group_code FROM ${SCHEMA}.$1 WHERE $2 ORDER BY 1;" \
    '\else' \
    '\echo __LNK_NOTABLE__' \
    '\endif' \
    '\echo __LNK_END__'
}

# .hosts_psql <local|ssh target>: run the psql script on stdin against that
# host's database and print what it prints. Its exit status means nothing
# (ssh can exit 0 whatever ran), so every caller frames its script with
# sentinels and judges the output. The remote route is the one
# schema_consolidate.R uses (docker exec into fresh-db).
.hosts_psql() {
  if [ "$1" = "local" ]; then
    PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres -d fwapg \
      -X -q -t -A -v ON_ERROR_STOP=1 2>/dev/null
  else
    ssh -o ConnectTimeout=20 -o BatchMode=yes "$1" \
      'docker exec -i fresh-db psql -U postgres -d fwapg -X -q -t -A -v ON_ERROR_STOP=1' \
      2>/dev/null
  fi
}

# .hosts_query <local|ssh target> <table> <condition> [strict]: prints the groups, one
# per line. Returns 0 when the database answered, 1 when it did not. With
# strict=1 a missing table is "did not answer" too.
#
# Judged on the output, never on the exit status: ssh to a host on the tailnet
# can exit 0 whatever the remote command returned, and an empty answer from a
# host that could not be reached would otherwise read as "nothing there",
# which is the one answer that lets it be burned. Both sentinels and nothing
# but group codes between them, or it is unknown. The remote route is the one
# schema_consolidate.R uses (docker exec into fresh-db).
.hosts_query() {
  local where="$1" strict="${4:-0}" out
  [ -n "$where" ] || return 1
  out=$(.hosts_wsg_sql "$2" "$3" | .hosts_psql "$where") || true
  printf '%s\n' "$out" | awk -v strict="$strict" '
    $0 == "__LNK_BEGIN__" { if (begun) bad = 1; begun = 1; next }
    $0 == "__LNK_NOTABLE__" { if (!begun || ended) bad = 1; notable = 1; next }
    $0 == "__LNK_END__"   { if (!begun || ended) bad = 1; ended = 1; next }
    $0 == ""              { next }
    begun && !ended && $0 ~ /^[A-Z][A-Z][A-Z][A-Z]$/ { rows[++n] = $0; next }
    { bad = 1 }
    END {
      if (!begun || !ended || bad) exit 1
      if (notable && strict == 1) exit 1
      for (i = 1; i <= n; i++) print rows[i]
    }'
}

# host_finished <local|ssh target>: groups whose log row for this run is closed. A
# persist with no log table yet has closed none (known, empty); the log's done
# markers still reach the consolidate bucket.
host_finished() {
  .hosts_query "$1" log "run_uid = '${RUN_UID}' AND date_end IS NOT NULL"
}

# host_remaining <local|ssh target> <csv>: which of these groups still have streams
# rows on the host. Independent of run_uid and date_end. STRICT: every
# dispatched cypher has <schema>.streams (cypher_prep runs lnk_persist_init),
# so a missing table means the probe is pointed at the wrong database, schema
# or container, and reading that as "nothing left" would burn the host.
host_remaining() {
  local in
  in=$(.hosts_lines "$2" | sed "s/.*/'&'/" | paste -sd, -)
  .hosts_query "$1" streams "watershed_group_code IN (${in:-NULL})" 1
}

# host_complete <local|ssh target> <csv>: which of these groups have
# streams_mapping_code rows on the host. lnk_pipeline_run() writes them last,
# after its final persist and the habitat gate (.lnk_mapping_code_persist(),
# link#349); the pre-persist writes streams, habitat and barriers before access
# exists. So a group with streams rows and no mapping-code rows did not finish
# there. Strict, as for streams.
host_complete() {
  local in
  in=$(.hosts_lines "$2" | sed "s/.*/'&'/" | paste -sd, -)
  .hosts_query "$1" streams_mapping_code "watershed_group_code IN (${in:-NULL})" 1
}

# host_baseline <ws>: before dispatch, which of the host's bucket already have
# streams OR streams_mapping_code rows (HOST_PRE; HOST_PRE_STATE known|unknown). A
# cypher spins from a warm image and persist_init keeps rows (it drops a table
# only on column drift, one table at a time), so rows found later are this
# run's only if they were not there before. Never fails.
host_baseline() {
  local ws="$1" pre mc
  if pre=$(host_remaining "${HOST_SSH[$ws]:-}" "${HOST_BUCKET[$ws]:-}") && \
     mc=$(host_complete "${HOST_SSH[$ws]:-}" "${HOST_BUCKET[$ws]:-}"); then
    HOST_PRE_STATE[$ws]=known
    HOST_PRE[$ws]=$(.hosts_union "$(printf '%s\n' "$pre" | .hosts_csv)" \
      "$(printf '%s\n' "$mc" | .hosts_csv)")
    [ -z "${HOST_PRE[$ws]}" ] || \
      echo "  NOTE: $(.hosts_label "$ws"): rows before dispatch (from its image) for: ${HOST_PRE[$ws]}"
  else
    HOST_PRE_STATE[$ws]=unknown
    HOST_PRE[$ws]=""
    echo "  WARN: $(.hosts_label "$ws"): could not read its streams before dispatch; mapping-code rows will not count as finished"
  fi
  return 0
}

# host_wait <ws> <pid>: wait for a cypher's dispatch session and record its
# exit status in HOST_RUN_RC, only once wait has returned. A driver killed during
# the wait runs its EXIT trap with the session still building there; a status
# assigned before the wait would read as settled in that trap. Returns the
# session's status.
host_wait() {
  local rc=0
  wait "$2" || rc=$?
  HOST_RUN_RC[$1]=$rc
  return "$rc"
}

# .hosts_settled <ws>: nothing the driver started is still writing to the
# host, so its rows no longer change. After dispatch the driver writes to a
# cypher in exactly two ways: the dispatch ssh session and schema_consolidate
# (which copies and then deletes from the source). A killed driver runs its
# EXIT trap while either keeps going, so the host is settled only when its
# session ended with status 0 (unset: still running, or the run stopped
# before the wait) and consolidate is not in flight against it. Consolidate
# copies one host at a time (link#369), so CONSOLIDATING names that host.
.hosts_settled() {
  [ "${CONSOLIDATING:-}" != "$1" ] && [ "${HOST_RUN_RC[$1]:-}" = "0" ]
}
.hosts_unsettled_why() {
  if [ -n "${CONSOLIDATING:-}" ] && [ "${CONSOLIDATING:-}" = "$1" ]; then
    echo "consolidate was still running against it"
  else
    echo "its dispatch session had not ended 0"
  fi
}

# .hosts_doubt_why <ws>: why its unknown groups are unknown. HOST_DOUBT comes
# from exactly one rule per baseline state, so the state names the cause.
.hosts_doubt_why() {
  if [ "${HOST_PRE_STATE[$1]:-unknown}" = "known" ]; then
    echo "rows from before dispatch, no finish signal of this run"
  else
    echo "mapping-code rows, no baseline taken"
  fi
}

# host_split <ws> <csv>: measure what is left on a cypher for these groups and
# split it. HOST_UNCONS = recoverable: left, and finished there by any signal
# this run wrote (its database log row, its log done, or mapping-code rows for
# a group that had no rows before dispatch). HOST_PARTIAL = left and finished by
# none. On a SETTLED host that is a group that failed after the pre-persist;
# consolidating it would replace the dispatcher's whole copy with a broken
# one. On an unsettled host it may still be building. Returns 1, changing
# nothing, when the host does not answer.
host_split() {
  local ws="$1" check="$2" left complete fin run_fin run_log db
  left=$(host_remaining "${HOST_SSH[$ws]:-}" "$check") || return 1
  # This run's own finish signals. Read here when accounting has not run (a
  # report from the EXIT trap): without them a group rebuilt over an image's
  # rows would have no signal left once those rows are discounted.
  if [ -n "${ACC_STATE[$ws]:-}" ]; then
    run_fin="${ACC_FINISHED[$ws]:-}"
    run_log="${ACC_DONE_LOG[$ws]:-}"
  else
    if db=$(host_finished "${HOST_SSH[$ws]:-}"); then
      run_fin=$(printf '%s\n' "$db" | .hosts_csv)
    else
      run_fin=""
    fi
    run_log=$(host_log_reported "$LOG_DIR/${TS}_run_$ws.log" done | .hosts_csv)
  fi
  left=$(printf '%s\n' "$left" | .hosts_csv)
  if [ -n "$left" ]; then
    complete=$(host_complete "${HOST_SSH[$ws]:-}" "$left") || return 1
  else
    complete=""
  fi
  complete=$(printf '%s\n' "$complete" | .hosts_csv)
  # Mapping-code rows are this run's only for a group with no rows before
  # dispatch. With no baseline they cannot be told from an image's: they are
  # then no finish signal, and the groups they mark go to HOST_DOUBT, which
  # holds the host (they may be this run's work) but is never recovered
  # (they may be an image's stale rows).
  HOST_DOUBT[$ws]=""
  if [ "${HOST_PRE_STATE[$ws]:-unknown}" = "known" ]; then
    complete=$(.hosts_minus "$complete" "${HOST_PRE[$ws]:-}")
  else
    HOST_DOUBT[$ws]=$complete
    complete=""
  fi
  fin=$(.hosts_union "$run_fin" "$run_log" "$complete")
  HOST_UNCONS[$ws]=$(.hosts_inter "$left" "$fin")
  # A group that had rows before dispatch and shows no finish signal of this
  # run is of unknown provenance, never "partial": its rows may be this run's
  # finished work whose signals were lost, or the image's.
  HOST_DOUBT[$ws]=$(.hosts_union "${HOST_DOUBT[$ws]}" \
    "$(.hosts_inter "$left" "${HOST_PRE[$ws]:-}")")
  HOST_DOUBT[$ws]=$(.hosts_minus "${HOST_DOUBT[$ws]}" "$fin")
  HOST_PARTIAL[$ws]=$(.hosts_minus "$(.hosts_minus "$left" "$fin")" "${HOST_DOUBT[$ws]}")
  return 0
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
# Members of $1 not in $2, and members of both, as CSV.
.hosts_minus() { comm -23 <(.hosts_lines "$1") <(.hosts_lines "$2") | .hosts_csv; }
.hosts_inter() { comm -12 <(.hosts_lines "$1") <(.hosts_lines "$2") | .hosts_csv; }

# host_account <key> <local|ssh target> <logfile> <expected csv>
# <key> is `dispatcher` or a cypher's workspace; ACC_* are keyed by it (plain
# keys: a subscript holding brackets is fragile). Records the database's
# finished set, the log's done and SKIP sets, prints one line, and returns 0
# only when the database answered and every expected group is finished or
# SKIPped. Log/database disagreement is printed; the log only ever adds.
host_account() {
  local key="$1" where="$2" log="$3" expected="$4" label fin
  local acc missing extra hidden phantom exp_n acc_n
  if [ "$key" = "dispatcher" ]; then label="dispatcher"; else label=$(.hosts_label "$key"); fi
  if fin=$(host_finished "$where"); then
    ACC_STATE[$key]=known
  else
    ACC_STATE[$key]=unknown
    fin=""
  fi
  ACC_FINISHED[$key]=$(printf '%s\n' "$fin" | .hosts_csv)
  # Since link#369 the dispatcher is accounted after the cyphers' consolidates,
  # which copy their log rows here, so its log also names their groups. Those
  # are not the dispatcher's finished work: leave out every group a consolidate
  # was attempted for, unless the dispatcher's own bucket has it.
  if [ "$key" = "dispatcher" ]; then
    local ws copied=""
    for ws in ${HOST_ARR[@]+"${HOST_ARR[@]}"}; do
      [ -n "${HOST_CONS_STATE[$ws]:-}" ] || continue
      copied=$(.hosts_union "$copied" "${HOST_BUCKET_DONE[$ws]:-}")
    done
    ACC_FINISHED[$key]=$(.hosts_minus "${ACC_FINISHED[$key]}" "$(.hosts_minus "$copied" "$expected")")
  fi
  ACC_SKIP[$key]=$(host_log_reported "$log" SKIP | .hosts_csv)
  ACC_DONE_LOG[$key]=$(host_log_reported "$log" done | .hosts_csv)
  [ "$key" = "dispatcher" ] || \
    HOST_UNCONS[$key]=$(.hosts_union "${ACC_FINISHED[$key]}" "${ACC_DONE_LOG[$key]}")

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

# host_release <ws> <expected csv>: call only once consolidate has returned
# and recorded an outcome for every source (a refused or failed source is
# carried past since link#358, and HOST_CONS_FAIL names its stage). Releases the
# hold only when the dispatch session exited 0 and the host's database answers
# that no FINISHED group is left on it (host_split): a source consolidate did
# not take keeps its groups, because consolidate deletes from a source only
# after copying all of it. Partial groups left there do not hold it: they are
# failed builds, already reported missing, and must not be consolidated.
# Anything else keeps it, with the reason in HOST_WHY.
host_release() {
  local ws="$1" expected="$2"
  if [ "${ACC_STATE[$ws]:-unknown}" != "known" ]; then
    HOST_WHY[$ws]="database did not answer at accounting; finished set unknown"
  elif [ "${HOST_RUN_RC[$ws]:-1}" != "0" ]; then
    HOST_WHY[$ws]="dispatch session exited ${HOST_RUN_RC[$ws]:-?}; groups may still be running there"
  elif ! host_split "$ws" "$(.hosts_union "$expected" "${HOST_UNCONS[$ws]:-}")"; then
    HOST_WHY[$ws]="database did not answer after consolidate"
  elif [ -n "${HOST_UNCONS[$ws]}" ] && [ -n "${HOST_CONS_FAIL[$ws]:-}" ]; then
    HOST_WHY[$ws]="consolidate failed at stage ${HOST_CONS_FAIL[$ws]}; finished groups left on the host"
  elif [ -n "${HOST_UNCONS[$ws]}" ]; then
    HOST_WHY[$ws]="finished groups left after consolidate"
  elif [ -n "${HOST_DOUBT[$ws]}" ]; then
    HOST_WHY[$ws]="groups of unknown provenance left ($(.hosts_doubt_why "$ws")): ${HOST_DOUBT[$ws]}"
  else
    HOST_HOLD[$ws]=0
    if .hosts_is_worker "$ws"; then
      echo "  ✓ $(.hosts_label "$ws"): no finished group left on the host after consolidate — may be released"
    else
      echo "  ✓ cy[$ws]: no finished group left on the host after consolidate — may be burned"
    fi
    [ -z "${HOST_PARTIAL[$ws]}" ] || \
      echo "    note: $(.hosts_label "$ws"): partial groups left there (failed builds, not consolidated; rebuild them): ${HOST_PARTIAL[$ws]}"
    return 0
  fi
  echo "  ✗ $(.hosts_label "$ws"): ${HOST_WHY[$ws]} — KEEPING it${HOST_UNCONS[$ws]:+ (groups: ${HOST_UNCONS[$ws]})}"
  return 0
}

# A host's kind (link#376): `cypher` (a cloud host the driver spins and
# burns; the default, so a map left unset reads as before) or `worker` (a
# persistent machine reached by its own ssh target, never spun or burned).
.hosts_kind() { echo "${HOST_KIND[$1]:-cypher}"; }
.hosts_is_worker() { [ "${HOST_KIND[$1]:-cypher}" = "worker" ]; }
# How a host is named in the driver's output: cy[<workspace>] for a cloud
# host, its key (worker1, ...) for a worker. Never a worker's ssh target,
# which is the operator's infrastructure, not evidence.
.hosts_label() {
  if .hosts_is_worker "$1"; then echo "$1"; else echo "cy[$1]"; fi
}

# host_db_id <local|ssh target>: the database's system identifier, so the
# driver can refuse a worker whose database is the dispatcher's or another
# worker's (link#376). Framed by sentinels; returns 1 when it did not answer
# with exactly one.
host_db_id() {
  local out
  out=$(printf '%s\n' '\echo __LNK_BEGIN__' \
    'SELECT system_identifier FROM pg_control_system();' \
    '\echo __LNK_END__' | .hosts_psql "$1") || true
  printf '%s\n' "$out" | awk '
    $0 == "__LNK_BEGIN__" { b = 1; next }
    $0 == "__LNK_END__"   { e = 1; next }
    b && !e && /^[0-9]+$/ { id = $0; n++; next }
    b && !e && $0 != ""   { bad = 1 }
    END { if (!b || !e || bad || n != 1) exit 1; print id }'
}

# host_drop_partials <ws>: on a RELEASED worker, delete its partial groups
# (HOST_PARTIAL: failed builds whose pre-persist left rows, never consolidated)
# from every persist table, so the next run's prior-rows check finds the
# worker clean (link#376). Log tables keep their rows: a partial group's open
# log row is the only record of its failure. Only where nothing could be
# another build's: the host is settled and its baseline was known and empty.
# A cloud host is burned instead, so it is never touched here. Judged on the
# sentinels framing the script; a drop that did not finish returns 1, and the
# rows left make the next run's prep refuse the worker, so it fails closed.
host_drop_partials() {
  local ws="$1" arr out
  .hosts_is_worker "$ws" || return 0
  [ "${HOST_HOLD[$ws]:-1}" = "0" ] || return 0
  [ -n "${HOST_PARTIAL[$ws]:-}" ] || return 0
  if ! .hosts_settled "$ws" || [ "${HOST_PRE_STATE[$ws]:-unknown}" != "known" ] \
     || [ -n "${HOST_PRE[$ws]:-}" ]; then
    echo "    note: $(.hosts_label "$ws"): not dropping its partial groups (${HOST_PARTIAL[$ws]}): its rows before dispatch were not known empty, or it is not settled; the next run refuses it until they are gone"
    return 0
  fi
  arr="{${HOST_PARTIAL[$ws]}}"
  out=$(printf '%s\n' \
    '\echo __LNK_BEGIN__' \
    "SELECT format('DELETE FROM %I.%I WHERE watershed_group_code = ANY (%L::text[])', c.table_schema, c.table_name, '$arr') FROM information_schema.columns c JOIN information_schema.tables t USING (table_schema, table_name) WHERE c.table_schema = '${SCHEMA}' AND c.column_name = 'watershed_group_code' AND t.table_type = 'BASE TABLE' AND c.table_name !~ '^log(_|\$)' ORDER BY c.table_name \\gexec" \
    '\echo __LNK_END__' | .hosts_psql "${HOST_SSH[$ws]:-}") || true
  if printf '%s\n' "$out" | awk '$0 == "__LNK_BEGIN__" { b = 1 } $0 == "__LNK_END__" && b { e = 1 } END { exit !e }'; then
    echo "    $(.hosts_label "$ws"): dropped partial groups ${HOST_PARTIAL[$ws]} from its persist tables (log rows kept)"
    return 0
  fi
  echo "  WARN: $(.hosts_label "$ws"): the drop of partial groups ${HOST_PARTIAL[$ws]} did not finish; the next run refuses this worker until they are gone"
  return 1
}

# Droplet name for a tofu workspace (rtj env/do/dev/cypher/main.tf:25-26); a
# worker has none.
host_droplet_name() {
  if .hosts_is_worker "$1"; then echo "-"; return; fi
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

# Why a host is kept, for the TSV and the banner; empty when the only reason
# is --keep-cyphers. A cause is never hidden behind the flag.
.hosts_keep_cause() {
  local ws="$1"
  if [ -n "${HOST_WHY[$ws]:-}" ]; then echo "${HOST_WHY[$ws]}"; return; fi
  [ "${HOST_HOLD[$ws]:-0}" = "1" ] || return 0
  echo "run stopped before consolidate released it; may hold finished groups"
}
.hosts_keep_reason() {
  local cause
  cause=$(.hosts_keep_cause "$1")
  if [ "$KEEP_CYPHERS" = "1" ] && ! .hosts_is_worker "$1"; then
    echo "${cause:+$cause; }--keep-cyphers"
  else
    echo "$cause"
  fi
}

# burn_cyphers [ended]: burn every cypher that is neither held nor already
# burned, and record every other one. Idempotent; runs after each host's
# consolidate and again from the EXIT trap. The caller's status is passed
# through. With `ended`, hosts whose leg has not ended (HOST_LEG_DONE) are left
# out entirely: a burn after one host's consolidate must not list a host that
# is still modelling as kept (link#369). The trap passes nothing: every host.
#
# A worker (link#376) is never burned. Held, it is listed as kept, like a
# cloud host; released, or never dispatched, it is neither. So this also runs
# on a run with workers and no cyphers (WORKERS_UP), or a held worker would
# go unreported. --keep-cyphers keeps cloud hosts only.
burn_cyphers() {
  local rc=$?
  [ "${CYPHERS_UP:-0}" = "1" ] || [ "${WORKERS_UP:-0}" = "1" ] || return $rc
  local scope="${1:-all}" ws burn=() keep=() clean=1 n dl name doctl_ok why
  for ws in ${HOST_ARR[@]+"${HOST_ARR[@]}"}; do
    [ "${CY_BURNED[$ws]:-0}" = "1" ] && continue
    [ "$scope" != "ended" ] || [ "${HOST_LEG_DONE[$ws]:-0}" = "1" ] || continue
    if .hosts_is_worker "$ws"; then
      [ "${HOST_HOLD[$ws]:-0}" = "1" ] && keep+=("$ws")
      continue
    fi
    # A cloud host is burned only once its spin started (CYPHERS_UP).
    [ "${CYPHERS_UP:-0}" = "1" ] || continue
    if [ "$KEEP_CYPHERS" = "1" ] || [ "${HOST_HOLD[$ws]:-0}" = "1" ]; then
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
        HOST_WHY[$ws]="burn did not complete ($why); see $LOG_DIR/${TS}_burn_$ws.log"
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
# nothing is kept. Sets KEPT_N, and KEPT_CAUSE_N for hosts kept for a reason
# other than --keep-cyphers alone.
#
# `groups` is MEASURED where the host answers: what is still on it, for every
# group it was asked to run, finished, or logged done. That matters for
# recovery: schema_consolidate DELETEs the bucket on the dispatcher before it
# copies, so consolidating a group the host holds only in part destroys the
# dispatcher's copy of its persist rows (its log rows survive). One it no
# longer holds at all has no log row there, so consolidate refuses it when the
# dispatcher has a log row for it; one with only pre-log rows on the
# dispatcher is still deleted and not replaced (#354). Where the host does not answer, `groups` is the
# candidate set and `groups_measured` says no.
#
# No IP in the file: redact_log_addresses rewrites every ${TS}_* file, so it
# names the command that prints one.
hosts_kept_report() {
  local tsv="$LOG_DIR/${TS}_kept_hosts.tsv" ws check measured ipc bc n_cy=0
  KEPT_N=$#
  KEPT_CAUSE_N=0
  if [ "$#" -eq 0 ]; then
    rm -f "$tsv"
    return 0
  fi
  printf 'workspace\tdroplet\treason\trun_uid\tschema\tgroups\tgroups_partial\tgroups_unknown\tgroups_measured\tip_command\tburn_command\n' > "$tsv"
  for ws in "$@"; do .hosts_is_worker "$ws" || n_cy=$((n_cy + 1)); done
  if [ "$n_cy" -gt 0 ]; then
    echo "=== HOSTS KEPT ($#) — still running and billed ==="
  else
    echo "=== HOSTS KEPT ($#) — holding this run's groups ==="
  fi
  for ws in "$@"; do
    [ -z "$(.hosts_keep_cause "$ws")" ] || KEPT_CAUSE_N=$((KEPT_CAUSE_N + 1))
    check=$(.hosts_union "${HOST_BUCKET[$ws]:-}" "${ACC_FINISHED[$ws]:-}" \
      "${ACC_DONE_LOG[$ws]:-}" "${HOST_UNCONS[$ws]:-}")
    if host_split "$ws" "$check"; then
      if .hosts_settled "$ws"; then measured=yes; else measured=unsettled; fi
    else
      HOST_UNCONS[$ws]="$check"
      HOST_PARTIAL[$ws]=""
      HOST_DOUBT[$ws]=""
      measured=no
    fi
    # A worker's target is the operator's own and never written here: the
    # file is committed as evidence (link#376).
    if .hosts_is_worker "$ws"; then
      ipc="the --workers= target given for $ws"
      bc="none (persistent worker; nothing to burn)"
    else
      ipc="cd $CYPHER_TF && TF_WORKSPACE=$ws tofu output -raw droplet_ip"
      bc="cd $CYPHER_DIR && ./cypher_down.sh --workspace $ws"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ws" "$(host_droplet_name "$ws")" \
      "$(.hosts_keep_reason "$ws")" "$RUN_UID" "$SCHEMA" "${HOST_UNCONS[$ws]}" \
      "${HOST_PARTIAL[$ws]:-}" "${HOST_DOUBT[$ws]:-}" "$measured" \
      "$ipc" "$bc" >> "$tsv"
    echo "  $(.hosts_label "$ws") ($(host_droplet_name "$ws")): $(.hosts_keep_reason "$ws")"
    [ "$measured" = "no" ] || [ -z "${HOST_DOUBT[$ws]:-}" ] || \
      echo "    unknown provenance ($(.hosts_doubt_why "$ws"); check before consolidating): ${HOST_DOUBT[$ws]}"
    if [ "$measured" = "yes" ]; then
      echo "    finished, still on the host: ${HOST_UNCONS[$ws]:-nothing}"
      [ -z "${HOST_PARTIAL[$ws]:-}" ] || \
        echo "    partial, do NOT consolidate: ${HOST_PARTIAL[$ws]}"
    elif [ "$measured" = "unsettled" ]; then
      echo "    $(.hosts_unsettled_why "$ws"), so this may still change:"
      echo "    finished when probed: ${HOST_UNCONS[$ws]:-nothing}"
      [ -z "${HOST_PARTIAL[$ws]:-}" ] || \
        echo "    NOT finished when probed (may still be building): ${HOST_PARTIAL[$ws]}"
      echo "    Re-measure once nothing runs there (pgrep -f wsg_run_one on the host)."
    else
      echo "    host did not answer; candidates (NOT measured): ${HOST_UNCONS[$ws]:-none}"
    fi
  done
  echo "  To recover: get each host's address (ip_command; a worker's is its"
  echo "  --workers= target). Consolidate ONLY the"
  echo "  groups column, and only where groups_measured = yes; where it says"
  echo "  unsettled, wait until nothing runs there (the remote loop, and"
  echo "  schema_consolidate on this machine) and re-measure; where it says"
  echo "  no, find out what is left first. Never groups_partial. schema_consolidate"
  echo "  DELETEs its bucket on the dispatcher before it copies, so a group the"
  echo "  host holds only in part loses the dispatcher's copy of its persist rows"
  echo "  (one it no longer holds at all is refused, dest_log_newer, where the"
  echo "  dispatcher has a log row for it; with pre-log rows only, it is lost)."
  if [ "${RECOMPUTE_RAN:-0}" = "1" ]; then
    echo "  The run's recompute ran WITHOUT these groups: after consolidating,"
    echo "  recompute each one and each run group upstream of it"
  else
    echo "  The run's recompute did NOT run: after consolidating, recompute EVERY"
    echo "  group of the run, not only these"
  fi
  echo "  (every group: bash data-raw/study_area_run.sh --recompute-only"
  echo "   --run-uid=$RUN_UID --config=<config> --schema=$SCHEMA${RUN_LABEL:+ --run-label=$RUN_LABEL}"
  echo "   --wsgs=<the run's groups>; one group: LNK_RUN_UID=$RUN_UID ${RUN_LABEL:+LNK_RUN_LABEL=$RUN_LABEL }LNK_SCHEMA=$SCHEMA"
  echo "   LNK_LOAD=loadall Rscript data-raw/wsg_recompute_one.R <WSG> <config>)."
  if [ "$n_cy" -gt 0 ]; then
    echo "  Then burn:"
    for ws in "$@"; do
      .hosts_is_worker "$ws" || echo "    cd $CYPHER_DIR && ./cypher_down.sh --workspace $ws"
    done
  fi
  [ "$n_cy" = "$#" ] || \
    echo "  A worker is not burned: once its groups are consolidated it is left as it is."
  echo "  Recorded in $tsv"
  return 0
}
