## Checklist read

- `code-check.md` (329 KB): the prose of every H3 under `## Mechanisms`, all 14 (table rows skipped). Rules that stand alone, Security and Spreadsheets/PDFs not read: no heading there names a tool or pattern this diff uses.
- `code-check-r.md` (175 KB): 16 headings read in full: Postgres row order; `sprintf("%g")` Inf/NA into SQL; `information_schema` literal-name lookup; `$` partial match; yaml mixed int/float; `identical()` on two reader results; `sort()`/`order()` and `LC_COLLATE`; `match()` and NA; `function(...)` mock; `data-raw/` must load the source tree; `nzchar(NA)`; `ifelse()` all-NA; `::text` spelling; DBI driver values; dplyr column masking; `paste()` zero-length. The other ~110 headings were not read.
- `code-check-shell.md` (121 KB): no headings read. The diff changes no shell, psql or git script.
- `code-check-spatial.md` (154 KB): 1 heading read ("FWA main flow is not edge type 1000 alone"); about 95 not read. The diff uses no terra, sf, GDAL or bcdata.

Ran in a copy (`scratchpad/linkcopy`, NOT_CRAN=true): test-lnk_rules_build, _discharge, _pipeline_persist, _habitat_validate, _pipeline_classify, _preflight_fresh, _config, _log and _persist_init. All 0 failed, 0 error. I rebuilt the rules for default, default_tuned and bcfishpass from their own dims and thresholds through the harness's write.csv round trip. Each parses identical to its committed rules.yaml, so fix 4 gives a ladder on those bases its own rules only when a baked cell moves. The frozen default_extrabreaks and default_rearbreaks bundles differ only by inert `near_river: false` stamps.

## Findings

- **[fragile]** `R/lnk_pipeline_persist.R:233-239`: the pair-scoped DELETE (round-1 fix 2) reads which pairs to replace from the rows the walk returned, not from the pairs it walked.
  - `fresh::frs_near_river()` writes a row only for a segment that found a river (fresh `R/frs_near_river.R`: "gets no row"). So a pair walked in this WSG with zero hits contributes nothing to `SELECT DISTINCT measure, threshold, distance_max FROM <working>.streams_habitat_near_river`.
  - The earlier build's rows for that WSG and pair are then kept. They are keyed by `id_segment`, which a re-model can reassign.
  - The validator passes `<schema>.streams_near_river` to `frs_habitat_predicates()` (`R/lnk_habitat_validate.R`, `.lnk_hv_check_schema()`), so the predicate reads those stale distances. The log check passes, because the logged pairs still equal cfg's. The result is false "persisted FALSE, predicate TRUE" disagreements, or misses masked.
  - The removed always-DELETE covered this case; the fix moved the defect one axis over.
  - When it happens: the same pair goes from some hits to none in a WSG, for example after channel_width or discharge inputs change, or a group with no `mad_m3s` under a discharge-measured pair.
  - Reproduced in scratch schemas `zzcr2_p` / `zzcr2_w` (dropped afterwards): an empty working table, after the DELETE and INSERT, leaves both earlier rows in place.
  - Fix: build the DELETE's pair set from the pairs classify was asked to walk, i.e. `.lnk_near_river_pairs()` / fresh's `.frs_near_river_specs()` for the species and size model persisted (as VALUES), not from the walk's output.
- **[fragile]** `data-raw/habitat_variants_score.R:322-333`: the new `rules_sha256` / `dimensions_sha256` check accepts NA when `variants$dims` is NA.
  - Since round-1 fix 4, a variant without dims can carry its own rules.yaml: a baked `rear_lake_ha_min`, or `rear_gradient_max` on a `gradient` door (bcfishpass CO).
  - `write_bundle()` rewrites the bundle at the start of `run_variant()`. A rebuild that stops partway therefore leaves the bundle on its own rules while built.csv still holds NA rows for WSGs that were classified on the base's rules. The score accepts those rows.
  - The thresholds sha check cannot catch this, because the thresholds did not change.
  - Fix: accept NA only where the bundle's `rules` / `dimensions` resolve to the base's files, e.g. `normalizePath(cfgs[[v]][[k]]) == normalizePath(cfgs[[base_variant]][[k]])`, rather than where `dims` is empty.

The other round-1 fixes check out:
- Fix 1 (radix sort) is correct.
- Fix 3 (the builder stops) refuses no shipped bundle: default, default_tuned and bcfishpass all build. The categories, all-edges and no_fw / lake_only stops fire only on the combinations they name.
- The rest of the diff (log column, persist DDL, classify's DROP before the walk, preflight formals, validator log check, harness ANALYZE) found nothing that fails.
