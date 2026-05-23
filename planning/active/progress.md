# Progress — mapping_code accessibility, reproduce bcfp `barriers_<sp>` (#200)

## Session 2026-05-23

- M4→M1 handoff resumed; v0.40.3 shipped (PR #199 merged `46b2042`, tagged).
- Environment up on M1: docker fresh-db, link 0.40.3, bcfp snapshot reloaded (`v0.7.15-14-ge12c1a5`, `streams_vw_bcfp` loaded locally), local `:63333→:5432` forwarder (db_newgraph tunnel key deauthorized on M1 — not blocking).
- Read bcfp access machinery end-to-end (5 species models + `barriers_user_definite.sql` + `load_streams_access.sql`) — see findings.
- Plan-agent design review: rejected per-WSG view (B'); user pushed for province-wide correctness. Final design = persist all access inputs province-wide (USER_DEFINITE family + persist barrier_overrides + `_access` view). Plan approved.
- Archived #196 PWF; created branch `200-mapping-code-accessibility-reproduce-bcf`; scaffolded #200 PWF baseline.
- Phase 1 done: `USER_DEFINITE` family in `lnk_barriers_unify` (FALLS-pattern FWA ltree join); `cols_barrier_overrides` + DDL in `lnk_persist_init`; persist copy in `lnk_pipeline_persist` (pre-persist auto-picks it up). Unit tests 96 pass; DB-smoke validated DDL + branch (empty-fallback safe, one-row resolves ltree/geom). Both configs persist to schema `fresh` (provincial `fresh_default` is a runtime `--schema` override). Commit `a82a7fc`.
- Phase 2 done: `barriers_<sp>_access` view in `lnk_barriers_views` (natural-only + override anti-join + definite-exempt). DB-smoke: 904,262 natural rows, 0 non-natural. code-check clean. Commit `f758e44`.
- Phase 3 done: repoint `barriers_per_sp` → `_access` + comment. Commit `c412d68`.
- Phase 4 done: validated PARS BT 98.95%, LFRA BT 97.77% / CO 97.90% vs `streams_vw_bcfp`; `;DAM` tokens correct. Found+fixed `barrier_overrides` PK (added `watershed_group_code` — boundary-stream cross-WSG collision). Worked around stale bt+co persist tables (DROP + recreate full-width). PARS needed PCEA+UPCE persisted first (cross-WSG dams). Commit `2ea3a7d`.
- Phase 5: RUNBOOK §2a/§3/§5/§7 updated; NEWS + DESCRIPTION → 0.40.4; temp scripts removed. test 1193 pass (lone FAIL = env db_conn). Next: archive + open PR (stop before merge per user).
