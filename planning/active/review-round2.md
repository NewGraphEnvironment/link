# Code-check round 2: #432 branch (merge-base 2a5d8811..dbab92f0)

## Checklist read

- code-check-r.md (115 headings): read in full "`paste()` with a zero-length argument returns length ONE, not zero"; "A `function(...)` mock hides arguments the real callee no longer accepts"; "An `information_schema` lookup by the literal table name misses what Postgres resolves"; "CSV whitespace: `trim_ws` and `strip.white` do not do what the name suggests"; "`$` on a list partial-matches, so a longer sibling key answers for a missing one". 110 not read (index lines only).
- code-check.md (37 headings): read the prose of the `## Mechanisms` H3s "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output", "A guard's scope, escape hatches, and remedies", "A fix lands in one of two callers that share a harness", "Restore the bug and prove the guard fires"; the remaining Mechanisms H3s and the stand-alone rules from their index lines only. About 30 not read in full.
- code-check-shell.md (70 headings): none read in full (the shell/SQL in the diff is psql PL/pgSQL `format()`/`EXECUTE`, no shell idiom from the index applies). 70 not read.
- code-check-spatial.md (94 headings): none applicable. 94 not read.

## What was checked (beyond round 1)

- Every caller of `lnk_pipeline_species()`, `lnk_persist_init()`, `lnk_pipeline_persist()`, `lnk_barriers_views()`, `lnk_access()`, `.lnk_mapping_code_persist()` in `R/` and `data-raw/` (incl. `study_area_run.sh`, `worker_prep.sh`, `cypher_prep.sh`, `barriers_views_build.R`, `habitat_variants_build.R` base / recompute / variant pass, `wsg_run_one.R`, `wsg_recompute_one.R`, `study_area_compare.R`, `habitat_validate.R`).
- Empty-species paths end to end: `lnk_pipeline_access()` with an empty named `barriers_per_sp` and `observations = NULL`; `lnk_access(merge = TRUE)` with `species = character(0)` (the `paste0()` phantoms `has_barriers__dnstr` / `access_` drop out at `intersect(scratch_cols)`; the per-source SET clause is non-empty); `wsg_recompute_one.R`'s guarded prior table and gate; `.lnk_log_arr()` writes `ARRAY[]::text[]`, which the new verifier check judges (not skipped as NULL).
- Working-schema staleness for a paused-only group: `lnk_pipeline_setup(overwrite = TRUE)` drops the working schema, so no stale `streams_habitat_near_river` survives the skipped classify.
- Consolidate: bucket DELETE runs over every table the source enumerates and COPY uses explicit shared columns, so the changed per-species column order in a new schema (paused species now last) is harmless.
- `study_area_verify.sql` stale check: `substr(table_name, 17)`, three `%I` args in order, `upper(v_sp)` against uppercase `log.species`.
- Published quantities: segment falls 0.23 % (BULK) to 6.04 % (KETL), MURT 5.36 %; KOTL BT rearing 2,161.29 → 2,166.69 (+5.40 km); 33 / 1,473 and 4 / 47 records; LEUT and LNRS 19 readers each (`data-raw/logs/partial_readers_274/deps_line.tsv`, line rule); 73 groups recomputed from `parameters_fresh` access classes and `lnk_presence()`; 241 / 234 groups; `species_modelled.csv` checksum matches `config.yaml`. All supported.
- Tests: the run, persist and species tests added fail if the change is reverted (old code errors on empty species / refuses the group). The prep_minimal test pins behaviour that already held at the merge-base (prep_minimal always read `cfg$species`), which is fine as a pin.

## Findings

- **[severity: fragile]** data-raw/habitat_variants_build.R:351 — the paused-species guard intersects the **whole** variants file (`variants$species_code`) with `cfg_base$species_paused`, but the harness only builds `run_variants` (`--only`, line 589) and `--step=base` builds no variant at all. Every committed variants file except `variants.csv`, `variants_331*` and `variants_364` lists RB or KO rows (`variants_300.csv`, `variants_302.csv`, `variants_305.csv`), so a run that selects only BT or GR variants from one of them with `--only=`, or a `--step=base` run with such a file, is now refused with "variants name RB, which default pauses" although nothing paused would be built. Before this branch those invocations ran. Intersect `run_variants`' species (computed after `only` is parsed) instead of the file's. (The guard's comment, "a new variant schema has no table to persist it in", is also no longer true: `lnk_persist_init()` now adds the paused species' tables to every schema.)
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"
