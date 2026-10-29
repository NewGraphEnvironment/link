# Findings — Adopt fresh v0.46.0: the walk prefilter (fresh#272) in the recompute (#409)

## Issue context

**If we do it:** every group's recompute walk reads only the features that can reach the group. #261 estimated that cuts 36 to 51 % of the recompute's summed work on every provincial run, and it unblocks #394. **If we never do:** each walk keeps probing the group's segments once per feature in the province, so CHWK costs 18 times what SALR does.

- Bump `DESCRIPTION`'s fresh floor and `Remotes:` pin from v0.44.0 to v0.46.0. v0.45.0 carries NewGraphEnvironment/fresh#272 (fresh PR #276). v0.46.0 makes fresh's connectivity passes match `watershed_group_code` (NewGraphEnvironment/fresh#242).
- **Outputs should not move.** fresh#272 returned the same features in 32 of 32 walks. link's habitat tables hold one group each, which fresh#242's fix leaves alone. Check this with per-table digests on a few groups built before and after.
- **Measure** with `data-raw/logs/recompute_cost_261/` on CHWK, SALR and SETN, and fill #377's line.
- Hosts need the new fresh, re-prepped with `--auto-install` (RUNBOOK §8d).

## Library isolation

`pak::pkg_install(lib = <scratch>)` installs the dependencies it resolves into that library too (25 here: RPostgres, sf, DBI, …; sf and s2 at newer versions than the shared library, the rest the same versions; corrected 2026-10-29 after a review of the convention append), so an `R_LIBS` arm would differ from the shared one in more than fresh. Keep only `fresh/` in the scratch library and check `find.package()` for the others (`data-raw/logs/prefilter_409/model/stamp.txt`, the `[rerun]` header line).

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

## Code-check round 1 (`review-round1.md`)

Seven findings, all documentation claims wider than the evidence, plus an uncommitted evidence file; all fixed. The per-call scope cost is 1.0 to 1.3 s only in the three small groups (LSKE 2.0 to 2.4, SETN 3.5 to 4.2); CHWK's anthropogenic walk got faster, not slower; model-time digests cover five table kinds, not `barrier_overrides` or `streams_near_river`; SETN a2 refused once, not twice; `rerun.R` checks for company only at its start; the remediation tie check covers 134 groups of one build; `pick_only.md` was untracked. Nothing in the code or the outputs.

## Code-check round 2 (`review-round2.md`)

Five findings; the first sits inside round 1's fix (round 1 corrected the per-call numbers and kept an unmeasured cause, the temp-table build, which fresh's own timing puts at 0.07 to 0.7 s). Fixed: the cause is now stated as unmeasured, with fresh's figure beside the rise; CLAUDE.md names SETN's 1.8×; KO reaches fresh#242's pass in NATR, not ADMS; the 189-position count now has its query (`ties_natural.*`, m4's 30-group copy, labelled); the driver no longer overwrites a refused run's log, SETN a2's refusal log is kept, and LSKE a2's loss is recorded with where the cause was read. Because a defect sat inside a fix, round 3 ends on an enumeration of every claim against its producer.

## Code-check round 3 (`review-round3.md`)

Mechanism, as the reviewer named it: earlier rounds fixed the numbers a review pointed at, but the clauses interpreting them ("which is why …", "describe the 2026-10-23 build", "where the walk returns little", "each run four times") were written from the experiment's design, not re-derived from its outputs. Enumeration: 75 claims, 58 supported, 12 wider, 2 unsupported, 3 wrong. Fixed by cutting interpretation rather than rephrasing it: NEWS's entry and CLAUDE.md's status were rewritten to measured statements; "small groups gain least" removed (SETN, the largest, gains least; the untouched steps explain small groups); the remediation tie check is scoped to working schemas of unrecorded date (the dispatcher modelled 74 groups on 2026-10-23, verified); per-group sums named as such (per walk 1.45× to 18.5×); the walks' share under 0.46.0 (41 to 87 %) replaces "the recompute's cost is its walks"; the prefilter is described by its two conditions, not as "only what can reach"; the CHWK/SALR order change no longer cites m4's copy as its cause; #411's unmeasured saving removed; README window, header and per-group wording; `rerun.R`'s header; an unmatched `RESUME` now exits 2; the duplicate SETN a2 log untracked.

## Code-check round 4 (`review-round4.md`)

Enumeration of 77 claims: 71 supported, 5 wider, 1 wrong. Wrong: fresh's temp-table timing was labelled "on m4" (a label round 2's reviewer supplied); fresh's record says a province-wide `fresh_default` (11.3 M rows), which m4's copy (860 k) is not, so the host is now left unnamed and the population stated. Wider, all fixed: RUNBOOK's "Most of the recompute's cost" beside a 41 % figure (inside round 3's fix); CLAUDE.md's 66 to 96 % range scoped to the fastest runs; "first runs read colder" replaced by what the outputs show (b1 the slowest total in each complete group, re-derived); `rerun.R` "does not look again" corrected (it samples at its end, it does not refuse again); the README's "the driver now keeps" scoped to the committed script, with the waiting frozen copy named. Outside the diff: #410's body still calls the mapping-code walks province-wide; left for the session working #410.

## Code-check round 5 (`review-round5.md`), terminal

Enumeration of the 28 claims in round 4's added lines: 27 supported, 1 wider (CLAUDE.md's bold lead still said `rerun.R` "checks for company only at its start" beside a body saying it also samples at its end). Fixed in the lead's words; the README's `b1` parenthesis, true but not support for its sentence, cut. The loop ends on this enumeration.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `diff` reported 0 changed lines for an edited copy | `diff` is a shell function here; use `command diff` |
