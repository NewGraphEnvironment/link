# Progress — lnk_wsg_resolve (#207)

## Session 2026-05-27

- Plan-mode exploration — phases approved by user
- Archived #175 PWF (commit `f964537`, pushed to main)
- Created branch `207-lnk-wsg-resolve-bundle-aware-wsg-resolve` off main
- Scaffolded PWF baseline from issue #207 with approved 5-phase plan
- **Phase 1 complete:** DESCRIPTION bumped `fresh@v0.31.0 → @v0.32.0` (Remotes + Suggests); fresh v0.32.0 installed via pak (pkg sha `5e7fa81` matches fresh main); smoke test passed — `fresh::frs_wsg_drainage(conn, c("PARS","BULK"))` returns the exact 15-WSG closure from inside link's session.
- **Phase 2 complete:** Wrote `R/lnk_wsg_resolve.R` — signature `lnk_wsg_resolve(cfg, loaded, wsgs = NULL, expand = TRUE)`; validation mirrors `lnk_pipeline_species`; 3-branch dispatch (province/closure/strict); composes `fresh::frs_wsg_drainage()` for closure expansion; species filter inline. `/code-check` Round 1 caught 3 issues — (a) undocumented province ordering → now sorted alphabetically + documented in `@return`; (b) silent strict-mode drops → now `message()` with dropped list; (c) silent closure-mode drops → now `message()` (parity with `study_area_wsgs.R:67-71`); Round 2 Clean. Smoke-validated all four behaviors against live fwapg. Commit `196fd63`. Function commit pending.
- **Phase 3 complete:** Wrote `tests/testthat/test-lnk_wsg_resolve.R` — 13 test_that blocks / 22 expectations. Code-check Round 1 caught stub-was-pre-sorted bug (`sort()` not exercised) → reordered stub to `c("CCCC","AAAA","BBBB")` so positives are NOT in alpha order; Round 2 caught misleading test name → renamed. 22/22 PASS against live fwapg. Commit `c7ae248` (function); test commit pending.
- **Phase 4 complete:** `data-raw/study_area_wsgs.R` shrunk 76 → 33 lines; closure + filter + ordering block replaced with single `lnk_wsg_resolve()` call. Byte-identical stdout vs pre-#207 (76 bytes for `PARS,BULK` regression baseline). Stderr unchanged. `/code-check` Round 1 Clean. Commit `9a95081` (tests); shim commit pending.
- **Phase 5 release-prep:** NEWS.md `# link 0.41.0` section added (two paragraphs matching v0.40.x style); DESCRIPTION bumped 0.40.5 → 0.41.0, Date 2026-05-27. Lintr installed + run; 2 indent findings on R/lnk_wsg_resolve.R + test file → fixed by extracting `bad` predicate and lifting `empty_wp` out of nested `expect_error`. All 3 changed files lint clean. Tests still pass. Commit `bb1a6ab` (shim); Release commit pending.
- Next: Release v0.41.0 commit, then `/planning-archive` + `/gh-pr-push`
