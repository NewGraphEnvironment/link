# Code-check round 3 — #375 (`<TS>_phases.tsv`)

Diff: `git diff e496d853...HEAD -- data-raw/study_area_finish.sh data-raw/study_area_phases.sh data-raw/study_area_run.sh tests/ RUNBOOK.md`

## Checklist read

None of the four FULL TEXT files is under 40,000 bytes, so none was read in full.

- `code-check.md` (330,698 B): read the prose of all 14 H3s under `## Mechanisms`, without their `|` table rows. Of the stand-alone rules I read only the index lines, and none names a shape this diff uses.
- `code-check-shell.md` (124,118 B): read in full the sections for the shapes this diff uses. These were: `wait` with no argument; `if ! cmd; then rc=$?`; a second `trap … EXIT`; parallel writers sharing one output file; a failed `cd`; `stat`/`date` are GNU on this Mac; cleanup on EXIT, not RETURN; `&` binds to the whole `&&` list; empty arrays under `set -u`. I did not read the other ~85 sections.
- `code-check-r.md` (177,187 B): read the index only. The R diff is two testthat files that run bash through `system2()` and read the result with `read.delim()`. I checked those two index entries (`system2(stdout = TRUE)` warns, `read.delim()` quotes by default) against the tests, and both are handled: the tests read the status attribute and pass `quote = ""`. I did not read any section in full.
- `code-check-spatial.md` (155,517 B): index only. Nothing spatial is in this diff, so I read 0 sections.

## The mechanism behind round 1

The assumption was that wrapping an existing block in a new compound leaves the block behaving as before. The wrappers were an outer `( … ) &`, a status capture `|| var=$?` and the extra process layer. The assumption fails because the wrapper changes the context the block runs in. Round 1 hit the errexit case: a block on the left of `||` runs with `set -e` off. That case has siblings, and I listed every place this diff wraps, moves or re-derives something:

| place | sibling | verdict |
|---|---|---|
| local model leg, inner `( … ) || mrc=$?` | errexit off inside | fixed (`cd … \|\| exit 1`). Nothing else in the loop relied on errexit; `Rscript \|\| echo` is accepted. |
| cypher prep, inner `( … ) || prc=$?` | errexit off inside | accepted. Re-checked: a failed `date` in the deadline arithmetic now runs on to the `ssh_ok != 1` branch and exits 1, the same outcome. |
| cypher model, `ssh … || mrc=$?` | errexit off | one simple command: no change. |
| `LOCAL_PID` / `CY_PID[$WS]` = the wrapper subshell, not ssh | a PID that now names a different process | only `wait` reads them (`host_wait`, line 1524), and `exit "$mrc"` passes the status through (signal codes too, as 128+n). `host_release` and `.hosts_settled` read `CY_RUN_RC`, which is unchanged. |
| outer wrappers are new forked processes | do they inherit the EXIT trap (a leg running `burn_cyphers`)? | no. Measured on bash 5.3: a `( … ) &` subshell runs no inherited EXIT trap. |
| outer wrappers keep the driver's stdout and stderr | a new fd lifetime | **finding 1** |
| wrappers carry the driver's argv | `pkill -f study_area_run` now matches them | measurement only: ssh still survives, but that leg's late row is lost (folded into finding 1). |
| `phases_close_open \|\| true`, `phases_report \|\| true` in `on_exit` before `burn_cyphers` | could the new code stop the burn? `\|\| true` does not cover `set -u` | every expansion is `:-`-guarded or a declared map, and every `phase_end` caller passes `$4`. No key is empty (each holds `\|`), so `bad array subscript` cannot happen. `unset` arguments are quoted, so they are never globbed. `$?` reaching `burn_cyphers` is 0, as before. |
| new main-shell code after spend (`RUN_N=$( … )`, `cons_n=$(( … ))`, `phase_*`) | errexit abort between dispatch and consolidate | none can fail. `csv_count` always prints a number, `cons_st` is set on every path, and every `phase_*` function returns 0. |
| `phase_end` inside a subshell | a global written where the parent cannot see it | the parent's `PHASE_OPEN` copy is cleared by `phase_forget` after each wait, and `phases_close_open` dedupes on phase, host and start. Exercised in a temp copy: correct. |

Statuses, counts and times against what each row says. `prep`/WS needs both exit 0 and READY. `model` is the session exit, which is accepted. `burn` is checked against `CY_BURNED`, the map `burn_cyphers` really sets. `coverage` is right; `COV_MISSING` is the union. `views` reads `RECOMPUTE_FAIL`, which only the views and log-table steps can have set by then. `recompute` and `compare` are right. Each `groups` value counts what the phase was given. One borderline case I judged sound: the `consolidate` status is taken from `crc` before `host_release`, the step the row's comment says it covers. A host kept for "finished groups left after consolidate" can therefore sit beside `consolidate ok`. With `crc=0` those groups were never in the copy's bucket (`CY_UNCONS` adds mapping-code-complete groups that are absent from `CY_BUCKET_DONE`), so "ok, covering all it was given" holds literally.

Bounds. Every begin and end brackets the work it names. Nothing a row claims runs before its begin or after its end. `host_baseline` and `run_expected_from_hosts` sit outside every row, and the critical path still covers them. The critical path counts only rows with two parseable ISO times, all from the dispatcher's own clock (an ssh leg's row is written on the dispatcher). Skipped rows are excluded, and so are rows whose `date` failed. Each invocation has a new `TS`, so `phases_init` never appends to an earlier run's file. On the trap path, a phase closed `failed` ends at the moment of exit, which is the truth for that report.

## Findings

- **[severity: fragile]** `data-raw/study_area_run.sh:1355` (prep wrapper `( prc=0 … ) &`), `:1470` (dispatcher model wrapper `( mrc=0 … ) &`) and `:1513` (cypher model wrapper `( mrc=0 … ) &`). Before the diff, each leg's only open file descriptors were its log: `( … ) > log 2>&1 &` and `ssh … > log 2>&1 &` apply the redirection in the forked child. Now each outer wrapper inherits the driver's stdout and stderr and holds them until its leg ends. The redirection applies only to the inner command.
  - **Effect:** a driver that exits while legs are still running, which is the kill path RUNBOOK §8d documents, no longer sends EOF to whatever reads its output. A driver run as `… | tee run.out`, or under any harness that waits for EOF on the driver's output, now hangs until the last model leg ends, which can be hours.
  - **Measured on bash 5.3:** `bash -c '( ( sleep 3 ) >/dev/null 2>&1 ) & exit 0' | cat` returns in 0 s. The new shape, `bash -c '( rc=0; ( sleep 3 ) >/dev/null 2>&1 || rc=$?; exit $rc ) & exit 0' | cat`, returns in 3 s.
  - **Related:** the wrappers are forked copies of the driver, so they carry its argv. `pkill -f study_area_run` therefore now also kills the prep and cypher-model wrappers. The ssh sessions survive, because their argv lacks the pattern, but the late row RUNBOOK promises ("that leg later writes its own row too") is never written for those legs.
  - **Neither touches burn or hold safety,** and the documented launch (`nohup … > file`) is unaffected.
  - **Fix:** point the wrapper's own stdout and stderr at the log, or at `/dev/null`, after the inner command. It prints nothing (`quiet`) except the unwritable-file WARN, which could go to the log. For example, open the wrapper as `( … ) >>"$LOG_DIR/${TS}_run_local.log" 2>&1 &`, with the inner redirection unchanged.
