# Task: Decouple bcfp compare from link pipeline run (#168)

The link pipeline produces the BC freshwater network model — PG `fresh.*` tables — and that IS the deliverable. Today `R/lnk_compare_wsg.R` bundles modelling + comparison into one call, and `data-raw/run_provincial_parity.R` uses RDS file existence as a resume check. On 2026-05-14 a 16-WSG `--no-cyphers` run reported "16 OK" but only 12 WSGs actually populated PG — stale RDS files silently skipped re-running the pipeline. Decouple into two independent functions (`lnk_pipeline_run`, `lnk_compare_rollup`), switch the resume check to PG state, add `--force` flag.

## Phase 1 — `R/lnk_pipeline_run.R` (modelling-only umbrella)

- [ ] Add `R/lnk_pipeline_run.R` with `lnk_pipeline_run(conn, aoi, cfg, loaded, schema, dams, cleanup_working)`. Phases: setup → load → prepare → crossings → break → classify → connect → species → persist_init → barriers_unify → persist. Drop working schema on exit when `cleanup_working = TRUE`.
- [ ] Roxygen with `@examples` (using bundled test cfg + `\dontrun{}` for DB).
- [ ] `devtools::document()` to register the export in NAMESPACE.
- [ ] Add `tests/testthat/test-lnk_pipeline_run.R` — arg validation + phase-order composition via `mockery::stub` (mirror `test-lnk_compare_wsg.R:23-110, 174-368`).
- [ ] `Rscript -e 'devtools::test(filter = "lnk_pipeline_run")' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5`
- [ ] `lintr::lint("R/lnk_pipeline_run.R")` clean
- [ ] `/code-check` clean on staged diff
- [ ] Commit "Add lnk_pipeline_run — modelling umbrella for one WSG"

## Phase 2 — `R/lnk_compare_rollup.R` (comparison-only)

- [ ] Add `R/lnk_compare_rollup.R` with `lnk_compare_rollup(conn, aoi, cfg, reference = "bcfishpass", conn_ref = NULL, species = NULL)`. Reads `<persist_schema>.streams` + `streams_habitat_<sp>` (NOT working schema). Reference dispatch lifted from existing `.lnk_compare_wsg_rollup_reference`.
- [ ] Adapt link-side rollup queries: today's working-schema long-format query (`R/lnk_compare_wsg.R:299-364`) becomes per-species queries on wide `streams_habitat_<sp>` joined to `streams`, UNION ALL into the existing long output shape. Lake/wetland ha queries adapt similarly.
- [ ] Roxygen with `@examples` mirroring `lnk_compare_wsg`.
- [ ] `devtools::document()`.
- [ ] Add `tests/testthat/test-lnk_compare_rollup.R` — arg validation + reference dispatch.
- [ ] Bit-identical-rollup test: same PG state, `lnk_compare_rollup()` must match `lnk_compare_wsg()` rollup column-for-column. Live DB test, skip-if-not-local gated.
- [ ] `Rscript -e 'devtools::test(filter = "lnk_compare_rollup")' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5`
- [ ] `/code-check` clean
- [ ] Commit "Add lnk_compare_rollup — reference-agnostic comparison reader"

## Phase 3 — `.lnk_wsg_persisted()` PG-state probe

- [ ] Add `.lnk_wsg_persisted(conn, cfg, aoi)` to `R/utils.R` after `.lnk_working_schema`. Uses `.lnk_table_names()` to get `<persist_schema>.streams`. Returns `FALSE` if table absent, else `nrow(SELECT 1 ... LIMIT 1) > 0`.
- [ ] Add `tests/testthat/test-utils.R` entries — table-missing / table-present-with-WSG / table-present-without-WSG.
- [ ] `/code-check` clean
- [ ] Commit "Add .lnk_wsg_persisted PG-state probe for resume checks"

## Phase 4 — Refactor `R/lnk_compare_wsg.R` as wrapper

- [ ] Replace body of `lnk_compare_wsg()` for rollup-only path: calls `lnk_pipeline_run() + lnk_compare_rollup()`. For `with_mapping_code=TRUE` retain the current bundled flow (working-schema-based mapping_code build kept intact — decoupling deferred).
- [ ] Verify the 5 existing tests in `tests/testthat/test-lnk_compare_wsg.R` still pass unchanged (arg validation + phase-composition assertions).
- [ ] `Rscript -e 'devtools::test(filter = "lnk_compare_wsg")' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5`
- [ ] `/code-check` clean
- [ ] Commit "Refactor lnk_compare_wsg as wrapper over lnk_pipeline_run + lnk_compare_rollup"

## Phase 5 — `data-raw/` split

- [ ] `git mv data-raw/compare_bcfishpass_wsg.R data-raw/wsg_compare.R`
- [ ] Edit `data-raw/wsg_compare.R`: function becomes `wsg_compare(wsg, config, reference = "bcfishpass", species = NULL)`. Removes pipeline orchestration; calls `link::lnk_compare_rollup()`. Keeps the `ref_value → bcfishpass_value` rename when `reference == "bcfishpass"`.
- [ ] Write `data-raw/wsg_pipeline_run.R`: function `wsg_pipeline_run(wsg, config, dams = TRUE, cleanup_working = TRUE)`. Opens local fwapg conn, stamps via `lnk_stamp`, calls `link::lnk_pipeline_run()`. Returns invisibly.
- [ ] Update `data-raw/_targets.R` (3 references at lines 49, 69, 78): source both new files; replace `compare_bcfishpass_wsg(wsg, config)` with `wsg_pipeline_run(wsg, config); wsg_compare(wsg, config)`.
- [ ] Update `data-raw/regress_dams_isolation.R`: same pattern.
- [ ] Update `data-raw/rule_flexibility_demo.R`: same pattern.
- [ ] `/code-check` clean
- [ ] Commit "Split compare_bcfishpass_wsg.R into wsg_pipeline_run.R + wsg_compare.R"

## Phase 6 — `data-raw/run_provincial_parity.R` resume-check rewrite

- [ ] Source `wsg_pipeline_run.R` + `wsg_compare.R` (replace single source of old file).
- [ ] Open one `conn` to local fwapg at top of script (replace per-WSG conn churn).
- [ ] Add `--force` CLI flag parse.
- [ ] Replace cache-skip block (lines 200-205) with the four-branch logic (force / fully-cached / compare-only / pipeline+compare).
- [ ] Helper `.is_error_stub(rds_path)` reads the RDS, returns `TRUE` iff it's a `list(error=..., elapsed_s=...)` stub. Stub-detection mirrors lines 264-270 of the post-loop annotation block.
- [ ] Update header comments to reflect PG-state resume.
- [ ] `/code-check` clean
- [ ] Commit "Update run_provincial_parity.R: PG-state resume check + --force"

## Phase 7 — Smoke matrix (1-WSG, 4 cache states)

Pick smallest available WSG (ADMS or DEAD). Run on M4, local fwapg.

- [ ] **State A — empty:** delete RDS, drop WSG from `<persist_schema>.streams`. Run loop. Expect: pipeline + compare fire, PG populated, RDS written. Wall time ~80s.
- [ ] **State B — pipeline-cached:** keep PG state from A, delete RDS only. Run loop. Expect: skip pipeline, run compare only, RDS written. Wall time ~3-5s.
- [ ] **State C — fully cached:** keep PG + RDS from B. Run loop. Expect: "cached, skip" message, no-op. Wall time <1s per WSG.
- [ ] **State D — `--force`:** keep PG + RDS. Run with `--force`. Expect: pipeline + compare re-run, RDS overwritten. Wall time ~80s.
- [ ] Document each outcome in `progress.md` with wall times.

## Phase 8 — `devtools::check()` + release v0.37.0

- [ ] `Rscript -e 'devtools::check()' 2>&1 | grep -E "(ERROR|WARNING|NOTE)" | tail -10` → 0 errors, 0 warnings
- [ ] `Rscript -e 'lintr::lint_package()' | head -20` clean (or only previously-accepted lints)
- [ ] Update `DESCRIPTION` Version 0.36.1 → 0.37.0
- [ ] Update `NEWS.md` with v0.37.0 entry — one short paragraph covering the decouple + new exports + new resume logic.
- [ ] Update `CLAUDE.md` "Exported Functions" section: bump count, add `lnk_pipeline_run` and `lnk_compare_rollup` rows under appropriate family headers.
- [ ] Commit "Release v0.37.0"
- [ ] `/planning-archive` with slug `decouple-pipeline-compare`
- [ ] `/gh-pr-push` opens PR with SRED tag in body
- [ ] After merge: `/gh-pr-merge` handles tag + post-merge CI watch

## Validation

- [ ] Tests pass (`devtools::test()` — full suite, not just filtered)
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
