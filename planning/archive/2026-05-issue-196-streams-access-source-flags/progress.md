# Progress — #196 streams_access per-source flags + cross-WSG mapping_code

## Session 2026-05-19

- PWF scaffolded retroactively (started #196 without it; scope grew to 3 bugs).
- Phase 1 (`91f3f90`): persist DDL per-source flag cols via `.lnk_cols_streams_access_source_flags()`.
- Phase 2 (`e23819a`): pre-persist barriers so views default to persist (cross-WSG dam visibility).
- Phase 3 (`475e397`): `lnk_pipeline_persist` INSERT projection now includes the source flags — THE actual NONE-token bug. Verified in isolation: persist streams_access flags populate (anth 48559, dams 48559, dam_ind 32406).
- Branch `196-streams-access-source-flags`, 3 commits ahead of main.
- Phase 4 IN FLIGHT: clean PARS `lnk_pipeline_run(mapping_code=TRUE)` (task `btkkjqxlp`) — rebuilds habitat (damaged by debug shortcut persisting from half-built working_pars_dbg) + verifies end-to-end token output.
- Phase 4 result: streams_access flags NOW persist (dams 48561, dam_ind 32370). BUT tokens still wrong — found **Cause 4** (methodology, not bug): access_bt=0 (blocked) for ALL PARS segments because cross-WSG dams are downstream → `accessible=FALSE` → token1/2/3 collapse to SPAWN/REAR/blank. bcfp emits SPAWN;DAM regardless. See findings Cause 4. **Paused for user decision** on accessibility-gating semantics.
- 3 persist commits (91f3f90, e23819a, 475e397) are correct + shippable on their own (flags should persist). Token semantics is separate — likely new issue, possibly tied to #197 rules engine.
- Next: (a) user decides Cause-4 semantics; (b) decide Phase 5 wall-time; (c) rebuild BULK; (d) ship v0.40.3 (persist fixes) maybe independent of the token-semantics work.

## Session 2026-05-23

- Resumed via `/loop continue phase 7`. Tested the Cause-4 `_min` swap (uncommitted edit to lnk_pipeline_run barriers_per_sp).
- `_min` swap **FAILED mechanically** (PARS run `bpzeq473w`): `barriers_bt_min_id does not exist`. `_min` tables are break-specs (no surrogate id); `frs_network_features` (via lnk_pipeline_access) requires a feature id. `_unified` views are the feature-shaped tables (id_barrier + geom + blocks_species). `barriers_per_sp` mechanically requires `_unified`-shape input.
- Architectural truth: `barriers_<sp>_unified` = persist.barriers WHERE sp ∈ blocks_species. Over-blocking reduces to "is DAM in blocks_species for BT". Correct fix = per-species natural-only feature view (keeps id, drops dams) — BUT gated on confirming bcfp's real semantics.
- Tunnel down again (stale, timeout). Per user ("rerun the snapshot locally"): launched `snapshot_bcfp.sh --with-bcfp-views --force` against local docker fwapg (tunnel-free, public sources) → task `be94vol3c`. Lands this week's bcfp into `fresh.streams_bcfp` for the row-level dam-segment diff that decides the fix shape.
- The `_min` swap is still in the working tree (uncommitted) — to be reverted once snapshot confirms direction.
- Next: snapshot completes → inspect bcfp dam-upstream segment mapping_code → decide fix shape → surface to user.

## Session 2026-05-23 (cont.) — mechanism resolved by reading bcfp source

- User pushed hard: "dam blockage is species specific based on our rules", "fish are above these dams, dam means nothing on its own", "how does bcfp do it? understand mechanisms", "blocks_species maybe the wrong design — nothing black-white", "we have species overrides (fish above → override)", "do our homework and DOCUMENT so we can find it. tricky to carry all this knowledge". → wrote **RUNBOOK.md** (repo root) + CLAUDE.md pointer.
- Read bcfp source authoritatively (`gh api`, smnorris/bcfishpass@v0.7.15):
  `model_access_bt.sql`, `load_streams_access.sql`, `load_streams_mapping_code.sql`.
  **Finding:** bcfp `barriers_<sp>` = natural-only (gradient@species-threshold + falls + subsurface) MINUS upstream-observation/habitat overrides ∪ user_definite. Dams NEVER in the access set — they annotate (token2) via separate `barriers_dams_dnstr`. token2 gate identical to link.
- **link's bug, fully characterized:** (1) `barriers_per_sp = barriers_<sp>_unified` carries dams (wrong content); (2) `lnk_barrier_overrides` output feeds classify (habitat) not access (mapping_code). Documented in RUNBOOK §5 + findings.
- Reverted broken `_min` swap → `_unified` (runnable, known-divergent), comment → RUNBOOK §5.
- Confirmed user's instincts on every point. The real fix = build a natural-only per-species feature view reproducing bcfp barriers_<sp> + wire overrides into access. Real work (Phase 4d), needs scoping.
- streams_vw_bcfp load failed on transient gzip (snapshot otherwise OK exit 0); retrying (task b122hazyb) for empirical parity numbers.
- Next: user reviews the mechanism/runbook; scope Phase 4d; decide whether blocks_species redesign is its own issue.

### Environment
- docker `fresh-db` up (was down mid-session; `open -a Docker` + `docker compose up -d db` in fresh/docker/).
- bcfp tunnel `localhost:63333` flaky (dropped 3×); needs PG_PASS_SHARE. Build is tunnel-free; only parity diff needs it.
