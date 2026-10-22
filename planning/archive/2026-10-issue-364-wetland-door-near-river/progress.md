# Progress — Through-wetland stretches: use the stream door plus a near-river test, not a free pass (#364)

## Session 2026-10-21

- Plan gate: the parked v3 plan in the issue body was presented as the draft and approved. It was verified against both repos first: no R/inst/tests commit on link or fresh main since the body was written.
- Created branch `364-through-wetland-stretches-use-the-stream` off main.
- Scaffolded the PWF baseline with the approved phases.
- Next: Phase 0 in fresh (`/planning-init fresh#263`, sequenced with fresh#262).
- Phase 0 in fresh: branch `263-inherit-near-river-from-the-thresholds-c`, three phases committed, `/code-check branch` in progress. fresh 0.42.0 is installed locally from a copy with only the version bumped; the fresh release commit comes after the review.
- Phase 1: `Imports: fresh (>= 0.42.0)`, `Remotes: NewGraphEnvironment/fresh@v0.42.0`. The tag does not exist until the fresh PR merges, so CI cannot install it before then. Preflight gains `frs_habitat_predicates(near_river_table)` and `.frs_near_river_specs`. Suite on the Phase 1 tree alone, in a worktree: 3,415 expectations, 2 failures, 0 errors, 6 skips. Both failures are the known stale golden dams pin (8 ADMS dams; `cabd.dams` gives 7; CLAUDE.md 2026-10-16), not this change.
- Phase 2: `rear_wetland_flow` and `rear_near_river` in `lnk_rules_build()`, both dictionaries, and the bundle columns. The bundles get NA thresholds columns; `default` takes `free` / `both`, and `bcfishpass` gives CO `gradient`. The rules diff is as intended. Every river-polygon rule gains `near_river: false`. bcfishpass CO's 1050/1150 rule gains `gradient: [0, 0.0549]`; `default` changes only by the stamps. The 1050/1150 rule is emitted as codes in categories mode too, and no shipped bundle builds in categories mode. A fixture frozen from the 0.66.7 builder (`tests/testthat/fixtures/rules_build_0667/`) checks that the new builder differs only by those changes. `regen_provenance.R` resolves its root from its own location, covers `default_tuned` and the thresholds CSV, and leaves 0 drifted entries in all three bundles. `audit_configs.R` exits 0, with two narrow rules for the frozen bundles. Near-river columns absent altogether are not "stale", because fresh reads them as NA; a partial set still flags. Rules that differ only by `near_river: false` match when the bundle's thresholds carry no near-river column, where the stamp is inert. Builder tests: 323 expectations; dictionaries 99.
- Phase 3, code:
  - The discharge reader is renamed `.lnk_discharge_read_rules()` and answers through fresh's `.frs_near_river_specs()` (`.lnk_near_river_pairs()`).
  - `<schema>.streams_near_river` is created by persist init and copied by persist; a WSG's rows are always deleted. Classify drops a stale working near-river table first.
  - `log.near_river` holds the pair text.
  - The validator refuses a schema without the table when cfg reads a pair, and a log whose pairs differ. It passes the persisted table to both predicate calls.
  - Statement counts move 8 to 9 and 7 to 8.
  - Consolidate discovers tables by `watershed_group_code`, so the new table travels. `study_area_verify.sql` enumerates habitat tables only, so nothing there changes.
- Phase 3, verification on ADMS (`data-raw/logs/wetland_door_364/verify_phase3_adms.txt`): the test bundle (CH stream door, pair model / 15 m / 3 m3/s / 1000 m) runs end to end in 2.3 min.
  - 5,849 near-river rows are persisted, and the log reads `channel_width:15:1000`.
  - The validator scores CH: 11 locations, 0 post_predicate.
  - `default` filled and unfilled give the same habitat digest.
- Width for 3 m3/s: 15 m (`data-raw/query_mad_width_equivalent.R`; the 15 m bin, n 600, median 3.29). The narrowest bin with n >= 100 whose median reaches 3 m3/s; a "stays above" rule read noise in the sparse bins over 20 m and gave 44 m.
- Phase 4, harness. `habitat_variants_build.R` and `_score.R` learn three things.
  - A `dims` column holds cells of the variant species' row in the base's `dimensions.csv`. The variant writes its own `dimensions.csv` and a rebuilt `rules.yaml`, both with provenance entries the verify loop reads.
  - A structure row class: no column, on `cw`, from the base, with `dims` and/or `set`. It is scored against the base in `structure_bands*.csv` and kept out of ladders.
  - `set` may name `*_river_*` cells. `built.csv` gains `rules_sha256` and `dimensions_sha256`, NA for older rows, which only a variant without dims may have. Ladders hold `dims` fixed like `set`. A near-river ladder's first step (base cell NA) is an anchor like a model change, and its core leaves the base out.
  - The score's known-habitat guard now looks only at the scored groups: per flag for a structure row (a biased flag is skipped and named), per step for a ladder (still a stop). CH's reaches in the five groups are all spawning.
- Pre-flight on SQAM, build 8.3 min:
  - An inert `dims` change (`notes`) persists CH habitat identical to the base (md5 c8abbeb5…).
  - The stream door moves 2.7 km out of CH rearing and 0.2 km in.
  - `ch_w30` is taken as the pair anchor.
  - The score refuses a bundle whose `rules.yaml` changed after the build.
- Phase 4 run decisions, 2026-10-21. Config `default`; schemas `score364_<variant>`; working `working_score364_<wsg>`. Focal groups ADMS, BULK, CHWK, CLWR, SQAM, all `held_out`: the pair's numbers came from province-wide work (#346) and the 15 m width from `fresh_default` province-wide, so none of these groups chose them. The closure is resolved by the harness and listed in `score/closure.txt`. Variants are CH and CO, from `data-raw/habitat_score/variants_364.csv`. Discharge is fwapg, filled only on `ch_q3_discharge`. Scored with `--floor=expected`.
- Phase 4 build, first attempt (19:36 to 21:35 UTC). The base finished: 14 groups, 3.5 to 18.8 min each, CLWR the longest. The recompute left access unchanged on all five focal groups. The base re-classify reproduced every focal digest. The variants then slowed from 0.3 min a group in the pre-flight to 6 to 13 min: the habitat gate's count was planned on statistics taken before the variant's rows were inserted. Re-run by hand on fresh statistics, the same count takes 0.2 s. The run was stopped during `ch_pair_both` BULK. The harness now runs ANALYZE on the variant's tables before the gate, and the variants step is re-run on the same base.
- Phase 4 results (`data-raw/logs/wetland_door_364/README.md`). Variants step 63.7 min; score clean.
  - The stream door removes 43.1 km of CH rearing, where 0 locations were found and 3.1 expected, and keeps capture at 260 of 291.
  - The pair with scope `both` adds 275.6 km with 1 location against 19.5 expected (ratio 0.05), which the expected floor would refuse. Scope `wetland_flow` adds 4.3 km and decides nothing.
  - Both ladders' anchors are poorly used: 1 of 13.2 and 0 of 10.7. Every later step is underpowered, so the walk lands 20 m and 500 m unscored.
  - On `cw` the door keeps 83 to 95 % of through-wetland CH rearing in four groups (58 % on SQAM), because the size test is a 1.5 m width.
  - CO under `bcfishpass`: ADMS rearing 352.55 → 352.33 km (bcfishpass 351.19); BULK 2,215.57 → 2,214.12 (2,221.93).
- Decision 6's `rear_near_river = both` is contradicted by these groups. It goes to the operator before Phase 5 moves `default`'s pair.
- Operator decision, 2026-10-21, on Phase 4's evidence: the pair on wetland lines only. `default` takes `rear_wetland_flow = stream` for BT, CH, CO, ST, WCT, CT, DV and RB, and CH `rear_near_river = wetland_flow`. CH's pair is model / 15 m / 3 m³/s / 1000 m in `default` and `default_tuned`. The rules diff is as intended: six species' 1050/1150 rule becomes the inheriting stream door (CT and DV have no thresholds row), and CH's stream rule gains `near_river: false`. Provenance shows 0 drift in all three bundles, and the audit exits 0.
- Phase 5 docs: RUNBOOK §7 (new section and two table rows), §6b (log columns), §6d (the pair is not exported); NEWS 0.67.0; CLAUDE.md status; the research section and header; README rows. Tests updated for `default`'s pair: the validator fixtures use `default_nopair()`, the pre-#364 shape they were built for.
- Code-check round 1: six fragile findings; four fixed (`3692a509`), one documented, one accepted. Full suite before the fixes: 3,726 expectations, 2 failures (the stale golden dams pin only). The persist, discharge and builder tests pass after the fixes.
- Round 2's reviewer stopped on the account's spend limit (HTTP 429) before writing anything; no findings exist for it.

### Parked 2026-10-21 (operator: park until credits allow)

State: Phases 0–5 done and committed; fresh PR #264 open (not merged; v0.42.0 not tagged). The link branch is pushed, with no PR yet.

Left, in order:
1. `/code-check branch` rounds 2 and 3 at least. Round 2 reviews `3692a509`'s fixes first; the brief is the round 1 shape plus that fix diff. Round 1 found a defect pattern (inert or leaking combinations), so end on a clean round, or on an enumeration of the builder's dims combinations against what fresh compiles.
2. Re-run the full suite after any fixes (`NOT_CRAN=true`; expect only the 2 golden dams failures).
3. `/planning-archive`; the archive README carries `data-raw/logs/wetland_door_364/README.md`'s headline numbers. Keep `rule_table_issue_draft.md` for body review, unfiled.
4. `/gh-pr-push` with the drafted body (`planning/active/pr_body_draft.md`) (`Closes #364`; note fresh PR #264 must merge and be tagged first).

### Resume

    cd /Users/airvine/Projects/repo/link && git fetch -q origin && git checkout 364-through-wetland-stretches-use-the-stream && git pull --ff-only && git merge origin/main

## Session 2026-10-22

- Resumed from the park. Code-check round 2: two findings inside round 1's fixes, fixed (`7bf11106`). Round 3: two findings of the same mechanism, one inside round 2's fix, fixed (`370b648f`). The loop ends on the enumeration in findings.md (13 rows, each set read from its source).
- Full suite: 3,742 expectations, 2 failures (the stale golden dams pin only), 0 errors, 6 skips.
