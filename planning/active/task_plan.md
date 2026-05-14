# Task: Decouple bcfp compare from link pipeline run (#168)

The link pipeline produces the BC freshwater network model — PG `fresh.*` tables — and that IS the deliverable. Today `R/lnk_compare_wsg.R` bundles modelling + comparison into one call, and `data-raw/run_provincial_parity.R` uses RDS file existence as a resume check. On 2026-05-14 a 16-WSG `--no-cyphers` run reported "16 OK" but only 12 WSGs actually populated PG — stale RDS files silently skipped re-running the pipeline. Decouple into two independent functions (`lnk_pipeline_run`, `lnk_compare_rollup`), switch the resume check to PG state, add `--force` flag.

## Phase 1 — `R/lnk_pipeline_run.R` (modelling-only umbrella)

- [x] Add `R/lnk_pipeline_run.R` with `lnk_pipeline_run(conn, aoi, cfg, loaded, schema, dams, cleanup_working)`. Phases: setup → load → prepare → crossings → break → classify → connect → species → persist_init → barriers_unify → persist. Drop working schema on exit when `cleanup_working = TRUE`.
- [x] Roxygen with `@examples` (using bundled test cfg + `\dontrun{}` for DB).
- [x] `devtools::document()` to register the export in NAMESPACE.
- [x] Add `tests/testthat/test-lnk_pipeline_run.R` — arg validation + phase-order composition via `with_mocked_bindings` (mirror `test-lnk_compare_wsg.R:23-110, 174-368`).
- [x] `Rscript -e 'devtools::test(filter = "lnk_pipeline_run")'` — 16 PASS, 0 FAIL.
- [x] `lintr::lint("R/lnk_pipeline_run.R")` — 1 indentation lint on DROP TABLE sprintf, matches existing pattern in `lnk_compare_wsg.R:162` (accepted, pre-existing style).
- [x] `/code-check` clean on staged diff (round 1 clean).
- [x] Commit "Add lnk_pipeline_run — modelling umbrella for one WSG" (d4e046f)

## Phase 2 — `R/lnk_compare_rollup.R` (comparison-only)

- [x] Add `R/lnk_compare_rollup.R` with `lnk_compare_rollup(conn, aoi, cfg, reference = "bcfishpass", conn_ref = NULL, species = NULL)`. Reads `<persist_schema>.streams` + `streams_habitat_<sp>` (NOT working schema). Reference dispatch + assembly reused from existing `.lnk_compare_wsg_rollup_reference` and `.lnk_compare_wsg_assemble_rollup`.
- [x] Adapt link-side rollup queries: per-species `UNION ALL` across `streams_habitat_<sp>` for km query; per-species UNION ALL into DISTINCT-waterbody_key joins for lake/wetland ha. Species auto-discovered from PG via `information_schema` probe — no need for `loaded$wsg_species_presence` here.
- [x] Roxygen with `@examples` mirroring `lnk_compare_wsg`.
- [x] `devtools::document()`.
- [x] Add `tests/testthat/test-lnk_compare_rollup.R` — arg validation + reference dispatch + composition (resolve → link → ref → assemble) + caller-species intersection.
- [ ] Bit-identical-rollup test: same PG state, `lnk_compare_rollup()` must match `lnk_compare_wsg()` rollup column-for-column. Live DB test — deferred to Phase 7 smoke matrix (cheaper to run there alongside the cache-state matrix).
- [x] `Rscript -e 'devtools::test(filter = "lnk_compare_rollup")'` — 15 PASS, 0 FAIL.
- [x] `lintr::lint("R/lnk_compare_rollup.R")` — 0 lints after `# nolint start: indentation_linter` block + species-suffix regex filter (round-1 fragility fix).
- [x] `/code-check` — round 1: 1 fragile (sp interpolation), fixed via regex filter; round 2 clean.
- [x] Commit "Add lnk_compare_rollup — reference-agnostic comparison reader" (ece0f11)

## Phase 3 — `.lnk_wsg_persisted()` PG-state probe

- [x] Add `.lnk_wsg_persisted(conn, cfg, aoi)` to `R/utils.R` after `.lnk_working_schema`. Two-stage probe: `information_schema.tables` (early-exit FALSE when streams table absent), then `LIMIT 1` row check.
- [x] Add `tests/testthat/test-utils.R` entries — arg validation (3) + table-missing / table-present-with-WSG / table-present-without-WSG (6 new test_that blocks, 48 PASS total in file).
- [x] `/code-check` clean (round 1; one fragility raised was already in accepted-tradeoffs).
- [ ] Commit "Add .lnk_wsg_persisted PG-state probe for resume checks"

## Phase 4 — Refactor `R/lnk_compare_wsg.R` as wrapper

- [x] Replace body of `lnk_compare_wsg()`: both paths now call `lnk_pipeline_run() + lnk_compare_rollup()`. Mapping_code branch additionally calls `.lnk_compare_wsg_mapping_code` after the rollup; forces `cleanup_working = FALSE` on the pipeline call so the working schema survives the mapping_code build.
- [x] **Behavior shift documented:** active-species set is now discovered from PG state (post-persist), not `cfg$species ∩ wsg_species_presence` (pre-persist). Equivalent on a fresh single-call run; future-proofs `lnk_compare_rollup` against config drift between modelling + comparison.
- [x] Update existing tests in `tests/testthat/test-lnk_compare_wsg.R` — composition tests now mock `lnk_pipeline_run` + `lnk_compare_rollup` at the new boundary instead of per-phase mocks. Arg-validation tests unchanged.
- [x] `Rscript -e 'devtools::test(filter = "lnk_compare_wsg")'` — 55 PASS, 0 FAIL. Full suite: 1172 PASS / 0 FAIL.
- [x] `lintr::lint("R/lnk_compare_wsg.R")` — 46 lints (down from 48 pre-existing on main; refactor removed two sprintf blocks).
- [x] `/code-check` round 1 clean.
- [ ] Commit "Refactor lnk_compare_wsg as wrapper over lnk_pipeline_run + lnk_compare_rollup"

## Phase 5 — `data-raw/` split

- [x] `git mv data-raw/compare_bcfishpass_wsg.R data-raw/wsg_compare.R`
- [x] Edit `data-raw/wsg_compare.R`: function `wsg_compare(wsg, config, species, reference = "bcfishpass")`. Removes pipeline orchestration; calls `link::lnk_compare_rollup()`. Keeps the `ref_value → bcfishpass_value` rename when `reference == "bcfishpass"`.
- [x] Write `data-raw/wsg_pipeline_run.R`: function `wsg_pipeline_run(wsg, config, dams = TRUE, cleanup_working = TRUE)`. Opens local fwapg conn, stamps via `lnk_stamp`, calls `link::lnk_pipeline_run()`. Returns invisibly.
- [x] Update `data-raw/_targets.R` — source both new files; tar_map target bodies now call `wsg_pipeline_run; wsg_compare` (return value of last expression becomes target value).
- [x] Update `data-raw/regress_dams_isolation.R`: same pattern; `dams` flag now passed to `wsg_pipeline_run`.
- [x] Update `data-raw/rule_flexibility_demo.R`: same pattern.
- [x] Update `data-raw/run_provincial_parity.R` source + call site (loop body retains the cache-skip — Phase 6 rewrites that). Mapping_code branch wraps the bundled `lnk_compare_wsg(with_mapping_code = TRUE)` flow in an IIFE so `on.exit` has a real frame.
- [x] `/code-check` round 1 found connection-leak bug (`on.exit` in top-level for-loop binds to globalenv, doesn't fire); fixed via IIFE wrap. Round 2 clean.
- [ ] Commit "Split compare_bcfishpass_wsg.R into wsg_pipeline_run.R + wsg_compare.R"

## Phase 6 — `data-raw/run_provincial_parity.R` resume-check rewrite

- [x] Source `wsg_pipeline_run.R` + `wsg_compare.R` (done in Phase 5).
- [x] Add a script-level `probe_conn` for the PG-state probe (separate from per-WSG function conns, which open + close internally).
- [x] Add `--force` CLI flag parse.
- [x] Replace cache-skip block with the four-branch logic (force / fully-cached / compare-only / pipeline+compare).
- [x] Two new helpers: `.is_error_stub(rds_path)` and `.rollup_has_mapping_code(rds_path)`. The mapping_code helper covers the case where a previous rollup-only run saved a bare tibble but the current run wants mapping_code — invalidates the cache so re-run fires.
- [x] Update header comments to reflect the new resume semantics.
- [x] `/code-check` round 1 clean (1 dead assignment noted, removed).
- [ ] Commit "Update run_provincial_parity.R: PG-state resume check + --force"

## Phase 7 — Smoke matrix (1-WSG, 4 cache states) — DONE

Ran against isolated schema `fresh_smoke168` on M4 (DEAD WSG, ~12k segments). Schema dropped after smoke; canonical `fresh.*` untouched.

| State | Setup | Wall | Outcome |
|-------|-------|------|---------|
| A — empty | drop schema + RDS | 57s | pipeline + compare fired, 42 rollup rows, RDS written; `<schema>.streams` + per-species habitat + barriers populated |
| B — pipeline-cached | drop RDS only | 9s | `[compare-only]` log marker, 42 rows, RDS written (~6× speedup vs A) |
| C — fully cached | both intact | 2s | `(cached, skip)` no work |
| D — `--force` | both intact | 56s | pipeline + compare re-fired regardless of cache state |

Post-pipeline PG state: `fresh_smoke168.streams` = 12,301 rows for DEAD (matches canonical `fresh.streams` count); 6 per-species habitat tables created (BT, CH, CO, PK, SK, ST); `fresh_smoke168.barriers` populated (confirms `lnk_barriers_unify` always-on change works).

- [x] State A: empty → pipeline + compare fire.
- [x] State B: pipeline-cached → compare-only fires.
- [x] State C: fully cached → skip.
- [x] State D: `--force` → both re-fire.
- [x] Decoupled architecture verified end-to-end against live DB.

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
