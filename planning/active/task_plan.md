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

- [x] `data-raw/compare_bcfishpass_wsg.R` — wraps pipeline phases for one WSG, returns ~10-row tibble (wsg × species × habitat_type × link_km × bcfishpass_km × diff_pct). Creates own conn + conn_ref with fail-early on missing `PG_PASS_SHARE`, registers on.exit cleanup per-conn (no leak on second conn failure), cleans up on exit. Defensive drop of `fresh.streams*` at entry.
- [x] Pulls comparison diff against `bcfishpass.habitat_linear_*` reference over tunnel. All interpolated strings go through `DBI::dbQuoteLiteral`.
- [x] `data-raw/_targets.R` with static `tar_map(wsg = c("ADMS","BULK","BABL","ELKR"))` + synchronous execution (crew removed after the controller hung on dispatched-but-never-complete behavior; shared `fresh.streams` prevents parallel anyway).
- [x] `targets` + `tarchetypes` + `tibble` + `dplyr` → DESCRIPTION Suggests (crew dropped).
- [x] **Promote `.lnk_pipeline_classify_species` → exported `lnk_pipeline_species(cfg, aoi)`** — canonical public helper for "species this config classifies in this AOI". Used by classify + connect internally and by data-raw externally. Removes both the duplicated private helper and the inlined `.wsg_species_present` from data-raw.
- [x] Run `tar_make()` end-to-end on all 4 WSGs. Rollup = 34 rows, all within 5% of bcfishpass. Reproducibility check: runs 10 + 11 produced bit-identical rollup tibbles.
- [x] Log the run under `data-raw/logs/20260422_10_tar_make_from_dataraw.txt` + `20260422_11_tar_make_final.txt` (plus `20260422_12_*` post-fix re-verify).
- [x] `/code-check` before commit — found a real conn leak (second dbConnect could throw before on.exit registered) and a SQL quoting inconsistency on species; both fixed and re-verified.
- [x] **Correctness framing** — reframed verification from "within 5% of bcfishpass" to "bit-identical across repeated runs". Added section to CLAUDE.md + memory entry. Confirmed across three runs (10, 11, 12) — all 34 rollup rows identical.
- [ ] PR 2: SRED tag — Relates to #38

## PR 3: Retire old script + research doc refresh + vignette

- [x] `tar_mermaid()` reviewed — output is hashed-ID orchestration graph, poor replacement for the hand-written pipeline-phase DAG. Kept the pipeline DAG in `research/bcfishpass_comparison.md`; added a small "Targets orchestration" Mermaid showing cfg → 4 WSGs → rollup.
- [x] Research doc refreshed with 2026-04-22 rollup numbers (was 2026-04-15) + reproducibility framing at top.
- [x] Delete `data-raw/compare_bcfishpass.R` — superseded by `_targets.R` + `compare_bcfishpass_wsg.R`. Git history preserves.
- [x] Vignette `vignettes/reproducing-bcfishpass.Rmd` — narrative, three-line entrypoint, rollup table, BULK CH habitat mapgl map, reproducibility note, pointers to future default-variant vignette.
- [x] `data-raw/vignette_reproducing_bcfishpass.R` — pre-computes `rollup.rds` + `bulk_ch.rds` into `inst/extdata/vignette-data/` so the vignette doesn't hit the DB at build time. CLAUDE.md vignette convention.
- [x] `mapgl`, `sf` added to DESCRIPTION Suggests.
- [x] NEWS entry + bump to 0.5.0.
- [ ] `/code-check` before commit
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
