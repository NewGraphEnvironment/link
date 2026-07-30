# Task: Rename dimensions_columns.csv → dictionary_dimensions.csv; add dictionary_parameters_fresh.csv (#233)

Two config CSVs carry the pipeline's methodology. `dimensions.csv` has a data dictionary; `parameters_fresh.csv` has none — its 19 columns are documented only in scattered prose (`RUNBOOK.md` §7 covers two families, roxygen on `lnk_barrier_overrides()` covers the observation block, the 9 `cluster_*` columns are undocumented). The existing dictionary is also named for its shape (`dimensions_columns.csv`) rather than what it is.

The deeper problem this fixes: **the fresh↔link column-ownership boundary keeps getting re-derived.** It was settled by NewGraphEnvironment/fresh#129 (shipped fresh 0.12.7 — `observation_*` removed from fresh because "fish passage interpretation belongs in link, not the network engine") and is enforced today by `data-raw/audit_configs.R` §3b. That decision is currently findable only by archaeology through two repos' planning archives. Encoding it as an `owner` column, and making the audit read it, ends the re-derivation.

## Correction to the issue body

The issue says `cluster_*` (9 columns) → `R/lnk_pipeline_connect.R`. That is imprecise and the implementation must not copy it. link only **passes** `loaded$parameters_fresh` through (`R/lnk_pipeline_connect.R:107` → `.frs_run_connectivity()`); the columns are actually **read in fresh** at `fresh/R/frs_habitat.R:1164-1196`. `access_gradient_max` is genuinely dual-consumed (link `R/lnk_barriers_unify.R:139` + `R/lnk_pipeline_prepare.R:553`, and fresh). So `consumed_by` must distinguish reader from pass-through, traced per column rather than assumed.

## Phase 1: Rename + reference repair

- [x] `git mv inst/extdata/configs/dimensions_columns.csv inst/extdata/configs/dictionary_dimensions.csv`
- [x] Update `CLAUDE.md:256` (#75 entry) to the new filename
- [x] Confirm sweep clean: `grep -rn "dimensions_columns" . --exclude-dir=.git` returns only `NEWS.md:421` + `planning/archive/2026-05-issue-45-gradient-classes/findings.md:108` (both historical, intentionally untouched)
- [x] `devtools::test()` — confirms the rename is inert (`lnk_config()` resolves bundles via `dir.exists()`, `R/lnk_config.R:280`; nothing reads the dictionary). 1294 PASS; 1 pre-existing FAIL (`test-lnk_wsg_resolve.R:138`) from missing `public.wsg_outlet` DB table — builder is open follow-up #227, unrelated to this rename
- [x] Verified no indirect reference: the only `list.files()` over a bundle dir is `data-raw/audit_configs.R:205`, scoped to `overrides/`, never the configs root. No hits in `_pkgdown.yml`, `.github/`, `vignettes/`, `man/`, `NAMESPACE`

## Phase 2: Test first — dictionary/schema contract

- [ ] `tests/testthat/test-dictionaries.R`, using `system.file("extdata", "configs", ...)` (`inst/` ships; `data-raw/` is `.Rbuildignore`d, so testthat is the durable guard — the audit script is dev-only)
- [ ] Assert: every column in each bundle's `parameters_fresh.csv` has exactly one dictionary row, and every dictionary row names a real column
- [ ] Assert: `owner` ∈ {`fresh`, `link`}; the `link`-owned set is exactly the 5 `observation_*` columns
- [ ] Assert: `dictionary_dimensions.csv` covers every column of each bundle's `dimensions.csv`
- [ ] `skip_if_not_installed("fresh")` on the cross-package assertion — fresh is Suggests (>= 0.32.0)
- [ ] Tests fail at this point (no dictionary yet). That is the contract.

## Phase 3: Author dictionary_parameters_fresh.csv

- [ ] `inst/extdata/configs/dictionary_parameters_fresh.csv`, 19 rows, schema `column,type,group,owner,consumed_by,default_when_absent,description,related` (mirrors `dictionary_dimensions.csv` with `emits` → `consumed_by`, plus `owner`)
- [ ] Groups: `key` / `access` / `gradient` / `cluster` / `observation`
- [ ] Trace every `consumed_by` to a real `file:line`, distinguishing reader from pass-through. Verified refs on current HEAD:
  - `access_gradient_max` → `R/lnk_barriers_unify.R:139`, `R/lnk_pipeline_prepare.R:553` (+ fresh)
  - `spawn_gradient_min` → `fresh/R/frs_habitat_classify.R:171`, `fresh/R/frs_habitat_predicates.R:87`
  - `cluster_*` → `fresh/R/frs_habitat.R:1164-1196`; link pass-through at `R/lnk_pipeline_connect.R:107`
  - cluster semantics prose → `fresh/R/frs_cluster.R` roxygen (documents `direction` / `bridge_gradient` / `bridge_distance` / `confluence_m` in full)
  - `observation_*` → `R/lnk_barrier_overrides.R`
- [ ] Record `rear_gradient_min` as unused — header-only in both packages, zero readers. fresh-owned, so its fate is a fresh-side call; do not drop it here
- [ ] Phase 2 tests now pass

## Phase 4: Make the dictionary load-bearing in the audit

- [ ] `data-raw/audit_configs.R` §3b (line 164): replace the hardcoded `grepl("^observation_", extra_link)` ownership rule with a lookup against the dictionary's `owner` column
- [ ] Add a dictionary-coverage check so an undocumented new column flags via `flag()` rather than passing silently
- [ ] Preserve existing semantics: `flag()` accumulator, end-of-run rollup, non-zero exit
- [ ] `Rscript data-raw/audit_configs.R` reports "No findings — config layers aligned." and exits 0

## Phase 5: Documentation

- [ ] `RUNBOOK.md` §7 "Where every rule lives": new ownership row pointing at fresh#129 + `audit_configs.R` §3b — the durable fix for the re-derivation problem
- [ ] `NEWS.md` entry
- [ ] Version bump to 0.44.3 as the **final** commit of the branch (per CLAUDE.md release convention)

## Validation

- [ ] `Rscript -e 'devtools::test()' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5`
- [ ] `Rscript -e 'lintr::lint_package()'` clean
- [ ] `Rscript data-raw/audit_configs.R` → 0 findings, exit 0
- [ ] Every `consumed_by` entry resolves to a real file:line (spot-check by grep)
- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

## Out of scope

- #75's auto-generated README + `lnk_rules_build()` validation — this unblocks it by giving both files a consistent shape
- Dropping or relocating `rear_gradient_min`
- Any change to `fresh`
- `audit_configs.R`'s hardcoded `setwd("/Users/airvine/Projects/repo/link")` (line 14) — a real portability defect that `/code-check` will flag when §3b is touched, but not this issue's scope. Worth its own issue.
