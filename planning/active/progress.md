# Progress — #196 streams_access per-source flags + cross-WSG mapping_code

## Session 2026-05-19

- PWF scaffolded retroactively (started #196 without it; scope grew to 3 bugs).
- Phase 1 (`91f3f90`): persist DDL per-source flag cols via `.lnk_cols_streams_access_source_flags()`.
- Phase 2 (`e23819a`): pre-persist barriers so views default to persist (cross-WSG dam visibility).
- Phase 3 (`475e397`): `lnk_pipeline_persist` INSERT projection now includes the source flags — THE actual NONE-token bug. Verified in isolation: persist streams_access flags populate (anth 48559, dams 48559, dam_ind 32406).
- Branch `196-streams-access-source-flags`, 3 commits ahead of main.
- Phase 4 IN FLIGHT: clean PARS `lnk_pipeline_run(mapping_code=TRUE)` (task `btkkjqxlp`) — rebuilds habitat (damaged by debug shortcut persisting from half-built working_pars_dbg) + verifies end-to-end token output.
- Next: confirm PARS BT tokens include DAM/MODELLED/ASSESSED; decide Phase 5 (wall-time double-persist); rebuild BULK; release v0.40.3.

### Environment
- docker `fresh-db` up (was down mid-session; `open -a Docker` + `docker compose up -d db` in fresh/docker/).
- bcfp tunnel `localhost:63333` flaky (dropped 3×); needs PG_PASS_SHARE. Build is tunnel-free; only parity diff needs it.
