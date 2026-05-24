# Progress — tunnel-free `lnk_compare_mapping_code` + orchestrator (#175)

## Session 2026-05-24

- #200 (v0.40.4) merged via PR #202; cyphers proven (3-way spin/burn) + tunnel-free reference verified (`v0.7.15-14-ge12c1a5`).
- Edited #175 + #167 in-body (no new issues): #175 now scopes tunnel-free `lnk_compare_mapping_code` + orchestrator (M1-dispatch + post-consolidate recompute); #167 superseded by tunnel-free.
- Plan-mode exploration; phases approved by user.
- Archived #200 PWF; created branch `175-promote-with-mapping-code-flag-to-stand` off main; scaffolded #175 PWF baseline.
- Phase 1 done: `lnk_compare_mapping_code()` tunnel-free + `.lnk_compare_wsg_mapping_code_diff` delegates + `.lnk_mc_diff` shared. Live PARS BT 98.95% tunnel-free; 1216 tests pass (lone FAIL = env db_conn). Caught id_segment ~22× cartesian → fixed `lnk_compare_rollup` (full-PK joins) + WSG-active species resolution; filed #203 (position-derived globally-unique id_segment, bcfp-verified). 
- Next: Phase 2 — route `lnk_compare_wsg(mapping_code=TRUE)` tunnel-free + `wsg_compare.R`.
