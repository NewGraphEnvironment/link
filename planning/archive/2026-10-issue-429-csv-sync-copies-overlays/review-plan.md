# Plan review — #429 (Plan agent, 2026-10-31, spawned 19:10Z)

Findings as returned, each with what was done.

| # | Finding | Disposition |
|---|---|---|
| B1 | Overlay appends `ko` after `notes`; column order reaches readers (`.lnk_wsg_species_present()` order → the observations `VALUES` list in `.lnk_pipeline_prep_obs_province()`). | Fixed: an added column is inserted before the first non-key base column that sorts after it (radix), else at the end. `ko` lands before `pk`, as before; acceptance is plain `identical()` again. |
| B2 | `R/lnk_overlay.R` is on the modelling path; mapping it `none` fails `test-pretest.R`. | Mapped `any`, like `lnk_load_overrides.R`. Sync-only helpers stay `none`. |
| B3 | Static guard vs the dead `user_modelled_crossing_fixes_20240825.csv` (no entry, not in the dump). | Deleted from `bcfishpass` and `default` (no reader, not in `files:`, not hashed; git keeps it). Guard limited to `bcfishpass` and `default`. Plan correction: the plan said "report unchanged". |
| O1 | Provenance update must land with the copy change. | Done in Phase 1's commit. |
| O2 | Pulling the presence cells breaks resolution until `acc-bcfp-4` exists. | Phases 4 and 5 land as one commit. |
| O3 | Phase 1's hand-made copy must match the dump but for two cells. | Phase 4 adds a cell-level diff of the loaded table before/after the sync: exactly UTRE/ch and QUES/st. |
| G1 | The sync must load the bundle by path, not name (CI installs link first). | Sync loads `inst/extdata/configs/<bundle>`. |
| G2 | A hand-set `token_input` flag can go stale. | Replaced: the sync computes `lnk_vocabulary_resolve()` specs on the bundle path before and after writing; any axis change is `review`, and the new spec goes in the PR body. No `token_input` key. |
| G3 | An overlay row whose key upstream drops makes the bundle fail to load. | The sync loads each written bundle; a load failure is `review` with the error in the body. |
| G4 | Overlay CSV unmapped in `pretest_inputs.csv`; gate must re-run before the next provincial run. | Added to the presence row's pattern; re-run added to owed. |
| G5 | Only `audit_configs.R` needed the loader. | Done that way (Phase 1); `wsg_species_presence_check.R`'s printed path also names the overlay. |
| G6 | Test path bug. | Fixed before commit. |
| G7 | PR summary says both bundles updated identically; workflow needs a `review` branch; precedence. | Summary rewritten per bundle; `shape` outranks `review` outranks `byte`; both non-byte kinds open a labelled PR and exit non-zero. |
| A1 | `config_hash` moves for bcfishpass, default, default_tuned. | Accepted; stated in NEWS and the report (earlier builds read as another bundle until re-modelled). |
| A2 | A child re-declaring a `files:` entry drops the parent's overlay. | Documented in the RUNBOOK section. |
| A3 | Muffling only the final-line warning keeps parsing unchanged. | Confirmed. |
