# #394: test existence instead of building natural-barrier arrays, and walk each barrier set once (folds in #409)

## Outcome

link pins fresh v0.47.0, which brings fresh's walk prefilter (fresh#272, #409) and an existence mode for `frs_network_features()` (fresh#281). `lnk_pipeline_access()` now asks each walk only for what it reads. The per-species views and `pscis` take `result = "exists"`. `anthropogenic` + `dams`, `remediations` (with a crossings table) and the observation walk keep their arrays. Species views whose admissible rows are identical share one walk, keyed by `.lnk_walk_keys()`: an md5 over the record text of the rows `fwa_downstream()` could admit from the group. `lnk_preflight_fresh()` asserts `frs_network_features(result)`. What was learned:

- The prefilter is most of the gain wherever the cost was the probe.
- Existence walks help only modestly: fresh's `"exists"` is a `DISTINCT` over the same join, so the pairs are still enumerated.
- Repeated identical walks were more than half of what was left.

Verdict revised in [`research/recompute_cost.md`](../../../research/recompute_cost.md); mechanics in RUNBOOK §3, "How the walks run", and §8d.

## Measurement

Access step on m1's `fresh_default` (2026-10-23 build), mean of two runs (four for `exists`), seconds:

| group | fresh 0.44.0 | prefilter | existence walks | one walk per set |
|---|---|---|---|---|
| SALR | 26.9 | 3.9 | 4.0 | 4.0 |
| CHWK | 535.0 | 21.5 | 19.6 | 9.3 |
| LFRA | 1,145.7 | 89.5 | 74.5 | 35.3 |
| SETN | 763.6 | 347.3 | 292.0 | 136.5 |

- **Every output digest equals the fresh 0.44.0 baseline's.** Scratch models of ADMS and ELKR, built at each of the four steps, digest identical in every persisted table (80 rows).
- **The lever-2 gate set at plan approval was 10 %.** Repeated walks were 57 % of walk seconds over the four groups (58 % in CHWK, LFRA and SETN; 0 in SALR), so it was built.
- **The plan review's per-group keep criterion misses in SALR by 0.06 s.** SALR has nothing to share and the key query costs 0.16 s there. The miss is inside its four-run spread (3.84 to 4.15 s), so the lever was kept.
- **fresh's prefilter adds a fixed cost to every walk.** SETN's `pscis` walk went from 0.2 to 3.3 s; the species walks gave back 481 s.

Wrong turns:

- **The first measure.R collided with a live recompute on `fresh_default`.** It reused `lnk_access()`'s scoped-table name. The plan review caught it; measure.R now takes its own names, and the SALR rows taken before that are kept as `*_round0.tsv`.
- **The first live key test held no NULL.** It could not tell `concat_ws()` from record text, so a NULL fixture row was added.
- **Code-check's three rounds found three more code weaknesses, none in shipped output:** an empty wscode errored in the key query, the blue-line arm was untested, and a keyed view also given as a source was walked twice. They also found doc figures computed on a different population than the one they described.

## Evidence

`data-raw/logs/recompute_access_394/` (its README indexes the scripts and TSVs).

## Owed

- Re-prep the worker and cloud hosts for fresh v0.47.0 before the next provincial run. (No separate step: cloud hosts install it at prep from the `Remotes:` pin, and a persistent worker gets it from launching the run with `--auto-install`, which the pre-flight demands.)
- The provincial recompute minutes at this release (#377's runs row).
- The pre-run gate (#372) must pass again before the next provincial run: `R/lnk_pipeline_access.R` and fresh's `R/frs_network_features.R` both changed since its record.
- Possible follow-up: `lnk_access()`'s `zz_lnk_streams_<aoi>` duplicates fresh's per-walk temp table since 0.45.0, and its name collides with a live recompute of the same group.

Closed by: PR (this branch, `394-recompute-test-existence-instead-of-buil`)
