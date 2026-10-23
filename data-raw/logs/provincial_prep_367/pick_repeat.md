# The PSCIS pick built repeatedly (link#367, 2026-10-22)

`.lnk_pipeline_pscis_build()` for ADMS into scratch schemas on the local fwapg (primitives loaded 2026-10-17). Step 2 builds the candidate table province-wide whatever the AOI, so the pick covers every PSCIS crossing that matches a stream: 17,377. Main (`67a410e2`, frozen worktree) and the branch, each built twice, minutes apart.

| comparison | PSCIS picking a different modelled crossing | different stream / measure |
|---|---|---|
| main vs main | 464 | 0 |
| branch vs branch | 0 | 0 |
| main vs branch | 656 | 56 |

After the branch's Step 3b no PSCIS has a top-ranked tie whose rows differ in any column the pick passes on. Rows sharing `(stream_crossing_id, linear_feature_id, modelled_crossing_id)` (15,019 rows, 14,995 keys) are exact copies from the `fwa_rivers_poly` join.

Barrier positions with more than one row, across all 241 groups of `fresh_default` (run `20261017_004619-3f4c713b`): only FALLS, at 3 positions, 2 of them identical rows and 1 (USIK, blue_line_key 359512912 at 431.04 m) two rows on different `linear_feature_id`s, which is why falls ids end on `linear_feature_id`.
