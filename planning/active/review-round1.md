# Code-check round 1 — branch 369 (`git diff 102762da...HEAD`)

## Checklist read

- `index_code-check.md`, `index_code-check-shell.md`, `index_code-check-r.md`, `index_code-check-spatial.md`: all four in full.
- `code-check.md`: the prose of all 14 H3s under `## Mechanisms`, with the `|` table rows and evidence blocks skipped. I read none of the "Rules that stand alone" sections in full; their index lines name nothing this diff uses.
- `code-check-shell.md`: 9 sections in full: "`wait` with no argument…", "`if ! cmd; then rc=$?`…", "A second `trap … EXIT` replaces the first", "A failed `cd`…", "`for x in $(cmd | grep … || true)`…", "Put cleanup on the EXIT trap, not RETURN…", "A `local` statement cannot read a variable it is assigning…", "`grep -c` prints the count AND exits 1…", "`exit` inside a loop condition…". The other ~65 I took from their index lines only.
- `code-check-r.md`: 4 sections in full: "An `information_schema` lookup by the literal table name…", "Postgres row order is never fixed…", "`system2(stdout = TRUE)` warns…", "A `function(...)` mock hides arguments…". The others I took from their index lines only.
- `code-check-spatial.md`: index only. Nothing in this diff is spatial.

## Findings

- **[severity: bug]** `data-raw/study_area_legs.sh:211-215`. The fallback in `legs_wait` for a `wait` that reports no job can never run. Instead it aborts the driver. `wait -n -p who` *unsets* `who` when it returns without a job: exit 127 when no listed pid is a child, or >128 when a trapped signal interrupts it. Under the driver's `set -u`, the very next `[ -z "$who" ]` then dies with `who: unbound variable`. The `who=""` on line 210 does not help, because `wait -p` unsets the variable first. Since `legs_wait` is called bare, the driver exits through the EXIT trap in the middle of the legs. Hosts that have not been finished stay held and are kept. The legs that are still modelling run on unwatched, and nothing after `legs_wait` runs (dispatcher accounting, coverage, recompute). The header comment ("A pid wait cannot report (not a child) is waited on directly, so the loop always ends") states the opposite.
  - Reproduced on bash 5.3.9 against a copy of the four libs under `/private/tmp/claude-501/rv369/`, with `LOCAL_PID` a real child and `CY_LEG_PID[a]=1`. The first `wait -n` returns the child. The second runs on the non-child alone and prints `study_area_legs.sh: line 212: who: unbound variable`, then `EXIT trap rc=1`.
  - The same unset happens for a trapped signal (`t4.sh`: `rc=158 set=` then `who: unbound variable`).
  - Fix: `[ -z "${who:-}" ]`. No test reaches this branch: every `test-study_area_legs.R` case passes real child pids.

- **[severity: fragile]** `data-raw/study_area_legs.sh:234-241` with `data-raw/study_area_hosts.sh:425-432`. A host deferred for overlapping the dispatcher's bucket is reported as kept mid-run.
  - `CY_LEG_DONE[$ws]=1` is set *before* the overlap deferral. So once another cypher finishes before the dispatcher leg, that cypher's `burn_cyphers ended` counts the deferred host as ended.
  - The deferred host is still `CY_HOLD=1`, so it goes on the keep list. `hosts_kept_report` then writes it to `<TS>_kept_hosts.tsv` and prints `=== HOSTS KEPT (n) — still running and billed ===`, giving the reason `run stopped before consolidate released it; may hold finished groups` (`.hosts_keep_cause`). That is false mid-run: the run will consolidate the host once the dispatcher ends. Each such burn also runs an ssh `host_split` against it.
  - Rule 5 and the RUNBOOK ("so `<TS>_kept_hosts.tsv` and its banner never list a host still modelling") are true to the letter, but an operator reading the banner sees a host waiting to be consolidated described as one the run gave up on.
  - No data is lost: the host stays held, and the final `burn_cyphers` rewrites the record.
  - Fix: set `CY_LEG_DONE` only when the host is handed to `host_finish_leg`, or skip deferred hosts in `burn_cyphers ended`. `CY_RUN_RC` must still be recorded at once for `.hosts_settled`.

## Checked and found sound

- **errexit through `legs_wait` → `host_finish_leg` → `host_consolidate` / `host_release` / `.legs_no_outcome`.** Called bare under `set -euo pipefail`. I walked every simple command:
  - Each failure is either tested (`||`, `if`, `elif !`) or comes from a helper that cannot fail.
  - `host_release` returns 0 on every path, and `host_split` sits in an `elif !`.
  - `burn_cyphers ended || true` turns errexit off for the whole burn.
  - The consolidate subshell keeps `cd … || exit 1` where errexit is off.
- **The EXIT trap's view at each point in `legs_wait`:**
  - Blocked in `wait`: legs that have ended are not yet recorded, so they read unsettled.
  - During accounting or release: `CONSOLIDATING` is empty or `0` and `CY_RUN_RC` is set, so the host is settled, held and measured.
  - During a copy: `CONSOLIDATING=<ws>`, so that host alone reads unsettled. `CONSOLIDATING=0` from the driver's initialisation does not match any workspace name.
- **`wait -n -p` on 5.3.9:**
  - A job that ends during another host's long foreground work is returned on the next call with its own status (`t1.sh`).
  - A job already returned is returned again (`t2.sh`), which is why the pending-list filter matters.
  - When two jobs had both ended, the one that ended later came back first. Harmless.
- **Background backup:**
  - The rc file is written by the outer subshell. A failed write leaves no file, which reads as non-zero, so it fails closed.
  - The prep `wait` now waits on `PREP_PIDS` only. No other bare `wait` remains in the driver's main shell; the pool waits on its own pids.
- **`consolidate_outcomes "$tsv" "$ws"`:**
  - The ok=FALSE, missing-row and ok=TRUE-with-crc≠0 cases each append to `CONS_FAILED` / `CONS_EXCLUDED` exactly once.
  - `state_unwritten` and `no_outcome` both reach `CY_CONS_FAIL`, so `run_expected_from_hosts` drops their signals and `RUN_INCOMPLETE` is set.
- **`consolidate_state_write` / `run_unconsolidated_from_state`:**
  - A host not yet consolidated has no rows, and `--recompute-only` handles that consistently: its groups have no run_uid rows on the dispatcher and fall out at coverage.
  - Both headers are accepted.
- **Quoting:**
  - `.legs_consolidate_r` (unquoted heredoc): `\$` becomes `$`, and `'\t'` reaches R intact.
  - The persist-init and backup `Rscript -e` strings: `\$` is escaped and `\\n` becomes `\n`.
- **Persist-init species set** matches `cypher_prep.sh`. `consolidate_missing_persist()` runs before the DELETE.
- **The R catalog skips fail toward issuing every statement**, as before. `CREATE TABLE IF NOT EXISTS` and `CREATE OR REPLACE VIEW` take no lock that conflicts with ROW EXCLUSIVE.
- **The tests can fail:**
  - Removing the pending filter makes the loop endless, so `system2(timeout = 60)` fails.
  - `ok_exit1` pins the "no release after no outcome" rule.
  - The mid-run `kept_mid.tsv` pins the `ended` scope.
  - The hosts test pins `CONSOLIDATING` naming the host.

## Not verified

- **The bash 5.1 / 5.2 floor.** Only 5.3.9 is on this machine. Whether `wait -n` with pid arguments returns a job reaped during an earlier foreground command is version-dependent. If it does not, legs are taken late, not lost: statuses come from the saved-pid list. Through the empty-`who` path above, though, it reaches the abort.

/Users/airvine/Projects/repo/link/planning/active/review-round1.md
