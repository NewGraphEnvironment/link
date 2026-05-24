# Task: tunnel-free `lnk_compare_mapping_code` + provincial orchestrator for 4-way study-area parity (#175)

Promote the `with_mapping_code` flag to a stand-alone `lnk_compare_mapping_code()` export, made **tunnel-free** (reference = local snapshot `fresh.streams_vw_bcfp`, not the `:63333` bcfp tunnel), then fix the provincial orchestrator (M1-dispatch + post-consolidate cross-WSG recompute) so the 3 study areas (Peace 16 / Fraser 8 / Skeena 5, ~52 drainage-closed WSGs) run correctly 4-way (3 cyphers + M1). Full design: `planning/active/findings.md` + issue #175 (updated 2026-05-24). Relates to SRED NewGraphEnvironment/sred-2025-2026#24.

## Phase 1 — `lnk_compare_mapping_code()` standalone + tunnel-free (reusable core)

- [x] New export `R/lnk_compare_mapping_code.R`: tunnel-free (reference = local `fresh.streams_vw_bcfp`, `conn_ref=NULL` default; tunnel path kept for back-compat). Joins `<persist>.streams_mapping_code` → `<persist>.streams` on the **full PK** `(id_segment, watershed_group_code)`, diffs vs the snapshot on `(blue_line_key, round(measure,3))` per **WSG-active** species. Returns `wsg, species, total_segs, match_pct, n_diffs, top_pattern, top_pattern_count`.
- [x] Refactor `.lnk_compare_wsg_mapping_code_diff` → delegates; shared merge/match in `.lnk_mc_diff`.
- [x] Tests: `test-lnk_compare_mapping_code.R` (arg-val + `.lnk_mc_diff` compose + live PARS BT) + adapted the moved test in `test-lnk_compare_wsg.R`. 93 compare tests pass; **live PARS BT 98.95% tunnel-free**.
- [x] **Bug caught + fixed:** `id_segment` is per-WSG (not globally unique; 80,555 distinct / 1.5M rows → ~22× cartesian on `id_segment`-alone persist joins). Fixed `lnk_compare_rollup`'s 3 joins to full PK (PARS BT spawning_km 36,820 → 1,681). Added WSG-active species resolution (avoids spurious 0% for absent species). Filed root issue **#203** (position-derived globally-unique `id_segment`, bcfp-style).
- [ ] `/code-check` + commit.

## Phase 2 — compare-family wiring + back-compat

- [x] `lnk_compare_wsg(mapping_code = TRUE)` routes through `lnk_compare_mapping_code` tunnel-free (no `conn_ref` for the mapping_code lens; rollup still uses the tunnel — snapshot lacks `habitat_linear`). Removed dead `.lnk_compare_wsg_mapping_code_diff` helper; fixed the `lnk_mapping_code` doc ref.
- [x] `data-raw/wsg_compare.R`: added `wsg_compare_mapping_code()` — tunnel-free (local conn only, no `PG_PASS_SHARE`/`:63333`). The dispatcher's post-consolidate compare entry.
- [x] Tests: repointed `lnk_compare_wsg` composition test to mock `lnk_compare_mapping_code`; 93 compare pass / 1216 total (lone FAIL = env db_conn). Live `wsg_compare_mapping_code("PARS")` = 98.95% with `PG_PASS_SHARE` unset.
- [ ] `/code-check` + commit.

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
