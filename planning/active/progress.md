# Progress — lnk_wsg_resolve (#207)

## Session 2026-05-27

- Plan-mode exploration — phases approved by user
- Archived #175 PWF (commit `f964537`, pushed to main)
- Created branch `207-lnk-wsg-resolve-bundle-aware-wsg-resolve` off main
- Scaffolded PWF baseline from issue #207 with approved 5-phase plan
- **Phase 1 complete:** DESCRIPTION bumped `fresh@v0.31.0 → @v0.32.0` (Remotes + Suggests); fresh v0.32.0 installed via pak (pkg sha `5e7fa81` matches fresh main); smoke test passed — `fresh::frs_wsg_drainage(conn, c("PARS","BULK"))` returns the exact 15-WSG closure from inside link's session.
- **Phase 2 complete:** Wrote `R/lnk_wsg_resolve.R` — signature `lnk_wsg_resolve(cfg, loaded, wsgs = NULL, expand = TRUE)`; validation mirrors `lnk_pipeline_species`; 3-branch dispatch (province/closure/strict); composes `fresh::frs_wsg_drainage()` for closure expansion; species filter inline. `/code-check` Round 1 caught 3 issues — (a) undocumented province ordering → now sorted alphabetically + documented in `@return`; (b) silent strict-mode drops → now `message()` with dropped list; (c) silent closure-mode drops → now `message()` (parity with `study_area_wsgs.R:67-71`); Round 2 Clean. Smoke-validated all four behaviors against live fwapg. Commit `196fd63`. Function commit pending.
- Next: Phase 3 — tests
