# Task Plan: link R Package Scaffold & Function Build

## Goal
Build the `link` R package — a connectivity-system-agnostic crossing interpretation layer that scores, overrides, and prioritizes crossings for any network engine, with fresh as the first integration target.

## Current Phase
Phase 1

## Phases

### Phase 1: Package Scaffold
- [ ] Create branch `scaffold-link` from main
- [ ] `usethis::create_package(".")` + DESCRIPTION fields
- [ ] `usethis::use_mit_license("New Graph Environment Ltd.")`
- [ ] `usethis::use_testthat(edition = 3)`
- [ ] `usethis::use_pkgdown()` + GitHub Action
- [ ] `usethis::use_directory("dev")` + `dev/dev.R`
- [ ] `usethis::use_directory("data-raw")` + `data-raw/testdata.R`
- [ ] `inst/extdata/thresholds_default.csv`
- [ ] `R/link-package.R` with package-level roxygen
- [ ] `.lintr` config
- [ ] Commit: `Scaffold link package` — Relates to #1
- **Status:** pending

### Phase 2: Core Utilities & Thresholds (Issues #3–4)
- [ ] `lnk_thresholds()` — load/merge configurable scoring defaults (#3)
- [ ] `lnk_db_conn()` / internal DB helpers (#4)
- [ ] Tests + examples for each
- [ ] `devtools::document()`, `lintr::lint_package()`, `devtools::test()`
- [ ] Commit each function closing its issue
- **Status:** pending

### Phase 3: Override Family (Issues #5–7)
- [ ] `lnk_override_load()` — read CSV, validate structure, write to DB (#5)
- [ ] `lnk_override_apply()` — join overrides onto crossings table (#6)
- [ ] `lnk_override_validate()` — check referential integrity (#7)
- [ ] Tests + examples for each
- [ ] `devtools::document()`, `lintr::lint_package()`, `devtools::test()`
- [ ] Commit each function closing its issue
- **Status:** pending

### Phase 4: Match Family (Issues #8–10)
- [ ] `lnk_match_sources()` — generic multi-source spatial matching (#8)
- [ ] `lnk_match_pscis()` — PSCIS-to-modelled convenience wrapper (#9)
- [ ] `lnk_match_moti()` — MOTI chris_culvert_id integration (#10)
- [ ] Tests + examples for each
- [ ] Commit each function closing its issue
- **Status:** pending

### Phase 5: Score Family (Issues #11–12)
- [ ] `lnk_score_severity()` — classify by biological impact (#11)
- [ ] `lnk_score_custom()` — user-defined scoring rules (#12)
- [ ] Tests + examples for each
- [ ] Commit each function closing its issue
- **Status:** pending

### Phase 6: Bridge & Habitat (Issues #13–14)
- [ ] `lnk_break_source()` — produce fresh-compatible break source list (#13)
- [ ] `lnk_habitat_upstream()` — per-crossing upstream habitat rollup (#14)
- [ ] Tests + examples for each
- [ ] Commit each function closing its issue
- **Status:** pending

### Phase 7: Integration & Release
- [ ] End-to-end vignette with bundled test data
- [ ] `devtools::check()` passes
- [ ] NEWS.md, README, hex sticker
- [ ] PR to main: `Relates to NewGraphEnvironment/sred-2025-2026#24`
- [ ] pkgdown deploy
- **Status:** pending

## Key Questions
1. What test data can we bundle without DB dependency? (small CSV crossings + thresholds)
2. Which functions need DB for examples vs can use local data?
3. Should `lnk_match_sources()` use spatial distance or network measure distance?

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| `lnk_` prefix | Autocomplete discoverability, consistent with fresh `frs_` pattern |
| System-agnostic column params | BC/PSCIS names as defaults, but any jurisdiction can swap |
| CSV thresholds pattern | Matches `frs_params()` — users understand the pattern |
| One function, one file | Convention: `R/lnk_score_severity.R` → `tests/testthat/test-lnk_score_severity.R` |
| Override CSVs with provenance cols | Tens of thousands of hand-reviewed crossings need audit trail |
| `lnk_break_source()` returns list | Direct input to `frs_habitat(break_sources = ...)` — zero friction bridge |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
|       | 1       |            |

## Notes
- Branch: `scaffold-link`, all commits close function issues with `Fixes #N`
- PR closes with `Relates to NewGraphEnvironment/sred-2025-2026#24`
- Every exported function gets runnable examples with bundled test data
- Examples show WHY the function is useful, HOW it integrates, WHAT it produces
