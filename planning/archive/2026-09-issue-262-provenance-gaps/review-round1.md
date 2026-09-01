# Code review — link#262 staged diff (round 1)

Reviewed: `R/lnk_log.R`, `R/lnk_stamp.R`, `R/lnk_pipeline_run.R`,
`data-raw/wsg_recompute_one.R`, `data-raw/study_area_run.sh`,
`data-raw/study_area_verify.sql`, `data-raw/study_area_verify_negative.sh`,
`data-raw/recompute_sweep.sh`, `data-raw/recompute_parity.sh`,
`tests/testthat/test-lnk_log.R`, `tests/testthat/test-lnk_git_dirty.R`.

Probes run (not reasoned about): a throwaway `postgres:16` container to execute
`study_area_verify.sql` in five states; `.lnk_git_dirty_at()` against a real
temp checkout in five states; `/bin/bash` 3.2.57 syntax + runtime checks on all
four shell scripts; `devtools::document()`; `testthat::test_file()` on the four
affected test files (`221 + 13 + 39 + 45` pass, 0 fail).

**Staging note before anything else.** The working tree carries *unstaged*
changes to `data-raw/study_area_verify.sql` and
`data-raw/study_area_verify_negative.sh` (plus `DESCRIPTION`, `NEWS.md`,
`RUNBOOK.md`, `CLAUDE.md`, `planning/`). Finding 1 below is already fixed there.
As staged, the bug ships.

## Findings

- **[bug] data-raw/study_area_verify.sql:78 — `\quit 1` exits 0, so the FATAL
  branch reports success.** psql's `\quit` takes no exit-code argument. Measured
  on psql 16.10 and 18.3:

  ```
  psql:q1.sql:2: warning: \quit: extra argument "1" ignored
  EXIT=0
  ```

  Run against the current `fresh.log` — whose 37 rows predate `run_uid` — the
  resolver's `coalesce(...)` returns `''`, `have_run` is false, the script
  prints `FATAL: no run_uid supplied and none found in the log` and **exits 0**.
  That is a fail-toward-pass on the one branch written to stop a silent zero-row
  pass, inside a file whose header says "exits non-zero on a real failure". It
  is also invisible to `study_area_verify_negative.sh`, which never exercises
  this path. *Already fixed in the working tree with a `DO $$ … RAISE
  EXCEPTION`; `git add` that file or the fix does not ship.* Verified the fixed
  form exits 3.

- **[bug] data-raw/study_area_run.sh:1320 — the new log-tables prep failure
  sends the operator to a log file that was never written.** The branch sets
  `RECOMPUTE_FAIL_STAGE="views"`, so the final gate at line 1412 prints

  ```
  The barrier views could not be built, so NO WSG was recomputed.
  See $LOG_DIR/${TS}_recompute_views.log.
  ```

  but the views step is gated on `[ "$RECOMPUTE_FAIL" = "0" ]` (line 1328) and
  never ran, so `${TS}_recompute_views.log` does not exist. The real evidence is
  `${TS}_recompute_logtables.log`. This is precisely the failure the comment at
  lines 1323–1327 says the nesting avoids ("Two prep steps, two diagnoses") —
  the nesting fixed the *message* at the point of detection and left the
  *stage token* pointing at the other step. Needs a third value (e.g.
  `RECOMPUTE_FAIL_STAGE="logtables"`) and a matching arm at the gate.

- **[fragile] data-raw/study_area_verify.sql:259 (and header line 35) —
  `expected_n` will raise on a healthy run that contains a species-skipped
  WSG.** The assertion compares against `count(DISTINCT watershed_group_code)
  FROM <schema>.log`, while the header instructs the operator to source the
  number from the driver's `csv_count "$ALL_WSGS"`. Those are different
  populations: `data-raw/wsg_run_one.R:56` exits 0 *without* calling
  `lnk_pipeline_run()` when a WSG has no modelled species, so it is dispatched
  and counted but never logged. `study_area_run.sh:1301` contemplates exactly
  this case ("if every focal WSG on the dispatcher species-skips"). Confirmed
  the assertion fires: 3 logged vs `expected_n=4` → `exit=3`. Fails toward abort
  (the safe direction), but it is a false alarm at the end of a paid provincial
  run, and the documented way to obtain the number is the one that produces it.
  Either derive `expected_n` from dispatched-minus-skipped, or state in the
  header that species-skips must be subtracted.

- **[fragile] data-raw/study_area_verify.sql:142 and :312 — the new
  `link_dirty` assertion cannot fire on a NULL, which is every cypher row.**
  `link_dirty` is three-valued. `R/lnk_stamp.R:374` returns `NA` whenever no
  `.git` is found next to the package, which is the case for an *installed*
  link — and cyphers run `Rscript data-raw/wsg_run_one.R` with no `LNK_LOAD` in
  the ssh string (study_area_run.sh:925), i.e. `library(link)` against the pak
  install. Both `count(*) FILTER (WHERE link_dirty)` and
  `... OR bcfp_model_version IS NULL OR link_dirty)` skip NULL, so the guard is
  structurally scoped to the dispatcher, and a dispatcher on which `git` itself
  failed also passes silently. `R/lnk_stamp.R:353` goes out of its way to keep
  the distinction ("NA must never be collapsed into FALSE: 'git failed' and
  'nothing changed' are different facts") and the SQL collapses it one layer
  down. `link_dirty IS DISTINCT FROM false` — or a separate
  `link_dirty IS NULL` report — makes the scope deliberate rather than
  incidental.

- **[bug] R/lnk_log.R:945 — malformed roxygen block breaks `document()`.** The
  block on `.lnk_log_recompute_start` puts prose *after* `@noRd` and then adds a
  second `@noRd`. `devtools::document()` reports:

  ```
  ✖ lnk_log.R:945: @noRd must not be followed by any text.
  ```

  New with this diff (no other `✖` in the run). Move the `run_uid` / `run_label`
  paragraph above `@return` and delete the duplicate tag. `man/` is otherwise in
  sync — `document()` produced no diff.

- **[fragile] R/lnk_stamp.R:293 — the `data-raw/logs` exclusion is
  link-specific but applied to every package.** `.lnk_git_dirty_pathspec` is a
  package-level constant consumed by `.lnk_pkg_git_dirty()`, which
  `lnk_stamp()` calls for `fresh` as well as `link`. A modified or untracked
  file under `fresh/data-raw/logs/` is now silently excluded from `fresh_dirty`
  too. Narrow in effect, but the justification (link's own run writes there)
  does not hold for the other package, and nothing says so.

- **[fragile] data-raw/study_area_verify_negative.sh:16 — the header states a
  safety mechanism the script does not use.** "the DELETE happens inside a
  transaction that is always rolled back" is not what happens: case 2 issues a
  bare `DELETE` in its own psql session (it could not be otherwise — each
  `run_verify` opens a new session, as the comment at line 107 correctly says)
  and restores by re-`INSERT`. The actual protection is the scratch schema plus
  the EXIT trap, which is sound. Worth correcting, because someone trusting the
  transaction claim could remove the scratch-schema indirection and then be
  deleting from `fresh.log_recompute` for real.

## Checked and clean

- `.lnk_git_dirty_at()` behaves as documented — probed on a real temp repo:
  clean `FALSE`; tracked+untracked churn under `data-raw/logs` only `FALSE`;
  a modified `R/f.R` alongside that churn `TRUE`; identical from a subdirectory
  (`:(top,…)` anchoring works); non-repo `NA`, never `FALSE`. `shQuote()` on the
  pathspec is load-bearing and present; `Sys.which("git")` guard is before the
  `system2()` call, and the skip condition is reachable (not the dead
  `is.null(status) && tool-absent` shape).
- `LNK_RUN_UID` / `LNK_RUN_LABEL` / `LNK_BCFP_MODEL_VERSION` reach **both**
  legs. The local exports are at study_area_run.sh:275–277 (global scope, before
  the dispatcher loop); the ssh string re-exports all three at line 925. The
  `LNK_BCFP_MODEL_VERSION` export at line 525 is inside `preflight_local`, but
  only `bcfp_ver` is `local`, and `preflight_local` is invoked directly at line
  748 — not in a subshell or pipeline — so the export survives. `${…:-}` guards
  are present for `set -u`.
- `--run-label=` parsing: empty value rejected, and the charset guard
  `*[!A-Za-z0-9._-]*` correctly rejects a space and a single quote and accepts
  `ok-name_1.2` (the trailing `-` is literal inside the bracket expression).
  Fails toward abort.
- `RUN_UID` minting is fixed-width and collision-safe within a second;
  `printf '%04x%04x' "$RANDOM" "$RANDOM"` verified on bash 3.2.57.
- All four shell scripts pass `/bin/bash -n` under 3.2.57. No unguarded empty
  array expansion introduced.
- `study_area_verify_negative.sh` cannot report success without testing:
  case 1 (healthy) is mandatory and runs first, case 2's skip branch increments
  `fails`, case 3 always runs. The EXIT trap's quoting assembles correctly
  (`"${PSQL[@]}"` deferred, `$SCRATCH` expanded at trap-set time) and it does
  fire. The restore `INSERT ... SELECT *` is positionally safe because the
  scratch tables were built by `CREATE TABLE AS SELECT *` from the same source.
- `study_area_verify.sql` psql interpolation: `:'x'` used for every value,
  `:x` only for the schema identifier; the `set_config` + `format(%I)` route
  into the `DO` block is correct (psql does not interpolate inside dollar
  quotes) and is injection-safe. `\set expected_n ''` genuinely yields the empty
  string (confirmed: prints `NOT CHECKED: no -v expected_n= given`). All five
  `RAISE EXCEPTION` arms verified reachable — healthy `exit=0`, wrong
  `expected_n` `exit=3`, deleted recompute row `exit=3`.
- `.lnk_blank_to_na()` covers the "empty is not unset" trap at the SQL boundary
  for `run_uid`, `run_label` and the two bcfp env vars; `''` never reaches an
  `INSERT`.
- `wsg_recompute_one.R` control flow: the top-level `on.exit()` problem is
  correctly worked around. `recompute_wsg()` is a real function, so the
  `zz_lnk_mc_scratch_*` `DROP` now fires; the error path marks the row before
  `quit(status = 1)`; `date_end` is set only after the post-condition; the
  disconnect is explicit on both exits. `rlog` is only dereferenced under
  `.rc_log`, and `.rc_start` cannot return `NULL` on that branch.
- `utils::getFromNamespace()` over `link:::` — the *code* is right (both resolve
  through `asNamespace()`, so both would in fact pick the `load_all` namespace;
  the stated rationale is wrong but harmless). All real callers
  (`recompute_one`, `recompute_sweep.sh`, `recompute_parity.sh`) run under
  `LNK_LOAD=loadall`, so there is no installed-vs-source hazard.
- `LNK_LOG=0` covers every benchmark caller. `data-raw/pool_probe.sh` also
  matches `recompute_one`, but it *stubs* the function and never invokes the R
  script, so it writes no `log_recompute` rows — the enumeration is complete.
- `.lnk_log_recompute_start`'s presence check runs no DDL when the table exists
  (asserted by test), is schema-qualified and `dbQuoteLiteral`-quoted, and is
  loud rather than soft. It cannot be defeated short of a same-named view.
- `log_recompute` joining the consolidate set is safe:
  `schema_consolidate.R:192` takes `intersect(src_wgc, dest_wgc)`, so a
  destination missing the table is skipped rather than erroring.
- `lnk_log_read()`'s new `run_uid` / `phase` arguments are appended after
  `latest`, so no positional caller breaks; `run_uid` correctly overrides
  `latest`, and `aoi` + `run_uid` compose with `AND`.
