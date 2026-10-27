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

## Tools

- `data-raw/breaks_diff.R <WSG> [--schema=] [--out=] [--suffix=]` is the break census, promoted from #324's `breaks.R`. It labels each link break `MINIMAL_<class>` when it sits in the group's reduced `gradient_barriers_minimal`, `<source>_NON_MINIMAL` when it sits on a barrier position the reduction dropped (so an independent break source, an FWA line start, an observation or a crossing put it there), `FWA_BASE_SEGMENT`, or `none`.
