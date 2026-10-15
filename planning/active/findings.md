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


