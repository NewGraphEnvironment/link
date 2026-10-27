# segmentation_326 — breaking only where a present species' access changes (#326)

## Run decision (written before any re-model)

- **What re-segments.** The change moves break positions in every group, under every config. Every persisted group must re-model, in both `fresh` (bcfishpass config) and `fresh_default` (`default`), all 241, followed by the post-consolidate recompute. That is the next provincial run (#377's runs row) at the release this lands in, done after merge. A partial re-model leaves the two schemas, and groups within each, on different segmentations.
- **What is re-modelled here.** On m4's local docker fwapg only, for measurement:
  - PCEA, FINA, PARS and LKEL × {`bcfishpass` into `fresh`, `default` into `fresh_default`};
  - the remaining groups of the 11-WSG cross-section, `bcfishpass` only.
  Groups run DS-first, then `wsg_recompute_one.R` with `merge = TRUE`. m4's local schemas are dev state and are published nowhere.
- **Primitives.** The m4 snapshot was loaded 2026-10-25 05:40 UTC. `lnk_preflight_vintage()` passed on 2026-10-27 (oldest stamp 1.9 days), so it was not re-pulled.
- **Before state.** m4's local `fresh` held pre-#223 builds, reduced before the lifts: FINA 26,096 segments, PCEA 33,765, PARS 48,561 and LKEL 3,376. bcfishpass's `fresh.streams_vw_bcfp` holds 28,650, 37,957, 43,655 and 3,360. The before-state comparison of record is #324's census (`data-raw/logs/rearing_diff_324/`), taken on the dispatcher's every-position build.

## Pre-flight (Phase 2): FINA, bcfishpass config

`preflight_FINA_bcfishpass.log` holds the run, from a worktree at `11ed42c7` on fresh 0.42.0. It started 2026-10-27 02:08 UTC and took 17.0 min, while another session was loading the same database.

| | link before | link now | bcfishpass |
|---|---|---|---|
| FINA segments | 26,096 (m4, pre-#223); ~70 k (dispatcher, every position) | **28,650** | 28,650 |
| breaks held by the other side within 1 m | — | 20,394 of 20,394 | 20,394 of 20,394 |
| link-only breaks | 41,720 (#324, dispatcher) | **0** | — |
| BT accessible km | — | 6,084.04 | 6,085.25 (−0.02 %) |

- **#223's frontier holds.** On blue line 359209845, no segment straddles 3,834.78 m. The segment there is BT-blocked, and accessible BT reach tops out at 3,835 m. The position is one of the 3,883 rows in `working_fina.barriers_bt_min`, reduced from 23,700 post-lift rows.
- **Only BT's set was built.** FINA is BT-only, so `working_fina` holds `barriers_bt` and `barriers_bt_min` and no other species' table.
- The census is `fina_breaks_preflight.csv` (`data-raw/breaks_diff.R FINA --suffix=_preflight`). A `<class>_NON_MINIMAL` row is a break that sits on a barrier position the reduction did not keep but that something else broke there, such as an FWA line start, an observation or a crossing. bcfishpass breaks at all of them too.

## Pre-flight (Phase 3): PARS, bcfishpass config, cancelled

`preflight_PARS_bcfishpass.log` holds the run, from the worktree at `1b69ad7c` on fresh `25dca92`. It started 02:28 UTC. The per-segment BT access walk (`frs_network_features` over the persisted `fresh.barriers`, 7.47 M rows) was still running after 1 h 58 min, while another session ran four CPU-bound `pcic` loads at once. It was cancelled at the 04:30 UTC deadline. The plan is the province-scale nested loop the walk always uses, and #326 does not change it: the walk reads persisted barriers, and PARS now has fewer segments. Planner statistics were current (`reltuples` 7,468,955 against a count of 7,468,927). It is the OKAN shape in CLAUDE.md. PARS is re-modelled in Phase 4 instead.

## Phase 4: how the runs are laid out

`run_phase4.sh` (driver log `phase4_driver.log`, per-run status `phase4_status.tsv`):

1. It waits until no `pcic` query has run for five minutes, up to three hours.
2. `default` BEFORE: PCEA, FINA, PARS and LKEL at main (`a34d5357`), into the scratch schema `zz326_default_pre`. m4's `fresh_default` holds pre-#223 builds, so it cannot serve as `default`'s before state.
3. `default` AFTER: the same four groups at `ae1df6ff`, into `fresh_default`.
4. `bcfishpass` AFTER: the 11 cross-section groups (LKEL BULK KISP USKE MORR PCEA FINA PARS LFRA KOTR ELKR) at `ae1df6ff`, into `fresh`. These run last, so each `working_<wsg>` holds the bcfishpass build that `breaks_diff.R` reads.
5. It runs `wsg_recompute_one.R` with `merge = TRUE` over every group of each schema.

Both worktrees use fresh 0.43.0 (`18b94fe`), installed from a git archive, so log rows carry no fresh `RemoteSha`. A failed group is retried once and named in the status file.

## Round 1 (`round1/`): the branch at `ae1df6ff`, fresh 0.43.0

`run_phase4.sh` as above, from 2026-10-27 ~05:00 UTC. Driver `round1/phase4_driver.log`, per-run status `round1/phase4_status.tsv`.

- **Failed steps.** Only the `default` recomputes of PCEA, FINA and PARS failed, before and after, on the recompute's last step. That step is the downstream-dam post-condition: Peace Canyon and Site C sit in UPCE, which neither dev schema holds. The recompute's access, gate and mapping-code work commits before that check runs, and dams set no access or habitat. LKEL passed.
- **Segments, link against bcfishpass:** BULK 42,989 / 42,965; ELKR 38,245 / 38,214; FINA 28,650 / 28,650; KISP 30,873 / 30,852; KOTR 37,674 / 37,610; LFRA 27,612 / 27,442; LKEL 3,374 / 3,360; MORR 29,100 / 29,093; PARS 43,776 / 43,655; PCEA 37,972 / 37,957; USKE 27,255 / 27,268.
- **`default` segments, before against after:** PCEA 106,079 → 39,566; FINA 70,329 → 30,136; PARS 97,537 → 46,341; LKEL 7,448 → 3,378.
- **Break census** (`round1/*_breaks.csv`). There are 454 link-only breaks over the 11 groups: falls 129, observations, crossings and endpoints 320, gradient 4, user-definite 1. There are 40 bcfishpass-only breaks. FINA has 0 of each.
- **Parity** (`round1/parity_crosssection.log`). 114 of 122 pairs were within tolerance. The misses were ELKR and the parked BULK SK. ELKR read LARL's pre-#127 rows in `fresh`: a no-override gradient barrier on the Pend Oreille at 723 m, below the BC Flathead. After LARL was re-modelled at the branch and ELKR recomputed (`round1/*LARL*.log`, `round1/recompute_bcfishpass_post_ELKR_after_LARL.log`), BT accessible km was 4,208.1 against 4,207.2. ELKR's habitat stayed low because the habitat gate is one-way, so round 2 re-models ELKR.
- **BT habitat, segment by segment** (`round1/habitat_diff/`):

  | Group | Rearing link-only / bcfishpass-only (km) | Spawning link-only (km) |
  |---|---|---|
  | FINA | 0 / 0.06 | 4.58 |
  | PCEA | 0.05 / 1.2 | 1.78 |
  | PARS | 0 / 8.11 | 5.49 |
  | LKEL | 0 / 0 | 0.02 |

  Spawning link-only is fresh's `>=` against bcfishpass's `>` at exactly 2.0 m, the follow-up drafted for it.
- **PARS's 8.1 km of bcfishpass-only rearing** is order 1, parent order 5 or more, with a known width under 1.5 m. Of PARS's qualifying lines the exception does not admit, 10.73 km fail `frs_order_child()`'s direct-child test (`stream_order = stream_order_max`; fresh#158's choice). The exception does run: 16.76 km rear through it.
- **Unbroken frontiers** (`unbroken_frontiers.sql`, `round1/unbroken_frontiers.csv`). These are accessible segments holding an access-view barrier more than 1 m above their start: 57 segment-species, 18 for BT. 11 of the 18 BT segments were barrier rows `lnk_barriers_unify()` dropped because `FWA_LocateAlong()` returned no point (`round1/unify_dropped_rows.csv`). The reduction had kept those positions. The fix is `21e0fea2`. Neither residual the plan named appeared (a lift held by another group, or the out-of-AOI pruner): every holder was the segment's own group.

## Round 2 (`round2/`): the unify fix at `21e0fea2`

`run_round2.sh` re-ran `default` AFTER (4 groups) and `bcfishpass` AFTER (11) at `21e0fea2`, then the same measurements, from 07:31 to 08:46 UTC on 2026-10-27. Status is `round2/status.tsv`, driver `round2_driver.log`. The failed steps are the same three `default` recomputes, on the same dams.

- **Segments and breaks are unchanged** from round 1, group by group (454 link-only, 40 bcfishpass-only). The fix changes which barrier rows persist, not where streams break.
- **Unbroken frontiers: 57 → 27 segment-species, BT 18 → 9** (`round2/unbroken_frontiers.csv`; rows in `round2/unbroken_frontiers_rows.csv`). The 27 sit on 13 barrier positions, and at each the nearest break is 1.07 to 1.43 m away. For the four positions within 1.5 m of a line's start (PARS BT 1.30, PCEA BT 1.42, USKE CH / CO / SK 1.38, ELKR WCT 1.33), that break is the line's start. This is #349's metre-rounded break family (A), which predates #326 and is fresh#258's to fix.
- **Parity: 120 of 122** (`round2/parity_crosssection.log`). The two over are BULK SK spawning and rearing (parked). ELKR is within tolerance on every metric (BT accessible −0.03 %, spawning +1.40 %, rearing −0.01 %). The FINA structural frontier passes.
- **BT habitat is identical to round 1** in all four groups (`round2/habitat_diff/`).
- **Geometry.** Rows that only the fallback locates got one fixed point in round 2, a defect `21e0fea2` carried (an uncorrelated subquery) and code-check round 4 fixed in `34da7d1a`. Access, breaks and habitat do not read `barriers.geom`, so no round-2 measurement moves. m4's dev schemas keep those points until the provincial re-model.

## Tools

- `data-raw/breaks_diff.R <WSG> [--schema=] [--out=] [--suffix=]` is the break census, promoted from #324's `breaks.R`. It labels each link break `MINIMAL_<class>` when it sits in the group's reduced `gradient_barriers_minimal`, `<source>_NON_MINIMAL` when it sits on a barrier position the reduction dropped (so an independent break source, an FWA line start, an observation or a crossing put it there), `FWA_BASE_SEGMENT`, or `none`.
