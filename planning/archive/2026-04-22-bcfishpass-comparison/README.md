# Archive: bcfishpass comparison (closed 2026-04-22)

## Outcome

All 4 watershed groups (ADMS, BULK, BABL, ELKR) within 5% of bcfishpass across all species. Key fixes landed in fresh 0.13.5–0.13.8 (SK outlet ordering, spawn_connected, three-phase cluster) and in link CSVs (ST observation_species, WCT threshold, BT cluster_rearing). Final results + DAG documented in `research/bcfishpass_comparison.md`.

## Closed via

- Issues: link#16 (end-to-end ADMS), link#31 (ST/WCT gap), fresh#147, fresh#153, fresh#154, fresh#157
- Merges: fresh PRs #151 (SK outlet), #155 (spawn_connected), #157 (bridge gradient), #159 (three-phase cluster)

## What superseded it

- New PWF cycle starts 2026-04-22 for `lnk_config` (link#37) and `_targets.R` pipeline (link#38)
- Generic non-minimal barrier removal extracted to fresh 0.14.0 (`frs_barriers_minimal`, #160)
