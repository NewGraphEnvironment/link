# Review round 3 (#481), branch at 74582a30

## Checklist read

- **code-check.md**: read the prose of all 14 H3 under `## Mechanisms` (tables skipped), with full attention to "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output", "A guard's scope, escape hatches, and remedies", "A fix lands in one of two callers that share a harness", "Restore the bug and prove the guard fires", "Zero-length, empty, and unset are three different things", "Written data outlives the fix". Stand-alone rules checked by index line. 24 stand-alone, security and spreadsheet H3 not read in full (nothing in the diff uses them).
- **code-check-r.md**: read "`on.exit()` at a script's top level never fires", "A database driver's value is not a base R type — and it fails twice", "`nzchar(NA)` is TRUE — non-empty checks silently pass NA", "`expect_message(expr, regexp)` checks only the FIRST condition, so a progress line hides the message under test", "An `information_schema` lookup by the literal table name misses what Postgres resolves", "testthat 3e `expect_message()` returns the condition, not the expression's value", "A `function(...)` mock hides arguments the real callee no longer accepts". Checked the rest by index line (skips, `tryCatch` nesting, `Rscript -e`, data-raw loading, lintr). About 123 not read in full.
- **code-check-shell.md**: checked by index line against `run.sh` (`set -u`, a failed `cd`, `a && b || c`, `grep -c`, quoting). 73 not read in full.
- **code-check-spatial.md**: no spatial code in the diff; 96 not read.

## The mechanism behind round 1

Round 1's three findings share one assumption: **a visible stand-in was taken for the property it usually goes with** (code-check.md, "A proxy is not the property").

- The validator checked the key whenever the table **existed**; the property was whether a rule **reads** it.
- The explicit `lnk_db_conn()` call muffled fresh's message, which stopped the print; the property was fresh's once-per-session **flag**, set before it prints.
- `verify.R` **registered** an `on.exit()` at top level; the property was that the cleanup **runs**.

## Every place in the diff that assumption reaches

1. **Validator: `nzchar(near_river)` stands for "a rule reads the table".** Sound. `near_river` comes from `.lnk_near_river_logged(cfg, aoi)`, which uses fresh's own resolver over both models, the same resolver classify walks.
2. **Validator: `near_river_lfid = !is.null(near_river_table)` stands for "both tables carry the column".** Sound.
   - With a pair, the near-river side is checked through the catalog (`dbListFields`). The streams side (`s` = `<schema>.streams`) always carries `linear_feature_id` (`cols_streams`).
   - With no pair, the table is passed without the check. But `frs_habitat_predicates()` is pure and no rule names the table, so nothing reads the column. The test drops the column there and still passes.
3. **Validator NULL check: no NULL in a scored group stands for "every row keyed as the build keyed it".** Sound. A new build's persist INSERT copies fresh's column. The only NULL sources are rows from an unmigrated host's consolidate, or orphan rows with no streams segment, and both refuse.
4. **Migration: the column in the catalog stands for "the table is filled".** Sound by design, but one-way: rows that reach a migrated table as NULL later (an unmigrated source consolidated in) are never refilled. A re-run of `lnk_persist_init()` skips, because the column exists. The validator refuses with "re-model those groups", which is correct but costs more than a re-fill. RUNBOOK and NEWS say to migrate every host first, which closes it. The empty-catalog skip is the accepted tradeoff and fails loudly at the persist INSERT.
5. **`lnk_db_conn()`: "all five given" stands for "fresh fills nothing from `PG_*_SHARE`".** Sound. `.lnk_conn_arg_set()` is byte-for-byte fresh's `.frs_is_set()`, and fresh's fill loop only fills NULL fields.
6. **`lnk_db_conn()`: unsetting the variables stands for "the notice is unspent".** Sound, and it is tested on the property: a later call that reads the variables must still print.
   - Mutation: removing the guard turns "a fully explicit call says nothing of PG_*_SHARE, and leaves the notice" red, with 2 failures.
   - The restore runs from `on.exit()` inside a function, so it fires on error too. A set-but-empty variable is kept as `""`.
7. **`verify.R`: the explicit drop stands for cleanup.** Sound. The drop runs after check 2's read, and the header states the leftover-on-failure case. Check 3 counts mock calls, so a mock that was never reached cannot pass. The mock carries fresh's full formals.
8. **Tests: `skip_if_no_fwa_downstream()` stands for "closure mode can run".** Sound. At v0.55.1, `frs_wsg_drainage()` reads only the `fwa_downstream()` routine, and the outlets come from a `VALUES` list.
9. **`lnk_preflight_fresh`: the `near_river_lfid` and `connect_timeout` formals stand for the behaviour.** Sound. The `Imports` floor of 0.55.1 guards the behaviour the formals cannot show.
10. **`run.sh`: "gate passed" stands for "the database was quiet".** It fails toward pass after 60 minutes, and its stdout is not committed, so the README's "after five quiet minutes" is unverifiable from the record. This is harmless, because the verdict is digest equality, not minutes.
11. **`wsg_vignette_data.R`: four `PG_*_SHARE` fields set stands for "the tunnel is available".** Sound. A failure lands in the `try-error` branch with a message.
    - With an empty `PG_PASS_SHARE`, the call is partial and libpq takes `PGPASSWORD`.
    - The old code did the same: `PG_PASS_SHARE` unset fell to `PGPASSWORD`, and libpq treats an explicit `""` as unset.
12. **Prose restatements of the validator's scope.** NEWS and RUNBOOK now say "when cfg reads a pair". CLAUDE.md's new status (line 20) still says "refuses a missing column or NULL" with no scope. This is doc wording only and changes no behaviour, so it is not a finding.

Also checked:
- Every bare `lnk_db_conn()` caller in `R/`. `lnk_wsg_resolve()` closure mode calls it only when `conn` is NULL; every data-raw caller passes `conn`; `lnk_wsg_downstream_check()` uses strict mode.
- Every modelling and recompute driver passes all five fields.
- The persist INSERT names `linear_feature_id` from fresh's working table, which at 0.55.1 carries it whenever the working streams do (always, in link).

Ran in a detached worktree at HEAD (`R_LIBS=…/lib0551`, `NOT_CRAN=true`) and removed it after:
- `test-lnk_db_conn.R`: 8 blocks, 0 failed.
- `test-lnk_persist_init.R`: 75 expectations, 0 failed.
- `test-lnk_preflight_fresh.R`: 43 expectations, 0 failed.
- The mutation in item 6.

The live persist test makes and drops its own `zz_test452_*` schema.

## Clean
No issues found.
