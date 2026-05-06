## Outcome

Reproduced bcfishpass's three classification surfaces in link as additive layers: `crossings.barrier_status` (Phase 1, already populated by `lnk_pipeline_load`), `streams_access` (Phase 2, new `lnk_pipeline_access`), `streams_mapping_code` (Phase 3, new `lnk_pipeline_mapping_code`). ADMS validation: 15762/15762 byte-identical for all 8 species on `streams_mapping_code`; ≥99.9% on `streams_access`. Side deliverables: fresh#204 (per-side wscode/localcode args + R list-column return, v0.29.0), `scripts/update_hosts.sh` (pak-bug bypass), trifecta `--rds-dir=` pass-through, sibling QGIS view `streams_<sp>_bcfp_vw`. Caveat: BT/WCT mapping_code uses bcfp's pre-computed `dam_dnstr_ind` / `remediated_dnstr_ind` merged in — sequence-aware computation from primitives is the open follow-up.

Closed by: PR #134, squash `8adbade`, tag v0.30.0. Follow-up: #135 (sequence-aware dam_dnstr_ind).
