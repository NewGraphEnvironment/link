# Habitat validation against fish observations

**Verified:** 2026-09-26 · **Issues:** #283 (this), #284 (step 5 scores with it), #203 (full-key joins), fresh#218 · **Produced by:** `lnk_habitat_validate()` via `data-raw/habitat_validate.R` → `data-raw/logs/habitat_validate_283/` (link @ `0c19e0a`) · **Status:** baseline only; `default_tuned` not yet scored

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
  must be present in the WSG per `wsg_species_presence`. DV records count as BT where BT
  is present (the #284 pooling). Match types are A/B only (stream, within 100 m). One
  location per species × `blue_line_key` × metre, which is staged if any record there is.
- **The segment:** the one *starting* within 1 m of the point, because the pipeline
  breaks at observations; otherwise the containing one. Every join is on the full
  `(id_segment, watershed_group_code)` key.
- **Accessible:** `streams_access.access_<sp> IN (1, 2)`, the definition `accessible_km`
  uses. The habitat flags are gated by `streams_habitat.accessible`, which differs
  slightly, so spawning capture is not strictly a subset of accessible capture. #284
  used the latter.
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
| BT | any | 4,600 | bcfishpass | 64.5 | 81.7 | 81.7 | 64.5 | 46,512 | 76,872 |
| BT | any | 4,600 | default | 65.4 | 81.1 | 82.8 | 65.4 | 47,099 | 75,280 |
| BT | rear | 1,047 | bcfishpass | 41.8 | 63.6 | 63.6 | | | |
| BT | rear | 1,047 | default | 44.3 | 65.9 | 66.5 | | | |
| BT | spawn | 81 | bcfishpass | 45.7 | 70.4 | 70.4 | | | |
| BT | spawn | 81 | default | 45.7 | 70.4 | 72.8 | | | |

BT has no `user_habitat_classification` rows, so its outside-UHC share is its share.

- **BT:** `default` captures slightly more rear-staged locations (66.5 vs 63.6 % on any
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

**Misses** (`misses.csv`, `default` over its 55 WSGs, any stage): BT 344 `fails_gradient`, 160
`width_null`, 126 `fails_width`, 100 `fails_gradient_and_width`, 89 `post_predicate`
(clustering or gating), 42 `not_accessible`. CH 51 `fails_gradient`, 47 `width_null`,
27 `not_accessible`. For BT the gradient maximum is the binding threshold, which is
what #284 moved. NULL width is the second: 160 locations, which is consistent with
#284's finding that 49 % of accessible BT stream length has no width.
`misses_binned.csv` carries the gradient × width bins for each.

## Reconciliation with #284

At buffer 0 on its own 55 WSGs, `fresh_default` retains **5,104** BT+DV and **1,745** CH
locations, exactly #284's pooled counts. The filters are the same code path.

## Using it for #284 step 5

Model `default_tuned` into its own schema (`fresh_default_tuned`), stating the run
decisions at launch. Then run:

    Rscript data-raw/habitat_validate.R \
      --bundles=default:fresh_default,default_tuned:fresh_default_tuned --wsgs=...

- Read `share_rearing_any` against `rearing_km` for BT on the rear stage.
- Read `share_*_outside_uhc` for CH.
- Hold out records for the in-sample BT value (point 3 above).

`diff.csv` gives the per-WSG deltas. It is per WSG × species × stage, so step 5's
question 2 (how much newly admitted BT rearing sits above spawning) still needs a
segment-level diff.
