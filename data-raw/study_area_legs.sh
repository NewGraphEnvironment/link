# data-raw/study_area_legs.sh — consolidate each cloud host when its own leg
# ends, then burn it (link#369). Sourced by study_area_run.sh after
# study_area_hosts.sh, study_area_finish.sh and study_area_phases.sh, and by
# tests/testthat/test-study_area_legs.R. Sourcing defines functions and
# declares the maps they use, nothing else.
#
# Until #369 the driver waited for every leg, consolidated every cypher in one
# schema_consolidate() call, and then burned them. A cypher that finished early
# sat idle and billed, holding the only copy of its groups, until the slowest
# leg and the whole consolidate were done: about 3 host-hours on 2026-10-17 and
# about 20 on 2026-10-23. Now each cypher is accounted, consolidated, released
# and burned as soon as its own leg ends, while the other legs keep modelling.
#
# The rules:
#
#   1. Consolidates run one at a time, in the main shell, in the order the
#      legs end. The hold, burn and outcome maps live in this shell; a
#      consolidate in a subshell would lose them.
#   2. CONSOLIDATING names the one host being copied. A driver killed mid-copy
#      reads that host as unsettled and the others as their own state says.
#   3. A cypher whose bucket overlaps the dispatcher's (possible in closure
#      mode, where an overlap only warns) is consolidated after the dispatcher
#      leg ends, as before #369: copying a group the dispatcher is still
#      writing would race its delete and insert.
#   4. A consolidate that ends without an outcome for its host keeps the host,
#      leaves its groups `in_flight` in the state record and out of the
#      recompute, and the run carries on and exits non-zero. Ending the run
#      there, as before, would leave the other legs running unwatched.
#   5. A burn mid-run considers only hosts whose leg has ended, so a host
#      still modelling is never reported as kept. The EXIT trap considers all.
#
# Globals read: SCHEMA TS LOG_DIR REPO_ROOT LOCAL_PID DISP_BUCKET CY_WS_ARR
#   CY_IP HOST_BUCKET CONS_STATE RUN_WSGS_TSV KEEP_CYPHERS; CONSOLIDATE_RSCRIPT
#   (default Rscript)
# Globals written: HOST_LEG_PID (set by the driver at dispatch) HOST_LEG_DONE
#   HOST_RUN_RC HOST_CONS_STATE HOST_CONS_UTC HOST_BUCKET_DONE HOST_CONS_FAIL HOST_NO_OUTCOME
#   CONS_FAILED CONS_EXCLUDED CONSOLIDATING COMPLETE_FAIL DISP_RC
# Functions read: host_account host_consolidate_bucket host_release
#   burn_cyphers .hosts_* (study_area_hosts.sh); consolidate_outcomes
#   consolidate_state_write run_wsgs_write (study_area_finish.sh); phase_begin
#   phase_end phase_skip phase_forget phase_print (study_area_phases.sh)
#
# Needs bash >= 5.1 (`wait -n -p`), as the driver does.

declare -A HOST_LEG_PID HOST_LEG_DONE HOST_CONS_STATE HOST_CONS_UTC HOST_NO_OUTCOME

# .legs_now: an ISO UTC time for the state record.
.legs_now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# .legs_consolidate_r <source as an R list> <outcome tsv>: the R program that
# consolidates one source and writes its outcome row (host, ok, stage,
# groups), which consolidate_outcomes reads. No backup (the driver took the
# run's one before its dispatcher leg wrote) and no whole-schema count print.
.legs_consolidate_r() {
  cat <<EOF
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
source('data-raw/schema_consolidate.R')
res <- schema_consolidate(schema = '$SCHEMA', sources = list($1), backup = FALSE, verify = FALSE)
print(res)
out <- do.call(rbind, lapply(names(res\$sources), function(h) {
  s <- res\$sources[[h]]
  data.frame(host = h, ok = isTRUE(s\$ok),
             stage = if (is.null(s\$stage)) NA_character_ else as.character(s\$stage),
             groups = paste(s\$groups, collapse = ','), stringsAsFactors = FALSE)
}))
if (!is.null(out)) utils::write.table(out, '$2', sep = '\t', quote = FALSE,
                                      row.names = FALSE, na = '')
ok <- all(vapply(res\$sources, function(s) isTRUE(s\$ok), logical(1)))
quit(status = if (ok) 0 else 1)
EOF
}

# .legs_no_outcome <ws> <why>: rule 4. The host stays held: it is never
# released, because a consolidate that died after its source cleanup leaves
# nothing on the host, and release would then burn the only record of what
# happened.
.legs_no_outcome() {
  local ws="$1"
  HOST_NO_OUTCOME[$ws]=1
  HOST_CONS_FAIL[$ws]=no_outcome
  HOST_CONS_STATE[$ws]=in_flight
  CONS_FAILED="${CONS_FAILED:+$CONS_FAILED }$ws"
  CONS_EXCLUDED=$(.hosts_union "${CONS_EXCLUDED:-}" "${HOST_BUCKET_DONE[$ws]:-}")
  HOST_WHY[$ws]="consolidate ended with no outcome ($2); its groups may be half-copied on the dispatcher"
  echo "  ✗ cy[$ws]: $2 — KEEPING it; its groups stay in_flight and out of the recompute: ${HOST_BUCKET_DONE[$ws]:-none}"
}

# host_consolidate <ws>: copy one cypher's finished groups to the dispatcher.
# Sets HOST_CONS_STATE / HOST_CONS_UTC, and through consolidate_outcomes
# HOST_CONS_FAIL, CONS_FAILED and CONS_EXCLUDED. Never fails.
host_consolidate() {
  local ws="$1" bucket_r src log tsv crc=0
  bucket_r=$(.hosts_lines "${HOST_BUCKET_DONE[$ws]:-}" | sed "s/.*/'&'/" | paste -sd, -)
  src="list(host = 'cypher@${CY_IP[$ws]}', via = 'docker', bucket = c($bucket_r))"
  log="$LOG_DIR/${TS}_consolidate_${ws}.log"
  tsv="$LOG_DIR/${TS}_consolidate_${ws}.tsv"
  # in_flight BEFORE the copy (link#358): a driver that dies mid-copy leaves
  # the record saying so. A record that cannot be written stops this host's
  # copy, never the run: the host keeps its groups.
  HOST_CONS_STATE[$ws]=in_flight
  HOST_CONS_UTC[$ws]=$(.legs_now) || HOST_CONS_UTC[$ws]=""
  if ! consolidate_state_write "$CONS_STATE"; then
    HOST_CONS_FAIL[$ws]=state_unwritten
    HOST_CONS_STATE[$ws]=""
    CONS_FAILED="${CONS_FAILED:+$CONS_FAILED }$ws"
    CONS_EXCLUDED=$(.hosts_union "${CONS_EXCLUDED:-}" "${HOST_BUCKET_DONE[$ws]:-}")
    echo "  ✗ cy[$ws]: could not write $CONS_STATE; not consolidating it (its groups stay on the host)"
    return 0
  fi
  # Removed first, so an outcome left from an earlier attempt is never read.
  rm -f "$tsv"
  echo "  consolidating cy[$ws]: $(.hosts_n "${HOST_BUCKET_DONE[$ws]}") groups (see $log)"
  CONSOLIDATING="$ws"
  ( cd "$REPO_ROOT" || exit 1
    "${CONSOLIDATE_RSCRIPT:-Rscript}" -e "$(.legs_consolidate_r "$src" "$tsv")" ) \
    > "$log" 2>&1 || crc=$?
  CONSOLIDATING=""
  HOST_CONS_UTC[$ws]=$(.legs_now) || HOST_CONS_UTC[$ws]=""
  if [ "$crc" = "0" ]; then
    HOST_CONS_STATE[$ws]=ok
    echo "  ✓ cy[$ws]: consolidated"
  elif consolidate_outcomes "$tsv" "$ws" && [ -n "${HOST_CONS_FAIL[$ws]:-}" ]; then
    # A refused or failed source with a recorded stage (link#358): its groups
    # are not consolidated, and host_release keeps it while they are there.
    HOST_CONS_STATE[$ws]="failed:${HOST_CONS_FAIL[$ws]}"
    echo "    see $log"
  else
    # No row, or R failed after recording ok: nothing says what landed.
    .legs_no_outcome "$ws" "consolidate exited $crc with no outcome it can be judged on"
  fi
  consolidate_state_write "$CONS_STATE" \
    || echo "  WARN: could not record cy[$ws]'s outcome in $CONS_STATE; its groups stay in_flight there"
  return 0
}

# host_finish_leg <ws>: everything after a cypher's leg ends: account,
# consolidate, release, burn. Called bare in the main shell, never in $( ) or
# a pipe, so its maps survive; every step inside handles its own failure.
host_finish_leg() {
  local ws="$1" st n
  # From here a mid-run burn considers this host (rule 5). Not when its leg
  # ended: a host deferred behind the dispatcher (rule 3) is not yet the
  # kept-hosts report's to name.
  HOST_LEG_DONE[$ws]=1
  echo "=== cy[$ws]: leg ended (exit ${HOST_RUN_RC[$ws]:-?}); account, consolidate, burn ==="
  phase_begin account "$ws"
  st=ok
  host_account "$ws" "${CY_IP[$ws]}" "$LOG_DIR/${TS}_run_$ws.log" "${HOST_BUCKET[$ws]}" \
    || { st=failed; COMPLETE_FAIL=1; }
  # Database ∪ log done; empty for a host whose database did not answer, which
  # is then not consolidated (consolidate reads it over the same route) and
  # stays HELD.
  HOST_BUCKET_DONE[$ws]=$(host_consolidate_bucket "$ws")
  [ "${ACC_STATE[$ws]:-unknown}" = "known" ] || \
    echo "    cy[$ws]: left out of consolidate; the host will be KEPT"
  # This host's SKIPs, now known (link#358). Never fatal: the host is held.
  run_wsgs_write "$RUN_WSGS_TSV" \
    || echo "  WARN: could not rewrite $RUN_WSGS_TSV with cy[$ws]'s SKIPs"
  phase_end account "$ws" "$(.hosts_n "${HOST_BUCKET[$ws]:-}")" "$st"

  phase_begin consolidate "$ws"
  n=$(.hosts_n "${HOST_BUCKET_DONE[$ws]:-}")
  if [ "$n" = "0" ]; then
    # Nothing finished there to copy. It still goes through release, which
    # keeps it only for a reason it can measure (link#347).
    echo "  WARN: cy[$ws] has nothing to consolidate — skipping the copy"
    st=failed
  else
    host_consolidate "$ws"
    st=ok
    [ -z "${HOST_CONS_FAIL[$ws]:-}" ] || st=failed
  fi
  # Release reads the host again: a host is released only when nothing it
  # finished is left on it (link#347). Not after a consolidate with no
  # outcome (rule 4).
  if [ "${HOST_NO_OUTCOME[$ws]:-0}" != "1" ]; then
    host_release "$ws" "${HOST_BUCKET[$ws]}"
  fi
  phase_end consolidate "$ws" "$n" "$st"

  phase_begin burn "$ws"
  burn_cyphers ended || true
  # burn_cyphers returns its caller's status, not its own (link#375): the row
  # reads what it left. failed when the host was free to burn and is not.
  st=ok
  [ "$KEEP_CYPHERS" = "1" ] || [ "${HOST_HOLD[$ws]:-0}" = "1" ] \
    || [ "${CY_BURNED[$ws]:-0}" = "1" ] || st=failed
  phase_end burn "$ws" "" "$st"
  return 0
}

# .legs_overlap <ws>: groups in both this cypher's bucket and the
# dispatcher's (rule 3).
.legs_overlap() { .hosts_inter "${HOST_BUCKET[$1]:-}" "${DISP_BUCKET:-}"; }

# legs_wait: wait for the dispatcher's leg (LOCAL_PID) and every cypher's
# (HOST_LEG_PID), in the order they end, and finish each cypher as it ends.
#
# `wait -n -p` returns a job that has already been returned again on the next
# call (bash 5.3), so each pid is removed from the pending list once returned
# and the loop ends when the list is empty. A pid wait cannot report (not a
# child) is waited on directly, so the loop always ends.
legs_wait() {
  local pid who rc ws d disp_done=0 rest
  local -a pending=() deferred=()
  local -A ws_of=()
  pending+=("$LOCAL_PID"); ws_of[$LOCAL_PID]=dispatcher
  for ws in ${CY_WS_ARR[@]+"${CY_WS_ARR[@]}"}; do
    pid="${HOST_LEG_PID[$ws]:-}"
    [ -n "$pid" ] || continue
    pending+=("$pid"); ws_of[$pid]="$ws"
  done
  while [ "${#pending[@]}" -gt 0 ]; do
    who=""; rc=0
    wait -n -p who "${pending[@]}" || rc=$?
    # wait UNSETS who when it reports no job (127: no listed pid is a child;
    # >128: a trapped signal), so a bare $who would end the driver under set -u.
    if [ -z "${who:-}" ]; then
      who="${pending[0]}"; rc=0
      wait "$who" || rc=$?
    fi
    rest=()
    for pid in "${pending[@]}"; do [ "$pid" = "$who" ] || rest+=("$pid"); done
    pending=(${rest[@]+"${rest[@]}"})
    ws="${ws_of[$who]:-}"
    [ -n "$ws" ] || continue
    if [ "$ws" = "dispatcher" ]; then
      DISP_RC=$rc
      [ "$rc" = "0" ] || echo "  WARN: dispatcher run returned $rc; see $LOG_DIR/${TS}_run_local.log"
      phase_forget model dispatcher; phase_print model dispatcher
      disp_done=1
      for d in ${deferred[@]+"${deferred[@]}"}; do host_finish_leg "$d"; done
      deferred=()
      continue
    fi
    # Recorded only once wait has returned (link#347): a session that
    # dropped may have left its loop running on the host, so host_release
    # keeps a host whose session did not exit 0.
    HOST_RUN_RC[$ws]=$rc
    [ "$rc" = "0" ] || echo "  WARN: cy[$ws] run returned $rc; see $LOG_DIR/${TS}_run_$ws.log"
    phase_forget model "$ws"; phase_print model "$ws"
    if [ "$disp_done" = "0" ] && [ -n "$(.legs_overlap "$ws")" ]; then
      echo "  cy[$ws]: its bucket overlaps the dispatcher's ($(.legs_overlap "$ws")); consolidating it once the dispatcher leg ends"
      deferred+=("$ws")
      continue
    fi
    host_finish_leg "$ws"
  done
  # Defensive: a dispatcher pid wait never reported still finishes the queue.
  for d in ${deferred[@]+"${deferred[@]}"}; do host_finish_leg "$d"; done
  return 0
}
