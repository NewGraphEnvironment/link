# Code-check round 1 — branch 432-turn-species-off-in-a-bundle-s-runs-with (diff vs 2a5d8811)

## Checklist read

- code-check.md (334,881 bytes): the prose of every H3 under `## Mechanisms`, table rows skipped (all 14: A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice). "Rules that stand alone", Security and Spreadsheets sections not read.
- code-check-r.md (190,768 bytes): read 7 sections — "An `information_schema` lookup by the literal table name misses what Postgres resolves"; "Postgres row order is never fixed unless the query fixes it, ..."; "`paste()` with a zero-length argument returns length ONE, not zero"; "CSV whitespace: `trim_ws` and `strip.white` do not do what the name suggests"; "`sprintf("%g", x)` writes `Inf` and `NA` into SQL as bare words, ..."; "A value compared as `::text` in SQL has PostgreSQL's spelling, not R's"; "Rscript reads a script as it runs, ...". Not read: the remaining ~110 sections (index lines only).
- code-check-shell.md (132,401 bytes): index only; the diff's shell content is one new evidence script (data-raw/logs/species_paused_432/arm.sh) and no driver changes. 0 sections read in full.
- code-check-spatial.md (156,392 bytes): index only; no spatial code in the diff. 0 sections read in full.

## What was checked (no defect found)

- `.lnk_species_modelled()`: every refusal path; `files$species_modelled$path` NULL path; order preserved (`setdiff(rules_species, paused)`); checksum/shape of species_modelled.csv verified with `lnk_config_verify()` for default and default_tuned (no drift); dictionary consumed_by lines 446/463/470/475 point at the reading lines.
- Zero-length handling on every new empty-species path: `lnk_access()` (lapply not paste0; `has_barriers__dnstr` / `access_` phantoms removed by the `intersect(..., scratch_cols)`; merge SET clause still non-empty from the per-source flags), `.lnk_cols_streams_*_per_sp()`, `lnk_barriers_views()`, `lnk_pipeline_access()` (empty named list; presence vapply over character(0)), `wsg_recompute_one.R` prior table guard, `.lnk_mapping_code_persist()` base-row path (base columns are only the PK pair), `.lnk_log_arr()` writes `ARRAY[]::text[]`, `.lnk_pg_array()` reads `{}`.
- `.lnk_near_river_pairs(species = character(0))` returns 0 rows (probed in a worktree), so a paused-only group's clear deletes all of the group's near-river rows; working near-river cannot be stale because `lnk_pipeline_setup(overwrite = TRUE)` drops the working schema first.
- `.lnk_persist_clear_unmodelled()`: LIKE/ESCAPE literal under standard_conforming_strings; `^[a-z]+$` filter excludes `streams_habitat_near_river` and the long view; read-only probe of local `fresh` / `fresh_default` shows only species tables match. Callers of `lnk_pipeline_run()` (variants base, compare_wsg, wsg_run_one, wsg_pipeline_run) all pass a full-bundle cfg; nothing narrows `cfg$species` before a run.
- Consolidate (`schema_consolidate.R`) deletes the bucket from every table both sides hold, and `lnk_persist_init()` now unions `cfg$species_paused` on every host (dispatcher init, cypher_prep.sh, worker_prep.sh, variants), so the RUNBOOK claim that consolidate clears paused tables holds.
- `study_area_verify.sql` new block: `substr(..., 17)` is right for `streams_habitat_`; `$2` upper-case matches `log.species`; paused-only groups log `{}` and are judged; NULL lists skipped as stated.
- Province resolve: `lnk_wsg_resolve()` over default still gives 241 groups, and the paused-only set is BRID, GRNL, LEUT, LNRS, MURT, PITR, UISR (probed), matching the RUNBOOK.
- Vocabulary: default and default_tuned resolve to acc-v5; bcfishpass unchanged at acc-bcfp-4 (default_extrabreaks / default_rearbreaks fail on their cut token, pre-existing and unrelated).

## Clean
No issues found.
