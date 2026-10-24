# Code-check round 2: #375 phases.tsv (diff2.patch, through bca489a6)

## Checklist read

- code-check-r.md (177 KB): index read in full; no full sections read. The R side of this
  diff is testthat scaffolding (`system2()`, `read.delim(quote = "")`) already covered by
  index lines I checked against the code (`system2` status attr, `read.delim` quoting).
- code-check-shell.md (124 KB): index read in full; full sections read (10): "Empty arrays
  under `set -u`", "`&` binds to the whole `&&` list", "`wait` with no argument", "`if ! cmd;
  then rc=$?`", "A second `trap … EXIT`", "A failed `cd` lets every later command run",
  "Put cleanup on the EXIT trap, not RETURN", "Parallel writers sharing one output file",
  "`exit` inside a loop condition", "`for x in $(cmd | grep … || true)`". The remaining
  ~60 headings not read in full.
- code-check-spatial.md (156 KB): index read in full; nothing spatial in the diff, so no
  full sections read.
- code-check.md (331 KB): prose of all 14 `## Mechanisms` H3s read in full (table rows
  skipped); other sections by index only.

## The bca489a6 fix

`( cd "$REPO_ROOT" || exit 1; for … ) > log 2>&1 || mrc=$?` is correct. Reproduced in a temp
copy of the lib with `REPO_ROOT=/nonexistent/x` under Homebrew bash 5.3: the leg exits 1
(`wait $LOCAL_PID` reports rc=1), the row is written `failed`, and nothing in the loop runs.

## Every place the diff put existing code where errexit is off

1. **Dispatcher model leg, inner subshell** (left of `|| mrc=$?`). Contents: `cd` (now
   `|| exit 1`), `for w in $(echo … | tr …)`, env-prefixed `Rscript … || echo "[WARN] …"`.
   Relied on errexit before: the `cd` (fixed). Otherwise only the trailing `echo` of the
   `Rscript || echo` list: before, if Rscript failed *and* the echo's write to the log
   failed (for example disk full), errexit ended the leg; now the loop continues to the next
   group. That is the soft-fail behaviour the loop was written for, and the leg's later
   groups fail on the same disk anyway. Not a defect. The `for` word-list substitution never
   triggered errexit (probed: `set -e; for w in $(false; echo a b)` runs).
2. **Cypher model leg** (`ssh … > log 2>&1 || mrc=$?`). One simple command; before, it was
   the async command itself. Its status reaches `host_wait` unchanged through
   `exit "$mrc"`. stdin is still /dev/null (inherited from the async subshell), and SIGINT
   is still ignored as for any async job. Nothing relied on errexit.
3. **Prep wrapper, inner subshell** (left of `|| prc=$?`). Rechecked: the `ssh_deadline=$((
   $(date +%s) + … ))` assignment would have aborted under errexit if `date` failed. Now
   the deadline comes out as `PREP_SSH_WAIT_S` alone, the `while` test is false at once,
   `ssh_ok` stays 0, and the explicit `exit 1` fires. Same outcome. `sleep 10` failing used
   to abort; now the loop goes on until the deadline. Harmless. The body still ends in
   explicit `exit 1` or `scp && ssh`, and the READY gate is separate and unchanged. Round
   1's judgement stands.
4. **Outer wrapper subshells** (model ×2, prep). errexit is on: they are async, not
   tested. `phase_end` always returns 0. Its only way to fail is the WARN `echo` to a dead
   stderr after a failed row write. Then the subshell exits non-zero before `exit "$mrc"`.
   That fails toward *keeping* the host (host_release keeps any non-zero session). It can
   never turn a non-zero leg into 0, because nothing before `exit "$mrc"` exits 0.
5. **on_exit**: `phases_close_open || true` and `[ … ] || phases_report || true`. New code,
   so nothing in it relied on errexit. `|| true` does not cover nounset errors, so I checked
   every expansion in `phases_close_open`, `phase_end`, `phase_print` and `phases_report`.
   Each is defaulted (`${PHASES_TSV:-}`, `${2:-}`, `${3:-}`, `${5:-}`, `${RUN_UID:-}`,
   `${PHASES_REPORTED:-0}`), or always passed (`$1`, and `$4`, which `phases_close_open`
   passes), or declared (`PHASE_OPEN`, assigned at source time).
   `${#PHASE_OPEN[@]}` on a map emptied by unset reads 0 under `set -u` (probed on bash
   5.3). The lib is sourced (line ~486) before `trap on_exit EXIT` (line 547), so the
   functions always exist when the trap runs. `burn_cyphers`'s own `local rc=$?` still sees
   0 from the line before it, as it did before.
6. **Command substitutions as arguments** (`"$(csv_count …)"`, `"$(.hosts_n …)"`,
   `"$([ … ] && echo ok || echo failed)"`). New code. `RECOMPUTE_FAIL` and `COMPARE_FAIL`
   are set before they are read.
7. **study_area_finish.sh**: the `phase_*` calls are added inside `run_finish`,
   `run_finish_recompute` and `run_finish_compare`, which are still called untested from
   top level. No existing code moved into a tested context.
8. **Burn**: `burn_cyphers || true` is unchanged. It now sits under `[ "$N_CY" -gt 0 ]`,
   which changes nothing: with no cyphers `CYPHERS_UP=0` and `burn_cyphers` returns at its
   first line.

Also checked: subshells do not run the parent's EXIT trap, so no leg wrapper can call
`burn_cyphers`. `cons_st` is set on every path that reaches `phase_end consolidate`, the
carry-on path (#358) included. The fatal consolidate branch closes its row before
`exit 1`, so the trap does not write it twice. The new top-level `RUN_N=$(…)` pipeline is
sed/sort/wc only, and `CY_BUCKET` is set for every workspace, so it cannot abort the driver.

## Clean
