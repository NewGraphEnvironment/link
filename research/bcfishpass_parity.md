# Parity with bcfishpass

**Verified:** 2026-11-02 · **Issues:** #440 (this record), #361, #362, #326, #364, #367, #349, #277, #279 · **Produced by:**
`data-raw/parity_crosssection.R`, `data-raw/logs/parity_0.78.0/moves.R`, log prefix
`data-raw/logs/parity_0.78.0/` · **Run:** `20261102_083253-52f261f8`, link 0.78.0 (`34c4c598`), fresh 0.52.0

How closely link's `bcfishpass` config reproduces bcfishpass's own output, in km of accessible,
spawning and rearing stream per group and species. This file is the current record: a parity run
revises it in place, and the dated files listed at the end are its history.

## Where parity stands

**48 of 50 pairs within tolerance** on ADMS, BULK, BABL and ELKR (accessible within 1 %,
spawning and rearing within 5 %). The two pairs over are BULK SK spawning (+10.99 %) and rearing
(+7.39 %), parked under #130 (SK upstream spawning over-credits multi-lake drainages; carried on from
fresh#190). Accessible km sits within 0.11 % on all 17 pairs.

Each cell is link km / bcfishpass km, link's difference, and in brackets the change in link's
km since the v0.68.0 build of 2026-10-23 where it is 0.1 km or more. Rearing leaves lake connection lines out on both sides.

| Group | Species | Accessible | Spawning | Rearing |
|---|---|---|---|---|
| ADMS | BT | 1230.3 / 1230.3, -0.01 % (-0.1) | 362.5 / 361.7, +0.22 % (-4.5) | 608.3 / 608.3, +0.00 % (-0.7) |
| ADMS | CO | 787.6 / 787.9, -0.03 % (-0.8) | 311.8 / 311.0, +0.26 % (-0.5) | 351.8 / 351.2, +0.18 % (-0.5) |
| ADMS | CH | 787.6 / 787.9, -0.03 % (-0.8) | 277.6 / 277.6, +0.00 % (-0.5) | 308.9 / 308.2, +0.21 % (-0.5) |
| ADMS | SK | 787.6 / 787.9, -0.03 % (-0.8) | 86.6 / 85.7, +1.09 % | 70.8 / 70.8, +0.00 % |
| BULK | BT | 7676.3 / 7676.4, +0.00 % (-0.2) | 1865.2 / 1848.0, +0.94 % (-1.1) | 3029.3 / 3048.6, -0.63 % (+21.4) |
| BULK | ST | 6462.7 / 6462.7, +0.00 % (-0.2) | 1287.6 / 1279.9, +0.60 % | 2242.6 / 2241.9, +0.03 % (+11.9) |
| BULK | CO | 5088.0 / 5088.0, +0.00 % (-1.6) | 1782.1 / 1768.3, +0.78 % | 2226.1 / 2217.6, +0.38 % (+11.8) |
| BULK | CH | 5088.0 / 5088.0, +0.00 % (-1.6) | 1260.2 / 1252.0, +0.66 % | 1742.1 / 1738.2, +0.22 % (+12.0) |
| BULK | PK | 5088.0 / 5088.0, +0.00 % (-1.6) | 1854.4 / 1850.0, +0.24 % | — |
| BULK | SK | 5088.0 / 5088.0, +0.00 % (-1.6) | 27.1 / 24.4, +10.99 % | 26.7 / 24.9, +7.39 % |
| BABL | BT | 6855.3 / 6855.4, +0.00 % (-0.2) | 896.5 / 890.1, +0.71 % (-2.6) | 2099.9 / 2107.3, -0.35 % (+23.3) |
| BABL | ST | 5955.4 / 5955.6, +0.00 % (-0.2) | 352.1 / 349.3, +0.82 % (-0.5) | 916.0 / 916.6, -0.06 % (+18.2) |
| BABL | CO | 5062.7 / 5063.6, -0.02 % (-1.1) | 811.1 / 805.1, +0.75 % (+0.2) | 1284.8 / 1287.0, -0.17 % (+4.6) |
| BABL | CH | 5062.7 / 5063.6, -0.02 % (-1.1) | 351.7 / 348.8, +0.82 % (-0.4) | 700.2 / 713.0, -1.79 % (+4.7) |
| BABL | SK | 5062.7 / 5063.6, -0.02 % (-1.1) | 57.2 / 56.3, +1.65 % | 299.9 / 299.9, +0.00 % |
| ELKR | BT | 4206.0 / 4207.2, -0.03 % (-2.1) | 1518.4 / 1497.5, +1.40 % (-8.2) | 2103.8 / 2104.1, -0.01 % (-1.4) |
| ELKR | WCT | 3681.3 / 3685.2, -0.11 % (-2.1) | 1558.9 / 1517.6, +2.72 % (-9.1) | 1885.4 / 1854.6, +1.66 % (-15.5) |

Pink has no freshwater rearing. Five pairs bcfishpass reports and the `bcfishpass` config does not
model in that group are left out: CM and PK accessible in ADMS and BABL, CM in BULK.

**The build.** The drainage closure of the four groups is 17 groups, all modelled under
`bcfishpass` on m1 into a scratch schema (`fresh_parity441`), from a worktree at `34c4c598`,
recomputed and verified by `study_area_verify.sql` (PASS). The primitives are the 2026-10-23 load
`fresh_parity361` was built on, and the reference did not move on any of the 50 pairs. The full
stamp is in `data-raw/logs/parity_0.78.0/README.md`.

## What moved at v0.78.0 (2026-11-02, #440)

The v0.68.0 score (run `20261023_215312-16fb3aae`, `fresh_parity361`) was 48/50; so is this one. Inputs
were held equal (the same primitive load; the reference moved on 0 of 50 pairs; no barrier override added
or lost), so every move is code. 40 of the 50 pairs moved by 0.1 km or more, all 17 accessible pairs among them (`pair_moves.csv`):

- **Rearing rose toward the reference in BULK and BABL** for BT, CH, CO and ST, by 4.6 to 23.3 km a pair.
  This is the direction #326's order-1 rearing exception (`rear_stream_order_bypass`, BT, CH, CO, ST and
  WCT in this bundle) moves rearing, and the only change in the range that adds rearing here. BULK CO crossed the reference (−0.14 % to +0.38 %).
- **Spawning fell toward the reference** in ADMS BT (−4.5 km), ELKR BT (−8.2) and ELKR WCT (−9.1), and
  ELKR WCT rearing fell 15.5 km, also toward it. #326 changed where streams break, so a segment's
  gradient and width tests moved.
- **Accessible km fell 0.1 to 2.1 km a pair,** every pair still within 0.11 % of the reference.
- **Seven pairs moved away from the reference,** by 0.06 percentage points or less, apart from BULK CO
  rearing above.

These are not decomposed segment by segment: under #326 the two builds share few segments (195,329
segments in one build only, on 17,527 lines of the four groups), so `segment_diff.csv` covers little.
`expected.txt`, written before scoring, bounded accessible moves at 0.1 km and spawning moves at 0.5 km; both
bounds were wrong, because the #326 measurement it leaned on was taken on other groups. The pass count and
the rearing direction held.

**`default` at the same code** (#440): KETL, KOTL, BULK and MURT built under `default` match their fresh 0.52.0 builds exactly, and against the last provincial build move only by the known changes since 0.68.0 (`data-raw/logs/test_builds_440/README.md`).

## What moved at v0.68.0 (2026-10-23, #361)

The v0.66.6 score (run `20261020_171738-477072be`, `fresh_parity362`) was 48/50; so is this one. Inputs were
not held equal: the provincial run of 2026-10-23 refreshed the primitives and reloaded the reference views, so
`pair_moves.csv` carries the reference's change beside link's. Three pairs moved, all CO rearing and all
link-side: ADMS −0.3 km (predicted −0.22), BULK −1.3 (predicted −1.45; the reference also moved +0.3) and
BABL −1.4 (predicted under 0.1: a miss). All three are #364's CO gradient test on through-wetland lines under
the `bcfishpass` bundle: the shared segments whose CO rearing changed are 52 FWA edge 1050 lines (2.1 km) and 5
main-stem lines (1.2 km) whose rearing cluster lost its connection with them. #364 measured ADMS and BULK only;
the BABL prediction was an extrapolation. The #367 PSCIS pick moved no pair by 0.1 km, and no barrier override
was added or lost. Evidence: `data-raw/logs/parity_0.68.0/` (its README tabulates the three moves).

## What moved at v0.66.6 (2026-10-20, #362), and why

The 2026-10-17 score (run `20261017_093603-31ab6242`, link `a17e9177`, `fresh_parity246`) was
48/50 on the same pairs against the same reference, over the same primitive load. Between the two,
#349 shipped: the habitat flags are settled on `streams_access` (the gate) and barrier lifts count
observations over every group.

- **Accessible: no change** on any pair. Province-wide counting can only add lifts. It added
  10 override positions in the closure and removed none: BT and WCT at five positions on the
  Columbia (blue_line_key 356570372), held by LARL. None reaches a scored pair.
- **The gate: as predicted.** BT rearing −0.269 km in BULK, −0.325 in BABL and −0.633 in ELKR,
  the 0.3 / 0.3 / 0.6 km `access_columns.md` predicted from the 2026-10-17 build. It also
  removes 0.002–0.043 km of spawning or rearing from ten other pairs. The prediction's
  "0 km of spawning" was these, read at 0.1 km. Each is a segment whose access did not change and
  is 0, with its habitat now cleared, and on the segments both builds share these are the only
  changes (`segment_diff.csv`).
- **ADMS CH +0.088 km spawning, +0.167 km rearing: not #349.** In the four scored groups, two
  builds over the same inputs break 8 lines in ADMS, BULK and ELKR at different places
  (39 segments in one build only, `resegmented.csv`). On each of the 8, a PSCIS crossing has two
  modelled crossings on one `linear_feature_id` to match to, and the two builds match it to
  different ones. That is the PSCIS-to-modelled pick in `R/lnk_pipeline_pscis_build.R`, whose
  last tiebreak, `linear_feature_id`, cannot separate two candidates on one feature. On
  blue_line_key 356333200 the break sits at 1,349 m (modelled crossing 100122), not 1,446 m
  (101854), and cuts an 88 m piece at gradient 0.0441, under CH's spawning maximum, where the
  old 167.5 m piece was at 0.0483. That piece spawns, and the 167.5 m from 1,269 m to 1,437 m now
  rears; that line had no CH rearing before. Over the 8 lines, CH gains exactly that, and BT
  spawning, CO spawning and CO rearing each lose 0.006 km (`resegmented_habitat.csv`). This is
  the run-to-run reproducibility defect #277, which now carries this measurement.
- **Annotation classes:** unchanged on all 50 pairs.

Evidence: `pair_moves.csv` (every pair, before and after), `segment_diff.csv` (changed
segments both builds share, by cause), `resegmented.csv` and `resegmented_habitat.csv`,
`override_diff.csv`, all in `data-raw/logs/parity_0.66.6/`.
The expected result was written down before scoring (`expected.txt`).

**mapping_code agreement** over all 17 groups (the run's compare) moved on 51 of 86 group ×
species rows, by −0.06 to +0.05 points. Two things move it at once: the gate, and lines the two
builds break in different places, which across the whole closure is 349 segments on 75 lines in
12 of the 17 groups (`resegmented_closure.csv`), and which also changes the downstream-barrier
flags of segments on other lines, with their access and habitat unchanged (in KOTL, HARR and
LSKE). The tie above is confirmed on the 8 lines in the
scored groups; the other 67 are not examined. 91a968ab does not reach it: it changes only a
species with no barrier in a group, and every one of the 86 rows has barriers. It is not diagnosed (`mapping_code_moves.csv`).

## What is not yet explained

Against `bcfp_divergence_taxonomy.yml` at its 2 % tolerance, five pairs are UNEXPLAINED and one is
class C (BULK SK spawning, `sk-lake-clustering-divergence`):

| Pair | link vs bcfishpass |
|---|---|
| BULK SK rearing | +7.39 % |
| BABL ST rearing | −2.05 % |
| BABL CH rearing | −2.44 % |
| ELKR WCT spawning | +3.33 % |
| ELKR WCT rearing | +2.50 % |

The same five as on 2026-10-17. Where streams break is the first suspect for the 2–3 % rows
(`bcfp_segmentation_parity.md`, #324), not measured on these pairs.

## What these four groups cannot show

Province-wide lift counting changes access only behind a barrier held in another group. None of
the four scored groups has one. The candidate that would show it under the `bcfishpass` config,
TURN BT behind a UKEC falls (69 BT records upstream, none in UKEC), cannot be scored: bcfishpass
models neither TURN nor UKEC (no `bcfishpass.streams` rows in run 143, and none in the local
reference). In #349's list of groups blocked whole by such a barrier, TURN BT is the only row for
a species the `bcfishpass` config models; the list was built under `default`, so this is not a
search of the `bcfishpass` config (`data-raw/logs/parity_0.66.6/turn_bt.txt`).

## Re-scoring

Rebuild the closure into a scratch schema, verify, score, compare:

```bash
bash data-raw/study_area_run.sh --focal=ADMS,BULK,BABL,ELKR --config=bcfishpass \
  --schema=<scratch> --run-label=<label> --recompute-jobs=8
psql ... -v schema=<scratch> -v run_uid=<uid> -v expected_n=17 -f data-raw/study_area_verify.sql
LNK_LOAD=loadall LNK_SCHEMA=<scratch> LNK_CONFIG=bcfishpass LNK_PARITY_OUT=<dir>/parity_annotated.csv \
  Rscript data-raw/parity_crosssection.R ADMS BULK BABL ELKR
```

Keep the reference fixed across the two runs being compared (do not pass `--refresh-primitives`),
or a move cannot be put down to code. `moves.R` compares two builds of the closure, so the previous build's schema is kept until the next re-score (today `fresh_parity441`, and `fresh_parity361` before it). Then revise
this file: the table, what moved, the run line under the heading.

## History

Earlier results, kept as written and cited by path elsewhere:

| File | What it scored |
|---|---|
| `data-raw/logs/parity_0.78.0/` | 2026-11-02, link `34c4c598` (0.78.0), the four groups: 48/50 (the table above) |
| `data-raw/logs/parity_0.68.0/` | 2026-10-23, link `1d00c04c` (0.68.0), the four groups: 48/50 |
| `data-raw/logs/parity_0.66.6/` | 2026-10-20, link `6e5cc837` (0.66.6), the four groups: 48/50 |
| `data-raw/logs/provincial_246/` | 2026-10-17, link `a17e9177`, the four groups: 48/50 (the baseline above) |
| [`parity_accessible_habitat_2026_07_03.md`](parity_accessible_habitat_2026_07_03.md) | 2026-07-03, accessible + spawning + rearing on 11 groups after #221 / #223 |
| [`provincial_parity_2026_05_25.md`](provincial_parity_2026_05_25.md) | 2026-05-25, per-segment mapping_code on 50 study-area groups |
| [`provincial_parity_2026_05_12.md`](provincial_parity_2026_05_12.md) | 2026-05-12, link 0.36.0, province-wide rollup + mapping_code |
| [`provincial_parity_2026_05_11.md`](provincial_parity_2026_05_11.md) | 2026-05-11, link 0.35.0, province-wide rollup |
| [`provincial_parity_2026_05_01.md`](provincial_parity_2026_05_01.md) | 2026-05-01, link 0.20.0, the first province-wide baseline |
