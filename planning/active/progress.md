# Progress — Stream-crossing accessibility labels: bcfishpass parity layer (#124)

## Session 2026-05-05

- Plan-mode exploration of bcfishpass DB (via db-newgraph MCP) and SQL source (`model/01_access/sql/load_crossings.sql`, `load_streams_access.sql`, `barriers_user_definite.sql`). Phases approved by user.
- Issue #124 filed (succinct body — Problem / Proposed Solution / Acceptance / Out of scope).
- Archived prior #121 PWF (auto-stamp bcfp baseline) — shipped as v0.29.1, PR #122, squash `bf5db25`.
- Created branch `124-stream-crossing-accessibility-labels-bcf` off main.
- Scaffolded PWF baseline (task_plan.md, findings.md, progress.md) with the approved 5-phase breakdown.
- Background: `default_rearbreaks` provincial trifecta running (started 2026-05-04 23:23 PDT), 36 / 32 / 18 % complete on M4 / M1 / cypher at last check. Auto-stamper from #121 firing on each host. Trifecta independent of #124 work.
- Phase 1 exploration: `<schema>.crossings.barrier_status` is ALREADY populated by `lnk_pipeline_load`. Two private helpers do override work (`.lnk_pipeline_apply_fixes` UPDATE-inline + `.lnk_pipeline_apply_pscis` via canonical `lnk_override`). ADMS parity test: 7/7 buckets match bcfp tunnel; 2-row diff out of 3597 (likely from bcfp build SHA drift in fresh's bundled CSV).
- User feedback: build abstract systems, not engineered machines. Reuse `lnk_*` family helpers. Consolidate duplicate code rather than extend it. Hardcode last.
- Plan revised: Phase 1 collapses to consolidate two apply helpers into one canonical `lnk_override`-based path + verify + document (~0.5 day). Phase 2 introduces a `lnk_dnstr_barriers` primitive (the system layer) — `streams_access` becomes thin orchestration over it (the parity layer). Phase 3 (mapping_code) is pure derivation, no new primitive. Total revised: ~4 days (was 4.5–5.5).
- Memory saved: `feedback_abstract_systems.md`.
- Next: start Phase 1 — consolidate `.lnk_pipeline_apply_fixes` to use `lnk_override`.
