# Findings — Adopt fresh v0.46.0: the walk prefilter (fresh#272) in the recompute (#409)

## Issue context

**If we do it:** every group's recompute walk reads only the features that can reach the group. #261 estimated that cuts 36 to 51 % of the recompute's summed work on every provincial run, and it unblocks #394. **If we never do:** each walk keeps probing the group's segments once per feature in the province, so CHWK costs 18 times what SALR does.

- Bump `DESCRIPTION`'s fresh floor and `Remotes:` pin from v0.44.0 to v0.46.0. v0.45.0 carries NewGraphEnvironment/fresh#272 (fresh PR #276). v0.46.0 makes fresh's connectivity passes match `watershed_group_code` (NewGraphEnvironment/fresh#242).
- **Outputs should not move.** fresh#272 returned the same features in 32 of 32 walks. link's habitat tables hold one group each, which fresh#242's fix leaves alone. Check this with per-table digests on a few groups built before and after.
- **Measure** with `data-raw/logs/recompute_cost_261/` on CHWK, SALR and SETN, and fill #377's line.
- Hosts need the new fresh, re-prepped with `--auto-install` (RUNBOOK §8d).

## Library isolation

`pak::pkg_install(lib = <scratch>)` installs every dependency it resolves into that library too (26 here: RPostgres, sf, DBI, …), so an `R_LIBS` arm would differ from the shared one in more than fresh. Keep only `fresh/` in the scratch library and check `find.package()` for the others (`data-raw/logs/prefilter_409/model/stamp.txt`, the `[rerun]` header line).

## Plan review (2026-10-29, `review-plan.md`): dispositions

- **B1 (ties could move `dam_dnstr_ind`), adopted and closed by measurement.** fresh 0.45 ends each array's `ORDER BY` on the feature id; v0.44.0 ended on the measure. Only co-located features can reorder. On the dispatcher's 2026-10-23 build, `barriers_anthropogenic_unified` holds 502,233 rows and **0** positions shared by two features (`data-raw/logs/prefilter_409/ties_anthropogenic.*`), so no mixed dam / non-dam tie exists in any of 241 groups.
- **G1 (`remediated_dnstr_ind` also reads `[1]`), adopted.** It is model-time only (the recompute keeps it). The remediation set is built per group; over the 134 groups whose `working_<wsg>.crossings` the dispatcher kept, 356,568 rows and **0** shared positions (`ties_remediations.*`). Phase 3 stop rule added.
- **G2 (digests of booleans cannot see dropped features), adopted:** `rerun.R` now digests each walk's arrays (in order, and each sorted with radix collation); `summary.R` requires one digest across every run of a walk.
- **G3 (NATR has no reproducibility baseline), adopted as a stop rule:** any Phase 3 mismatch rebuilds the 0.44.0 side before anything is attributed to fresh.
- **G4 (provenance from the build's own process), adopted:** `compare.R` reads each schema's `log.fresh_version` per group and refuses on a mismatch.
- **G5 / AC2 (no test guards the speed's one dependency, nor the floor), adopted:** `test-lnk_pipeline_access.R` asserts every downstream walk passes `aoi` and the observation walk is upstream; `test-lnk_preflight_fresh.R` asserts the floor equals the `Remotes:` tag. Each was shown to fail with its guard removed (aoi dropped from the source walks; floor left at 0.44.0).
- **G6 (inputs unchanged across runs), adopted:** tuple write counters of `fresh_default.streams` and `.barriers` recorded before and after Phase 2.
- **G7 (production conditions), adopted as an owed item:** the next provincial `log_recompute` minutes against 2026-10-23's.
- **G8, adopted:** RUNBOOK's pre-run gate section and CLAUDE.md's reach line are updated with the record.
- **O1–O3, O5, adopted:** every load before the shared install comes from a worktree or `R_LIBS`; the shared install waits for Phase 3's 0.44.0 builds as well; Phase 2 waits for Phase 3 to finish, and `rerun.R` records m4's 1-minute load; the pick ran with `R_LIBS`.
- **O4 (B then A favours A through the cache), adopted:** every group runs b1, a1, a2, b2.
- **AC1, adopted:** the 36–51 % figure is pooled over 241 groups; five groups are compared walk by walk against #261's table instead, and the provincial share is left to the next run.
- **AC3, AC4, noted:** the unit suite mocks the walk, so the database digests are the evidence; `test-pretest.R` ran 24 / 0 / 0 at the new pin (no skip).
- **Gate map for `frs_network_features.R` (input `segments`), not changed.** The reviewer is right that the walk's cost now follows the features it admits, but the gate's scratch schema holds only its picks' barriers, so no input would make it exercise the province-wide case; the recompute is already `unexercised`. Recorded in the research write-up.
- **S1 (`lnk_access()`'s own scoped streams table is now redundant), deferred:** a follow-up; removing it here would change what is measured.
- **AS1–AS4, noted.** AS1: the tie counts above make collation moot for these ids.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `diff` reported 0 changed lines for an edited copy | `diff` is a shell function here; use `command diff` |
