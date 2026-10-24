# Code-check round 1 — link#371 statement bound

## Checklist read

- **code-check.md** (37 H3): read the prose of all 14 `## Mechanisms` H3s (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree; A wrapper's exit is not the work; Zero-length, empty, and unset; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice), tables skipped. 23 not read in full (index lines only).
- **code-check-shell.md** (67 H3): read BSD vs GNU sed/grep portability; macOS `/usr/bin/awk` aborts on a byte slice; Reading a file line-by-line drops the last line; Quoting; A variable in a sed replacement is parsed; `for x in $(cmd | grep … || true)` hides a failing cmd; On this Mac `stat` and `date` are GNU. 60 not read in full.
- **code-check-r.md** (111 H3): read `tryCatch()` nests its handlers; Do not abort inside a handler for a warning raised from C++; `on.exit()` at a script's top level never fires; A `data-raw/` script must load the source tree; Tests that silently do not run; `system2(stdout = TRUE)` warns; `tryCatch(warning = )` DISCARDS the value. 104 not read in full.
- **code-check-spatial.md** (93 H3): none apply (no spatial code in the diff); 93 not read in full.

## Findings

- **[severity: bug]** `data-raw/study_area_finish.sh:408-411` (`run_timeouts`) — the first `sed -nE` over the raw host logs runs in the caller's UTF-8 locale. On the dispatcher that is macOS `/usr/bin/sed`, which aborts with `sed: RE error: illegal byte sequence`, rc 1, on the first byte that is not valid UTF-8 anywhere in any `<ts>_run_*.log` (e.g. a cli glyph `✔` cut off when an ssh session drops or a process is killed mid-write). The driver runs under `set -euo pipefail`, and `TIMEOUT_LINES=$(… | sed … | awk … | sort)` is a plain assignment inside a function called bare from `run_finish_report`, so pipefail carries sed's 1 out and errexit kills the driver in the middle of the INCOMPLETE report. Everything printed after `run_timeouts` is lost: the "statement bound hit" lines, the re-model command, the `--recompute-only` command, and the RECOMPUTE_FAIL ("bad output, not missing output") and COMPARE_FAIL blocks. The function's own comment says "Never fatal". Reproduced in a scratch copy: one log holding `printf 'cli \xe2\x9c'` beside a valid TIMEOUT log → `sed: RE error: illegal byte sequence`, exit 1, the following `echo` never runs; remove that log → `reached: TO=OKAN`, exit 0. Fix: `LC_ALL=C` on the `sed` (and the `awk`), and make the assignment non-fatal (`… ) || TIMEOUT_LINES=""`), as the `find` line already is. A `cat` of a log that vanished between `find` and `cat` fails the same way.

- **[severity: fragile]** `data-raw/study_area_finish.sh:711` — under `--recompute-only` the driver refuses `--statement-timeout`, so `STATEMENT_TIMEOUT_MIN` is unset there and the printed re-model always carries `statement_timeout=30min`, whatever bound the original run used. RUNBOOK §8d says "the printed re-model carries the run's `PGOPTIONS` bound". That holds in a full run only. If the run used a raised bound (say `--statement-timeout=120`) because a group needs it, an operator who pastes the re-model printed by a later `--recompute-only` re-models that group at 30 min, and it can be cancelled again. Either read the bound off the run's timeout lines or log, or say in the printed text and the RUNBOOK that the 30 is a default to raise.

No other issues found. Checked and clean:
- PGOPTIONS precedence: a startup option (PGC_S_CLIENT) beats `ALTER ROLE` settings, and a later `-c` beats an earlier one, so the appended local-leg bound wins.
- Nothing in link or fresh `R/` runs `SET`, `RESET` or `DISCARD` on `statement_timeout`.
- Calling-handler semantics: an inner `tryCatch` catches first, so the outer handler prints exactly once for a direct, a `.lnk_db_execute`-wrapped or a `dbWithTransaction`-re-thrown cancel.
- `lnk_pipeline_run`'s `on.exit` still records the failure.
- `link:::` under `load_all` resolves to the dev namespace.
- `withr` is declared.
- The bad-value driver test cannot dispatch: it fails at the `--focal` count check.
