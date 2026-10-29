# Task: Adopt fresh v0.46.0: the walk prefilter (fresh#272) in the recompute (#409)

**If we do it:** every group's recompute walk reads only the features that can reach the group. #261 estimated that cuts 36 to 51 % of the recompute's summed work on every provincial run, and it unblocks #394. **If we never do:** each walk keeps probing the group's segments once per feature in the province, so CHWK costs 18 times what SALR does.

## Context

#261 found the recompute's cost is `frs_network_features()` driving every downstream walk from every feature in the province (CHWK 18× SALR). fresh v0.45.0 (fresh#272) now copies the AOI's segments into an indexed session temp table and admits only features `fwa_downstream()` can return; v0.46.0 (fresh#242) makes fresh's connectivity passes match `watershed_group_code`. link still pins v0.44.0, so none of it reaches a run. #377's tracker item stays open until the recompute's per-group minutes are measured with the new fresh.

What exploration settled:
- **link already passes `aoi =` on every downstream walk** (`R/lnk_pipeline_access.R:156,184`), so the prefilter applies with no link code change. The observation walk is upstream and unchanged.
- **No link session is read-only**, so fresh 0.45's temp-table requirement is met. Only the frozen #261 evidence scripts (`walks.R`, `walk_prefilter.R`) set `default_transaction_read_only`; they stay as they are.
- **fresh#242 needs `watershed_group_code` on `frs_cluster()`'s table and habitat;** `lnk_pipeline_connect()` passes `<schema>.streams` / `<schema>.streams_habitat`, and fresh 0.46's `frs_habitat_classify()` writes that column (`R/frs_habitat_classify.R:239`). Nothing in link calls `frs_cluster()` directly.
- **`lnk_preflight_fresh()` reads its floor from DESCRIPTION** (`.lnk_fresh_floor()`), so a host left on 0.44 fails preflight once the floor moves. No new symbol or formal to add.
- **The pre-run gate (#372, just merged) maps fresh files between the two pins.** All seven fresh files changed v0.44.0→v0.46.0 (`frs_cluster`, `frs_feature_index`, `frs_habitat`, `frs_habitat_classify`, `frs_network_features`, `frs_network_segment`, `utils`) already have rows in `data-raw/pretest_inputs.csv`; two are `none`, whose `why` names v0.44.0 and must be re-verified at v0.46.0 (`test-pretest.R` walks fresh's graph at the DESCRIPTION pin). The bump voids the gate's existing record by design.
- **Risk to "outputs should not move":** fresh 0.45 now ends each array's `ORDER BY` on feature id, where ties for co-located features used to follow the plan. link reads the anthropogenic array's first element (`dam_dnstr_ind`); #261 saw it match in nine groups, but a tie could now resolve differently. The digests below are what would show it.

## Decided at the gate

Approved by the operator at the plan gate, 2026-10-28 ("Go all phases to pr").

- **Measure the recompute on the dispatcher's `fresh_default`** (the 2026-10-23 build, where CHWK, SALR, SETN, LSKE, LKEL live) with #261's `rerun.R` pattern: it re-runs a group's recompute, digests every table it writes before and after, backs the rows up first and stops with the restore statement if any digest moves. It writes back the same rows; it refuses beside another active client or a lock in the schema. m4's databases cannot stand in: a walk's cost is the province-wide feature count, which a scratch schema of a few groups does not hold.
- **Before/after differ only in fresh:** both run from one worktree at the link SHA that wrote the rows, with fresh v0.46.0 installed into a separate scratch library and put first by `R_LIBS` for the "after" runs. The shared library keeps 0.44.0 until every "before" run is done (load_all-vs-floor rule).
- Groups: the tracker's four (SALR, LKEL, CHWK, LSKE) plus the issue's SETN (output-bound, 1.2× expected). SETN runs before/after/after/before, since its gain is within cache noise; the rest one pair each.

## Phase 1: fresh v0.46.0 beside v0.44.0
- [x] Install fresh v0.46.0 into a scratch library (`pak` from the tag); confirm `RemoteSha` equals `git rev-parse v0.46.0^{commit}` and that the shared library still reports 0.44.0
- [x] Worktree(s) at each group's `log_recompute.link_sha` on the dispatcher (expected `1d00c04c`; `rerun.R` refuses any mismatch)

## Phase 2: the recompute, before and after (dispatcher `fresh_default`)
- [x] Copy `rerun.R` to `data-raw/logs/prefilter_409/` with the fresh version and `RemoteSha` stamped into each output, and the backup schema renamed `zz409_backup`
- [x] After Phase 3 finishes and m1 is quiet: SALR, LKEL, LSKE, CHWK ran b1, a1, a2, b2; SETN b1, a1 (its second pair is owed, below) (review O3, O4). Outputs: `steps_<WSG>_<label>.tsv`, `walks_…` (with array digests), `digest_…`, logs; `fresh_default.streams` / `.barriers` write counters before and after (G6)
- [x] Every table digest unchanged, and every walk's arrays identical across runs (if anything moves: stop, keep the restore, record the segments, and bring it back to the operator)
- [x] Tie risk counted before any write (review B1, G1): 0 co-located anthropogenic features in 241 groups, 0 in the remediation sets of 134 groups
- [x] `summary.R`: per group, lnk_access / walks / gate / mapping code, before vs after, and per walk against #261's table (the provincial share is left to the next run, AC1)

## Phase 3: model-time outputs do not move (m4, scratch schemas)
- [x] Build ADMS (SK/KO reach fresh#242's `connected_waterbody` path), NATR (BT, GR, KO, RB) and ELKR with `wsg_run_one.R` + `wsg_recompute_one.R` into `fresh_409b` (0.44.0) and `fresh_409a` (0.46.0), from one worktree at BASE
- [x] Per-group per-table digests (streams, barriers, streams_access, streams_mapping_code, every streams_habitat_<sp>) with `provincial_prep_367/compare.R`'s pattern, after asserting each schema's logged fresh: identical, as one host's builds are (#367). On any mismatch, rebuild the 0.44.0 side first (G3)
- [x] Drop the two scratch schemas once the digests are committed

## Phase 4: the pin
- [x] `DESCRIPTION`: `fresh (>= 0.46.0)`, `Remotes: NewGraphEnvironment/fresh@v0.46.0`
- [x] Install v0.46.0 into the shared library, after every 0.44.0 run (Phase 2's b runs and Phase 3's builds)
- [x] Tests: every downstream walk passes `aoi`; the floor equals the `Remotes:` tag; each shown to fail with its guard removed
- [x] `test-pretest.R` passes at the new pin (24 / 0 failed / 0 skipped); the `none` rows name both tags, the reach being identical; `pretest_run.sh --pick-only` exits 0 over `1d00c04c..HEAD` (fresh v0.42.0..v0.46.0, 31 files)
- [x] `devtools::test()` (1,180 / 0 failed / 1 skip, the dirty-tree test, which passes on a committed tree) and `lintr` (no new lints in changed files) at fresh 0.46.0
- [ ] `devtools::check()` at fresh 0.46.0

## Phase 5: record
- [x] `data-raw/logs/prefilter_409/README.md` (environment stamps, method, numbers, evidence index)
- [x] `research/recompute_cost.md`: "Measured since fresh#272" with the per-group minutes
- [x] CLAUDE.md status entry and its reach line; RUNBOOK: the walk's planner notes and the pre-run gate's "recompute's cost" line (G8)
- [ ] Edit #377's prefilter item with the measurement and tick it; NEWS + version bump (v0.69.6, outputs unchanged) as the last commit

## Owed at the end (reported, done after merge)

- [ ] SETN's second pair (a2, b2): the driver waits up to 6 h for a quiet dispatcher (`LIB044` arm), then fill it into the README, research table and #377

- [ ] Re-prep the cloud hosts and the persistent worker for fresh v0.46.0 (`--auto-install`, RUNBOOK §8d) before the next dispatch
- [ ] Run the full pre-run gate (`pretest_run.sh --config=default --schema=fresh_default`) at the new pin before the next provincial run; the bump voids the 2026-10-29 record
- [ ] #394 is unblocked: measure it on top of this release
- [ ] The next provincial run's `log_recompute` minutes against 2026-10-23's, at `-j8` on the dispatcher (G7)
- [ ] Follow-up issue: `lnk_access()`'s own scoped streams table is redundant beside fresh's (S1)

## Validation

- [x] Tests pass
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved: the recompute's rows digest identical before and after on five dispatcher groups (`rerun.R` restores and stops otherwise); model-time tables digest identical on three groups built both ways on one host; the gate's map covers the new fresh range (`--pick-only` exit 0, `test-pretest.R`); `lnk_preflight_fresh()` refuses 0.44.0 once the floor moves (existing test reads the floor from DESCRIPTION).

Approve runs every phase to the PR. To park, reject with `park`: the baseline is written and pushed, nothing more.
