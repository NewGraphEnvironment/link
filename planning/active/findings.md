# Findings — Tuning iterations: measure where a threshold variant's time goes (seven steps, two of them verification) (#404)

## Issue context

**If we do it:** we know which step makes a tuning loop slow before trying to speed it up, and the right change goes on #377's iteration-speed list. **If we never do:** speed work keeps landing on the access walk (NewGraphEnvironment/fresh#272, #394), which a tuning loop runs once per closure, while the cost paid on every variant goes unmeasured.

## What one tuning iteration actually runs

`data-raw/habitat_variants_build.R` models the base bundle once (`lnk_pipeline_run()`, then `lnk_access(merge = TRUE)` and the habitat gate). A threshold change touches no barrier, so every variant shares that access and only the per-variant pass re-runs.

**That pass is already timed — as a single number.** It ends with

```r
say("variant %s %s done in %.1f min (habitat %s)", v, w, ...)
```

and the `t0 <- Sys.time()` it measures from wraps **seven steps, not the three this issue first named**:

| # | step | kind |
|---|---|---|
| 1 | `lnk_pipeline_classify()` → `fresh::frs_habitat_classify()` | model |
| 2 | `lnk_pipeline_connect()` → `fresh::frs_cluster()` + the connected-waterbody pass | model |
| 3 | `working_habitat_digest()` | **verification** |
| 4 | `lnk_pipeline_persist()` | write |
| 5 | `copy_access()` + `ANALYZE` on `streams`, `streams_access`, `streams_habitat_<sp>` | write / planner |
| 6 | `lnk_habitat_gate()` | model |
| 7 | the `digest_of()` loop over `digest_sql` — `streams` and `streams_access` | **verification** |

Steps 3 and 7 are the correction that matters. They are `md5(string_agg(... ORDER BY id_segment))` over every row of the group — a full sort and aggregate per table, run twice per variant per group — and they exist to prove the re-classify path is a pure threshold change, not to produce habitat. Whether they are a rounding error or a third of the pass is **unmeasured**; that is the point of this issue. They also have a different remedy from the model steps: a verification cost can be sampled, moved behind a flag, or run once per closure instead of once per variant, where a model cost cannot.

Step 5's `ANALYZE` calls are already known to be load-bearing, not incidental: without them one gate count ran over 10 min where it takes 0.2 s (link#364, CLWR / SQAM / BULK).

## What the logs already say

#331's build (`data-raw/logs/habitat_score_331/build_20261015_full.log`, 2026-10-15) took 199.5 min: the base (17-group closure, then recompute of the 9 focal groups) about 48 min, and 13 variants × 9 focal groups 136.7 min summed (about 150 min wall), so variant passes are about three quarters of a tuning build. One variant on one group averaged 1.17 min (REVL 0.46 to PARS 2.46), about 11 to 14 min per variant over the nine. The log does not split a pass into classify, connect and gate, which is what this issue measures.

The passes run one group at a time. Different groups use different working schemas, so passes over groups could run in parallel (two variants on one group cannot: they share its working schema). At the roughly four jobs this database levels off at, that could bring about 150 min toward 40 to 50; an estimate, to be measured beside the step split.

## Groups

No `score*` closure exists on the measuring host, so the base is rebuilt. Recommended: #331's set (focal REVL, ELKR, KOTR, UARL, MURR, UBTN, LHAF, PARS, KOTL in their 17-group closure), the BT set `default_tuned` is tuned on, so the new totals can be checked against the 2026-10-15 log. Alternative: #364's five (ADMS, BULK, CHWK, CLWR, SQAM), for CH / CO. Decided at the plan gate.

## Measure

Split that one timer into seven, keep the existing line as the total, and do not rebuild the base.

- Reuse an existing closure with `--step=variants`, never `--step=base`. The latest variant set is `data-raw/habitat_score/variants_364.csv` with `wsg_roles_364.csv`; pick the prefix whose base schema still exists, and say in the record which closure was used.
- One variant, its scoring groups: `--only=<one variant> --step=variants --prefix=<existing> --out=data-raw/logs/variant_cost_404`. Narrow with `--wsgs=` for a pre-flight before the full set.
- Log per group: minutes for each of the seven steps, the total the existing `say()` line prints, the group's segment count, and the base pass's minutes beside them for reference.
- If one step dominates, break only that one into its statements — fresh's classify SQL, the cluster pass, the gate's counts — rather than instrumenting all seven to statement depth.
- Plot minutes against segment count per step, so a step that scales with the group is told apart from a fixed cost.

The classify and cluster numbers also feed NewGraphEnvironment/fresh#275, which asks for fresh's own record of the pipeline's cost. Time those two calls the way that issue would, so the two records describe the same calls and neither has to be re-run for the other.

## Environment

Pin the environment in the stamp, because these are comparative numbers:

- **fresh v0.44.0**, pinned by link 0.69.3 (`DESCRIPTION`: `fresh (>= 0.44.0)`, `Remotes: NewGraphEnvironment/fresh@v0.44.0`). Confirm the hosts resolve that and not `main` — #269 is open on exactly that disagreement, and an unpinned host would make these minutes incomparable.
- Host class, `-j`, and whether the run shared the database with anything else.

## Not in scope

- Making anything faster. This issue measures; the change it names goes on #377.
- fresh#272 and #394, which cut the access walk a tuning loop runs **once per closure**, not per variant.

## Acceptance

- [ ] Minutes per step per group for one variant, under `data-raw/logs/variant_cost_404/` with the environment stamp above.
- [ ] The model / verification / write split stated as a share of the pass, so steps 3 and 7 are either ruled out or named as a target.
- [ ] The next change is named and added to #377's iteration-speed section — or the record says the per-variant cost is already small enough to leave alone, which closes this issue on its own terms.



## Errors Encountered

| Error | Resolution |
|-------|------------|
| `--step=bundles` stopped: "re-writing default's thresholds does not reproduce … byte for byte" (on main and the branch) | `write_thresholds()` quoted `species_code` and `*_edge_types` by name; #364 (`1ae0c34f`) added the text column `rear_river_measure`. Now quotes every column holding a non-numeric value; reproduces all three bundles' files |
| `diff -r` printed a usage text and no verdict | `diff` is shadowed by a wrapper in this shell; `/usr/bin/diff` |

## Plan review (2026-10-28)

`review-plan.md` holds the findings. Disposition: the replace-key blocker and the `t0`-window
gap were already met by the code as written (key on (variant, group, step); total taken
before `record_built()`); the `persist_init` row, the commit-before-build ordering, the
`pg_stat_activity` snapshot, the backend-pid filter and the fresh#275 wording were folded
into `task_plan.md`; the `write_bundle` self-check assumption was real (table above).

## Environment at Phase 1

- m4, Apple M4 Max, 128 GB; docker `fresh-db` up 4 weeks. Load average 4.4 / 5.1 / 5.3 at
  11:40 PDT from another session's work, no R process of ours.
- fresh 0.43.0 (`18d92ceb`) was installed; `DESCRIPTION` pins `>= 0.44.0` /
  `@v0.44.0`. Installed v0.44.0 at 19:03 UTC: `RemoteSha 22034c1a22f5629edeaa4b6fcf70eb6980208450`
  = `git rev-parse v0.44.0^{commit}`.
- `lnk_preflight_vintage()` OK at 19:05 UTC, oldest 3.6 d.
- No `score*` / `working_score*` schema on m4; `discharge.fwa_v1_segment_monthly` is wet's
  annual pick built 2026-10-15T02:06:57Z (wet `acb820f`).
- Two lints on the new script lines are the hanging-indent style the file carries 63 times
  already; left to match the file.

## Measured (2026-10-28, m4, fresh 0.44.0, link 45b12b2e)

- Base: 17 groups modelled in 67.1 min (LPCE 1.7 to KOTR 7.0), nine recomputes 2.4 min.
- `bt_rear_wet_p10` over nine groups: 5.6 min; classify 2.04, connect 1.73, persist 1.69,
  copy + ANALYZE 0.09, gate 0.02, the two digests 0.023 min (1.4 s). Model 67.7 /
  verification 0.4 / write 31.9 %.
- `default` pass (all species, four steps): 6.8 min; classify 3.31, connect 3.48.
- Scaling: classify and connect linear in segment count (25,044 to 46,004); persist from a
  0.1 min floor. UBTN and LHAF connect sit above the fit at a load of 6.3 from elsewhere.
- Four jobs over groups: variant 5.6 → 1.6 min, `default` 6.8 → 1.8.
- 2026-10-15 m1 log, same variant and groups: 9.8 min (variant), 12.0 (`default`), base 42.7.
- REVL's pre-flight and full-pass digests are equal (`778f7c72`, `15073c87`).
