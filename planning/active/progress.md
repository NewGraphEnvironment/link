# Progress — tunnel-free `lnk_compare_mapping_code` + orchestrator (#175)

## Session 2026-05-24

- #200 (v0.40.4) merged via PR #202; cyphers proven (3-way spin/burn) + tunnel-free reference verified (`v0.7.15-14-ge12c1a5`).
- Edited #175 + #167 in-body (no new issues): #175 now scopes tunnel-free `lnk_compare_mapping_code` + orchestrator (M1-dispatch + post-consolidate recompute); #167 superseded by tunnel-free.
- Plan-mode exploration; phases approved by user.
- Archived #200 PWF; created branch `175-promote-with-mapping-code-flag-to-stand` off main; scaffolded #175 PWF baseline.
- Phase 1 done: `lnk_compare_mapping_code()` tunnel-free + `.lnk_compare_wsg_mapping_code_diff` delegates + `.lnk_mc_diff` shared. Live PARS BT 98.95% tunnel-free; 1216 tests pass (lone FAIL = env db_conn). Caught id_segment ~22× cartesian → fixed `lnk_compare_rollup` (full-PK joins) + WSG-active species resolution; filed #203 (position-derived globally-unique id_segment, bcfp-verified). 
- Phase 2 done: `lnk_compare_wsg(mapping_code=TRUE)` now tunnel-free (routes through `lnk_compare_mapping_code`, no conn_ref; rollup still tunnel — snapshot lacks habitat_linear). Removed dead `.lnk_compare_wsg_mapping_code_diff`; added `wsg_compare_mapping_code()` (tunnel-free orchestrator entry, verified PARS 98.95% w/ PG_PASS_SHARE unset). 93 compare / 1216 total pass.
- Next: Phase 3 — orchestrator (`wsgs_run_pipeline.sh` drop :63333 pre-flight + M1-dispatch + Step 9b post-consolidate recompute; `wsgs_run_host.R` cyphers run+persist only).

## Session 2026-05-25

- 3-WSG smoke (CRKD@M1, LCHL@cy1, ZYMO@cy2): plumbing spin→prep→run→consolidate→burn works; caught wide-table shape drift — cyphers' `streams_access`/`streams_mapping_code` had 11 species cols (CT/DV/RB) vs M1's 8 → positional COPY-consolidate failed. Cyphers burned + confirmed gone (0 tofu resources each).
- Root cause: `cypher_prep.sh` seeded `lnk_persist_init` from `parameters_fresh` (11 sp) while `lnk_pipeline_run` + dispatcher use `cfg$species` (8 sp). Warm snapshot predates wide tables (#187) — not a snapshot artifact.
- Phase 3a done (per user steer "build abstract, shouldn't matter which machine / how many species cols, don't hardcode"):
  - `schema_consolidate.R` → shape-tolerant COPY (runtime shared-column intersection, copy-by-name, dest ordinal order). No hardcoded species/cols/host.
  - `cypher_prep.sh` → persist species = `cfg$species` (mirrors `lnk_pipeline_run`).
  - Filed #204 (persist_init species-column-set drift detection + abstract/no-hardcode north star). `/code-check` clean.
- Next: Phase 3 orchestrator (M1-dispatch generalization — "shouldn't matter which machine runs"), then re-run the 3-WSG smoke to confirm consolidate of the two wide tables, then study-area parity.
