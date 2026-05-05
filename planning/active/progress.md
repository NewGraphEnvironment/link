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
- Phase 1 close-out: dropped the consolidate-the-two-helpers idea (genuinely different semantics — constant remapping vs value-driven; reuse-vs-surface-similarity lesson). Added roxygen note on `lnk_pipeline_load` distinguishing `barrier_status` (bcfp-parity) from `severity` (link's culvert geometry scoring). Phase 1 done.
- Phase 2 partial: shipped fresh#201 `frs_network_features()` (v0.28.0) as the canonical primitive — direction-agnostic, public, generic over any FWA-snapped point dataset. ADMS PSCIS parity 1031/1031 byte-identical to bcfp.
- `lnk_pipeline_access()` composes `frs_network_features` across species into a per-segment `streams_access` wide tibble + optional dest-table write. Live test on ADMS BT: byte-identical access_bt distribution to bcfp (10500 / 5262, modulo 1/2 collapse without observations).
- Two ergonomic gaps in fresh#201 surfaced during integration — filed as fresh#204:
  - `wscode_ltree`/`localcode_ltree` hardcoded in SQL — breaks for `bcfishpass.observations` (uses `wscode`/`localcode`).
  - Returns `pq__text` literal strings, not R list-columns — callers can't naturally read array contents.
- Today's `lnk_pipeline_access` uses set-membership + substring-grepl as workarounds. Full 1/2 access-code distinction + actual array persistence both blocked on fresh#204.
- Next: pause Phase 2 until fresh#204 ships (small follow-up — both gaps are well-scoped). When ready: extend to multi-species, wire into `lnk_pipeline_persist`, sweep on more WSGs.

## Session 2026-05-05 (afternoon resume)

- fresh#204 SHIPPED as v0.29.0 (PR #205, squash `f42e86a`, tag `v0.29.0`). Per-side overrides (`segments_*` / `features_*` wscode/localcode args) + `feature_ids` returns as R list-column of character vectors. Mocked tests 43/0; live ADMS PSCIS parity 1031/1031 byte-identical preserved; new live test covers `bcfishpass.observations` join. M4 reinstalled to fresh 0.29.0.
- Adjacent infra work surfaced same session: rtj#110 filed (cypher snapshot R libpath workaround for r-lib/pak#658); `link/scripts/update_hosts.sh` written; `data-raw/trifecta_provincial.sh` gained `--rds-dir=` pass-through.
- `lnk_pipeline_access` updated to drop both workarounds: replaced substring-grepl on `pq__text` with clean `%in%` on the parsed character-vector list-column, dropped the redundant observation_key call (species_code call alone now drives both `has_observation_key_upstr` and per-species `observed`), pass `features_wscode_col = "wscode"` / `features_localcode_col = "localcode"` for `bcfishpass.observations`. lintr clean.
- **ADMS BT live test: byte-identical to bcfp's `streams_access.access_bt`** distribution on the same WSG — `0 = 6728`, `1 = 3043`, `2 = 687`. Full 1/2 distinction (modelled vs observed) now correct (the earlier "10500 / 5262 mod 1/2 collapse" line above was an artifact of the workaround, not a genuine reference).
- Next: multi-species sweep (CH, CO, SK, ST, WCT, ...), wire into `lnk_pipeline_persist`, then Phase 3 (`lnk_pipeline_mapping_code`).
