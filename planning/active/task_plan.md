# Task: Known and suspected km per species in the group summaries (#403)

**If done:** `lnk_rollup_wsg()` reports, per group and species, the km accessible with the species recorded upstream (known) and the km accessible with no record upstream (suspected). **If never:** link reports accessible km only, and known against suspected still needs bcfishpass's tables.

`lnk_rollup_wsg()`'s default `accessible_km` is `access IN (1, 2)` (`R/lnk_rollup_wsg.R:118`, link@43e34096). No link output tells 2 from 1 (`data-raw/logs/observation_breaks_396/readers_code2.md`). bcfishpass's `aw_linear_summary()` reports the same split as `length_naturallyaccessible_obsrvd_<sp>`.

Branch `403-known-and-suspected-km-per-species-in-th` off `origin/main` at `39e9c2c5` (v0.71.0). Parked at the gate 2026-10-30; resumed the same day.

## Context

bcfishpass's `aw_linear_summary()` (`db/schema.sql:5283`, local clone at `smnorris/bcfishpass@620dbe43`) reports the split as `length_naturallyaccessible_obsrvd_<sp>` (`access = 2`) and `length_naturallyaccessible_model_<sp>` (`access = 1`). This adds the two default metrics the issue proposes, tests that they sum to `accessible_km`, and records the numbers for #396's five groups.

**All four blockers are still open** (#398 CT aliases, #399 record at a segment's start, #400 what "known" means, #401 every group's records). So today's split runs "observed" past each species' top fish to the next break and reads main stems below a group boundary as unobserved. The code lands now; the numbers are a labelled baseline the blockers move from.

## Decided at the gate (operator, 2026-10-30)

1. **Names:** `accessible_observed_km` / `accessible_unobserved_km`. Says what the code says, fits `<metric>_<qualifier>_km` (`rearing_lake_connection_km`), does not pre-empt #400.
2. **Habitat split: not in the defaults.** Checked against bcfishpass as asked. Its `length_spawningrearing_obsrvd_<sp>` is `greatest(spawning_<sp>, rearing_<sp>) >= 2`, and habitat code 2 is set in `model/02_habitat_linear/sql/load_habitat_linear.sql:37` only where the model says habitat **and** `user_habitat_classification` confirms it (3 = confirmed where the model says no). That is *expert-confirmed against model-only*, a different axis from `access = 2` (*fish recorded upstream*), reported spawning-or-rearing combined, per assessment watershed. On the reference view (`fresh.streams_vw_bcfp`, province-wide) BT habitat codes are 0/1 only; CH has 22,585 code-2 and 3,952 code-3 segments. link computes that overlay at gate time from the loaded CSV and persists no flag (`R/lnk_habitat_gate.R:91`), so a parity-shaped habitat split is a separate feature: noted as a follow-up in the research file, not filed. A split of spawning/rearing by `access` code has no bcfishpass counterpart; the roxygen `@examples` shows how to ask for it through `metrics =`.
3. **Numbers now,** from m4's `zz396_default_pre` / `zz396_default_post` (five groups, link `71ccc2ce` 0.69.1, fresh 0.43.0, all log rows closed), labelled the pre-#399/#401 baseline in `research/known_suspected_km.md`.
4. **Export (`lnk_scenario_export()`): deferred,** decided by the agent and stated at the gate. Nothing is published yet, the values move under #399 and #401, and a Parquet column is stored data. Revisit when the blockers land; noted in the research file.
5. **Compare side unchanged; the validator widens.** `lnk_compare_rollup()` passes its own `km_metrics`, so the default change does not reach it; `lnk_habitat_validate()` takes the defaults, so its `summary` gains the two columns (Phase 2). A parity reading of the split for BULK and PARS (link `bcfishpass` config vs the reference view's `access = 2` / `= 1`) goes in the research file as numbers, not as a code change.

## Mechanism (not a question)

- **SQL form of each new metric:** `round(sum(CASE WHEN access = 2 THEN length_metre ELSE 0 END) FILTER (WHERE access IN (1, 2))::numeric / 1000, 2)` (and `access = 1`). The FILTER is the same set `accessible_km` sums, so the pair is NULL exactly when `accessible_km` is NULL (access not built) and 0 when accessible rows exist but none carry the code. The identity `observed + unobserved = accessible_km` then holds on every row, to the 0.01 km each column is rounded to (the #319 pattern).
- Default frame goes from six to eight columns; README's printed block is refreshed from a real run.

## Phase 1: Tests first (red)

- [x] `tests/testthat/test-lnk_rollup_wsg.R`: amend the exact-names assertion at `:173-175` to the six-name default; offline test that the default `metrics` carry `accessible_observed_km` and `accessible_unobserved_km`, each with the `FILTER (WHERE access IN (1, 2))` set and the `access = 2` / `access = 1` CASE, and that the SQL text built from the defaults names both aliases.
- [x] Live test (`skip_if_no_db()`, localhost docker; skips when `fresh_default` is absent, so it proves the identity on whichever host runs `devtools::test()`): pick a group with BT `access_bt = 2` rows; `observed + unobserved` equals `accessible_km` within 0.0101 on the default frame, and exactly (`tolerance = 1e-9`) with unrounded custom metrics; `observed` equals a direct `sum(length_metre) FILTER (WHERE access_bt = 2)` that keeps the inner join to `streams_habitat_bt` on the full PK (the rollup's join shape, as #319's direct query at `:232-238`) and no polygon join.
- [x] Confirm the new tests fail at `39e9c2c5` (default frame lacks the columns).

## Phase 2: The two default metrics

- [x] `R/lnk_rollup_wsg.R`: add the two metrics to the `metrics` default after `accessible_km`; roxygen: the codes, the identity and its rounding, the NULL/0 semantics (and correct `:14-16`, which says an unbuilt access "resolves to 0": a `FILTER` sum over no rows is NULL), `@param metrics` (`:76-79`) listing the two additions, bcfishpass's `length_naturallyaccessible_obsrvd_<sp>` / `_model_<sp>` as the counterpart, and an `@examples` entry splitting spawning and rearing km by `access` through `metrics =`.
- [x] `lnk_habitat_validate()` calls the rollup with its defaults (`R/lnk_habitat_validate.R:349`) and merges the whole cost frame (`:1382`), so its `summary` gains the two columns: name them in its roxygen (`:238-239`); add them to `data-raw/habitat_validate.R`'s `cols_km` (`:163`) so totals and the pre/post comparison carry them. This is a second exported function's output change: name it for the NEWS line.
- [x] `devtools::document()`; `lintr::lint_package()` clean on the files; Phase 1 tests green.
- [x] `RUNBOOK.md`: one bullet beside the #319 rollup entry (~line 1244) naming the split and the identity.
- [x] Commit, so Phase 4 runs from a clean SHA.

## Phase 3: README output refreshed

- [x] Re-run the README example (`lnk_rollup_wsg(conn, "PARS", c("BT", "GR"), schema = "fresh_default")`) on m1's local `fresh_default` (0.68.0 build, the one the current block came from) and paste the printed eight-column frame into `README.md`'s block; check it does not wrap badly at the published width.

## Phase 4: Baseline numbers for #396's groups (m4's database, not m1's)

- [x] `data-raw/logs/known_suspected_403/rollup.R`: run from a worktree at the Phase 2 commit (`pkgload::load_all()`, the #396 scripts' pattern), connecting with explicit `dbname = "fwapg"` and credentials and the host from an env var (never in the file; `lnk_db_conn()` falls back to `postgis`); runs `lnk_rollup_wsg()` with the defaults on `zz396_default_pre` and `zz396_default_post` for BULK, ELKR, LKEL, PARS, UPCE, every species whose `access_<sp>` is not all `-9` in the group; writes `rollup.csv` (schema, wsg, species, the eight columns, `observed / accessible` share) and asserts the identity on every row where `accessible_km` is not NA, counting the NA rows (a present species with an empty accessible set gives NULL in all three).
- [x] Parity reading: for BULK and PARS, link's `bcfishpass`-config build (m4 `fresh`, #396's; confirmed 2026-10-30 from `fresh.log`: link `71ccc2ce`, 2026-10-28) against the reference view `fresh.streams_vw_bcfp` (`access_<sp> = 2` / `= 1` km, the view's own `IN (1, 2)` as the check), into `parity_bcfp.csv`. Equality has never been measured (`parity_crosssection.R:86` validates `IN (1, 2)` only); a difference is recorded in the research file with its mechanism, no code change.
- [x] `README.md` in the log dir: environment stamps (the commit `rollup.R` ran from, the builds' `log` rows: link `71ccc2ce`, fresh 0.43.0, config hash, the `fresh.log` rows of the two `bcfishpass` builds), what each file is, how it was run.
- [x] `research/known_suspected_km.md` (new topic file, header line with Verified / Issues / Produced by / Status): the rule the columns read, the table of numbers (pre vs post #396, the share observed), the parity reading, the caveats from the open blockers and which blocker moves which number, what bcfishpass tabulates on both axes, and the follow-ups not filed (export column; expert-confirmed habitat split). Add its row to `research/README.md`.

## Owed at the end (reported, done after merge)

- None. The blockers' before/after builds revise `research/known_suspected_km.md` under their own issues; the export column is a follow-up to draft when they land.

## Validation

- [x] `devtools::test()` passes (one call, grep for FAIL/ERROR/PASS)
- [x] `lintr::lint_package()` clean; `devtools::document()` leaves `man/lnk_rollup_wsg.Rd` regenerated; `pkgdown::check_pkgdown()` (no new export, so expected clean)
- [ ] `/code-check branch` clean before the PR
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, then `/gh-pr-push`

**Verification of the change itself:** the live test on `fresh_default` is the proof the identity holds on real rows; `rollup.R` asserts it on every row of the five groups in both scratch schemas; `parity_bcfp.csv` shows the `bcfishpass` config's observed km against the reference view for BULK and PARS (expected equal, since that config keeps every observation break and its access walk matches).
