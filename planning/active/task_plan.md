# Task: tunnel-free `lnk_compare_mapping_code` + provincial orchestrator for 4-way study-area parity (#175)

Promote the `with_mapping_code` flag to a stand-alone `lnk_compare_mapping_code()` export, made **tunnel-free** (reference = local snapshot `fresh.streams_vw_bcfp`, not the `:63333` bcfp tunnel), then fix the provincial orchestrator (M1-dispatch + post-consolidate cross-WSG recompute) so the 3 study areas (Peace 16 / Fraser 8 / Skeena 5, ~52 drainage-closed WSGs) run correctly 4-way (3 cyphers + M1). Full design: `planning/active/findings.md` + issue #175 (updated 2026-05-24). Relates to SRED NewGraphEnvironment/sred-2025-2026#24.

## Phase 1 — `lnk_compare_mapping_code()` standalone + tunnel-free (reusable core)

- [ ] New export `R/lnk_compare_mapping_code.R`: `lnk_compare_mapping_code(conn, aoi, cfg, reference = "bcfishpass", species = NULL)`. Diff link's `<persist>.streams_mapping_code` (joined to `<persist>.streams` for blk+measure) vs local `fresh.streams_vw_bcfp` on `(blue_line_key, round(downstream_route_measure,1))` per species. Returns `wsg, species, joined, matches, match_pct, n_diffs` + top token-mismatch pairs. Single `conn`, no `conn_ref`.
- [ ] Refactor `.lnk_compare_wsg_mapping_code_diff` (`R/lnk_compare_wsg.R`) to delegate; `reference`-switch keeps the tunnel path available but default tunnel-free.
- [ ] Tests `tests/testthat/test-lnk_compare_mapping_code.R`: SQL-shape (mock conn) + live-DB PARS BT ≈ 98.95% vs the loaded snapshot.
- [ ] `/code-check` + commit.

## Phase 2 — compare-family wiring + back-compat

- [ ] `lnk_compare_wsg(mapping_code = TRUE)` routes through the new export (tunnel-free default); preserve call surface.
- [ ] `data-raw/wsg_compare.R`: tunnel-free mapping_code path; drop mandatory `PG_PASS_SHARE`/`:63333` for it.
- [ ] Tests + `/code-check` + commit.

## Phase 3 — orchestrator: tunnel-free + M1-dispatch + post-consolidate recompute

- [ ] `wsgs_run_pipeline.sh`: drop `:63333` pre-flight + `PG_PASS_SHARE` req; add **Step 9b post-consolidate recompute** (loop `lnk_pipeline_access` + `lnk_mapping_code` over consolidated barriers for all run WSGs, then one `lnk_compare_mapping_code`). Fixes cross-WSG `;DAM` in distributed runs.
- [ ] M1-as-dispatcher: generalize host model in `wsgs_run_pipeline.sh` + `wsgs_dispatch.sh` (drop hardcoded self-`ssh m1`).
- [ ] `wsgs_run_host.R`: cyphers run + persist only — drop per-host tunnel compare.
- [ ] `/code-check` + commit.

## Phase 4 — 4-WSG end-to-end test (mechanics)

- [ ] `wsgs_run_pipeline.sh --wsgs=<4 small WSGs> --cy-workspaces=job1,job2,job3 --mapping-code`: spin → prep → dispatch → consolidate → recompute → tunnel-free compare → burn. Confirm M1 dispatch + new compare path.

## Phase 5 — study-area parity run

- [ ] Run 3 study areas (~52 drainage-closed WSGs; closure + DS-first via `public.wsg_outlet` / `wscode_ltree` ancestry), 3 cyphers + M1. Record per-WSG + per-study-area `match_pct`; surface UNEXPLAINED divergence.

## Phase 6 — docs + release

- [ ] RUNBOOK (tunnel-free compare + orchestrator recompute); NEWS + DESCRIPTION bump; `/planning-archive`; `/gh-pr-push`.

## Validation

- [ ] `devtools::test()` green; Phase 1 live-DB reproduces PARS BT ≈ 98.95% tunnel-free
- [ ] Phase 4 4-WSG run completes spin→…→burn, cyphers torn down clean
- [ ] Phase 5 study-area `match_pct` recorded; PARS shows `;DAM`
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
