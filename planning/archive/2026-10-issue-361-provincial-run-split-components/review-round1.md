# Code-check round 1 — branch `361-provincial-run-can-a-drainage-component`

Reviewer: fresh agent, read-only against `/tmp/codecheck.vz9pBy/` (diff, full changed files) plus
`data-raw/study_area_hosts.sh` and `R/lnk_wsg_resolve.R` in the checkout. No script was run against
the database or the cloud; the only probes were shell one-liners in the scratchpad.

## Checklist read

- `code-check.index.md`: in full.
- `code-check-shell.index.md`: in full.
- `code-check-r.index.md`: in full.
- `code-check-spatial.index.md`: in full.
- `code-check.md` (full text): the prose of all 14 H3s under `## Mechanisms` (table rows
  skipped), plus "An ordered dispatch makes severity ordering load-bearing" and "An assertion
  that matches an interpolated value cannot see the claim around it". Not read: the other 17
  stand-alone rules, Security and Spreadsheets/PDFs (nothing in the diff touches YAML, URLs,
  credentials, tfvars, S3 policy, spreadsheets or PDFs).
- `code-check-shell.md` (full text): read in full the sections "Empty arrays under `set -u`",
  "Quoting", "Heredoc precedence", "A heredoc whose body contains its own delimiter", "BSD vs GNU
  sed/grep", "`&` binds to the whole `&&` list", "`if ! cmd; then rc=$?`", "`timeout` is GNU
  coreutils", "psql does not interpolate `:'var'`", "A `local` statement cannot read a variable it
  is assigning", "`grep -c`", "macOS awk multibyte", "`exit` inside a loop condition", "A failed
  `cd`", "bash 3.2 heredoc inside `$( )`", "awk `==` version strings", "`for x in $(cmd | grep …)`",
  "A sed/awk range can run to EOF". Not read: 46 sections on git/gh/ssh/S3/docker/curl/conda/
  Perl/Python/sips/Qt, none of which the diff uses.
- `code-check-r.md` (full text): read in full "`on.exit()` at a script's top level", "A `data-raw/`
  script must load the source tree", "Tests that silently do not run", "testthat counts an
  uncaught error under `error`", "A `skip_if_not()` skips only its own block", "`expect_gt()`
  and friends take no `info`", "A database driver's value is not a base R type", "A value
  compared as `::text`", "`nzchar(NA)`", "`paste()` with a zero-length argument",
  "`strsplit()` drops a trailing empty field", "`sort()` and `order()` collate by `LC_COLLATE`",
  "`vapply(..., USE.NAMES = FALSE)`", "`match()` treats NA as a matchable VALUE", "`unlist()`
  prefixes a `split()` group's name", "`tolerance` in testthat is RELATIVE", "`[[` on a named
  ATOMIC vector", "`data.frame()` recycles a scalar", "Postgres row order is never fixed",
  "`sprintf("%g", x)` writes `Inf`", "An `information_schema` lookup", "Rscript reads a script as
  it runs", "`c(name = x)` keeps `x`'s own name", "`trace(exit =)`", "`Rscript -e` supplies
  `--args`", "`read.delim()` quotes by default". Not read: the other ~90 sections (xml2, glue,
  readr, arrow/duckdb, ggplot2, terra, pak, roxygen, knitr, cli, climr, earthdatalogin, …), none
  of which the diff uses.
- `code-check-spatial.md` (full text): 0 sections read. The diff has no terra, sf, bcdata or
  GDAL code.

## What was checked, and how

- **Order survives exact mode.** `study_area_wsgs.R --exact` → `lnk_wsg_resolve(expand = FALSE)`
  returns `focal[focal %in% modelable]`, order kept. `study_area_run.sh` strips whitespace only
  (`tr -d '[:space:]'`) and the dispatch loops (`for w in $(echo "$DISP_BUCKET" | tr ',' ' ')`,
  `B_SPACE`) iterate in that order. `.hosts_lines` (`sort -u`) is reached only by the accounting
  and `run_wsgs_write`, where order does not matter.
- **Overlap in exact mode is fatal, within a host too.** The `DUP` pipeline is `sort | uniq -d`
  over the concatenation of every bucket, so a group repeated inside one `--focal=` list (strict
  mode keeps duplicates) is also caught before any spend.
- **`${WSGS_FLAG[@]+"${WSGS_FLAG[@]}"}`, the two-header `case`, and the `[ … ] && echo || echo`
  banner** were probed under `/opt/homebrew/bin/bash` 5.3.9 with `set -euo pipefail`: empty and
  one-element arrays expand correctly, both headers match and a foreign one is refused, the
  banner line exits 0.
- **`BUCKET_MODE`** is set in `study_area_run.sh` before both `run_wsgs_write` calls (lines 1207/
  1210 → 1254 and 1467), is read with a `closure` default in the sourced lib, and collides with
  no other variable in `data-raw/*.sh`. `--recompute-only` only reads the TSV. No other reader of
  `_run_wsgs.tsv` exists in `R/`, `data-raw/` or `tests/`; the awk in `run_expected_from_file`
  reads `$1`, `$3`, `$4` only, so the appended fifth column is inert to it.
- **`study_area_verify.sql`:** both new `EXECUTE format()` strings use `%I` for the schema and
  `$1` for the run_uid; `'',''` inside the format literal yields `','`. `n_open`/`bad` are
  declared (`int`/`text`). The EXCEPTION arm precedes the NOTICE arm and both are sequential
  statements, not a first-match dispatch. Walking every arm of the DO block in order: for the 6g
  mutation (every row of one group `date_end` NULL) `n_model`, `expected_n`, the recompute gap
  and nothing later read `log.date_end`, so the new "never finished" raise is the only arm that
  can fire; for 6f (one extra open row, a copy of a finished row shifted 1 h earlier) every
  per-row provenance/pin check sees copied values, so no other arm fires. Both cases therefore
  isolate the guard they claim to test.
- **`study_area_verify_negative.sh` 6f/6g:** `log.run_id` is `text NOT NULL` (`R/lnk_log.R`),
  so `run_id || '-neg6f'` is valid; the scratch tables are `CREATE TABLE AS` copies with no PK,
  so the insert cannot collide; the heredoc is unquoted on purpose (interpolates `${SCRATCH}`,
  `${OPEN_WSG}`) and its body carries no backticks or `$(`; the restore re-copies the group's
  rows from the source schema, correlated, matching the other cases.
- **`study_area_buckets.R`:** `--minutes-schema` is regex-validated before reaching `sprintf()`;
  `extract(epoch …)/60` arrives as double; the `DISTINCT ON` pick ends on `date_start DESC`
  (timestamptz, unique per group in practice). `pack()` is positional over `order(-weights)` and
  ignores the names `vapply()` adds; `global_order[group_pack$assign == h]` keeps the global
  DS-first order; the within-host DS-first assertion still runs in group mode and resolves
  closures for non-focal members. `--write` is refused in group mode, so the component-only
  `--write` table (`sum(assign_h == h)`) is never reached with group-mode `assign_h`.
- **Test file:** the new assertions read the TSV with `colClasses = "character"` and compare
  whole columns; the five-column fixture is built from the four-column rows plus a literal.

## Findings

Clean. No bug, security issue or data-loss path found in the branch diff.

Two observations that are not findings (pre-existing, unchanged by this branch, recorded so the
next round need not re-derive them):

- In exact mode a misspelled group code is dropped by the species filter with a stderr message
  ("dropped N species-less WSG(s)"), not refused. Closure mode behaves the same way
  (`fresh::frs_wsg_drainage()` warns and drops an unknown code), and `expected_n` at verify is
  the backstop in both modes.
- The negative test's cases report FAIL/PASS by `psql`'s exit status and do not grep the raised
  message. The walk above shows 6f and 6g each reach only the arm they test today; the same
  pattern holds for every earlier case in the file.
