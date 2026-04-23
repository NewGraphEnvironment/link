# Progress

## Session 2026-04-22

- Archived lnk_config PWF (shipped as link 0.2.0 via PR #39)
- Starting link#38: `_targets.R` pipeline
- Dependencies cleared: fresh 0.14.0 (frs_barriers_minimal) and link 0.2.0 (lnk_config) are on main
- rtj data parity on M4 + M1 confirmed; R install on M1 (Phase 3) still pending but not blocking — single-host first
- Issue #38 updated with package-vs-pipeline split (helpers in `R/`, `_targets.R` + comparison in `data-raw/`)
- PR 1 Phase 1.1 done: `lnk_pipeline_setup()` (originally `lnk_habitat_setup_schema`, renamed before building more). Mocked tests for SQL shape + identifier validation (8 passing). Live DB test intentionally skipped — CREATE SCHEMA semantics are Postgres's, not ours to test.
- Naming decision: prefix is `lnk_pipeline_*` (not `lnk_habitat_*` — only 1 of 6 phases is actually about habitat). Phase names read as verbs: setup → load → prepare → break → classify → connect.
- Param decision: canonical `(conn, aoi, cfg, schema)`. `aoi` follows fresh convention — accepts a WSG code today; extends to ltree filters, sf polygons, mapsheets later. `setup` is the only outlier: `(conn, schema, overwrite)`.
- PR 1 Phase 1.2 done: `lnk_pipeline_load()` — loads crossings + misc crossings + applies modelled fixes (NONE/OBS → PASSABLE) + PSCIS barrier status overrides. Split into three internal `@noRd` helpers for readability. Cleaner scope than the original "load_inputs" plan: falls, definite barriers, observation exclusions, and habitat classification moved to `prepare` where they're actually consumed. 12 tests (4 input validation + 4 fixes SQL/branching + 1 apply_pscis branching + 3 structure). 169 link tests total.
- PR 1 Phase 1.3 done: `lnk_pipeline_prepare()` — thin orchestrator over 6 internal sub-helpers (prep_load_aux, prep_gradient, prep_natural, prep_overrides, prep_minimal, prep_network). First real consumer of `frs_barriers_minimal()` from fresh 0.14.0. `.lnk_quote_literal()` added to utils.R for safe SQL literal interpolation. 31 new tests (input validation + SQL shape + 4 model minimal reductions + union). Full link suite at 200 passing.
- Code-check found one genuine architectural concern for PR 2: `fresh.streams` is a shared schema, parallel WSG runs on one host would collide. Noted in findings.md with three mitigation options (leaning toward `workers = 1` for initial PR 2).
- PR 1 Phase 1.4 done: `lnk_pipeline_break()` — builds observations_breaks (species-filtered via `cfg$wsg_species` + data-error exclusions), habitat_endpoints (DRM + URM union), crossings_breaks, then sequential `frs_break_apply` respecting `cfg$pipeline$break_order` with `id_segment` reassignment between rounds. Four internal `@noRd` sub-helpers. 13 new tests (input validation + obs species derivation incl. CT expansion + SQL shape per branch + break_order honored). Full link suite at 229 passing.
- PR 1 Phase 1.5/1.6 done: `lnk_pipeline_classify()` + `lnk_pipeline_connect()` — classify builds `fresh.streams_breaks` (gradient FULL + falls + definite + crossings, WSG-filtered) then calls `frs_habitat_classify()` with rules YAML + barrier overrides. Connect wraps fresh's `.frs_run_connectivity` for per-species cluster + connected_waterbody. Both auto-derive species from `cfg$parameters_fresh` ∩ `cfg$wsg_species` presence for the AOI; both accept explicit `species =` override. 22 tests covering input validation, species derivation, access-gating breaks SQL shape, no-species error. Full link suite at 251 passing.
- **All six pipeline helpers complete.**
- PR 1 Phase 1.7 done: compare_bcfishpass.R rewritten from 635 lines to 136 lines using the six helpers. ADMS run 67s end-to-end, all species within 5%, spawning values identical to research doc, rearing within ~1% (acceptable ordering variance from id_segment tie-breaking).
- Fix along the way: added `cfg$species` (parsed from rules YAML at load) so `lnk_pipeline_classify_species` intersects against rules species (8) instead of parameters_fresh species (11). parameters_fresh has CT/DV/RB which bcfishpass doesn't model. Also added `barriers_definite` to `config.yaml` `break_order` (was missing).
- PR 1 ready to close. Remaining: NEWS/DESCRIPTION bump, final `/code-check`, PR with SRED tag.
- PR 1 MERGED as link 0.3.0 (PR #41). Branch deleted.

## PR 2 kickoff

- Branched `38-targets-pipeline-pr2` off main.
- Wrote `data-raw/compare_bcfishpass_wsg(wsg, config)` — wraps the six phase helpers for one WSG, returns a small tibble (wsg × species × habitat_type × link_km × bcfishpass_km × diff_pct). KB-scale return — no geometry, ships cleanly over SSH when distributed.
- Wrote `data-raw/_targets.R` — `tar_map(wsg = 4 WSGs)` over the per-WSG target, `crew_controller_local(workers = 1)`, rollup target binds all four tibbles. Serial because `fresh.streams` is a shared schema across workers on the same host (findings.md).
- Added `targets` / `crew` / `tibble` / `dplyr` to DESCRIPTION Suggests.
- Drift lesson from PR 1 → Issue #40 filed (CSV provenance + runtime stamps). Scope expands `lnk_stamp` (#24) into the lineage source.
- Next: `/code-check` on PR 2 staged diff, then `tar_make()` end-to-end, commit stamped verification log.
- Reframing (per user): the correctness bar is **bit-identical output from the same inputs**, not "within 5% of bcfishpass." The 5% comparison is parity diagnostics only. Saved to memory (`feedback_reproducibility.md`) + CLAUDE.md. Research-doc drift from earlier today (BT rearing -0.7 → -1.1) is env-state drift, not pipeline non-determinism — to be traceable once stamps/lineage ship (#40).
- tar_make end-to-end done. Three successive runs (10, 11, 12) produced bit-identical 34-row rollup tibbles — reproducibility proven. Wall clock ~8m 30s per run (serial).
- Promoted `.lnk_pipeline_classify_species` → exported `lnk_pipeline_species(cfg, aoi)` to remove duplication with the data-raw inline helper. Tests moved to `test-lnk_pipeline_species.R`. classify + connect internals updated. Compare wrapper uses `link::lnk_pipeline_species()`.
- Code-check surfaced a real connection leak (second `dbConnect` could throw before `on.exit` registered) and SQL quoting inconsistency on species list. Both fixed; 12th run confirms numbers unchanged.
- DESCRIPTION bumped to 0.4.0. NEWS entry captures the reproducibility + parity distinction. Committing and pushing PR 2 next.
