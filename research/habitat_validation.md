# Habitat validation against fish observations

**Verified:** 2026-09-27; size model per group 2026-10-02 · **Issues:** #283 (this), #284 (step 5 scores with it), #290 (pooling as data), #203 (full-key joins), #299 (cw / mad per group), fresh#218 · **Produced by:** `lnk_habitat_validate()` via `data-raw/habitat_validate.R` → `data-raw/logs/habitat_validate_283/` (link @ `0c19e0a`) · **Status:** baseline; #284 step 5 scored BT `rear_gradient_max` with it (see below)

## What it measures

For a persisted run (one bundle's schema), per WSG × species × stage (`any`, `spawn`,
`rear`):

- **Capture:** the share of observation locations on segments the run models as
  accessible, spawning, stream rearing, or any rearing (stream, lake or wetland).
- **Cost:** `accessible_km`, `spawning_km` and `rearing_km` from `lnk_rollup_wsg()`, so
  capture cannot be raised by calling more of the network habitat.
- **Misses:** why each missed location's segment is not habitat. The bundle's own
  predicates (`fresh::frs_habitat_predicates()` over its `rules.yaml` and thresholds) are
  re-evaluated with the gradient, then the width, relaxed to the stage minimum.
  `fails_gradient` means the gradient maximum is what binds.
- **Absences:** FISS sites sampled without the species, as a false-positive check.

The driver scores two bundles and diffs them on the WSGs both hold. It first asserts
that both retained the same observations.

## Method

- **Observations:** `bcfishobs.observations` with `observation_exclusions`
  (`data_error | release_exclude`) and every `Releases Database` record removed. Species
  must be present in the WSG per `wsg_species_presence`. Which observation species count
  as each model species comes from the pooling bundle's `species_pooling.csv` via
  `lnk_species_pooling()` ([`species_pooling.md`](species_pooling.md), #290): for
  `default`, DV counts as BT in the Fraser, Mackenzie, Skeena and Columbia, where BT is
  present. The driver resolves it once, from the first bundle that declares a tracker (or
  `--pooling=`), and applies it to both bundles; `stamp.txt` records which. Match types are A/B only (stream, within 100 m). One
  location per species × `blue_line_key` × metre, which is staged if any record there is.
- **Other sources:** `observations` takes any table or data frame that has
  `species_code`, `watershed_group_code`, `blue_line_key` and
  `downstream_route_measure`, so crew data, eDNA or a held-out subset can be scored the
  same way. A source can give its own `is_spawn` / `is_rear`. The two bcfishobs filters
  (`match_types`, `source_exclude`) default on. When the source lacks the column a filter
  needs, the function errors rather than skipping it, so a source without them passes
  `NULL`. Measured: with the defaults, the bcfishobs path reproduces this baseline
  exactly (120 of 120 summary rows, 5 WSGs).
- **The segment:** the one *starting* within 1 m of the point, because the pipeline
  breaks at observations; otherwise the containing one. Every join is on the full
  `(id_segment, watershed_group_code)` key.
- **Accessible:** `streams_access.access_<sp> IN (1, 2)`, the definition `accessible_km`
  uses. The habitat flags are gated by `streams_habitat.accessible`, which differs
  slightly, so spawning capture is not strictly a subset of accessible capture. #284
  used the latter.
- **Size model per group (#299):** each WSG is re-tested on the model the bundle's
  `parameters_habitat_method.csv` gives it, resolved by classify's own rule (fresh's
  `.frs_habitat_models()`). A `mad` group's predicates test `mad_m3s`, joined from
  `fwa_stream_networks_discharge` on `linear_feature_id` (the persist does not carry
  it), and its size relaxation moves discharge, not width. The reason labels are
  unchanged: `fails_width` / `width_null` mean "the group's size dimension", and the
  `model` and `mad_m3s` columns split them. `no_mad_threshold` is a `mad` miss the
  species' missing MAD range alone explains (BT, GR, KO, RB have none: fresh writes
  `FALSE` for the size test, which no relaxation reaches); one that needs the gradient
  relaxed too reads `fails_gradient_and_width`. MAD maxima bind (CH 100, CO 40, ST 60,
  WCT 40 m³/s rearing), so on `mad` a big-river miss also reads `fails_width`; read
  `mad_m3s` to tell it from a small one. The validator uses the method table of the
  `cfg` it is given: a schema built under another table, or with
  `lnk_pipeline_classify(method_csv =)`, is not detected.
- **Buffer:** `buffer_m` credits habitat that starts within that distance *upstream* on
  the same stream, because points often mark the downstream end of a site. The UHC flags
  test the same window. The driver reports 0 and 100 m.
- **Absences:** from the private `knowledge` repo's FISS snapshots (COTR, LNTH, PINE, UNTH
  and UPCE), snapped within 100 m and kept only inside those WSGs. A site is an absence
  of a species when it caught no fish, or when it listed species and none of them could
  be that species. A site that caught fish but listed none is left out: that is most
  empty lists, and counting them was 63 % of BT absences in the first draft. A WSG ×
  species with no absence rows reports `NA`, not 0.

## Reading it: what the score is not

1. **Accessible capture is partly circular.** Observations lift barriers
   (`observation_threshold` BT 1, CH 5) and are break points. It reads 96–99 % and says
   little.
2. **CH spawning capture is almost entirely the overlay.** With
   `apply_habitat_overlay` on, `default` forces `user_habitat_classification` reaches to
   habitat. **237 of the 245** spawn-staged CH locations in the shared WSGs sit in a
   confirmed spawning reach. Outside those reaches there are **8** locations, and 4 are
   captured under either bundle. Spawn-staged CH capture cannot score a CH spawning
   threshold. The `*_outside_uhc` shares are the part the observations did not decide.
3. **Thresholds set from these observations score in-sample.** BT `rear_gradient_max`
   0.1349 in `default_tuned` is the snapped P95 of these same BT+DV locations, so part of
   its capture gain is guaranteed. Score it on held-out records by passing a different
   `observations` table to the function (by project, by date, or by WSG).
4. **The two schemas differ in build vintage as well as config.** 4 of the 55
   `fresh_default` WSGs and 39 of the 59 `fresh` WSGs have run-log rows. The rest predate
   the log, so the diff below is not a pure config effect.
5. **Known biases:** sampling clusters near road access. And fish are only observed
   where they have access, so observed gradients are cut off at the access limit.

## Baseline: `default` vs `bcfishpass`, 51 shared WSGs, buffer 0

`totals_shared.csv`. Shares are % of observation locations (n_obs).

| species | stage | n | bundle | spawning | stream rearing | any rearing | spawning outside UHC | spawning km | rearing km |
|---|---|---|---|---|---|---|---|---|---|
| CH | any | 1,734 | bcfishpass | 82.1 | 86.6 | 86.6 | 76.7 | 15,640 | 21,570 |
| CH | any | 1,734 | default | 85.2 | 87.7 | 88.8 | 76.9 | 15,959 | 27,602 |
| CH | spawn | 245 | bcfishpass | 84.5 | 86.5 | 86.5 | 50.0 (n 8) | | |
| CH | spawn | 245 | default | 98.4 | 88.2 | 91.4 | 50.0 (n 8) | | |
| CH | rear | 510 | bcfishpass | 76.5 | 84.1 | 84.1 | | | |
| CH | rear | 510 | default | 77.5 | 84.7 | 84.7 | | | |
| BT | any | 3,771 | bcfishpass | 66.3 | 83.6 | 83.6 | 66.3 | 46,512 | 76,872 |
| BT | any | 3,771 | default | 66.9 | 82.3 | 84.1 | 66.9 | 47,099 | 75,280 |
| BT | rear | 622 | bcfishpass | 40.7 | 64.5 | 64.5 | | | |
| BT | rear | 622 | default | 42.6 | 65.6 | 66.1 | | | |
| BT | spawn | 64 | bcfishpass | 43.8 | 71.9 | 71.9 | | | |
| BT | spawn | 64 | default | 43.8 | 70.3 | 73.4 | | | |

BT has no `user_habitat_classification` rows, so its outside-UHC share is its share.

- **BT:** `default` captures slightly more rear-staged locations (66.1 vs 64.5 % on any
  rearing) with 1,592 km *less* rearing. That is the edge-type rule (bcfishpass's BT
  `rear: []` tests any edge), not the thresholds, which are the same in both bundles.
- **CH:** `default` models 6,032 km (28 %) more rearing for 1.1 points more stream
  rearing capture on the any stage (2.2 with lake and wetland rearing). That is the cost
  column doing its job.
- **Buffer 100 m** adds 0.4–2.8 points of spawning capture and 0–1.6 of rearing capture
  across rows. The "downstream end of the site" bias is real but small.

**Absences** (only 3 of the 51 shared WSGs are FISS snapshots: COTR, PINE, UPCE). CH:
68 sites, 11 (16 %) on modelled spawning, 12–15 on rearing. BT: 858 sites, 587 (68 %) on
modelled spawning, 678–686 on rearing. Most FISS sampling is juvenile electrofishing,
which says little about BT spawning. Not decision-grade.

**Misses** (`misses.csv`, `default` over its 55 WSGs, any stage): BT 268 `fails_gradient`, 130
`width_null`, 103 `fails_width`, 83 `fails_gradient_and_width`, 63 `post_predicate`
(clustering or gating), 26 `not_accessible`. CH 51 `fails_gradient`, 47 `width_null`,
27 `not_accessible`. For BT the gradient maximum is the binding threshold, which is
what #284 moved. NULL width is the second: 130 locations, which is consistent with
#284's finding that 49 % of accessible BT stream length has no width.
`misses_binned.csv` carries the gradient × width bins for each.

## Reconciliation with #284

At buffer 0 on its own 55 WSGs, `fresh_default` retains **4,275** BT+DV and **1,745** CH
locations, exactly #284's pooled counts under the Hazelton split. The filters are the same
code path.

**Under the #290 tracker.** The driver takes DV→BT pooling from `default`'s
`species_pooling.csv`, resolved once and applied to both bundles.
- **The region rule alone** reproduced the pre-#290 CSVs byte for byte, because every WSG
  in both schemas is in a pooled region.
- **The Hazelton split then moved BT.** 852 DV records in LSKE, KLUM, LKEL and ZYMO no
  longer count, so the shared BT set falls from 4,600 to 3,771 locations, and the
  rear-staged set from 1,047 to 622. The BT rows above are the re-run (knowledge @
  508bf44, same database); the CH rows are unchanged, byte for byte.
- [`species_pooling.md`](species_pooling.md) has the scenarios.

## How #284 step 5 used it

Step 5 did not diff two independently built schemas: two full runs differ by a segment
(the PSCIS tie), which would break a segment-level comparison. Instead:
- `data-raw/habitat_variants_build.R` prepares each WSG once under `default` and
  re-classifies it per threshold variant, into `score284_<variant>`.
- `data-raw/habitat_variants_score.R` runs this validator on every variant schema.
- It then scores each threshold step with `lnk_habitat_validate_band()`: locations per
  km on the segments the step moves, against the core every step agrees on.

Held-out WSGs, not held-out records, answered point 3: none of the eight decide-WSGs
were among the 55 the percentile came from. The results are in
[`habitat_thresholds.md`](habitat_thresholds.md), "Step 5"; the evidence is in
`data-raw/logs/habitat_score_284/`.
