# Task Plan: _targets.R pipeline (#38)

## Goal

Replace the 635-line `data-raw/compare_bcfishpass.R` script with a targets-driven pipeline that:
- Runs each DAG node as a `tar_target()` — inspectable, cacheable, skippable
- Parallelizes across watershed groups via `tar_map(wsg = c(...))`
- Regenerates the research doc DAG from `tar_mermaid()`
- Single-host on M4 first; distributed swap to `crew_controller_group(local=M4, cluster=M1)` is a follow-up after rtj Phase 4

Uses `lnk_config("bcfishpass")` (shipped in 0.2.0) and `frs_barriers_minimal()` (fresh 0.14.0).

## Package vs pipeline split

Helpers (`lnk_habitat_*`) go in `R/` as exported package functions — generic building blocks any caller can compose. `_targets.R` + `compare_bcfishpass_wsg()` go in `data-raw/` — this specific comparison pipeline, not part of the installed package. `data-raw/` is the canonical R-package home for "code that USES this package to produce outputs."

## PR 1: Extract helpers to R/lnk_pipeline_*.R

Break the 635-line script into small named functions (one per pipeline phase). Canonical signature `(conn, aoi, cfg, schema)` — `aoi` follows fresh convention (accepts a WSG code today; extends to ltree filters, sf polygons, mapsheets later). `setup` is the only outlier: `(conn, schema, overwrite)`.

- [x] `R/lnk_pipeline_setup.R` — create working schema, ensure `fresh` schema
- [x] `R/lnk_pipeline_load.R` — crossings + modelled fixes + PSCIS status overrides. Falls, definite barriers, observation exclusions, habitat classification moved to `prepare` (load stays focused on anthropogenic crossings)
- [x] `R/lnk_pipeline_prepare.R` — loads falls + definite + control + habitat confirms; detects gradient barriers (`frs_break_find`) with control pruning + ltree enrichment; builds natural_barriers; computes barrier overrides via `lnk_barrier_overrides`; per-model non-minimal reduction via `frs_barriers_minimal` (fresh 0.14.0); loads fresh.streams with channel_width + stream_order_parent + GENERATED cols + id_segment. Six internal `@noRd` sub-helpers
- [x] `R/lnk_pipeline_break.R` — builds observations_breaks (species-filtered + exclusions), habitat_endpoints (DRM + URM), crossings_breaks; runs sequential `frs_break_apply` in config-defined order with `id_segment` reassignment between rounds
- [x] `R/lnk_pipeline_classify.R` — builds access-gating `fresh.streams_breaks` (gradient + falls + definite + crossings), calls `frs_habitat_classify` with rules YAML + thresholds + barrier overrides. Species default derives from `cfg$parameters_fresh` ∩ `cfg$wsg_species` presence for the AOI.
- [x] `R/lnk_pipeline_connect.R` — calls fresh's `.frs_run_connectivity` (per-species cluster + connected_waterbody driven by `cfg$parameters_fresh` flags). Fresh internal access flagged as a follow-up (export a stable API in fresh).
- [x] Update existing `data-raw/compare_bcfishpass.R` to call the helpers — verified on ADMS (635 lines → 136 lines, all species within 5%, sub-1% rearing drift from research doc acceptable)
- [ ] Tests + runnable examples for each helper (live-DB tests skip without `.lnk_db_available()`)
- [ ] pkgdown reference entries
- [ ] `/code-check` before each commit
- [ ] PR 1: SRED tag (NewGraphEnvironment/sred-2025-2026#24) — Relates to #38

## PR 2: Add _targets.R + per-partition target fn

- [ ] `data-raw/compare_bcfishpass_wsg.R` — wraps pipeline phases for one WSG, returns ~10-row tibble (wsg × species × habitat_type × km × diff_pct). Name keeps `wsg` because this specific pipeline IS per-WSG (bcfishpass reference is partitioned that way). The generic pipeline helpers it calls are AOI-abstract.
- [ ] Pulls comparison diff against `bcfishpass.*` reference tables on localhost
- [ ] `data-raw/_targets.R` with static `tar_map(wsg = c(...))` over 4 WSGs + `crew_controller_local()`
- [ ] `targets` + `crew` + `tibble` + `dplyr` → DESCRIPTION Suggests (not Imports)
- [ ] Run `tar_make()` — verify numbers match research doc (all species within 5%)
- [ ] Log the run under `data-raw/logs/YYYYMMDD_NN_tar_make-first-run.txt`
- [ ] `/code-check` before each commit
- [ ] PR 2: SRED tag — Relates to #38

## PR 3: Retire old script + regenerate DAG

- [ ] Wire `tar_mermaid()` output into `research/bcfishpass_comparison.md` DAG section (keep glossary + classDef)
- [ ] Delete `data-raw/compare_bcfishpass.R` (git history preserves)
- [ ] Delete `data-raw/compare_adms.R` if redundant
- [ ] Vignette: "Running the comparison pipeline" — `tar_make()`, DAG inspection, rollup
- [ ] Update CLAUDE.md pipeline section — targets-based, not script-based
- [ ] NEWS entry + bump to 0.3.0
- [ ] `/code-check` before each commit
- [ ] PR 3: SRED tag — Fixes #38

## Follow-up (out of scope)

- Distributed execution — swap `crew_controller_local()` for `crew_controller_group(local=M4, cluster=M1)` after rtj Phase 4 passes the M4→M1 SSH exec check
- `configs/default/` variant wired into a second `_targets.R` or CLI arg — tracked via #19/#20/#21 biological decisions

## Follow-up (out of scope for this PR)

- Distributed execution — swap `crew_controller_local()` for `crew_controller_group(local=M4, cluster=M1)` after rtj Phase 4 passes the M4→M1 SSH exec check
- `configs/default/` variant wired into a second `_targets.R` or CLI arg — tracked via #19/#20/#21 biological decisions

## Versions at start

- fresh: 0.14.0
- link: main (0.2.0, target 0.3.0)
- bcfishpass: ea3c5d8
- fwapg: Docker (FWA 20240830)
