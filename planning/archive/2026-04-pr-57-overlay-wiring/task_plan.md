# Task: Call frs_habitat_overlay from lnk_pipeline_classify (link#55)

fresh v0.19.0 ships `frs_habitat_overlay()` (renamed from `frs_habitat_known`) plus a `known = NULL` parameter on `frs_habitat_classify()` that calls overlay automatically. link's pipeline already loads `user_habitat_classification.csv` into `<schema>.user_habitat_classification` via `lnk_pipeline_prepare()` — we just need to pass that table to fresh.

## Goal

Wire `<schema>.user_habitat_classification` into the `frs_habitat_classify()` call inside `lnk_pipeline_classify()` via the new `known` arg. Result: link's pipeline output now matches bcfishpass's `streams_habitat_linear.spawning_sk > 0` (model + known) instead of just `habitat_linear_sk.spawning` (model-only).

Closes the ~60 km BABL SK csv_only gap documented in `research/default_vs_bcfishpass.md` §6/§7.

## Phases

- [ ] Phase 1 — PWF baseline
- [ ] Phase 2 — Bump link DESCRIPTION → fresh (>= 0.19.0)
- [ ] Phase 3 — Install fresh 0.19.0 on m4 + m1
- [ ] Phase 4 — Wire `known = paste0(schema, ".user_habitat_classification")` into the `frs_habitat_classify()` call inside `R/lnk_pipeline_classify.R`. Gate on table existence (matches the pattern already in `lnk_pipeline_prepare`).
- [ ] Phase 5 — Pre-flight ADMS (single WSG, both bundles). Verify Shass Creek now shows as SK spawning under bcfishpass bundle. Frame against bcfp departures.
- [ ] Phase 6 — Full 5-WSG rerun via rtj harness. Verify BABL SK spawning under bcfishpass bundle rises from ~57.6 km toward ~132 km.
- [ ] Phase 7 — Refresh research doc per-WSG tables + observation §6
- [ ] Phase 8 — NEWS entry + version bump → 0.9.0
- [ ] Phase 9 — Mocked unit tests on the wiring
- [ ] Phase 10 — `/code-check` on the diff
- [ ] Phase 11 — Full link suite via rtj harness
- [ ] Phase 12 — PR, fix link#55

## Critical files

- `R/lnk_pipeline_classify.R`
- `DESCRIPTION`
- `NEWS.md`
- `research/default_vs_bcfishpass.md`

## Acceptance

- ADMS preflight: bcfishpass-bundle SK spawning rises from 88.83 → ~132 km. Shass Creek shows non-zero spawning km.
- 5-WSG rerun completes clean (~20 min).
- Research doc tables refreshed.
- `default_catches_known` bucket non-zero in §6.

## Risks

- **Reproducibility regression** vs v3-v6 expected (the whole point — outputs change).
- **Performance:** ~40 UPDATEs per WSG (9-11 species × 4 habitat types). Should be fast.
- **Schema column mismatch:** `user_habitat_classification` loaded by link must have `(blue_line_key, downstream_route_measure)` for the default `by` join key.
