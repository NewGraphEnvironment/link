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

- ~~Both bundles read province-wide records; no `pipeline:` key.~~ **Revised after the plan review
  (operator, 2026-10-30):** bcfishpass's code 2 is a hybrid (`spp INNER JOIN ids`, `ids` same-group),
  so other groups' records count only where an own-group record of any species is upstream. The
  `bcfishpass` bundle reproduces it through a new key, `pipeline: observation_upstream:`
  (`province` for `default`; `group_gated` for `bcfishpass` and when absent, as #396's
  `observation_breaks` defaults to bcfishpass's behaviour). Draft for upstream filed in our fork:
  NewGraphEnvironment/bcfishpass#16 (`upstream-draft`; confirm again and check what is pending
  before offering it; we may have a pull request in flight there).
- ~~Same specs.~~ The key enters the `acc` digest, so `acc-v3` and `acc-bcfp-3` carry new specs;
  `acc-v2` and `acc-bcfp-2` retire at 0.73.0. Minor release.
- The province table is dropped when `lnk_pipeline_run()` ends (`on.exit()`), not after the lifts.
- Walk mechanism (mine, from the review): per-species existence walks over each species' records
  instead of one array walk, because the array walk returns every segment-record pair (a Fraser
  main-stem segment would carry ~10^5 codes). The returned `obsrvtn_species_codes_upstr` becomes the
  walked species found upstream; nothing reads it, and it is never persisted.

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

- [x] `R/lnk_pipeline_run.R`: pass `paste0(schema, ".observations_province")` to
  `lnk_pipeline_access()`; drop it after the call and on the early return (line ~217). Comment
  cites the bcfishpass `spp` CTE.
- [x] `R/lnk_pipeline_prepare.R`: remove the drop from `.lnk_pipeline_prep_overrides()`; update the
  roxygen of `.lnk_pipeline_prep_observations()` (it says `<schema>.observations` serves code 2).
- [x] `R/lnk_pipeline_access.R`: the observation-walk comment names what it is given;
  `R/lnk_access.R:37` doc if it implies group scope.
- [x] `inst/extdata/vocabulary.csv`: retire `acc-v2`, `acc-bcfp-2` at 0.73.0; add `acc-v3`,
  `acc-bcfp-3` (definition: as before, but code 2 counts records in every group).
- [x] `devtools::document()`, `devtools::test()`, `lintr::lint_package()`. At fresh 0.48.0:
  4,866 pass, 0 fail; lints on added lines only match the files' existing indentation and the
  stale-install `object_usage` warnings main's helpers also get; two Rd files regenerated.

## Phase 2b: The bcfishpass gate and the walk's shape (added after the plan review)

- [x] Measure first (`walk_time.R`, below): array walk group-only vs province, and per-species
  existence walks over the province table, on LFRA, SETN and one small group. Go on only if the
  existence walks are tolerable; else draft a fresh distinct-result issue and stop for the user.
- [x] Tests: the key is checked at manifest load (`province` | `group_gated`, absent =
  `group_gated`); a DB fixture where a segment with an own-group record upstream reads 2 from
  another group's species under both values, and one with none reads 2 only under `province`;
  `lnk_pipeline_access()` walks one existence walk per present species plus, under `group_gated`,
  one over the group's own records; the acc digest moves with the key.
- [x] `lnk_config.R` key check; `lnk_pipeline_access()` gains the own-group table and the mode;
  `lnk_pipeline_run()` passes both tables; `default/config.yaml` sets `province`; the acc spec
  hashes the resolved value; `acc-v3` / `acc-bcfp-3` specs regenerated.

## Phase 2c: One distinct walk, from fresh (user, 2026-10-30: "fresh mode first")

- [x] fresh#284 filed; `result = "distinct"` on fresh branch `284-distinct-result` (aabba77), tests
  including SKGT live parity with `unique()` of `"ids"`; both guards fire with `DISTINCT` removed.
- [x] Timed fresh's own call (`walk_fresh_distinct.csv`): LFRA 65 → 37–39 s, BULK 21 → 8 s, SETN
  47 → 44–46 s, against today's group-only array walk.
- [x] link: one `"distinct"` walk over `observations`, one `"exists"` walk over `observations_gate`;
  the per-species views are gone. Tests pass against the fresh branch (scratch library).
- [x] `/code-check branch` on fresh (three rounds, Clean), PR NewGraphEnvironment/fresh#285.
- [x] Merge and release fresh (0.48.0, on the user's word); then link's `Imports:`
  floor and `Remotes:` pin move to it (the formals check cannot see a new value of `result`).
  fresh PR #285 merged as `3477123`, v0.48.0 tagged at `cd86c9a` with a GitHub release; link pin `9245726c`.

## Phase 3: Measure before and after (scratch schemas only, m1 local fwapg)

Run decision written into the evidence README before any build: host, scratch schemas
`zz401_*`, PRE = origin/main at the branch point, POST = the Phase 2 commit, each from its own
worktree under `load_all`, fresh 0.47.0, `PGPASSWORD` set for the quiet-database gate.

- [x] Walk cost, standalone (`data-raw/logs/obs_province_401/walk_time.R`): each group's
  segments copied from `fresh_default` into a temp table; time the walk shapes above, alternating
  order, with load, element counts and R peak memory recorded (as `prefilter_409/rerun.R`). Groups:
  LKEL, BULK, UPCE, PARS, ELKR, LNTH, SETN, LFRA. Done as `walk_time.csv` and
  `walk_fresh_distinct.csv`; R peak memory was not recorded.
- [x] Builds PRE and POST (`run.sh` adapted from `record_at_start_399/`): `default` on #396's
  five groups (LKEL, BULK, UPCE, PARS, ELKR) plus LNTH (confirmed by counting out-of-group
  records upstream of its lowest segment), and `bcfishpass` on BULK, PARS and UPCE. Speed read from
  the PRE/POST pairs; #396's `minutes.csv` is context only (other host state, other data).
- [x] `pre_post_diff.R` adapted from #399: segments and starts identical, `access_<sp>` moves
  1 → 2 only, each moved piece has a qualifying out-of-group record upstream (the walk's own
  `fwa_upstream(..., false, 1)` against the rebuilt province table), nothing else moves. Checks that
  can fail: completeness (no POST piece at 1 with a qualifying record upstream, under the bundle's
  rule), the AOI slice of the province table equals `<schema>.observations`, bcfishobs unchanged
  between PRE and POST. Restore-the-bug: hand-edit one piece in POST and see it stop.
- [x] `bcfishpass` parity against bcfishpass's observed km (reuse #399's `parity_pieces.sql`):
  BULK, PARS and UPCE match (0.00 km), steelhead excepted.
- [x] `data-raw/logs/obs_province_401/README.md` indexes it all.

## Phase 4: Docs

- [x] RUNBOOK §2c and §5 (~586): which table code 2 reads, the key, the gate; breaks read the
  group's own. `R/lnk_pipeline_break.R:23,152`; `research/access_columns.md:80` (the table lives
  longer).
- [x] `research/known_suspected_km.md` "After #401" (CLAUDE.md says #401 revises it);
  `research/observation_breaks.md`, `research/access_columns.md`, `research/output_vocabulary.md`.
- [x] CLAUDE.md: new status entry; correct #396's "Code 2 reads only the group's own records";
  the #403 owed export column now unblocked.
- [x] Grep for `acc-v2` / `acc-bcfp-2` and "own records" across the tree.

## Owed at the end (reported, done after merge)

- [ ] Every persisted group keeps the group-only code 2 until re-modelled: `fresh_default` and
  `fresh` at the next provincial run (#377's runs row), after the pre-run gate (#372) runs again.
- [ ] #403's export column (waiting on #401).

## Validation

- [x] Tests pass (4,866 at `9245726c`; later commits change comments, roxygen and the pre-run
  gate's map, whose tests pass: 24 tests, 100 expectations); `/code-check branch`: four rounds,
  ended by round 4's enumeration (about 45 claims about the province table and the walk's cost,
  5 false, all corrected); PWF checkboxes match; `/planning-archive`.
- Verification: the DB fixture proves a record in another group sets 2; `pre_post_diff.R` proves
  only 1 → 2 moved and each move is explained by an out-of-group record; parity holds; walk
  minutes recorded on the worst-case group.

