# data-raw/study_area_hosts.sh — what each host finished, and which hosts may
# be burned (link#347). Sourced by study_area_run.sh and by
# tests/testthat/test-study_area_hosts.R; defines functions only, so sourcing
# it has no side effects.
#
# Two rules, both learned the expensive way in run 20261017_004619-3f4c713b:
#
#   1. A host's finished set comes from its DATABASE, never from its log text.
#      R writes warnings into the same stream, and a warning flushed without a
#      newline put `[wsg_run_one] FIRE done` mid-line, where the old anchored
#      match could not see it. 18 finished groups were hidden that way. The
#      log is still read, unanchored, for diagnosis and for SKIP, which writes
#      no log row (wsg_run_one.R exits before lnk_pipeline_run).
#
#   2. A host that may hold unconsolidated work is never burned. Every cypher
#      is HELD from the moment its bucket is dispatched, and released only when
#      its database answered and everything it finished was consolidated. A
#      held host is kept on every exit path, including an abort, and is
#      written to ${TS}_kept_hosts.tsv with the command that burns it.
#
# Globals read (set by the driver, or by the test):
#   SCHEMA RUN_UID TS LOG_DIR CYPHER_DIR CYPHER_TF KEEP_CYPHERS CYPHERS_UP
#   CY_WS_ARR (array)  CY_IP CY_HOLD CY_BURNED (assoc arrays, keyed by workspace)
# Globals written:
#   ACC_STATE ACC_FINISHED ACC_SKIP (assoc arrays, keyed by host label)
#   CY_HOLD CY_BURNED CYPHERS_UP KEPT_N
#
# Needs bash >= 4 (assoc arrays), as the driver does.

# psql script: the run's finished groups, framed by sentinels. A host whose
# persist has no log table yet has finished nothing, and says so (begin and end
# with nothing between) rather than erroring into "unknown".
.hosts_finished_sql() {
  printf '%s\n' \
    '\echo __LNK_BEGIN__' \
    "SELECT to_regclass('${SCHEMA}.log') IS NOT NULL AS lnk_has_log \\gset" \
    '\if :lnk_has_log' \
    "SELECT DISTINCT watershed_group_code FROM ${SCHEMA}.log WHERE run_uid = '${RUN_UID}' AND date_end IS NOT NULL ORDER BY 1;" \
    '\endif' \
    '\echo __LNK_END__'
}

# host_finished <local|ip>: prints the groups this run finished on that host,
# one per line. Returns 0 when the database answered, 1 when it did not.
#
# Judged on the output, never on the exit status: ssh to a host on the tailnet
# can exit 0 whatever the remote command returned, and an empty answer from a
# host that could not be reached would otherwise read as "finished nothing",
# which is the one answer that lets it be burned. Both sentinels and nothing
# but group codes between them, or it is unknown.
host_finished() {
  local where="$1" out
  if [ "$where" = "local" ]; then
    out=$(.hosts_finished_sql | PGPASSWORD=postgres psql -h localhost -p 5432 \
      -U postgres -d fwapg -X -q -t -A -v ON_ERROR_STOP=1 2>/dev/null) || true
  else
    out=$(.hosts_finished_sql | ssh -o ConnectTimeout=20 -o BatchMode=yes \
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

# host_log_reported <logfile> <done|SKIP>: groups the log text names with that
# marker, ANYWHERE on a line. Diagnosis, plus the SKIP set; never the count.
# An unreadable log reports nothing: `grep` on a missing file must not abort a
# `set -e` caller into the EXIT trap.
host_log_reported() {
  [ -r "$1" ] || return 0
  { grep -oE "\[wsg_run_one\] [A-Z]{4} $2" "$1" || true; } \
    | awk '{ print $2 }' | sort -u
}

# Set helpers over CSV / line lists. `sed` deleting every line still exits 0,
# where `grep -v '^$'` exits 1 and would abort a `set -e` caller.
.hosts_lines() { printf '%s\n' "${1:-}" | tr ',' '\n' | sed '/^[[:space:]]*$/d' | sort -u; }
.hosts_csv()   { sed '/^[[:space:]]*$/d' | sort -u | paste -sd, -; }
.hosts_n()     { .hosts_lines "${1:-}" | wc -l | tr -d ' '; }
# Members of $1 not in $2 (both CSV), as CSV.
.hosts_minus() { comm -23 <(.hosts_lines "$1") <(.hosts_lines "$2") | .hosts_csv; }

# host_account <key> <local|ip> <logfile> <expected csv>
# <key> is `dispatcher` or a cypher's workspace; ACC_* are keyed by it (plain
# keys: a subscript holding brackets is fragile). Records ACC_STATE /
# ACC_FINISHED / ACC_SKIP, prints one line, and returns 0 only when the
# database answered and every expected group is finished or SKIPped.
# Disagreement between the log text and the database is printed for diagnosis
# and decides nothing.
host_account() {
  local key="$1" where="$2" log="$3" expected="$4" label
  local fin done_log acc missing extra hidden phantom exp_n acc_n
  if [ "$key" = "dispatcher" ]; then label="dispatcher"; else label="cy[$key]"; fi
  if fin=$(host_finished "$where"); then
    ACC_STATE[$key]=known
  else
    ACC_STATE[$key]=unknown
    fin=""
  fi
  ACC_FINISHED[$key]=$(printf '%s\n' "$fin" | .hosts_csv)
  ACC_SKIP[$key]=$(host_log_reported "$log" SKIP | .hosts_csv)
  done_log=$(host_log_reported "$log" done | .hosts_csv)

  if [ "${ACC_STATE[$key]}" = "unknown" ]; then
    echo "  ✗ $label: database did not answer — finished set UNKNOWN; the log names $(.hosts_n "$done_log") done (see $log)"
    return 1
  fi

  acc=$(printf '%s\n%s\n' "${ACC_FINISHED[$key]}" "${ACC_SKIP[$key]}" | tr ',' '\n' | .hosts_csv)
  missing=$(.hosts_minus "$expected" "$acc")
  extra=$(.hosts_minus "${ACC_FINISHED[$key]}" "$expected")
  hidden=$(.hosts_minus "${ACC_FINISHED[$key]}" "$done_log")
  phantom=$(.hosts_minus "$done_log" "${ACC_FINISHED[$key]}")
  exp_n=$(.hosts_n "$expected")
  acc_n=$(( $(.hosts_n "$expected") - $(.hosts_n "$missing") ))

  [ -z "$hidden" ]  || echo "    note: $label: finished in the database, no done marker in the log: $hidden"
  [ -z "$phantom" ] || echo "    note: $label: done marker in the log, not finished in the database: $phantom"
  [ -z "$extra" ]   || echo "    note: $label: finished groups outside its bucket (consolidated anyway): $extra"
  if [ -z "$missing" ]; then
    echo "  ✓ $label: $acc_n/$exp_n WSGs accounted for ($(.hosts_n "${ACC_FINISHED[$key]}") finished, $(.hosts_n "${ACC_SKIP[$key]}") SKIP; database)"
    return 0
  fi
  echo "  ✗ $label: only $acc_n/$exp_n WSGs accounted for; not finished: $missing (see $log)"
  return 1
}

# host_release <ws> <consolidated csv>: release the hold on a cypher only when
# its database answered and everything it finished is in what consolidate
# took. Anything else keeps it. Call only after consolidate returned success.
host_release() {
  local ws="$1" consolidated="$2" left
  if [ "${ACC_STATE[$ws]:-unknown}" != "known" ]; then
    echo "  ✗ cy[$ws]: finished set unknown — KEEPING it"
    return 0
  fi
  left=$(.hosts_minus "${ACC_FINISHED[$ws]}" "$consolidated")
  if [ -n "$left" ]; then
    echo "  ✗ cy[$ws]: finished but not consolidated: $left — KEEPING it"
    return 0
  fi
  CY_HOLD[$ws]=0
  echo "  ✓ cy[$ws]: all $(.hosts_n "${ACC_FINISHED[$ws]}") finished groups consolidated — may be burned"
}

# Droplet name for a tofu workspace (rtj env/do/dev/cypher/main.tf:25-26).
host_droplet_name() {
  if [ "$1" = "default" ]; then echo "cypher"; else echo "cypher-${1//_/-}"; fi
}

# Why a held host is kept, for the TSV and the banner.
.hosts_keep_reason() {
  local ws="$1"
  if [ "$KEEP_CYPHERS" = "1" ]; then echo "--keep-cyphers"; return; fi
  case "${ACC_STATE[$ws]:-}" in
    "")      echo "run did not reach completeness accounting; may hold finished groups" ;;
    unknown) echo "database did not answer; finished set unknown" ;;
    *)       echo "holds finished groups not confirmed consolidated" ;;
  esac
}

# burn_cyphers: burn every cypher that is neither held nor already burned, and
# record every other one. Idempotent; runs explicitly after consolidate and
# again from the EXIT trap. Never returns non-zero itself; the caller's
# status is passed through.
burn_cyphers() {
  local rc=$?
  [ "${CYPHERS_UP:-0}" = "1" ] || return $rc
  local ws burn=() keep=() clean=1 n dl name
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
    for ws in "${burn[@]}"; do
      CY_BURNED[$ws]=1
      # `|| n="?"` so a tofu hiccup (pipefail) cannot abort the loop when this
      # runs from the EXIT trap with set -e active.
      n=$(cd "$CYPHER_TF" && TF_WORKSPACE="$ws" tofu state list 2>/dev/null | wc -l | tr -d ' ') || n="?"
      echo "  cy[$ws]: $n tofu resources (expect 0)"; [ "$n" = "0" ] || clean=0
    done
    # Three outcomes, not two (link#246): capture first, test doctl's exit
    # status, then the value. Per droplet name, because a kept host is
    # legitimately still up.
    if dl=$(doctl compute droplet list --no-header --format Name 2>/dev/null); then
      for ws in "${burn[@]}"; do
        name=$(host_droplet_name "$ws")
        if printf '%s\n' "$dl" | awk -v n="$name" '$1 == n { f = 1 } END { exit !f }'; then
          echo "  ✗ doctl still shows $name"; clean=0
        fi
      done
      [ "$clean" = "0" ] || echo "  ✓ doctl: burned droplets gone"
    else
      echo "  ✗ could not query doctl — droplet state UNKNOWN, check manually"; clean=0
    fi
    [ "$clean" = "1" ] && echo "  ✓ burn clean" || echo "  ✗ BURN INCOMPLETE — investigate"
  fi

  hosts_kept_report ${keep[@]+"${keep[@]}"}
  return $rc
}

# hosts_kept_report <ws...>: write ${TS}_kept_hosts.tsv and print the banner.
# Rewritten on every call, so the file always states the current set; removed
# when nothing is kept. Sets KEPT_N.
hosts_kept_report() {
  local tsv="$LOG_DIR/${TS}_kept_hosts.tsv" ws
  KEPT_N=$#
  if [ "$#" -eq 0 ]; then
    rm -f "$tsv"
    return 0
  fi
  printf 'workspace\tdroplet\treason\tfinished_n\tburn_command\n' > "$tsv"
  echo "=== HOSTS KEPT ($#) — still running and billed ==="
  for ws in "$@"; do
    printf '%s\t%s\t%s\t%s\t%s\n' "$ws" "$(host_droplet_name "$ws")" \
      "$(.hosts_keep_reason "$ws")" "$(.hosts_n "${ACC_FINISHED[$ws]:-}")" \
      "cd $CYPHER_DIR && ./cypher_down.sh --workspace $ws" >> "$tsv"
    echo "  cy[$ws] ($(host_droplet_name "$ws")): $(.hosts_keep_reason "$ws")"
  done
  echo "  Consolidate what they hold, then burn each with:"
  for ws in "$@"; do echo "    cd $CYPHER_DIR && ./cypher_down.sh --workspace $ws"; done
  echo "  Recorded in $tsv"
  return 0
}
