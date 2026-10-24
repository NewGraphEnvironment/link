# Code-check round 1 — #375 phases.tsv (study_area_phases.sh + driver/finish wiring)

## Checklist read

- `code-check.md` (330 KB): the prose of all 14 H3s under `## Mechanisms`, tables and evidence blocks skipped. Of the 30 H3s outside Mechanisms (stand-alone rules, Security, Spreadsheets/PDFs), none read in full: none applies to this diff.
- `code-check-shell.md` (124 KB): read in full 8 sections: "Empty arrays under `set -u`", "Parallel writers sharing one output file", "On this Mac `stat` and `date` are GNU", "`&` binds to the whole `&&` list", "`wait` with no argument", "`if ! cmd; then rc=$?`", "A second `trap … EXIT`", "Put cleanup on the EXIT trap, not RETURN". About 60 others not read in full; their index lines were read.
- `code-check-r.md` (177 KB): read in full 6 sections: "Tests that silently do not run", "testthat counts an uncaught error under `error`", "A `skip_if_not()` skips only its own block", "`expect_gt()` and friends take no `info`", "`system2(stdout = TRUE)` warns on a non-zero exit", "`read.delim()` quotes by default". About 115 others not read in full.
- `code-check-spatial.md` (156 KB): none read in full; the diff has no spatial code.

## What was verified by running code (temp copies only)

- A leg shaped like the driver's ssh wrapper (`( mrc=0; cmd > log 2>&1 || mrc=$?; phase_end … quiet; exit "$mrc" ) &`), run under `set -euo pipefail` with the real `study_area_hosts.sh` and `host_wait`: a child that exits 255 is recorded as `CY_RUN_RC=255`. The wrapper passes the status through unchanged, so `host_release` sees the same value it saw before this change.
- The parent's EXIT trap does not fire in the `( … ) &` leg subshells (bash 5.3), so a leg that ends cannot run `burn_cyphers`.
- `on_exit`: `phases_close_open || true` and `… || phases_report || true` both leave `$?` at 0 before `burn_cyphers`, which reads the caller's status on entry. Before this change `local rc=$?` also left it at 0, so the trap still returns the status it did before. Under `set -u`, every expansion in the trap path is defaulted (`${PHASES_TSV:-}`, `${RUN_UID:-}`, `${2:-}`) or assigned before use (`PHASE_OPEN`). Every `phase_end` call site passes its 4th argument. So no unbound-variable abort can stop the burn.
- `tests/testthat/test-study_area_phases.R` run from a temp copy: 0 failed, 0 errors, 0 skipped.

## Findings

- **[severity: fragile, low impact]** `data-raw/study_area_run.sh:1469-1477`: wrapping the dispatcher leg as `( cd "$REPO_ROOT"; for … ) > log 2>&1 || mrc=$?` puts the inner subshell on the left of `||`, so bash turns off errexit for its whole body. Reproduced on bash 5.3: `( cd /nonexistent; echo continued ) > log || mrc=$?` prints `continued` and gives `mrc=0`. Before this change the inner subshell ran with errexit on, so a failed `cd "$REPO_ROOT"` ended the leg non-zero. Now it carries on in the driver's current directory, every `Rscript data-raw/wsg_run_one.R` fails, and the leg exits 0 with a `model … ok` row. The damage is small: the dispatcher has no host to burn, and `account` still reports the missing groups. But this is the one place the change silently weakened a guard. `cd "$REPO_ROOT" || exit 1` restores it. The prep wrapper (lines 1361-1404) also runs with errexit off now, but that body already ends in explicit `exit 1` / `scp && ssh`, and the READY gate stands apart from it, so its outcome does not change. The ssh model leg has no inner subshell.

Nothing else found. Checked and clean:
- Every exit path closes or skips its phase: coverage FATAL, consolidate failure `exit 1`, READY-gate and tofu FATALs, `--recompute-only` before and after its `prep` row.
- `cons_st` is set on every branch.
- `burn`'s `bst` logic.
- `RUN_N` under `pipefail`.
- The parallel `>>` appends: about 120-byte rows, one `printf` each.
- The duplicate check in `phases_close_open` (string compare on the ISO start).
- `phases_report` runs before the INCOMPLETE `exit 1`, and `PHASES_REPORTED` stops the trap printing the table twice.
- `--preflight-only` writes nothing.
- The evidence logs in `data-raw/logs/phases_375/` hold no host addresses.
