# Task: Count every group's fish records when asking whether a species is observed upstream (#401)


The code-2 walk reads `<schema>.observations` (`R/lnk_pipeline_run.R:284`, link@43e34096), which holds the group's own records only (`WHERE o.watershed_group_code = aoi`, `R/lnk_pipeline_prepare.R:346`). Barrier lifts had the same limit. Since #349 they read `<schema>.observations_province`, built in the same step. The recompute (`lnk_access(merge = TRUE)`) keeps a prior 2 and computes no new one (`observations = NULL`), so it does not fix this either.

Not measured: how many km this moves. bcfishpass models the province in one pass, so its code 2 likely sees every group's records; that is not checked against its SQL.

## Context

Code 2 (`access_<sp>` = accessible, and the species is recorded upstream) is computed by the
access walk in `lnk_pipeline_run()` (`R/lnk_pipeline_run.R:295`), which passes
`<schema>.observations`. That table holds the group's own records only
(`R/lnk_pipeline_prepare.R:344-349`, `WHERE o.watershed_group_code = aoi`). So a main stem reads
1 ("accessible, not observed") up to its group boundary even where the species is recorded
just upstream in another group.

What exploration settled:

- **bcfishpass reads every group's records for code 2.** In
  `model/01_access/sql/load_streams_upstr_observations.sql` (`smnorris/bcfishpass@620dbe4`), the
  `spp` CTE (which fills `obsrvtn_species_codes_upstr`) joins `bcfishpass.observations` with no
  group filter; only the `ids` CTE (observation keys, which link does not produce) adds
  `a.watershed_group_code = b.watershed_group_code`. So the `bcfishpass` bundle reads them all
  too, and **no bundle key is needed**, as for #399.
- **The table already exists.** `.lnk_pipeline_prep_obs_province()` builds
  `<schema>.observations_province` (every group's records, each kept by its own group's presence,
  minus exclusions, GiST on `wscode`/`localcode`), the same rows as `bcfishpass.observations`.
  Since #349 the barrier lifts read it. `.lnk_pipeline_prep_overrides()` then drops it
  (`R/lnk_pipeline_prepare.R:603-606`) to keep ~200 MB out of kept working schemas.
- **fresh's upstream walk does not prefilter features.** `frs_network_features()` with
  `direction = "upstream"` applies `aoi` to segments only (`fresh/R/frs_network_features.R:308`),
  so the walk probes the whole province table. That is the cost to measure. Worst case is a
  group with the most upstream area (LFRA); SETN is the slowest walk group overall (#394).
- **The recompute is unaffected.** `lnk_access(merge = TRUE)` passes `observations = NULL` and
  keeps the model-time 2 (`R/lnk_access.R:193,206`). Records come from bcfishobs, not from
  persisted groups, so model order and the recompute scheduler (#374) need no change.
- **Breaks keep the group's own records** (`lnk_pipeline_break()` reads `<schema>.observations`),
  as the issue asks. No change there.

## Decided at the gate (user approval of the plan, 2026-10-30)

- Both bundles read province-wide records; no `pipeline:` key (bcfishpass's SQL, above).
- Output changes with no spec change, so `acc-v2` and `acc-bcfp-2` retire at 0.73.0 for
  `acc-v3` and `acc-bcfp-3` with the same specs, the #399 pattern. Minor release.
- The province table is dropped after the access walk instead of after the lifts.

## Phase 1: Tests first

- [x] `test-lnk_pipeline_access.R`: DB fixture (modelled on #399's `seg399`/`obs399`). Group
  `AAAA` holds a segment on line 10 (`100.200`); a record of species X in group `BBBB` on a
  tributary (`100.200.300`) upstream of it, and a group-`AAAA` table with no X. The segment reads
  2 against the province-style table and 1 against the group-only one.
- [x] `test-lnk_pipeline_run.R`: (mocked) the access call gets `observations =
  "<schema>.observations_province"`, the break step still reads `<schema>.observations`, and the
  province table is dropped after access, including on the no-active-species early return.
- [x] `test-lnk_pipeline_prepare.R:1140`: `prep_overrides` still reads the province table for
  lifts but no longer drops it.
- [x] `test-lnk_vocabulary.R` / `test-lnk_log.R`: `default` resolves `acc-v3`, `bcfishpass`
  `acc-bcfp-3`; the old tokens are retired at 0.73.0.

## Phase 2: Code

- [ ] `R/lnk_pipeline_run.R`: pass `paste0(schema, ".observations_province")` to
  `lnk_pipeline_access()`; drop it after the call and on the early return (line ~217). Comment
  cites the bcfishpass `spp` CTE.
- [ ] `R/lnk_pipeline_prepare.R`: remove the drop from `.lnk_pipeline_prep_overrides()`; update the
  roxygen of `.lnk_pipeline_prep_observations()` (it says `<schema>.observations` serves code 2).
- [ ] `R/lnk_pipeline_access.R`: the observation-walk comment names what it is given;
  `R/lnk_access.R:37` doc if it implies group scope.
- [ ] `inst/extdata/vocabulary.csv`: retire `acc-v2`, `acc-bcfp-2` at 0.73.0; add `acc-v3`,
  `acc-bcfp-3` (definition: as before, but code 2 counts records in every group).
- [ ] `devtools::document()`, `devtools::test()`, `lintr::lint_package()`.

## Phase 3: Measure before and after (scratch schemas only, m1 local fwapg)

Run decision written into the evidence README before any build: host, scratch schemas
`zz401_*`, PRE = origin/main at the branch point, POST = the Phase 2 commit, each from its own
worktree under `load_all`, fresh 0.47.0, `PGPASSWORD` set for the quiet-database gate.

- [ ] Walk cost, standalone (`data-raw/logs/obs_province_401/walk_time.R`): time the upstream
  observation walk against the group-only and province tables on persisted `fresh_default`
  segments for LKEL, BULK, UPCE, PARS, ELKR, LNTH, SETN and LFRA, alternating order, with load
  sampled. If a group's walk rises past 2× and 1 min, draft (not file) a fresh issue for an
  upstream prefilter.
- [ ] Builds PRE and POST (`run.sh` adapted from `record_at_start_399/`): `default` on #396's
  five groups (LKEL, BULK, UPCE, PARS, ELKR) plus LNTH (main stem downstream of UNTH; confirm
  with `recompute_deps.R`'s line rule that it reads upstream groups, else pick another), and
  `bcfishpass` on BULK and PARS. Build minutes recorded against #396's `minutes.csv`.
- [ ] `pre_post_diff.R` adapted from #399: segments and starts identical, `access_<sp>` moves
  1 → 2 only, each moved piece has a record of the species upstream in another group, nothing
  else moves. Restore-the-bug check: hand-edit one piece in POST and see it stop.
- [ ] `bcfishpass` parity against bcfishpass's observed km (reuse #399's `parity_pieces.sql`):
  BULK and PARS stay at 0.00 km, steelhead excepted.
- [ ] `data-raw/logs/obs_province_401/README.md` indexes it all.

## Phase 4: Docs

- [ ] RUNBOOK §2c: the walk reads `<schema>.observations_province`; breaks read the group's own.
- [ ] `research/known_suspected_km.md` "After #401" (CLAUDE.md says #401 revises it);
  `research/observation_breaks.md`, `research/access_columns.md`, `research/output_vocabulary.md`.
- [ ] CLAUDE.md: new status entry; correct #396's "Code 2 reads only the group's own records";
  the #403 owed export column now unblocked.
- [ ] Grep for `acc-v2` / `acc-bcfp-2` and "own records" across the tree.

## Owed at the end (reported, done after merge)

- [ ] Every persisted group keeps the group-only code 2 until re-modelled: `fresh_default` and
  `fresh` at the next provincial run (#377's runs row), after the pre-run gate (#372) runs again.
- [ ] #403's export column (waiting on #401).

## Validation

- [ ] Tests pass; `/code-check branch` clean; PWF checkboxes match; `/planning-archive`.
- Verification: the DB fixture proves a record in another group sets 2; `pre_post_diff.R` proves
  only 1 → 2 moved and each move is explained by an out-of-group record; parity holds; walk
  minutes recorded on the worst-case group.

