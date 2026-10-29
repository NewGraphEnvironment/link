# Code-check round 1: link#372 pre-run gate (22034de5...HEAD)

## Checklist read

- **code-check.md** (index read in full). Read in full, prose only (table rows skipped): all 14 `## Mechanisms` H3s: A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice. I did not read the 22 standalone, security and spreadsheet sections in full; their index lines were enough to rule them out.
- **code-check-r.md** (index read in full). Read in full: `read.delim()` quotes by default; `system2(stdout = TRUE)` warns on a non-zero exit; An `information_schema` lookup by the literal table name; `on.exit()` at a script's top level never fires; Rscript reads a script as it runs; `tryCatch()` nests its handlers; A value compared as `::text`. Index-only for the other ~130 headings.
- **code-check-shell.md** (index read in full). I applied these from their index lines and the full text quoted in CLAUDE.md: Quoting; psql `:'var'` inside dollar quotes; `wait` with no argument; `if ! cmd; then rc=$?`; `timeout` is GNU; `grep -c`; A second `trap … EXIT`; A failed `cd`; A heredoc whose body contains its own delimiter; macOS awk byte slice. Index-only for the remaining ~55.
- **code-check-spatial.md** (index read in full). Nothing in this diff does spatial work beyond `ST_Intersects` counts in two input queries, so I read none of its sections in full.

## Findings

- **[severity: bug]** data-raw/pretest.R:335 (`pretest_record_check`) together with data-raw/pretest_verdict.R:87-93 and the map row `link,^DESCRIPTION$,none`. **A record that modelled nothing clears a run on any fresh.**
  - When no changed file is on the modelling path, the verdict writes `pass` with `fresh_sha = NA`.
  - The record check compares fresh only `if (!is.na(rec$fresh_sha))`, and diffs only link files between the record's SHA and HEAD.
  - DESCRIPTION maps to `none`, on the stated reason that "the fresh pin reaches the gate as fresh's own changed files". That holds at pick time, but nothing in the record check computes fresh's changed files.
  - So a commit after such a record that bumps the `Remotes:` fresh pin, plus `update_hosts.sh fresh` on the dispatcher (cyphers install the pin), clears preflight on a fresh the gate never picked against or modelled.
  - Reproduced with `pretest_record_check()` on a temp repo. The record had `fresh_sha = NA`, the history and `since` were at commit 1, and HEAD bumped DESCRIPTION `fresh@v0.44.0` to `@v0.45.0` with installed fresh `"sha_of_fresh_v0.45.0"`. The result was `ok = TRUE`.
  - The modelled case is safe only on the dispatcher, through `fresh_sha` equality. A pin bump without a reinstall there leaves cyphers on a fresh the gate did not run, and that is caught only by host parity after spin.
  - Fix:
    - In the record check, refuse when `pretest_fresh_pin()` at `rec$link_sha` differs from the pin at HEAD.
    - When the record carries no `fresh_sha`, record and compare the installed fresh anyway. The pick or the verdict can read it as preflight does.
    - Or map DESCRIPTION to `any` rather than `none`.

- **[severity: fragile]** data-raw/pretest.R:133 (`pretest_changed_fresh`). **fresh's changed files are read from `R/` only, so a fresh data file on the modelling path never reaches the map.**
  - `frs_wsg_drainage()` reads `inst/extdata/wsg_outlet.csv` (fresh `R/frs_wsg_drainage.R:154`). That function is the `dams` input row (the downstream guard, `lnk_wsg_resolve`).
  - A fresh release that changes only that CSV gives an empty fresh diff. It is neither mapped nor refused. The header's "an unmapped file refuses the gate" holds for link but not for fresh.
  - fresh's other `inst/extdata` CSVs are fallbacks link does not use, because it always passes `cfg`, so the gap today is one file.
  - Fix: diff `R/ inst/extdata/` (or the whole tree minus docs) and map what appears, which the existing `none` rows already make cheap.

- **[severity: fragile]** data-raw/pretest_pick.R:73-81. **The pick never checks `since` against the history the record check will hold it to.**
  - `pretest_record_check()` refuses unless `rec$since_sha` is an ancestor of every history `link_sha`, but the pick only resolves `since`.
  - An explicit `--since=` newer than some group's newest build gets the full gate run and a `pass` row written. Then `study_area_run.sh` refuses it ("range starts at …, after history built at …"). The same happens when `pretest_since_default()`'s "earliest date" SHA is not an ancestor of a group re-modelled later from an older commit (for example from a worktree).
  - It fails closed, but only after hours of modelling.
  - Fix: run the same `pretest_is_ancestor(since_sha, h)` loop over `built$link_sha` in the pick and refuse (exit 2) before anything is modelled.

- **[severity: fragile]** data-raw/pretest_run.sh:182. **An empty field in picks.tsv shifts every later column.**
  - `IFS=$'\t' read -r wsg inputs minutes host bound smin` treats tab as IFS whitespace, so consecutive tabs collapse.
  - A group whose history row has `host` NULL is written as an empty field (`na = ""` in pretest_pick.R:188). Then `host` gets the bound, `bound` gets the statement minutes, and `smin` is empty.
  - The PGOPTIONS then carry `statement_timeout=min`, and the wall-clock deadline is computed from the wrong column. Measured with bash 5.3: `host=[15] bound=[15] smin=[]`.
  - It fails closed (the connection or the group fails). Today none of fresh_default's 241 newest rows has a NULL host.
  - Fix: write `host` as `unknown` when NA, or split on a non-whitespace IFS (`IFS=$'\x1f'` after `tr '\t' '\x1f'`), or read the columns with `cut -f`.

- **[severity: fragile]** data-raw/pretest.R:86 and :310 (`pretest_git`, `pretest_is_ancestor`).
  - **The arguments are not quoted.** `system2()` pastes them raw into `/bin/sh`, and `--since` / `--until` (operator text, validated nowhere in pretest_run.sh or pretest_pick.R) and the `link_sha` / `since_sha` values read from the database reach it that way. A space, `;` or `$( )` in any of them is executed or split by the shell. Fix: `shQuote()` each ref, or validate refs as `^[0-9A-Za-z._/^{}~-]+$` and SHAs as hex before use.
  - **`pretest_git()` uses `stderr = TRUE`.** Any git warning on stderr ("inexact rename detection was skipped…", "refname … is ambiguous") becomes a line of output. In a `diff --name-only` it reads as a changed path, refused as "unmapped" with a misleading message. In `rev-parse` it makes `since_sha` length 2, which writes three lines to `range.txt`, and the run then refuses on `until != HEAD`. Both fail closed. Fix: capture stderr separately (`stderr = FALSE`, or a tempfile) and include it only in the error text.

## Checked and not findings

- **Scratch clone and the real sequences.** In `fresh` (the bcfishpass persist), `crossings_vw_bcfp`, `modelled_stream_crossings` and `streams_vw_bcfp` have `nextval('fresh.…_seq')` defaults. `LIKE … INCLUDING DEFAULTS` makes the scratch tables depend on fresh's sequences. I measured this in `zz_` schemas, now dropped: a plain `DROP TABLE` of the source then errors. `ogr2ogr -overwrite` (snapshot_bcfp.sh) drops with CASCADE and succeeded, silently stripping the scratch default. No non-CASCADE drop of those tables exists in R/ or data-raw/, so nothing breaks today. fresh_default has no serial or identity columns.
- **Index defs.** All 62 in fresh_default are schema-qualified (search_path is `public, whse_basemapping, usgs, hydrosheds`). An unqualified def would hit the real table, but it would fail on the existing name, not write.
- **Watchdog.** The pid is R itself (subshell `exec Rscript`, then Rscript's execv). R exits on SIGTERM at once (measured: rc 143, 0 s). Backends are ended by `application_name`, which reaches libpq through PGAPPNAME, since `lnk_db_conn` sets none.
- **Busy-check quoting** (`'%working\_%'`). The ANSI-C tab inside `${row%%$'\t'*}` in a case pattern works on bash 5.3.
- **Verdict.** A missing exit, a missing row, a breach, a kill (124), a skip (exit 0 with no row → `no_row`) and `--only` all fail. Empty `exits.tsv` with picks errors before writing a record.
- **`devtools::test(filter = "pretest")`:** FAIL 0, PASS 71.
