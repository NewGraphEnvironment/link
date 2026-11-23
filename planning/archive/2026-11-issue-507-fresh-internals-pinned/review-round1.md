# Review round 1: branch 507 (b89d3150...a44a52bf)

## Checklist read

- code-check.md: read the full prose (evidence blocks and table rows skipped) of "A guard that fails toward pass", "A fixture that cannot reach the failure mode" and "A proxy is not the property", and the opening of "Verification that reads its own output". The other 10 Mechanisms H3s were not read in full (index line only), and no "Rules that stand alone" section was read in full.
- code-check-r.md: index only. 0 sections read in full. The headings checked against the diff from their index lines: "`match()` treats NA...", "`vapply(..., USE.NAMES = FALSE)`...", "Inserting a helper between a roxygen block...", "`identical()` on two reader results...", "testthat counts an uncaught error under `error`...".
- code-check-shell.md: index only. 0 sections read in full. Checked from their index lines: "A failed `cd` lets every later command run...", "`grep -c` prints the count AND exits 1...", "psql does not interpolate...".
- code-check-spatial.md: no heading applies (no spatial code in the diff). 0 read.

## What was verified

- The four pinned signatures equal fresh v0.56.0's source (`/tmp/link507/fresh_0560/R`): `.frs_run_connectivity(conn, table, habitat, species, params, params_fresh, verbose = TRUE)`, `.frs_habitat_models(wsg_codes, params_method)`, `.frs_near_river_specs(params, species, models = "cw")`, `.frs_sql_num(x)`.
- The call sites match the stated calling style: three positional (`.frs_habitat_models`, `.frs_near_river_specs`, `.frs_sql_num` through `vapply`), and `.frs_run_connectivity` with `conn` positional and the rest by name.
- `grep` over `R/` finds exactly the four `getFromNamespace(…, "fresh")` calls, all literal, so `.lnk_fresh_internal_callsites()` neither errors nor misses one.
- `tests/testthat/test-lnk_preflight_fresh.R` was run in a detached worktree at HEAD with fresh 0.56.0 alone (`NOT_CRAN=true`): FAIL 0, ERROR 0, SKIP 0, PASS 70.
- `.lnk_fresh_mismatched_internal_formals()` handles each case correctly: a shorter installed formals list (caught by the `head()` comparison), a trailing formal with no default (the empty symbol, through `vapply(identical)`) and an absent internal.

## Findings

- **[severity: fragile]** data-raw/logs/fresh_pin_507/compare.R:67-96, with data-raw/logs/fresh_pin_507/run.sh:51-77. The verdict "no persisted output moves" never checks that the expected groups were built. compare.R requires only that the before and after digests hold the same (table, group) keys. So a group that fails both tries in both steps (run.sh's `run` returns 1, which nothing checks) is simply absent from both digests, and compare.R reports "N table-group digests identical". `builds.csv` then silently drops it (`st <- st[st$exit == 0L, ]`). run.sh also prints `RUN507_<step>_DONE` and exits 0 whatever the groups did. And it never drops `fresh_pin507_*` before building, so a group that fails in this run keeps whatever rows an earlier attempt left in the scratch schema, and those stale rows are what get digested. The NEWS line quotes ADMS and BULK under `default` and ADMS under `bcfishpass` as digest-identical, so the check should assert those three groups. The fix: assert that each step's status file holds a final exit-0 row for each of the three (step, config, wsg) builds, and that each digest's group set equals {ADMS, BULK} or {ADMS}. Also have run.sh exit non-zero, and not print the DONE marker, when any `run` fails, or drop the scratch schemas at the start of each step.
  - **Rule:** code-check.md "A guard that fails toward pass" ; code-check.md "A wrapper's exit is not the work"

No other issues found in R/lnk_preflight_fresh.R, its tests, digest.R, DESCRIPTION or the driver hunks (message text only).
