# Task Plan: _targets.R pipeline (#38)

## Goal

Replace the 635-line `data-raw/compare_bcfishpass.R` script with a targets-driven pipeline that:
- Runs each DAG node as a `tar_target()` — inspectable, cacheable, skippable
- Parallelizes across watershed groups via `tar_map(wsg = c(...))`
- Regenerates the research doc DAG from `tar_mermaid()`
- Single-host on M4 first; distributed swap to `crew_controller_group(local=M4, cluster=M1)` is a follow-up after rtj Phase 4

Uses `lnk_config("bcfishpass")` (shipped in 0.2.0) and `frs_barriers_minimal()` (fresh 0.14.0).

## Phase 1: Extract helpers from compare_bcfishpass.R

Break the 635-line script into small named functions (one per pipeline phase). Each takes `(conn, wsg, cfg, schema)` and writes to the worker's localhost DB.

- [ ] `R/lnk_habitat_setup_schema.R` — create `working_<wsg>` schema, ensure `fresh` schema
- [ ] `R/lnk_habitat_load_inputs.R` — crossings + overrides + barrier skip list (wraps `lnk_load`, `lnk_override`, `lnk_barrier_overrides`)
- [ ] `R/lnk_habitat_build_network.R` — gradient barriers + non-minimal reduction (`frs_barriers_minimal`) + base segments load
- [ ] `R/lnk_habitat_break_segments.R` — sequential `frs_break_apply` over break sources in config-defined order
- [ ] `R/lnk_habitat_classify.R` — `frs_habitat_classify` with rules YAML
- [ ] `R/lnk_habitat_cluster.R` — `frs_cluster` + `frs_connected_waterbody`
- [ ] Each helper has a roxygen docstring, `@noRd` for internal or `@export` if useful standalone
- [ ] Unit tests where behavior can be stubbed (most are integration-heavy; live DB tests with `skip_if_not(.lnk_db_available(), ...)`)

## Phase 2: Per-WSG target function

- [ ] `R/compare_bcfishpass_wsg.R` — wraps phases, returns small tibble (wsg × species × habitat_type × km × diff_pct)
- [ ] Pulls comparison diff against `bcfishpass.*` reference tables on localhost
- [ ] Returns ~10 rows per WSG — KB-scale only, no geometry
- [ ] Cleans up own schema on exit (namespacing `working_<wsg>` per rtj contract)

## Phase 3: _targets.R orchestrator

- [ ] `_targets.R` at repo root with single-host `crew_controller_local()`
- [ ] `tar_target(cfg, lnk_config("bcfishpass"))` — load config once
- [ ] `tar_map(values = tibble(wsg = c("ADMS", "BULK", "BABL", "ELKR")))` — per-WSG branch
- [ ] `tar_target(rollup, ...)` — bind all WSG tibbles
- [ ] `tar_target(dag_mermaid, writeLines(tar_mermaid(...), ...))` — regenerate research doc DAG
- [ ] `targets` + `crew` + `tibble` + `dplyr` added to DESCRIPTION Suggests (not Imports — these are pipeline-dev deps, not user-facing)

## Phase 4: Verify identical output

- [ ] `tar_make()` runs all 4 WSGs on M4 localhost
- [ ] Rollup tibble numbers match the research doc (every species within 5%)
- [ ] Log the run under `data-raw/logs/YYYYMMDD_NN_tar_make-first-run.txt`

## Phase 5: Regenerate research doc DAG

- [ ] Write `tar_mermaid()` output into `research/bcfishpass_comparison.md` DAG section
- [ ] Keep the glossary + classDef color-coding for human readability
- [ ] Verify it still renders cleanly in VS Code preview + GitHub

## Phase 6: Retire compare_bcfishpass.R

- [ ] Delete `data-raw/compare_bcfishpass.R` once verified (git history preserves)
- [ ] `data-raw/compare_adms.R` — probably also retires, check for uniqueness
- [ ] Update CLAUDE.md pipeline section — targets not script

## Phase 7: Docs + release

- [ ] Vignette: "Running the comparison pipeline" — `tar_make()`, DAG inspection, rollup
- [ ] `NEWS.md` entry
- [ ] Bump to 0.3.0
- [ ] `/code-check` on staged diffs before each commit
- [ ] PR with SRED tag (NewGraphEnvironment/sred-2025-2026#24) — Fixes #38

## Follow-up (out of scope for this PR)

- Distributed execution — swap `crew_controller_local()` for `crew_controller_group(local=M4, cluster=M1)` after rtj Phase 4 passes the M4→M1 SSH exec check
- `configs/default/` variant wired into a second `_targets.R` or CLI arg — tracked via #19/#20/#21 biological decisions

## Versions at start

- fresh: 0.14.0
- link: main (0.2.0, target 0.3.0)
- bcfishpass: ea3c5d8
- fwapg: Docker (FWA 20240830)
