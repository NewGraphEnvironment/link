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

## Phase 3a — consolidate/persist shape-tolerance (3-WSG smoke fixes, #204)

- [x] `data-raw/schema_consolidate.R`: shape-tolerant COPY — enumerate columns on both hosts, COPY the shared set **by name** in dest ordinal order (was positional `SELECT *` → `FROM STDIN`, which broke on any species-column-count drift). Host- and species-count-agnostic; nothing hardcoded. Sibling to #185.
- [x] `data-raw/cypher_prep.sh`: align persist species to `cfg$species` (matches `lnk_pipeline_run` R/lnk_pipeline_run.R:157), not `parameters_fresh` (11 sp incl CT/DV/RB). Removes the cross-host wide-table drift at source.
- [x] Filed #204 (persist_init blind to species-column-set drift; abstract/no-hardcode north star). `/code-check` clean (round 1 — 0 findings).

## Phase 3 — orchestrator: REVISED 2026-05-25 (reuse smoke flow, NOT old-orchestrator refactor)

**Decision (user steer "are these already dealt with in our start-to-finish scripts?"):** the 3-WSG smoke already proved an M1-dispatch, tunnel-free, abstract flow that BYPASSES the old M4-centric `wsgs_run_pipeline.sh`/`wsgs_dispatch.sh`/`wsgs_run_host.R`. Those carry M4/tunnel baggage and are NOT being refactored. Discarded the Plan-agent's 30-edit refactor.

The proven flow = `cypher_up.sh` → `cypher_prep.sh` → per-host `lnk_pipeline_run(aoi=WSG, mapping_code=TRUE)` (local, no tunnel, no M4) → `schema_consolidate(sources=list({host,via,bucket}))` (shape-tolerant) → `wsg_compare_mapping_code(wsg,cfg)` (tunnel-free) → `cypher_down.sh`.

- [x] ~~Cross-WSG `;DAM` solved WITHOUT recompute~~ **CORRECTED 2026-05-25: drainage-closed + DS-first is NOT sufficient.** It reduces but doesn't eliminate cross-WSG access gaps — downstream barriers can be cross-bucket or arrive late in DS-first order. Full run showed FINA 75.5% / PARA 68.6% per-host → 99%+ only after re-modelling on the full consolidated barrier set. **A POST-CONSOLIDATE RECOMPUTE is required** (see Phase 5 + #205). Drainage-closed bucketing is now just a speed knob (less divergence → less recompute), not a correctness lever.
- [x] Built 4 lean reusable scripts (reuse existing cypher_up/prep/down + schema_consolidate + lnk_pipeline_run + wsg_compare_mapping_code):
  - `data-raw/study_area_wsgs.R` — closure + DS-first list via `public.wsg_outlet`.
  - `data-raw/wsg_run_one.R` — `lnk_pipeline_run(mapping_code=TRUE)` for one WSG, local, host-agnostic (`LNK_LOAD=loadall` dispatcher / `library(link)` cyphers).
  - `data-raw/study_area_compare.R` — tunnel-free `wsg_compare_mapping_code` loop → CSV.
  - `data-raw/study_area_run.sh` — driver: pre-flight (tunnel-free) → spin → prep → run DS-first buckets (dispatcher local + cyphers) → consolidate cyphers→dispatcher → BURN (minimise idle) → compare → CSV. trap-EXIT burn safety net.
- [x] `/code-check` (1 fresh-eyes round): fixed burn-verification pipefail (`|| n="?"`), added bucket-overlap warning; accepted empty-array idiom (M1 bash 5.3). Committed.

## Phase 4 — end-to-end mechanics (lean flow)

- [x] Stage A (dispatcher-only PARS, $0): driver + tunnel-free pre-flight + DS-first + compare validated; PARS `ACCESS;DAM;INTERMITTENT`.
- [x] Full 3-area run (fullrun4, 50 WSGs, M1+2cy): spin → prep → run → consolidate (incl wide tables, #204 fix validated) → burn clean → compare. Caught the prep-race (#583a4ab), branch-on-cyphers (#7e96b10), data-loss-via-trap-burn (→ species filter #157 + soft-fail, 65d26ca).

## Phase 5 — study-area parity run + the recompute finding

- [x] **Authoritative parity obtained** (post-recompute, all 50 WSGs on M1): **median 99.66%, mean 99.11%**, 130/148 rows ≥99%. Genuine divergences (recompute-stable → taxonomy): SETN salmon ~94%, UNRS BT 61.8%.
- [x] **Methodology finding:** post-consolidate recompute REQUIRED (drainage-closed insufficient). Driver does it (recompute diverged WSGs <99% via full pipeline, then re-compare). Filed **#205** — the full-pipeline recompute is ~2× on diverged WSGs (re-runs streams/habitat to redo cheap access); the cheap access-only recompute (reuse persisted streams/habitat) makes recompute-ALL bulletproof + ~1×.
- [x] **DECIDED: build #205** (cheap recompute) → Phase 7 below. Then one clean driver-automated run that's both validated AND fast.
- [ ] Annotate SETN/UNRS via `research/bcfp_divergence_taxonomy.yml` (lnk_parity_annotate).

## Phase 6 — docs + release

- [x] `research/study_area_run.md` (lean flow + recompute methodology + gotchas); `data-raw/README.md` driver entry; memory.
- [ ] `research/provincial_parity_2026_05_25.md` (authoritative numbers — written this compact-prep).
- [ ] RUNBOOK (recompute step); NEWS + DESCRIPTION bump; `/planning-archive`; `/gh-pr-push` (after #205 + clean run).

## Phase 7 — #205 cheap access-only recompute (the efficiency keystone)

Plan: `~/.claude/plans/atomic-conjuring-tome.md`. Pre-flight DONE (PSCIS in persist barriers ✓; preservable phase-1 cols ✓). Builds on this `175-` branch.

- [ ] **7a.** New export `R/lnk_access.R` — `lnk_access(conn, cfg, aoi, table_streams, table_barriers, table_to, merge=FALSE, presence=NULL, species=NULL)`. Portable access builder (twin of `lnk_mapping_code`, `@family compare`, `table_<role>` params). Builds per-species `_access` + source views internally via `lnk_barriers_views(barriers_table=table_barriers)`; runs `lnk_pipeline_access` (observations=NULL, crossings=NULL) → scratch. `merge=FALSE` overwrite; `merge=TRUE` surgical UPDATE on `(id_segment, watershed_group_code)`: SET cross-WSG cols (`has_barriers_*`, `dam_dnstr_ind`), PRESERVE `remediated_dnstr_ind`, `access_<sp>` = 0-if-blocked / keep-2 / else-1. `devtools::document()`.
- [ ] **7b.** `data-raw/wsg_recompute_one.R` (sibling of `wsg_run_one.R`): `lnk_access(merge=TRUE, table_to=<persist>.streams_access)` + `lnk_mapping_code` (→ `<persist>.streams_mapping_code` via scratch + DELETE/INSERT). Wire `study_area_run.sh` recompute block to call it; switch to recompute-ALL (cheap); `--recompute=all|diverged` (default all). Docs: `research/study_area_run.md` past-tense #205, `RUNBOOK.md` §5.
- [ ] **7c.** `tests/testthat/test-lnk_access.R` (arg-val + gated DB). M1 validation: `wsg_recompute_one.R FINA/PARA` reproduces full-pipeline recompute (FINA 99.8% / PARA 99.3%) via `lnk_compare_mapping_code`, in seconds; REMEDIATED preserved; `;DAM` present.
- [ ] `/code-check` + commit per sub-phase.

## Validation

- [ ] `devtools::test()` green; Phase 1 live-DB reproduces PARS BT ≈ 98.95% tunnel-free
- [ ] #205: `lnk_access(merge=TRUE)` recompute reproduces full-pipeline numbers in ~seconds
- [ ] Phase 4 4-WSG run completes spin→…→burn, cyphers torn down clean
- [ ] Phase 5 study-area `match_pct` recorded; PARS shows `;DAM`
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
