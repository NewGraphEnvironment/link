# Plan review — #403 (Plan agent, 2026-10-30, before the baseline commit)

Reviewed the plan against the tree at `39e9c2c5` and the issue body. Every file:line below was re-read by the session before it was folded into `task_plan.md`; none was wrong.

## Blocker

- none

## Gap (all folded in)

- `tests/testthat/test-lnk_rollup_wsg.R:173-175` asserts the default `metrics` names are exactly the four current ones; it goes red when Phase 2 adds two. Phase 1 amends it to the six-name default.
- `lnk_habitat_validate()` calls `lnk_rollup_wsg()` with the defaults (`R/lnk_habitat_validate.R:349`) and `.lnk_hv_summary()` merges the whole cost frame (`:1382`), so its `summary` gains the two columns. Its roxygen (`:238-239`) enumerates the cost columns; `data-raw/habitat_validate.R:163` holds a fixed `cols_km` list that would leave the new columns out of totals. Both named in Phase 2.
- `R/lnk_rollup_wsg.R:14-16` says an unbuilt access "resolves to 0"; it is NULL. Corrected in the same roxygen pass, with `@param metrics` (`:76-79`) listing the two additions.
- Phase 1's direct sum must keep the inner join to `streams_habitat_bt` on the full PK, as #319's does (`:232-238`); the rollup inner-joins habitat, so a streams+access-only sum is a join-shape mismatch, not fan-out.

## Ordering (folded in)

- `rollup.R` stamps a link SHA and runs the new defaults, so it runs after Phase 2 is committed, from a worktree at that commit (the #396 scripts' pattern, `observation_breaks_396/build_obs.R:10`), and the log dir's README says which commit ran it.
- Phase 3 reads m1's local `fresh_default`; Phase 4 reads m4's scratch schemas. `skip_if_no_db()` connects to localhost, so the live test proves the identity only on whichever host runs `devtools::test()`. Stated in the phases.

## Assumption

- SQL form verified valid Postgres with the stated NULL / 0 semantics; rounding bound: `round(o) + round(u) − round(t)` is 0 or ±0.01, so 0.0101 holds.
- Connection: the repo's pattern is explicit `localhost/fwapg/postgres/postgres` args (`CLAUDE.md`, every #396 script); `lnk_db_conn()` falls back to `postgis`, not `fwapg` (`R/lnk_db_conn.R:39-40`). `rollup.R` passes `dbname = "fwapg"` and credentials explicitly, host from an env var. Naming m4 in committed text is the measurement-subject exception.
- The parity reading's "expected equal" for `access = 2` km has never been measured (`parity_crosssection.R:86` validates `IN (1, 2)` only). Folded in: a difference is recorded in the research file with its mechanism, no code change.
- A species with an empty accessible set yields NULL in all three columns; `rollup.R`'s assertion restricts to rows where `accessible_km` is not NA and counts the NA rows.
- m4's `fresh` still holds #396's `bcfishpass` BULK and PARS builds: confirmed by the session from `fresh.log` (link `71ccc2ce`, 2026-10-28 08:29 / 08:32 UTC); the log dir's README stamps it.

## Scope (folded in)

- The validator's `summary` widening is a second exported function's output change: named in Phase 2 and for the NEWS line.
- The PWF files were untracked while `task_plan.md` said "committed and pushed": the parked commit that follows this review makes the sentence true.

## Acceptance

- Both acceptance items are met by the phases as written; the identity is proved live (one group in the test, five groups × two schemas in `rollup.R`), and CI's offline test checks only the SQL text, as #319's precedent does.
- The issue's three open questions are answered at the gate; the "Blocked by" caveat is carried by labelling the numbers a pre-#399/#401 baseline.
