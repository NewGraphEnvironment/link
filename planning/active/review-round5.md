# Code-check round 5: link#347 branch, enumeration close-out

Reviewer: subagent, 2026-10-17, at HEAD `2fd3e04d`. Scope: the round-4 fix commit's diff,
every round-4 row whose action, proxy or label involves `CY_RUN_RC` / `host_wait` /
`.hosts_settled`, `host_split` / `host_release` / `hosts_kept_report`, `CY_PRE` /
`CY_PRE_STATE` / `host_baseline`, `CY_DOUBT`, `ACC_STATE` or the driver's dispatch-wait loop,
plus rows for what the fix introduced, plus every label those functions and the driver's
kept / INCOMPLETE blocks print. No repo file edited. Demos ran in `$SCRATCHPAD/r5/` with a
stub `ssh` / `tofu` / `doctl` on PATH and the real `data-raw/study_area_hosts.sh` sourced
(`mkworld.sh`, `prelude.sh`, `demo_consol.sh`, `drv_pre_fail.sh`, `drv_pre_fin.sh`,
`drv_waitb.sh`, `fgkill.sh`). Test file: `NOT_CRAN=true test_file()`: 35 blocks, 116
expectations, 0 failed, 0 error, 0 skipped.

## Enumeration

**43 rows**: 27 round-4 rows re-walked at HEAD, 16 added. **22 verified by running** (a
scratchpad demo, or a named test in the 35-block run that asserts that exact row), 21 by
reading. **1 unsafe (Finding 1), 1 label defect (Finding 2, held and reported, no loss).**

Round 4's three findings are fixed, and the fixes behave as stated:

- Kill during `host_wait` on host b, with host a's session ended 0 and accounting not yet
  run (`drv_waitb.sh`): a is `yes` with `groups = AAAA,BBBB` (BBBB's only signal is its
  DB row, read by the trap itself) and `groups_partial = CCCC`; b is `unsettled`.
- The baseline is streams ∪ mapping code, and `lnk_persist_init` creates
  `streams_mapping_code` (`R/lnk_persist_init.R:456-460`). So the strict `host_complete`
  probe does not turn every baseline into `unknown` before dispatch.

The defect inside the fix is in the same shape as rounds 3 and 4: **settledness is defined
by the dispatch session, but it also has to cover the consolidate process**, which changes
the host's rows and survives a kill of the driver.

## Findings

### 1. A driver killed during consolidate labels groups `measured = yes` that the still-running consolidate then deletes from the host (unsafe: the recovery record directs a consolidate that deletes the dispatcher's copy)

`data-raw/study_area_run.sh:1345-1352` runs consolidate as a foreground subshell. A SIGTERM
to the driver's PID (the `kill <pid>` an operator uses to stop a run) runs the EXIT trap at
once. Nothing has trapped TERM, so bash does not wait for that child, and the
`schema_consolidate` Rscript keeps running.

Measured, `r5/fgkill.sh`: the trap printed `child_alive=yes`, and the child then finished
and wrote its file.

In the trap every cypher is still `CY_HOLD = 1` (`host_release` has not run), `CY_RUN_RC = 0`
(all waits returned), and `ACC_STATE = known`. So `hosts_kept_report` reads each host as
settled and writes `groups_measured = yes`, with `groups` = what is on the host at probe time.

`schema_consolidate` then copies each source in turn and DELETEs that source's bucket from it
(`schema_consolidate.R:434-445`). Any source it has not yet reached when the trap probes is
listed in full and then emptied.

Measured, `r5/demo_consol.sh`. Two hosts, a foreground "consolidate" that empties host a
after 2 s and host b after 3 s, driver killed at 1 s:

```
  cy[a] (cypher-a): run stopped before consolidate released it; may hold finished groups
    finished, still on the host: AAAA
  cy[b] (cypher-b): run stopped before consolidate released it; may hold finished groups
    finished, still on the host: BBBB
--- after: consolidate finished? CONSOLIDATE_DONE
TSV:  a  AAAA  ""  ""  yes      b  BBBB  ""  ""  yes
--- host a now holds: (nothing)  host b: (nothing)
```

The banner and the RUNBOOK (lines 1263-1266) say to consolidate `groups` where
`groups_measured = yes`. That call DELETEs AAAA / BBBB on the dispatcher and copies zero rows.

The loss is backstopped. `schema_consolidate`'s default `backup = TRUE` takes a `pg_dump`
first, and the post-restore `post_rows > pre_rows` check (`:406-417`) flags the source as
failed. So the dispatcher's copy can be restored, and the failure is loud. But the record
labelled the state as settled when it was not, which is the property the branch sets out to
guarantee.

Precondition: a kill while consolidate runs, which takes minutes at 241 groups. CLAUDE.md
records the operator stopping the driver around exactly this step (#347's own run).

Fix (suggested): set a flag such as `CONSOLIDATING=1` before the consolidate subshell and
clear it as soon as the subshell returns, in the same statement that captures its status, so
it is cleared before the `|| { …; exit 1; }` branch runs. Then `.hosts_settled` (or
`hosts_kept_report`) treats every source host as `unsettled` while the flag is set. The
banner should add: wait until `schema_consolidate` no longer runs on the dispatcher, then
re-measure. A test would kill a script during a foreground child that changes the fixture,
as `demo_consol.sh` does. The RUNBOOK settledness sentence (line 1242) needs the same
clause.

### 2. (Low, label) `groups_unknown` from the new `CY_PRE` rule is explained as "mapping-code rows, no baseline", when there was a baseline and there may be no mapping-code rows

The round-4 fix sends `left ∩ CY_PRE` with no this-run signal to `CY_DOUBT`
(`study_area_hosts.sh:220-222`). The two strings that explain `CY_DOUBT` were written for
the unknown-baseline case only:

- `host_release` sets `CY_WHY = "mapping-code rows of unknown provenance left (no baseline): …"` (`:320`), which goes into the TSV `reason`.
- `hosts_kept_report` prints `"unknown provenance (mapping-code rows, no baseline; check before consolidating): …"` (`:480`).

Measured, `r5/drv_pre_fail.sh`. The baseline is known (NOTE printed). AAAA is from the
image, with `streams` rows only, and failed this run. BBBB finished and was consolidated:

```
  NOTE: cy[a]: streams rows before dispatch (from its image) for: AAAA
  ✗ cy[a]: only 1/2 WSGs accounted for; not finished: AAAA
  ✗ cy[a]: mapping-code rows of unknown provenance left (no baseline): AAAA — KEEPING it
    unknown provenance (mapping-code rows, no baseline; check before consolidating): AAAA
TSV reason: mapping-code rows of unknown provenance left (no baseline): AAAA
```

Both clauses are false there, and the same text appears on an unsettled host for a `CY_PRE`
group that is still building (`drv_waitb.sh`, host b: DDDD has no mapping-code rows).

Nothing is lost. The host is held, `CY_WHY` makes it count in `KEPT_CAUSE_N`, so the run
exits 1, and the next run's pre-flight refuses that workspace until it is burned. A host whose
only leftover is such a group cannot go unnoticed (row N6). But the record points the
operator's "check" at the wrong cause.

Related wording: `host_baseline`'s NOTE says "streams rows before dispatch" for a group that
had only mapping-code rows (`:144`).

Fix (suggested): name the cause per group. Use "rows before dispatch (from its image), no
finish signal of this run" for `left ∩ CY_PRE`, and keep "mapping-code rows, no baseline"
for the `CY_PRE_STATE != known` arm. Or use one neutral phrase: "rows of unknown provenance
(present before dispatch, or mapping code with no baseline)".

## Full table

Direction: **safe** (over-reports or holds), **unsafe**, **label** (wrong text, held),
**pre-existing**, **note**. How checked: **R** = run (a demo, or a named test in this run),
**r** = read.

### (a) Round-4 rows re-walked at HEAD `2fd3e04d`

| # | file:line at HEAD | action | state checked at HEAD | verdict | how |
|---|---|---|---|---|---|
| 5 | hosts.sh:309-330; run.sh:1357-1366 | release (`CY_HOLD=0`), then burn | reached after every `host_wait` returned and after `host_account`, so `CY_RUN_RC` is the real status and `ACC_STATE` is set; new `CY_PRE` arm keeps the host instead of releasing it | safe | R (tests "partial rows neither hold", "mapping-code rows from the image do not count as finished") |
| 6 | hosts.sh:465-490 | label `partial` / "do NOT consolidate" | settled now means `host_wait` returned 0, and signals are self-read before accounting (`drv_waitb.sh`: CCCC partial, BBBB groups by DB row). It is still read as settled while consolidate runs in flight | **unsafe via Finding 1** (labels groups as `yes`; partial is not over-claimed there) | R |
| 7 | hosts.sh:215-216, 481-482 | label `groups` (recoverable) | fin = this-run DB ∪ this-run log done ∪ (mapping code − CY_PRE); the baseline is now streams ∪ mapping code; but probed during consolidate | **unsafe via Finding 1** | R (demo_consol) |
| 8 | hosts.sh:467-471, 491-492 | `measured = no`: candidates | clears `CY_DOUBT` / `CY_PARTIAL`; the banner says NOT measured | safe | r |
| 10 | hosts.sh:462; run.sh:1566 | `KEPT_CAUSE_N`, non-zero exit | a `CY_PRE` DOUBT sets `CY_WHY` in `host_release`, so it counts; in a trap report `CY_HOLD = 1` gives the cause | safe | R (drv_pre_fail exits through KEPT) |
| 14 | hosts.sh:114-129 | missing table means unknown | `host_baseline` now also runs strict `host_complete`; `streams_mapping_code` exists after `cypher_prep` → `lnk_persist_init` (`R/lnk_persist_init.R:456`), so the baseline is not unknown by construction | safe | r |
| 16 | run.sh:1055-1060 | baseline loop, then hold | two ssh probes per host now; a kill during them leaves `CY_HOLD` unset, nothing dispatched, so burning is correct | safe | r |
| 17 | run.sh:1087-1094 | `CY_RUN_RC` | only `host_wait` assigns it (grep: one site), after `wait` returns; a kill during `wait $LOCAL_PID` leaves every cypher unset, which is unsettled | safe | R (test "a driver killed while waiting on a host sees that host unsettled"; drv_waitb) |
| 21 | hosts.sh:83-86 in the trap | ssh with no command timeout | the trap now makes three probes per kept host (remaining, finished, complete); a hang stalls the trap, nothing is lost | note (pre-existing shape) | r |
| 22 | run.sh:1055 | `host_baseline` call site under `set -e` | the probes sit in an `if`; every assignment pipes through `.hosts_csv` (exit 0 on empty); returns 0 | safe | r |
| 23 | hosts.sh:140-144 | baseline known: `CY_PRE` set | union of streams and mapping code | safe | R (test "the baseline counts an image's mapping-code rows too") |
| 24 | hosts.sh:145-148 | baseline failed: unknown | now also when only the mapping-code probe fails | safe | R (test "with no baseline … not a finish signal") |
| 25 | hosts.sh:138-142 | baseline source | round 4 F3 fixed: mapping-code-only groups are in `CY_PRE` | safe | R (same test) |
| 26 | hosts.sh:185-187, 210 | `complete − CY_PRE` on the release path | `ACC_FINISHED` / `ACC_DONE_LOG` filled; a `CY_PRE` group finished this run is kept by DB / done | safe | R (drv_pre_fin: groups AAAA, held) |
| 27 | hosts.sh:188-195 | the same in a kept report before accounting | self-read of `host_finished` and `${TS}_run_<ws>.log`; round 4 F2 fixed | safe | R (test "a report from the trap reads this run's finish signals itself"; drv_waitb) |
| 28 | hosts.sh:211-213 | settled, no baseline, before accounting | mapping code goes to DOUBT, DB / done from the self-read go to fin; finished groups read as `groups`, not unknown | safe | r |
| 29 | hosts.sh:220-223 | DOUBT minus fin; PARTIAL minus DOUBT | disjoint; DOUBT is never in `groups`; `CY_PRE` without a signal is never partial | safe | R (test "mapping-code rows from the image …") |
| 30 | hosts.sh:319-320 | DOUBT holds in `host_release` | holds; its text is wrong on the `CY_PRE` arm | **label: Finding 2** | R (drv_pre_fail) |
| 31 | hosts.sh:479-480 | DOUBT printed unless measured=no | prints on yes and unsettled; text wrong on the `CY_PRE` arm | **label: Finding 2** | R (drv_waitb host b) |
| 32 | hosts.sh:169 | `.hosts_settled` | input fixed by `host_wait`; still TRUE while consolidate runs | **unsafe via Finding 1** | R (demo_consol) |
| 33 | hosts.sh:313 | `host_release` reads `CY_RUN_RC:-1` | after every wait; a missing value is not 0 | safe | R (test "session that exited non-zero") |
| 34 | hosts.sh:485-490 | unsettled banner | prints wherever RC is not 0 or is unset | safe | R (test "aborted run's report") |
| 39 | hosts.sh:465-471 trap, droplet gone | ssh fails, so `measured = no` | the self-read happens after `host_remaining` succeeded, so it cannot turn `no` into `yes` | safe | r |
| 40 | run.sh:1302 | consolidate bucket vs `CY_PRE` | the bucket is DB ∪ log done and never reads `CY_PRE`; a `CY_PRE` group that failed this run is not consolidated | safe | r |
| 41 | hosts.sh:324-325 | release note "partial … rebuild them" | `CY_PRE` groups no longer reach it (they hold the host instead); a non-`CY_PRE` partial is this run's rows (the baseline saw none) | safe | r |
| 42 | tests:142 `run_hosts` | defaults `CY_RUN_RC = 0` | the new test unsets it for the waited-on host; no test kills during consolidate, which is why F1 passed | test gap behind F1 | r |
| 43 | hosts.sh:459 TSV | no baseline column | an operator re-measuring an unsettled host by hand cannot tell image rows from this run's; `groups_unknown` carries the outcome | safe | r |

### (b) Rows for what the fix introduced, and the cases asked for

| # | file:line | what | state checked | verdict | how |
|---|---|---|---|---|---|
| N1 | run.sh:1092-1093 | `host_wait` under `set -e` | the only driver call is `host_wait … \|\| echo WARN`, so errexit is off inside it; inside, `wait \|\| rc=$?` cannot abort; it returns the status | safe | r (grep: one call site) |
| N2 | run.sh:1087 vs 1092 | the dispatcher's wait vs `host_wait` | `wait $LOCAL_PID` is unchanged; during it every cypher's RC is unset, which is unsettled (over-cautious for a host that has already ended: safe) | safe | r |
| N3 | hosts.sh:189-193 | trap-time `host_finished` probe | ssh under `burn_cyphers \|\|` (errexit off); on failure run_fin is "" with no note, so a `CY_PRE` group falls to DOUBT and a non-`CY_PRE` finished group is still fin by mapping code (finished implies final persist implies mapping code: `lnk_pipeline_run.R:318`, `lnk_pipeline_persist.R:183-210`; the working schema is dropped per run, `lnk_pipeline_run.R:175`) | safe | r |
| N4 | hosts.sh:194 vs run.sh:1081 | log path | `"$LOG_DIR/${TS}_run_$ws.log"` matches `"$LOG_DIR/${TS}_run_$WS.log"`; `redact_log_addresses` runs after `burn_cyphers` in `on_exit` (run.sh:394-395), so the markers are intact | safe | R (drv_waitb read `T0_run_a.log`) |
| N5 | hosts.sh:215-216, 317-318 | a `CY_PRE` group finished this run (DB row only) still on the host after a successful consolidate | `ACC_FINISHED` puts it in fin, so it is in `CY_UNCONS`, the host is held as "finished groups left after consolidate", and it is in `groups` with `measured = yes`; consolidating it again is a same-data replace | safe | R (drv_pre_fin) |
| N6 | hosts.sh:319-320 | a host whose only leftover is a `CY_PRE` group that failed this run | held as unknown, `CY_WHY` set, `KEPT_CAUSE_N` counts it, the run exits 1, and the next pre-flight refuses that workspace; completeness also printed "not finished"; it cannot go unnoticed | safe (over-holds, reported); the text is Finding 2 | R (drv_pre_fail) |
| N7 | run.sh:1345-1352 + trap | driver killed during consolidate | the trap probes while the orphaned `schema_consolidate` deletes sources; `measured = yes` | **unsafe: Finding 1** | R (fgkill, demo_consol) |
| N8 | hosts.sh:320, 480 | unknown-provenance text on the `CY_PRE` arm | "mapping-code rows, no baseline" printed with a known baseline and streams-only rows | **label: Finding 2** | R |
| N9 | hosts.sh:220-222 | a `CY_PRE` group that SKIPs this run (no modeled species) | its image rows are not this run's, yet it holds the host; SKIP is in `ACC_SKIP`, not fin. Rare (an image would need rows for a species-less group) | safe (over-holds, reported) | r |
| N10 | hosts.sh:185 | `ACC_STATE = unknown` (DB down at accounting) | no re-read of the DB in the trap; done markers still count; a `CY_PRE` group finished with no done goes to DOUBT, never partial | safe | r |
| N11 | hosts.sh:158-163 | `wait` on an empty or non-child PID | nonzero, so unsettled | safe | r |
| N12 | hosts.sh:143-144 | baseline NOTE wording | "streams rows" for a mapping-code-only group | label (folded into Finding 2) | r |
| N13 | run.sh:1366 then trap | a kill during the explicit burn's `cypher_down` | the trap re-runs the burn; a tofu lock failure then reads "burn did not complete", listed. Untouched by the fix | pre-existing | r |
| N14 | RUNBOOK 1242-1247 | settledness sentence | true for the dispatch session; silent on an in-flight consolidate | **unsafe via Finding 1** | r |
| N15 | RUNBOOK 1238-1241 | "such a group … is `groups_unknown`, never partial" | matches hosts.sh:220-223 | safe | R |
| N16 | hosts.sh:463-464 | `check` before accounting = bucket ∪ `CY_UNCONS` | the self-read finished set is not added to `check`, so an out-of-bucket "extra" group goes unmeasured; extras only arise from overlap, which is the accepted pre-existing case | pre-existing | r |

### (c) Labels, and whether each holds on every printing path

| label (where) | assumes | holds? |
|---|---|---|
| TSV `groups` / "finished, still on the host" (hosts.sh:482) | this-run signal; settled | provenance yes; **settled no while consolidate is in flight (F1)** |
| TSV `groups_measured = yes` (466) | rows no longer change | **no while consolidate is in flight (F1)** |
| TSV `groups_partial` / "partial, do NOT consolidate" (484) | settled; every this-run signal read; not `CY_PRE` | yes (self-read; `CY_PRE` excluded). Under F1 a partial group's rows are not deleted by consolidate (it is not in the bucket), so the label stays true |
| "NOT finished when probed (may still be building)" (489) | unsettled | yes |
| "unknown provenance (mapping-code rows, no baseline; …)" (480) | no baseline | **no on the `CY_PRE` arm (F2)** |
| TSV `reason` "mapping-code rows of unknown provenance left (no baseline)" (320) | no baseline | **no on the `CY_PRE` arm (F2)** |
| TSV `reason` "run stopped before consolidate released it; may hold finished groups" (367) | held | yes |
| "host did not answer; candidates (NOT measured)" (492) | — | yes |
| host_release "✓ … may be burned" (323) | settled, `ACC` known, no fin and no DOUBT left | yes |
| host_release "partial groups left there (failed builds …)" (325) | settled; rows are this run's | yes (`CY_PRE` excluded; with no baseline an image group may be named, but nothing of this run is lost) |
| host_release "✗ … KEEPING it (groups: …)" (328) | informational | yes |
| host_baseline NOTE "streams rows before dispatch (from its image)" (144) | streams rows | wording only: may be mapping-code rows (N12) |
| host_baseline WARN "could not read its streams …" (148) | a probe failed | yes |
| "recompute ran WITHOUT these" / "did NOT run" (501-507) | `RECOMPUTE_RAN` | yes; a kill during consolidate gives "did NOT run", which is correct |
| driver INCOMPLETE "Consolidate only each host's groups column … groups_measured = yes" (run.sh:1572-1575) | as for the lib | **inherits F1** |
| driver INCOMPLETE recompute lines (1576-1582) | `RECOMPUTE_RAN` | yes |
| RUNBOOK recovery paragraph (1260-1269) | `yes` means the rows are stable | **inherits F1** |

## Not reported

- The ssh probes in the trap have no command timeout (now three per host). This is row 21's
  existing note, with no loss.
- A Ctrl-C (SIGINT to the whole process group) during consolidate kills the consolidate too,
  which leaves the dispatcher bucket deleted and the copy partial. That is the atomicity of
  `schema_consolidate`, which predates the branch.
