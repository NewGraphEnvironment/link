# Code-check round 3 (#371)

## Checklist read

- **code-check.md**: the prose of all 14 H3s under `## Mechanisms` (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree; A wrapper's exit is not the work; Zero-length, empty, and unset; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice). Not read: 23 (Rules that stand alone, Security, Spreadsheets and PDFs).
- **code-check-shell.md**: Quoting; BSD vs GNU sed/grep portability; macOS `/usr/bin/awk` aborts on a byte slice; A variable in a sed replacement is parsed; A value validated with one numeric grammar and consumed with another; `for x in $(cmd | grep … || true)`; awk `==` compares version strings as numbers; Reading a file line-by-line drops the last line; Over Tailscale SSH `ssh` exits 0; On this Mac `stat` and `date` are GNU; Empty arrays under `set -u`; `grep -c` exits 1 on zero; A sed/awk range can run to EOF; psql `:'var'` / `\quit N`; `if ! cmd; then rc=$?`; A verification command can be shadowed. Not read: 51.
- **code-check-r.md**: `tryCatch()` nests its handlers; Do not abort inside a handler for a warning raised from C++; A database driver's value is not a base R type; `nzchar(NA)` is TRUE; `system2(stdout = TRUE)` warns on non-zero exit; Rscript reads a script as it runs; `tryCatch(warning = )` discards the value; `expect_message(regexp = "...$")`; A `data-raw/` script must load the source tree. Not read: 102.
- **code-check-spatial.md**: none apply (no terra/sf/GDAL/bcdata in the diff). Not read: 93.

## Findings

- **[severity: fragile]** `data-raw/study_area_finish.sh:174` (`run_timeouts`, the `RUN_BOUND` sed) — the capture `statement_timeout=([0-9][0-9a-z]*)` accepts any digit-led prefix of the value, so a bound line that is cut or glued is read as a different, still-valid bound. Postgres reads a bare number as **milliseconds**. Reproduced on a copy of the function: when the last-sorted host log ends `[wsg_run_one] CCCC statement_timeout=30` with no newline, `RUN_BOUND=30` and the report prints `PGOPTIONS='-c statement_timeout=30'`, a 30 ms bound. The re-model it prints then cancels its first real statement and logs `TIMEOUT after 30ms`. RUNBOOK §8d sends the operator from there to "a real slow statement", which is the wrong diagnosis. A glued value (`30min` followed by a lowercase continuation) comes back as an invalid unit, so that case fails loudly at connect. This is R1's premise (a log cut by a dropped session) with a worse outcome: R1's cut aborted the report, while this one prints a plausible wrong command. The odds are low, because R flushes after each `cat` (measured) and the line is written in one call. Fix: accept only a whole Postgres value, `statement_timeout=([0-9]+(ms|s|min|h|d))([^0-9a-z]|$)`. Alternatively have `wsg_run_one.R` also print the minutes from `bound_ms` and read those, which also brings the printed form in line with `--statement-timeout`.

No other finding.

## Mechanism and enumeration

**Mechanism:** both earlier defects came from one assumption. The driver treats text as structured data without checking that it parses as the structure its consumer expects. R1 assumed a host log is clean UTF-8 text; R2 assumed that lines `echo`ed in sequence make one shell command. Candidate (a) is R2's half and candidate (b) is R1's half. The finding above is a third instance: a field pulled from a log line by a permissive regex is assumed to be a valid, complete value.

### (a) Text printed for an operator to paste, assembled by `echo`

| # | Member (branch adds or changes) | Interpolated values and their charset | Verdict |
|---|---|---|---|
| 1 | Re-model command, `study_area_finish.sh:712-715` | `RUN_BOUND` `[0-9][0-9a-z]*` or `STATEMENT_TIMEOUT_MIN` (digits); `RUN_UID` (validated `^[0-9]{8}_[0-9]{6}-[0-9a-f]{8}$` or generated); `RUN_LABEL` `[A-Za-z0-9._-]`; `SCHEMA`/`CONFIG` `[A-Za-z0-9_]` | **Parses** in every reachable case. Checked by `bash -n` in the test, and by charset: no value can carry a quote, space or `\`. **Value:** the bound can be wrong (finding above). |
| 2 | "raise it" note, `:711` | `TIMED_OUT` (`[A-Z]{4}` CSV) | Holds: prose above the command, not inside its continuation. |
| 3 | `statement bound hit:` lines, `:194-195` | SQL text | Holds: display only, not a command. |
| 4 | "Then recompute the whole run" command, `:730-732` | unchanged by the branch | Holds (pre-existing; nothing the branch changed reaches it). |
| 5 | `wsg_run_one.R` refusal messages (`:91-93`, `:129-131`) | `<N>` placeholder | Holds: a template, not a paste target. |
| 6 | Banner `statement:` / `TEST HOOK:` lines, driver `:458-461` | `STATEMENT_TIMEOUT_MIN`, `LNK_TEST_STALL_WSG` | Holds: display only. |
| 7 | The ssh command string, driver `:1454` (assembled by string interpolation, then executed remotely) | `STATEMENT_TIMEOUT_MIN`, validated to 1..1440 base 10 | Holds: simulated with `bash -c` and the remote sees `[-c statement_timeout=45min] [45]`. |
| 8 | Local-leg env prefix, driver `:1414-1415` | `${PGOPTIONS:+$PGOPTIONS }` | Holds: unset, empty and set all give a valid option string under `set -u` (simulated). |
| 9 | RUNBOOK §8d "A missing group costs only itself" recipe (`RUNBOOK.md:1428-1433`), which the new section calls "Recover as above" | placeholders | Parses, but carries **no** `PGOPTIONS`. It is a second copy of the re-model that the branch did not update, so an operator following the RUNBOOK re-models unbounded. Documentation drift, not a code defect, so it is not in Findings. |

### (b) Parsing host logs as text (bytes, lines, locale)

| # | Member | Verdict |
|---|---|---|
| 1 | `run_timeouts` file selection, `find … "${RUN_UID%-*}_run_*.log"` | Holds: `RUN_UID` is validated or generated, so the prefix is the run's `TS`; `_run_*.log` matches only the host logs (`_run_local`, `_run_<ws>`). |
| 2 | Concatenation via `while read f; cat "$f"` | Reading the filename list holds (`printf '%s\n'` terminates it). `cat` joins a log's unterminated last line onto the next log's first line, which feeds #4 and #5. |
| 3 | `RUN_BOUND` sed and awk (`LC_ALL=C`) | Bytes and locale hold (R1 fix). **Value does not hold:** a truncated or glued value is accepted (Finding). |
| 4 | `TIMEOUT_LINES` sed/awk/sort (`LC_ALL=C`) | Holds. `\t` in a BSD sed replacement is a real tab (measured on macOS `/usr/bin/sed`). The statement is space-squished by `.lnk_timeout_statement`, so it carries no tab to break `-F'\t'`. Membership is exact-token (`index(",want,", ",WSG,")`). A cut statement only garbles display. |
| 5 | `TIMED_OUT` sed (`LC_ALL=C`) and `paste -sd,` | Holds; empty input gives `""`. |
| 6 | Display `sed 's/^/      /'` without `LC_ALL=C` | Accepted tradeoff (measured rc 0). |
| 7 | `host_log_reported` (`study_area_hosts.sh:256`, pre-existing): `grep -oE` then `awk`, no `LC_ALL=C`. The branch adds new content (SQL text) to the logs it reads | Holds: measured that macOS `/usr/bin/grep` 2.6.0 returns both markers around an invalid `e2 9c` byte, rc 0. The new `statement_timeout=` and `TIMEOUT` lines cannot match its `[A-Z]{4} done` / `SKIP` patterns. |
| 8 | Bytes R writes into a log (`wsg_run_one.R` `cat` of the statement) | Holds: `substr` and `nchar` count characters on UTF-8-marked strings. In a C locale (a cypher under non-interactive ssh), `cat` writes `<U+…>` escapes, which are ASCII. Encoding errors inside `.lnk_timeout_statement` are swallowed by `name_timeout`'s `tryCatch`, so the TIMEOUT line goes missing but the original error is not replaced. |
| 9 | Line integrity of the markers themselves | Holds for detection: matching is unanchored (#347). R flushes stdout on every `cat` (measured: 43 bytes present 2 s into a 4 s Rscript), so a whole marker line goes out in one write. A mid-line cut needs the session to drop inside that write: unlikely, and #3 is the one place its effect is not cosmetic. |
