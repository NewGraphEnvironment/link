# Findings — Read discharge from wet in classify and the habitat export, and re-tune BT's MAD range on it (#331)

## Issue context

**If done:** classify, the validator, the scoring harness and the habitat export (#308) all read discharge from wet's published `discharge.fwa_v1_segment_monthly` (`month = 0`, `pick`), and the export's manifest records the wet dataset ID and the md5s of the wet parts the build used, so habitat → discharge provenance is one chain of manifests. BT's MAD range is re-tuned on wet's values the way #302 tuned it on fwapg's, so whether to move any group to `mad` is decided on the source it would run on. **If never:** link keeps reading `whse_basemapping.fwa_stream_networks_discharge`, whose version is only what `provenance.source_artifact` happened to record on the exporting host, and `default_tuned`'s BT 0.078 m³/s stays a threshold fitted to a source we mean to leave.

Split out of #308 (operator, 2026-10-14). The export reads the discharge the run classified on, so `*_ratio_mad` agrees with the flags; moving the source changes outputs, so it is its own change.

- One subquery already serves every consumer: `.lnk_discharge_sql()` (`R/lnk_discharge.R`), table named by `.lnk_hv_discharge_tbl()`. The fill (#305) is layered on it.
- wet's loader is `wet_db_load()` (NewGraphEnvironment/wet#7); it writes `discharge.fwa_v1_segment_monthly` with a partial index `(scenario, linear_feature_id) WHERE month = 0 AND pick`. Nothing needs building: the parts are published at `s3://fresh-bc/discharge/fwa/v1/`, so the first step on any database is `wet_db_load(conn, wet_catalog())` (43 parts, 103 M rows, 1.1 GB for `historical`).
- Every host that runs the pipeline needs the table once classify reads it: the multi-host dispatcher's prep and the vintage gate (`lnk_preflight_vintage()`, `snapshot_bcfp.sh`) should load or check it, and `provenance.source_artifact` should record the manifest it came from. Measured 2026-10-15 on a local fwapg: a full `historical` load took 15.5 min, 102,790,688 rows, 20 GB with indexes; 4,532,843 lines carry an annual pick (3,152,838 `pcic_routed`, 1,380,005 `wet_balance`, none twice) against 4,907,441 FWA lines and 2,716,652 rows in fwapg's discharge table.
- Decide: whether the #305 fill still applies to wet's values, and what to log per run (`log_input` row for the wet table plus the manifest md5s).
- Decide: switch the source outright, or make it a bundle setting (e.g. `pipeline: discharge_source: fwapg | wet`) defaulting to fwapg, so every run before this change still reproduces and one scoring build can compare both sources on the same segmentation (recommended).

## Re-tune BT discharge on wet's values (operator, 2026-10-15)

The same exercise #284 / #302 ran for gradient, width and discharge, repeated on the new source before any group moves to `mad`:

- [ ] **Unblock the scoring harness at HEAD.** `data-raw/habitat_variants_build.R` / `_score.R` stop at any HEAD after #307: the variant bundles `extends: default` by name and `default`'s thresholds moved, so the guard reports "variant … equals default" (`habitat_variants_build.R:311`): #302's rungs set `*_mad_max = 9999`, which `default` has carried since #307. #342 needs the same fix; do it once.
- [ ] **Recompute `default`'s width-converted MAD minimums on wet.** `default`'s 0.041 (spawn, 2 m), 0.20 (GR spawn, 4 m) and 0.021 m³/s (rear, 1.5 m) are the median fwapg `mad_m3s` at each width minimum (#307), so they move with the source. Producer: `data-raw/query_width_mad_equivalent.R`, with its source swapped.
- [ ] **Re-run #302's BT MAD ladder** on wet's discharge: same fixed rule (P10, P05 loosening refused unless it scores), same held-out WSGs, same species pooling. Report whether BT's 0.078 m³/s spawn / rear minimum moves.
- [ ] **Re-run #300's `cw`-against-`mad` score** for BT (with and without the #305 fill), size-adjusted, on the same held-out WSGs. Compare with #300 / #305: BT rearing `cw`-only 0.19 after the fill, `mad` −32 % BT stream rearing against `cw`.
- [ ] Write the result into `research/habitat_thresholds.md` beside the fwapg sections, and land any changed value in `default_tuned` only.

Out of scope: a spawning-season discharge rule from wet's monthly values. That is a new kind of rule, not a re-tune; file it separately if this result makes it worth doing.

Relates to #308, #305, #302, #300, #342, NewGraphEnvironment/wet#7.



## wet's table, measured 2026-10-15 (local fwapg, PG 17.5)

- Annual picks (`historical`, `month = 0`, `pick`): 4,532,843, one per `linear_feature_id`; only `historical` carries picks. `watershed_group_code` on every pick (246 WSGs). No NULL `q_m3s` among picks: wet's "no value" is an absent row (fwapg has 713 k NULL-valued rows of 2.72 M).
- Two normal periods in one pick: `pcic_routed` 1951-2012, `wet_balance` 1981-2010.
- 29,491 picks are exactly 0 (22,453 `wet_balance`, 7,038 `pcic_routed`); fwapg has 559 at or below 0. Operator: read 0 as no value (`nullif`).
- The wet relation plans as a nested loop over the partial index (plan review: BULK join 0.2 s).
- fwapg SQL from `.lnk_discharge_sql()` / `.lnk_discharge_candidates_sql()` is byte-identical to main's for every argument shape (checked by sourcing main's file beside HEAD).

## Plan review (`review-plan.md`), triage

| Finding | Disposition |
|---|---|
| B1 a wet bundle needs wet on every host | operator: only `default_tuned` reads wet; Phase 6 lands with Phase 5 |
| B2 validator check breaks the MAD instrument | source mismatch is a warning; docs say why |
| B3 #302 / #307 outputs not reproducible | re-run fwapg at HEAD as the baseline |
| G1 missed callers / docs | `discharge_fill_count.R` repointed; publish `runs.csv` carries the source; validator / classify / config / export-schema docs updated; orphan roxygen removed. `query_habitat_thresholds_fiss.R` and `logs/habitat_score_302/power_windows.R` stay fwapg (historical producers, not re-run here) |
| G2 no pipeline key validation | `lnk_config()` refuses an unknown `discharge_source` |
| G3 harness under-specified | (a,b,c,e) done; (d) resolved source and fill written into every bundle; (f) a model-only variant must be `mad`, so a source-only `cw` variant cannot exist |
| G4 fill per variant | `discharge_fill` column |
| G5 per-part md5s | no load record exists; Phase 6 logs the table comment, wet issue for a load record |
| G6 vintage gate | Phase 6: wet checked only for configs that read it, not age-checked |
| G7 guard not testable | scripted `--step=bundles` runs, recorded in progress |
| G8 per-WSG rules read | `.lnk_discharge_read_each()` reads rules and method once |
| O1 / O2 | Build B on `default_tuned`, after Phase 5 |
| O3 | commit before any build |
| S2 fill reach | measured in Phase 3 before scoring fill off |
| S3 `default_extrabreaks` / `default_rearbreaks` | stay fwapg (`extends: ~`, untouched) |
| S6 wet's `source` in `mad_m3s_source` | not done: it would change the export contract's value domain; `modelled` stays |
| A2 / A3 / A4 / A6 | acceptance reworded in the plan |

## Phase 3: discharge numbers on wet (`data-raw/logs/discharge_wet_331/`, 2026-10-15)

**Width-converted minima** (median `mad_m3s` at the width minimum, floored to 2 s.f.; `width_*`):

| | fwapg at HEAD | wet | fwapg, common lines | wet, common lines | `default` (#307) |
|---|---|---|---|---|---|
| spawn, 2 m (BT, KO, RB) | 0.042 | 0.043 | 0.042 | 0.041 | 0.041 |
| rear, 1.5 m (BT, GR, RB) | 0.021 | 0.023 | 0.021 | 0.022 | 0.021 |
| GR spawn, 4 m | 0.20 | 0.20 | 0.20 | 0.19 | 0.20 |

`default` keeps its values (operator); the source barely moves them. HEAD's fwapg spawn value is 0.042 against #307's 0.041: `fresh_default` gained DUNC since.

**BT at observations** (`mad_*`; P05 is the fixed rule's value, P10 / P02 the ladder's other rungs):

| | calibration WSGs | BT rows with no discharge | rear (any stage): n, P10 / P05 / P02 | spawn: deciding set, n, P10 / P05 / P02 |
|---|---|---|---|---|
| #302 committed (fwapg) | 46 | 10.7 % | 2,592: 0.078 / 0.027 / 0.0085 | any-stage fallback (17 spawn-staged) |
| fwapg at HEAD | 47 | 10.2 % | 2,803: 0.084 / 0.028 / 0.0089 | any-stage fallback, 2,802: 0.084 / 0.028 / 0.0089 |
| wet | 56 | 0.17 % | 4,199: 0.044 / 0.021 / 0.0082 | **spawn-staged, 58**: 0.013 / 0.0064 / 0.0020 |
| wet on fwapg's 47 WSGs | 47 | 0.19 % | 3,116: 0.091 / 0.036 / 0.014 | any-stage fallback, 3,115 (17 spawn-staged) |

- wet adds nine Skeena groups (BULK, KISP, KLUM, LKEL, LSKE, MORR, MSKE, USKE, ZYMO), where fwapg has no discharge. They bring 41 of the 58 spawn-staged BT locations, so spawning is decided on spawn-staged evidence for the first time (the rule's floor is 30), and its percentiles are far lower than the any-stage fallback.
- On the same 47 groups, wet reads higher than fwapg at BT locations (P05 0.036 against 0.028): the lines fwapg left empty, now valued, sit in larger water.
- Over all 56 groups, the Skeena locations pull the rearing percentiles down (P10 0.044 against 0.084).
- By wet's own source (`mad_wet/bt_quantiles_by_wet_source.csv`): 4,023 of 4,198 rearing locations are PCIC routed, with percentiles matching the pooled ones; 175 are wet's water balance (P05 0.022, median 0.53 against 1.24). Spawning is 57 of 58 PCIC routed.
- **Fill reach** (`fill_reach_1250.csv`): edge 1250 km with no value, #302's nine BT score groups 506 → 5; `fresh_default`'s 56 groups 5,967 → 29. On wet the #305 fill has almost nothing to fill, so no fill-off scoring variant.

Ladder rungs for Build A, floored to 2 s.f. as #302's rule does:
- wet: rear 0.043 / 0.020 / 0.0081; spawn 0.012 / 0.0063 / 0.0019.
- fwapg at HEAD, on the same segmentation, for a same-day comparison: rear and spawn 0.083 / 0.028 / 0.0089.
