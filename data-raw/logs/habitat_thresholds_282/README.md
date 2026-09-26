# #282 live verification — per-bundle habitat thresholds

Local docker fwapg (:5432), 2026-09-25. Scratch working schemas `zz282_*` only:
nothing persisted to `fresh` / `fresh_default`. `verify_classify.R` runs
setup → connect for one WSG and digests `<schema>.streams_habitat` per species;
`reclassify.R` re-runs only classify + connect on an already-prepared schema,
holding segmentation fixed.

Environment: link 0.50.0 (main `796c182` via worktree; branch
`282-per-bundle-habitat-thresholds-csv-in-co`). fresh 0.33.0 (`7f12d99`) for the
ADMS main/branch/main2 runs. **fresh was reinstalled as 0.34.0 (local install, no
RemoteSha) at 23:25 local by something outside this session**, so the `adms_def`,
tuned-probe and BULK runs are on 0.34.0 — each comparison below is within one
fresh version.

## Results

| check | result |
|---|---|
| ADMS `bcfishpass`, main vs branch, full runs | `streams_habitat` digests identical for BT/CH/CO/SK |
| ADMS, main code re-classifying main's own schema | reproduces main's digests exactly (classify is deterministic) |
| ADMS, branch re-classifying main's schema | identical to main for all 4 species |
| BULK `bcfishpass`, main full run vs branch re-classify | identical for BT/CH/CO/PK/SK/ST |
| ADMS `default` vs a temp bundle `extends: default` with CH `rear_gradient_max` 0.0549 → 0.0321 | CH rearing 1,470 → 1,280; CH spawning and BT/CO/RB/SK byte-identical; reverting restores exactly |

## Found on the way (pre-existing, not this branch)

Two identical **main** runs of ADMS differ: 39,423 vs 39,422 segments, CH
spawning 1,062 vs 1,060 (`20260925_adms_main.txt` vs `20260925_adms_main2.txt`).
Cause: `lnk_pipeline_pscis_build()` picks a PSCIS crossing's modelled match by
`name_score, distance_to_stream, linear_feature_id`, which ties when two
modelled candidates sit on the same feature (PSCIS 367: 100122 at 87 m vs 101854
at 9 m; PSCIS 197392: 100891 vs 101833). The loser survives as a separate
modelled break. Full-run digests are therefore not a valid main-vs-branch test on
their own; the re-classify comparisons are.
