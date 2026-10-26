# data-raw/study_area_recompute.sh — which groups may be recomputed now
# (link#374). Sourced by study_area_run.sh after study_area_hosts.sh, and by
# tests/testthat/test-study_area_recompute.R. Sourcing defines functions,
# nothing else.
#
# A group's recompute (wsg_recompute_one.R) reads its own rows and the
# barrier and override rows of every group on its downstream path. Until
# #374 it ran only after every leg and every consolidate. Now a group is
# recomputed once it, and every group it reads, has LANDED on the dispatcher:
#
#   a dispatcher group   its newest <schema>.log row is this run's, closed
#                        (date_end is written last, after every persist
#                        write; the rule run_coverage uses);
#   a remote group       its host's row in <TS>_consolidate_state.tsv is
#                        `ok` (written after the copy; `in_flight` before);
#   a SKIP, or a group   always landed: it has no rows this run writes.
#   outside the run
#
# A group a run gives to several hosts lands when every one of them has
# landed it. Which groups a group reads is <TS>_recompute_deps.tsv, the line
# rule of recompute_deps.R (complete by construction).
#
# Everything here FAILS CLOSED. An early recompute that reads too little
# cannot be undone (the habitat gate only clears flags), so an unreadable
# file, a database that does not answer, or a row that does not parse means
# "not landed" and the caller launches nothing new on that poll.
#
# Globals read: SCHEMA RUN_UID (through .hosts_query, study_area_hosts.sh)
# Functions read: .hosts_query .hosts_csv .hosts_lines .hosts_minus

# recompute_landed <run_wsgs.tsv> <consolidate_state.tsv>: the run's groups
# that have landed, as CSV. Returns 1, printing nothing, when any input is
# unknown. A state file that does not exist yet means no remote host has
# landed anything, which is known.
recompute_landed() {
  local wsgs="$1" state="$2" disp hdr
  [ -r "$wsgs" ] || return 1
  IFS= read -r hdr < "$wsgs" || return 1
  # Four columns since #358, bucket_mode appended by #361.
  case "$hdr" in "$(printf 'wsg\thost\tskip\trun_uid')"|"$(printf 'wsg\thost\tskip\trun_uid\t')"*) ;; *) return 1 ;; esac
  disp=$(.hosts_query local log "run_uid = '${RUN_UID}' AND date_end IS NOT NULL
    AND (watershed_group_code, date_start) IN (
      SELECT watershed_group_code, max(date_start) FROM ${SCHEMA}.log
      GROUP BY watershed_group_code)" 1) || return 1
  if [ -e "$state" ]; then
    [ -r "$state" ] || return 1
    IFS= read -r hdr < "$state" || return 1
    [ "$hdr" = "$(printf 'wsg\tworkspace\tstate\trun_uid\tstate_utc')" ] || return 1
  else
    state=/dev/null
  fi
  printf '%s\n' "$disp" | LC_ALL=C awk -F'\t' -v uid="$RUN_UID" -v st="$state" -v ws="$wsgs" '
    BEGIN {
      while ((getline l < "/dev/stdin") > 0) if (l != "") closed[l] = 1
      n = 0
      while ((getline l < st) > 0) {
        if (++n == 1) continue
        split(l, f, "\t")
        if (f[1] !~ /^[A-Z][A-Z][A-Z][A-Z]$/ || f[4] != uid) { bad = 1; continue }
        if (f[3] == "ok") cons[f[1] SUBSEP f[2]] = 1
      }
      n = 0
      while ((getline l < ws) > 0) {
        if (++n == 1) continue
        split(l, f, "\t")
        w = f[1]; h = f[2]
        if (w !~ /^[A-Z][A-Z][A-Z][A-Z]$/ || h == "" || f[4] != uid) { bad = 1; continue }
        seen[w] = 1
        if (f[3] == "yes") continue
        if (h == "dispatcher") { if (!(w in closed)) out[w] = 1 }
        else if (!((w SUBSEP h) in cons)) out[w] = 1
      }
      if (bad) exit 1
      for (w in seen) if (!(w in out)) print w
    }' | .hosts_csv
  [ "${PIPESTATUS[1]}" = "0" ]
}

# recompute_ready <landed csv> <deps.tsv> <launched csv> <run_wsgs.tsv>: the
# run's groups that are landed, not SKIPs, not launched, and whose every
# dependency in the run is landed, as CSV. A dependency outside the run has
# landed already. Returns 1, printing nothing, on an unreadable or malformed
# dependency file or group list.
recompute_ready() {
  local landed="$1" deps="$2" launched="$3" wsgs="$4" hdr
  [ -r "$deps" ] && [ -r "$wsgs" ] || return 1
  IFS= read -r hdr < "$wsgs" || return 1
  case "$hdr" in "$(printf 'wsg\thost\tskip\trun_uid')"|"$(printf 'wsg\thost\tskip\trun_uid\t')"*) ;; *) return 1 ;; esac
  IFS= read -r hdr < "$deps" || return 1
  [ "$hdr" = "$(printf 'wsg\trule\tdep')" ] || return 1
  LC_ALL=C awk -F'\t' -v landed="$landed" -v launched="$launched" -v ws="$wsgs" -v dp="$deps" -v uid="$RUN_UID" '
    BEGIN {
      n = split(landed, a, ","); for (i = 1; i <= n; i++) if (a[i] != "") L[a[i]] = 1
      n = split(launched, a, ","); for (i = 1; i <= n; i++) if (a[i] != "") D[a[i]] = 1
      n = 0
      while ((getline l < ws) > 0) {
        if (++n == 1) continue
        split(l, f, "\t")
        if (f[1] !~ /^[A-Z][A-Z][A-Z][A-Z]$/ || f[4] != uid) { bad = 1; continue }
        run[f[1]] = 1
        if (f[3] == "yes") skip[f[1]] = 1
      }
      n = 0
      while ((getline l < dp) > 0) {
        if (++n == 1) continue
        split(l, f, "\t")
        if (f[1] !~ /^[A-Z][A-Z][A-Z][A-Z]$/ || f[3] !~ /^[A-Z][A-Z][A-Z][A-Z]$/) { bad = 1; continue }
        if (f[2] != "line") continue
        if ((f[3] in run) && !(f[3] in L) && !(f[3] in skip)) blocked[f[1]] = 1
      }
      if (bad) exit 1
      for (w in run) if ((w in L) && !(w in skip) && !(w in D) && !(w in blocked)) print w
    }' | .hosts_csv
  [ "${PIPESTATUS[0]}" = "0" ]
}

# recompute_scheduler: run in the background beside the legs, as
# `recompute_scheduler &`. Every RC_POLL seconds (default 30) it reads which
# groups are ready and starts them, longest first (recompute_order), into
# RECOMPUTE_JOBS slots through recompute_one, which writes each job's .log and
# .rc into RC_DIR as the end-of-run pool does. Each launch appends
# "<wsg>\t<iso> <epoch>\t<early|final>" to RC_DIR/launched.tsv.
#
# It ends three ways:
#   final set   run_finish writes RC_FINAL (tmp + mv, so its existence means
#               it is whole): one line, "FINAL <csv>", the groups coverage
#               found finished this run. Every one not yet started starts,
#               ready or not (every leg and consolidate is over), and the
#               scheduler returns 0 once its jobs end.
#   stop        RC_STOP exists (the driver's EXIT trap): nothing new starts;
#               jobs already running finish, as a killed pool's always have.
#               Returns 2.
#   orphaned    RC_PARENT is gone (a driver killed with SIGKILL runs no
#               trap): as stop, returning 3. Two drivers must never work one
#               schema, so a scheduler never outlives the run it serves.
#
# Its own error handling, not the driver's: errexit is off in here, because
# a poll that fails must cost one poll, never the scheduler. A poll that fails
# starts nothing (recompute_landed / recompute_ready fail closed).
#
# Globals read: RC_DIR RC_DEPS RC_FINAL RC_STOP RC_PARENT RC_POLL
#   RUN_WSGS_TSV CONS_STATE RECOMPUTE_JOBS (and what recompute_one,
#   recompute_order and recompute_landed read)
# Functions read: recompute_one recompute_order (study_area_run.sh)
#   recompute_landed recompute_ready .hosts_minus .hosts_lines .hosts_csv
recompute_scheduler() {
  set +e
  local width="${RECOMPUTE_JOBS:-1}" poll="${RC_POLL:-30}" launched="" final="" have_final=0
  local queue landed ready w pid line now ret tick
  local -a pids=() alive=()
  mkdir -p "$RC_DIR" || return 1
  : >> "$RC_DIR/launched.tsv" || return 1
  while :; do
    alive=()
    for pid in ${pids[@]+"${pids[@]}"}; do
      if kill -0 "$pid" 2>/dev/null; then alive+=("$pid"); else wait "$pid" 2>/dev/null; fi
    done
    pids=(${alive[@]+"${alive[@]}"})
    ret=""
    [ -e "$RC_STOP" ] && ret=2
    [ -z "$ret" ] && ! kill -0 "$RC_PARENT" 2>/dev/null && ret=3
    if [ -n "$ret" ]; then
      for pid in ${pids[@]+"${pids[@]}"}; do wait "$pid" 2>/dev/null; done
      return "$ret"
    fi
    if [ "$have_final" = "0" ] && [ -e "$RC_FINAL" ]; then
      IFS= read -r line < "$RC_FINAL"
      case "$line" in
        "FINAL "*) final="${line#FINAL }"; have_final=1 ;;
        *) echo "[recompute_scheduler] $RC_FINAL is not a final set ('$line'); stopping" >&2
           for pid in ${pids[@]+"${pids[@]}"}; do wait "$pid" 2>/dev/null; done
           return 1 ;;
      esac
    fi
    if [ "$have_final" = "1" ]; then
      queue=$(.hosts_minus "$final" "$launched")
    else
      landed=$(recompute_landed "$RUN_WSGS_TSV" "$CONS_STATE") || landed=""
      queue=""
      if [ -n "$landed" ]; then
        ready=$(recompute_ready "$landed" "$RC_DEPS" "$launched" "$RUN_WSGS_TSV") || ready=""
        queue="$ready"
      fi
    fi
    if [ -n "$queue" ] && [ "${#pids[@]}" -lt "$width" ]; then
      for w in $(recompute_order "$queue" 2>/dev/null); do
        [ "${#pids[@]}" -lt "$width" ] || break
        case "$w" in [A-Z][A-Z][A-Z][A-Z]) ;; *) continue ;; esac
        now=$(date -u '+%Y-%m-%dT%H:%M:%SZ %s')
        recompute_one "$w" &
        pids+=("$!")
        launched=$(.hosts_union "$launched" "$w")
        printf '%s\t%s\t%s\n' "$w" "$now" "$([ "$have_final" = "1" ] && echo final || echo early)" \
          >> "$RC_DIR/launched.tsv"
      done
    fi
    if [ "$have_final" = "1" ] && [ "${#pids[@]}" -eq 0 ] \
       && [ -z "$(.hosts_minus "$final" "$launched")" ]; then
      return 0
    fi
    # One second at a time, so the final set or a stop is acted on at once
    # rather than at the next poll (a 30 s poll held a run's last groups for
    # 27 s, link#374's Run A).
    if [ "$have_final" = "1" ]; then
      sleep 1
    else
      for ((tick = 0; tick < poll; tick++)); do
        [ -e "$RC_FINAL" ] || [ -e "$RC_STOP" ] && break
        sleep 1
      done
    fi
  done
}

# recompute_final_write <csv>: the final set, for the scheduler (tmp + mv).
recompute_final_write() {
  printf 'FINAL %s\n' "${1:-}" > "$RC_FINAL.tmp" && mv "$RC_FINAL.tmp" "$RC_FINAL"
}
