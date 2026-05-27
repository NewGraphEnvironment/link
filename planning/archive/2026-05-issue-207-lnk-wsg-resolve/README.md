# Issue #207 — lnk_wsg_resolve + study_area_wsgs.R → CLI shim

## Outcome

Added `lnk_wsg_resolve(cfg, loaded, wsgs = NULL, expand = TRUE)` — the bundle-aware WSG resolver that composes `fresh::frs_wsg_drainage()` (the FWA drainage-closure primitive from NewGraphEnvironment/fresh#211 / v0.32.0) with the bundle's `wsg_species_presence` filter (link#157). Three call patterns: province (`wsgs = NULL`, sorted alphabetically), closure (`wsgs + expand = TRUE`, focal + drainage DS-first), strict (`wsgs + expand = FALSE`, species-filter input verbatim). Closure + strict modes emit `message()` listing any species-less WSGs dropped — preserving the diagnostic the old script had inline. New `@family wsg` pre-stages the family for future `lnk_wsg_*` helpers.

`data-raw/study_area_wsgs.R` shrank from 76 → 33 lines — pure CLI shim now, delegating to `lnk_wsg_resolve()`. **Byte-identical stdout** for the regression baseline (`PARS,BULK` → the 15-WSG `KISP, KLUM, LKEL, LSKE, MSKE, USKE, BULK, FINA, LBTN, LPCE, MORR, PARA, PCEA, UPCE, PARS`), so `data-raw/study_area_run.sh` is unaffected. fresh dependency pin bumped `Remotes: fresh@v0.31.0 → @v0.32.0`. 22 tests added (`tests/testthat/test-lnk_wsg_resolve.R`); /code-check ran 2 rounds on the function (3 findings → all fixed: undocumented province ordering, silent strict-mode drops, silent closure-mode drops) and 2 rounds on the tests (1 finding → stub deliberately reordered so `sort()` is load-bearing).

Released as **v0.41.0**.

Closed by: commits `196fd63` (Phase 1: fresh dep bump), `c7ae248` (Phase 2: function), `9a95081` (Phase 3: tests), `bb1a6ab` (Phase 4: shim), `c0735f3` (Release v0.41.0). PR forthcoming via `/gh-pr-push`.
