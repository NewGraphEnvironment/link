# Task Plan: link R Package Scaffold & Function Build

## Goal
Build the `link` R package — a connectivity-system-agnostic crossing interpretation layer that scores, overrides, and prioritizes crossings for any network engine, with fresh as the first integration target.

## Current Phase
Phase 7

## Phases

### Phase 1: Package Scaffold
- [x] Create branch `scaffold-link` from main
- [x] DESCRIPTION, LICENSE, NAMESPACE, .Rbuildignore, .gitignore
- [x] testthat (edition 3) + pkgdown + GitHub Action
- [x] `dev/dev.R` + `data-raw/testdata.R`
- [x] `inst/extdata/` — thresholds, crossings, overrides CSVs
- [x] `R/link-package.R` with package-level roxygen
- [x] `.lintr` config
- [x] Commit: `Scaffold link package` — Relates to #1
- **Status:** complete

### Phase 2: Core Utilities & Thresholds (Issues #3–4)
- [x] `lnk_thresholds()` — load/merge configurable scoring defaults (#3)
- [x] `lnk_db_conn()` / internal DB helpers (#4)
- [x] Tests + examples for each (63 pass + 10 skip-if-no-db)
- [x] 3-round code check: SQL injection, allowlist, reserved-word quoting, NaN/Inf guards
- [x] `devtools::document()`, `lintr::lint_package()`, `devtools::test()` — all clean
- [x] Committed in scaffold (issues close when PR merges)
- **Status:** complete

### Phase 3: Override Family (Issues #5–7)
- [x] `lnk_override_load()` — two-phase CSV validation + DB write (#5)
- [x] `lnk_override_apply()` — auto-detect columns, quoted SQL (#6)
- [x] `lnk_override_validate()` — orphans, duplicates, counts (#7)
- [x] Tests: 68 pass, 34 skip (DB), 0 fail
- [x] 3-round code check: SQL injection, partial-load atomicity, empty-CSV guard
- [x] Examples: load→validate→apply pipeline, verbose output, error cases
- [x] Committed: Fixes #5, #6, #7
- **Status:** complete

### Phase 4: Match Family (Issues #8–10)
- [x] `lnk_match_sources()` — generic N-way matcher with 1:1 dedup (#8)
- [x] `lnk_match_pscis()` — PSCIS wrapper with xref CSV priority (#9)
- [x] `lnk_match_moti()` — MOTI wrapper with 150m tolerance (#10)
- [x] Tests: 69 pass, 50 skip (DB), 0 fail, 0 lints
- [x] 3-round code check: many-to-many dedup, where alias isolation
- [x] Committed: Fixes #8, #9, #10
- **Status:** complete

### Phase 5: Score Family (Issues #11–12)
- [x] `lnk_score_severity()` — threshold-driven, NULL-safe, column-agnostic (#11)
- [x] `lnk_score_custom()` — weighted rank with primary key join (#12)
- [x] Tests: 69 pass, 65 skip (DB), 0 fail, 0 lints
- [x] 2-round code check: threshold SQL guard, ctid->PK, direction validation
- [x] Committed: Fixes #11, #12
- **Status:** complete

### Phase 6: Bridge & Habitat (Issues #13–14)
- [x] `lnk_break_source()` — fresh-compatible break source spec (#13)
- [x] `lnk_habitat_upstream()` — per-crossing upstream rollup (#14)
- [x] Tests: 69 pass, 77 skip (DB), 0 fail, 0 lints
- [x] Code check: clean first round
- [x] Committed: Fixes #13, #14
- **Status:** complete

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
