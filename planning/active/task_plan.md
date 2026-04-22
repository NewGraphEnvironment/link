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
- [ ] `R/lnk_pipeline_load.R` — crossings + overrides + barrier skip list (wraps `lnk_load`, `lnk_override`, `lnk_barrier_overrides`)
- [ ] `R/lnk_pipeline_prepare.R` — gradient barriers + non-minimal reduction (`frs_barriers_minimal`) + base segments load
- [ ] `R/lnk_pipeline_break.R` — sequential `frs_break_apply` over break sources in config-defined order
- [ ] `R/lnk_pipeline_classify.R` — `frs_habitat_classify` with rules YAML
- [ ] `R/lnk_pipeline_connect.R` — `frs_cluster` + `frs_connected_waterbody`
- [ ] Update existing `data-raw/compare_bcfishpass.R` to call the helpers — verify identical output on ADMS/BULK (sub-basin if faster)
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
