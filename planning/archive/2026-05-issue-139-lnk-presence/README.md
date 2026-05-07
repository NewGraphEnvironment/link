## Outcome

Shipped `lnk_presence(wsg_species_presence, aoi, groups = ...)` — structured per-AOI species-presence helper with bcfp species-group expansion (salmon = CH/CM/CO/PK/SK; ct_dv_rb = CT/DV/RB). Returns `$present` / `$absent` / `$is_present(sp)` / `$row` / `$aoi`. Coexists with `lnk_pipeline_species()`. 8 testthat blocks / 37 expectations green via mocked tibbles. Will be picked up by #135 to short-circuit absent-species in `lnk_pipeline_mapping_code` and skip `frs_network_features` queries in `lnk_pipeline_access`.

Closed by: PR #140, squash `7678653`, tag v0.30.1.
