# Findings — rearing_km means two things (#319)

## Issue context

**If done:** `rearing_km` means one thing in every link output: habitat km with lake connection lines reported apart. **If never:** two CSVs with a `rearing_km` column can differ by 55–95 % for SK, and nothing says why.

## Problem (link PR #318, branch `317-lake-km-should-1450-connection-lines-cou` @ `c3ea9d7`)

- #317 split lake connection lines out of the compare rollups. FWA connectors (edge 1450) in a lake or reservoir polygon are now `rearing_lake_connection` km, outside `rearing_km`.
- `lnk_rollup_wsg()`'s default `rearing_km` was left as the flag total, connection lines included. Code-check showed that changing it alone would break the callers that compare the flag:
  - `lnk_habitat_validate()`'s cost;
  - `data-raw/parity_crosssection.R` and `data-raw/wsg_vignette_data.R`, against `fresh.streams_vw_bcfp`.
- So `rearing_km` has two meanings, and the gap is large where lakes rear. SK loses 55–95 % on seven WSGs, KO 62 % on NATR (`data-raw/logs/lake_connection_317/`).

## Measured: where lake fish sit

bcfishobs, match types A / B, observations inside a lake or reservoir polygon (local fwapg, 2026-10-08):

| species | in a lake | on 1450 | on 1200 |
|---|---|---|---|
| BT | 146 | 94 | 44 |
| CO | 445 | 124 | 301 |
| RB | 1,357 | 710 | 624 |
| KO | 354 | 282 | 67 |
| SK | 270 | 128 | 139 |

About half of in-lake records sit on a connection line. A lake fish gets attached to whichever line is nearest, so these records are evidence for the lake, not for the line. **Capture must keep reading the `rearing` flag.**

## Plan (operator decision 2026-10-08: one meaning everywhere)

1. **`lnk_rollup_wsg()`.** The default `rearing_km` leaves connection lines out (`rearing AND NOT connection`). A default `rearing_lake_connection_km` is added, so the two sum to the flag total. Update the roxygen and the tests that pin the flag-total default.
2. **`lnk_habitat_validate()`.**
   - Capture is unchanged (flag).
   - The cost carries `rearing_km` (no connection lines) plus `rearing_lake_connection_km`.
   - Fix `R/lnk_habitat_validate.R:83-84`: "`rearing` is stream rearing" is stale since #310, which put lake lines in.
   - Document the table above as the reason capture and cost differ for lakes.
3. **Parity scripts.** `data-raw/parity_crosssection.R` and `data-raw/wsg_vignette_data.R` apply `.lnk_sql_lake_connection()` on the `streams_vw_bcfp` side too. That view carries `edge_type` and `waterbody_key`, and it is the symmetric rule #317 proved (SK 0.0 % on six bcfishpass-config WSGs). Re-run the cross-section on its default WSGs: FINA BT and the SK groups move, both sides alike.
4. **Reproducibility check.** Re-score #284 at the new HEAD and confirm `habitat_change.csv` and `verdict.csv` reproduce. The expectation is exact: #284 / #300 / #302 / #305 predate #310, when BT / CH / GR / RB lakes reared on 1000 / 1100 only, so their connection km is 0. If it is not exact, that is a finding.
5. **Downstream readers.** Check `data-raw/habitat_validate.R`, `habitat_variants_score.R` and `species_pooling_evidence.R`: they read `rearing_km` by name and need no change unless step 4 disagrees.

## Not in scope

- `lnk_aggregate()` (per-crossing upstream km). It is link-side SQL, not `fresh::frs_aggregate()` (corrected 2026-10-08: an earlier draft said it went through fresh). It sums boolean habitat columns, so it has no connection split. Separately, it counts only the crossing's own `blue_line_key` upstream of the crossing, not the tributaries. Its own issue.
- The rules: 1450 stays in the L rule for `cluster_rearing`. 1400 ("other flow / inferred connection") is construction flow, not a connector, and counts in km (operator, 2026-10-08).

Relates to #317.

## Plan-mode measurement (2026-10-08, local fwapg, `fresh` schema)

Measured now (read-only, local fwapg, `fresh` schema), connection km in BT rearing, both parity sides:

| WSG | bcfp side | link side |
|---|---|---|
| PARS | 9.77 | 9.77 |
| FINA | 393.57 | 393.57 |
| PCEA | 375.89 | 367.68 |
| LKEL | 11.47 | 11.47 |

Symmetric, so parity should hold; FINA/PCEA BT rearing km drop ~14–19 % on both sides. PARS moves
9.77 km, so the vignette's `pars_accessible.rds` changes.

## Parity after #319 (2026-10-09)

See `data-raw/logs/lake_connection_319/README.md`. PCEA BT is the one asymmetric group: link carries 367.7 km of connection lines in BT rearing, bcfishpass 375.9, so its rearing diff widens +1.10 → +1.87 %. PARS `fresh` spawning moved 0.02 km since the July vignette artifact with no code change (input drift).

## Why not a full `wsg_vignette_data.R` run

It rebuilds `pars.gpkg` (context layers over the tunnel, skipped if it is down) and `pars_parity.rds` from current `fresh` / `fresh_default` state, both moved by #310 and earlier. Only `pars_accessible.rds` reads `rearing_km`, so only it was regenerated.

## Step 4: reproducibility (2026-10-09)

- `habitat_variants_score.R` will not re-score #284 at any post-#307 HEAD: the thin variant bundles `extends: default` by name, and `default`'s thresholds changed in #307, so its guard stops. Pre-existing; CLAUDE.md already records the same for #302 ("regenerate only at v0.58.0").
- Direct check instead (`data-raw/logs/lake_connection_319/README.md`): BT/CH/GR/RB rear on no connection line in any score schema; #284 `habitat_change.csv` reproduces 36/36. SK and KO do rear on them (KO KOTL ~310 km, SK BABL 642 km), and #300/#305's KO cost rows would move on a re-score (in-sample, unscored, no verdict). The issue's "exact" expectation holds for every scored species and fails for KO — recorded, not acted on.
- `score284_bt_rear_0p*` MORR had no planner statistics; the rollup's polygon join took minutes until `ANALYZE`. Killing an R client does not cancel its backend query, which first read as general slowness.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| Re-score: "no bundle for bt_rear_0p1249 under <out>" | the script reads variant bundles from `--out`; copy the run's log dir there first |
| Re-score: "thresholds bundle for default is not the one ... built from" | bundle drift since #307; replaced by the direct check above |
| `lnk_rollup_wsg()` minutes on score284 MORR | stale stats; `ANALYZE` |

## #283 baseline moves for BT (code-check round 3, 2026-10-09)

Step 4 enumerated the score schemas only. The #283 validator baseline scored `fresh` (bcfishpass config), whose BT rear rule admits every edge, connection lines included: on its 51 shared WSGs 2,503.43 of 76,872.28 BT km are connection lines, so `rearing_km` now reads 74,368.85 against `fresh_default`'s 75,280.2 (none). #283's "default has 1,592 km less BT rearing" becomes about 911 km more; the gap was those lines. CH: 0 on both sides. Written into `research/habitat_validation.md` beside the original bullet.
