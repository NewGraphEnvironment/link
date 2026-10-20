# Plan review — #259 baseline (Plan agent, 2026-10-20, delivered after the parked commit `05d8632e`)

Verified by read-only psql: `fresh_default.log` = 246 rows / 241 groups, 0 rows with `date_end` NULL, 5 groups with an older pre-run row (`run_uid` NULL; LARL, PINE `link_dirty`); newest-finished-row sums 165/205/231/272 min, counts 49/55/78/59, SETN 16.5 max, R² time~source 0.483, 241 joined, 0 log groups missing from the network table. The Context table holds. May CSVs: 104 distinct `status=ok` WSGs (23 files, recursive). `wsgs_dispatch.sh:12,164` still carries the deterministic-split fallback (Owed item is accurate).

## Blocker

**B1. `--schema=` default reads the wrong log.** Plan "schema from `cfg$pipeline$schema`, overridable". `study_area_run.sh:288-299`: both `bcfishpass` and `default` resolve `$pipeline$schema` to `fresh`, and the driver is FATAL for a non-bcfishpass config without `--schema=`. `fresh.log` holds 65 rows / 39 groups of bcfishpass runs (Aug 31–Sep 26). The Phase 3 regen command and the `--weights=time` validation both omit `--schema=`, so `--config=default` would read `fresh.log`: refuse on ~202 groups, or with `--fill-missing` pack 241 groups off 39 bcfishpass times. Say: the packer mirrors the driver's guard; both commands carry `--schema=fresh_default`; and `--schema=` names the log the packer READS, which need not be the persist target (a parity run into `fresh_parity362`, 17 log rows, should still read `fresh_default.log`).

## Acceptance

**A1. "Per option on at least one real run" is only honestly met for option 1.** The 219/219/218/217 figure uses the Oct minutes as both weight and scorer — a tautology, not a prediction — and the Owed section defers the rest. But an out-of-sample per-option comparison on the Oct run is available now: pack with the time source as it stood on 2026-10-17 (option 2: 104 May groups + 137 median-filled; option 3: `fresh_default.log` held 5 rows pre-run, so it REFUSES, and `--fill-missing` is 236/241 filled), then score each packing's buckets with the Oct per-group minutes (host-independence is the plan's own assumption). Phase 3 `hosts.csv` should carry three packings × predicted vs Oct-scored makespan; the Owed item stays but the box can be ticked.
**A2. Which "measured makespan".** Plan uses log sums (272); `research/study_area_run.md:227` records wall 171/207/277/~225, and psql wall is 171/207/343 (m1, pause + re-runs)/277. Say sums-vs-sums (the prediction is a sum) and reconcile the 5-min gap in the Phase 4 bullet.

## Gap

**G1. Success predicate unstated.** `log` has no status column (`R/lnk_log.R:301-347`). `date_end` is written only by `.lnk_log_run_finish` ("Close a run-log row on success", :1047-1054); failure = `date_end NULL + notes` (:1102-1103). Say `date_end IS NOT NULL` IS the success filter, cite those lines, and put the WHERE before `DISTINCT ON` so a newer failed attempt cannot shadow an older success (`lnk_scenario_export.R:287` depends on NULL meaning "did not finish").
**G2. Executed host ≠ packed host.** KITR and UPET were rebuilt on m1 at `a17e9177` (06:40 UTC) but packed to job1 / job3 (`buckets_default.md` rows 30, 10). "Measured minutes per host under the run's packing" uses the log `host`, so m1's 231 includes 8.4 min packed elsewhere. Phase 3 should score by packed host (from the in-process components) and say so for the within-host R².
**G3. Median scope for `--fill-missing`.** "over the measured groups": focal or schema-wide? `pack_weights_time(conn, schema)` returns every logged group; the segment rule's median is over ALL network groups. Pin schema-wide, per-group-rate median (0.170 min/1k; pooled is 0.180).
**G4. `research/study_area_scope_and_funders.md:62-65`** says "Whether its segment-count weight is the right one is open in #259" — not in Phase 4. Other readers (`study_area_run.md:16,34`, `research/README.md:43`) are fine; nothing executes the `--focal=` strings.
**G5. Wrong precedent for sourcing an R lib.** Plan copies `test-study_area_hosts.R` (bash). The R precedent is `tests/testthat/test-schema_consolidate.R:7-18`: `sys.source()` into a fresh env via `test_path("..", "..", "data-raw", ...)` (works for any file; 6 tests use it), with the script's main guarded by `!interactive() && sys.nframe() == 0L` (`schema_consolidate.R:679-680`). No data-raw R file sources a sibling from its own path — existing `source()` calls are cwd-relative (`_targets.R:49`, `study_area_compare.R:28`). Say the packer locates the lib from `--file=` as it already does for `--write`.
**G6. Reproduction scope.** Phase 2 adds `est. min` and a coverage line to a 7-column host table. "Byte-for-byte" can hold only for the Components table (`buckets_default.md` lines 1-68) and the `segments` values; say that, and say what `est. min` prints under `--weights=segments`. The Oct packing was `--host-speeds=1,1,1,1` (archive task_plan.md:28); the validation command should pass it explicitly rather than rely on Phase 2's default change.

## Ordering

**O1.** The Components `host` column reproduces only if `pack_lpt` keeps `order(-weight)` (stable) over the pre-sorted components. Make tie-breaking a Phase 1 test, not an implicit property.
**O2.** The `study_areas.md` regen must run after Phase 2 lands (old 1/0.45 default would change the split) and Phase 4's numbers come from Phase 3 — implied; state it.

## Assumption

**AS1.** "October measured the hosts equal": per-host min/1k is 0.139–0.226; the plan calls composition a confound. Open #163 ("Adaptive host_speeds") owns that question; cross-reference it in gate decision 3.
**AS2.** Coverage 241/241 holds only because the Oct run populated `fresh_default.log`. `lnk_persist_init` is `CREATE TABLE IF NOT EXISTS` (`R/lnk_persist_init.R:178`) and #354 keeps log history through consolidate, so re-runs into `fresh_default` keep coverage; a new schema has none. Say the time source lives per schema in the DB only (unlike the committed May CSVs) and what a new-schema run passes (B1).

## Scope

**S1.** `data-raw/buckets_balance.R` (#174, reads the same `_per_wsg_times.csv`, hardcoded m4/m1/cy factors) is unmentioned; #163's body names it. Retire it or list it beside `wsgs_dispatch.sh` in the archive note.
**S2.** #361 (opened today) states "a fifth cloud host buys nothing"; Phase 4 rewrites that sentence at `study_area_run.md:244`. Cross-link so they agree (floor 205 both ways; "buys 14 min" is 219→205).
**S3.** #179 is the open issue for the dispatcher fallback; cite it in the Owed item.
**S4.** Recent commits to `study_area_run.sh` (#358, #349) do not touch the packer; last packer commit is `0ae73a79` (#246). No conflict.

## Disposition (parent, 2026-10-20)

All folded into `task_plan.md` in the follow-up commit; B1 as a gate-decision correction (the packer requires `--schema=` for a non-`bcfishpass` config, as the driver does), A1 as an extra Phase 3 task, the rest as task edits. Issue numbers spot-checked with `gh` before citing.
