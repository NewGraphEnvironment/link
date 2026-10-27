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

## Tools

- `data-raw/breaks_diff.R <WSG> [--schema=] [--out=] [--suffix=]` is the break census, promoted from #324's `breaks.R`. It labels each link break `MINIMAL_<class>` when it sits in the group's reduced `gradient_barriers_minimal`, `<source>_NON_MINIMAL` when it sits on a barrier position the reduction dropped (so an independent break source, an FWA line start, an observation or a crossing put it there), `FWA_BASE_SEGMENT`, or `none`.
