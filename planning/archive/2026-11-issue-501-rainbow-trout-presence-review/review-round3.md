# Code-check round 3 — branch 501 (RB back in `default`)

Reviewed HEAD `9d8e63d2` against merge-base `b89d3150`, with round 2's fix (`9d8e63d2`, `.lnk_measures_per_record()`) read on its own. Nothing was run against the database. Every reader below was found by grep over `R/`, `data-raw/` (including `data-raw/logs/*/`), `tests/` and `inst/`, then read.

## Checklist read

- **code-check.md**:
  - Under `## Mechanisms` I read the prose (table rows skipped) of these H3s:
    - "A guard that fails toward pass"
    - "A fixture that cannot reach the failure mode"
    - "A proxy is not the property"
    - "Verification that reads its own output"
    - "A guard's scope, escape hatches, and remedies"
    - "A fix lands in one of two callers that share a harness"
    - "Restore the bug and prove the guard fires" (first part)
    - "Zero-length, empty, and unset are three different things"
    - "Written data outlives the fix"
  - Not read in full: the other 5 Mechanisms H3s and the ~24 "Rules that stand alone" headings.
- **code-check-r.md**: I read these headings in full.
  - "Postgres row order is never fixed unless the query fixes it, so a pick, a float sum and a presence check can each depend on it"
  - "`match()` treats NA as a matchable VALUE, so two unknowns join to each other"
  - "`sort()` and `order()` collate by `LC_COLLATE`, so a canonical form is locale-dependent"

  I applied two more from their index lines: "A `data-raw/` script must load the source tree, not the installed package" and "`paste()` with a zero-length argument returns length ONE, not zero". 125 headings not read.
- **code-check-shell.md**: none apply; the shell file in the diff (`build.sh`) already ran and is an accepted tradeoff. 73 not read.
- **code-check-spatial.md**: none apply. 96 not read.

## The mechanism

**The code-to-species map was assumed to be a function, and that assumption decided the grain of every reader.**

- **What held before.** Every join through the alias or pooling map assumed one target per (group, recorded code). Two places enforced it:
  - the `duplicated()` stop in `.lnk_record_aliases()`;
  - the `one` filter in `.lnk_record_aliases_everywhere()`.
- **What changed.** The branch removed both, so the map is now a relation. `SST` and `WST` each have two targets, ST and RB.
- **What follows.** A table joined through the map has one row per (record, species it reads as).
  - **Safe:** readers written against that grain, which key on the species, count `DISTINCT observation_key`, or test existence.
  - **Affected:** readers that keep record grain, keyed on `observation_key` alone through `merge()`, `match()`, `DISTINCT ON (observation_key)`, or `count(*)` meant as records. They silently double the alias records.
- **The observation tables were already relation-grained before this branch.** DV pooled into BT with DV present gave two rows. Their readers were written for that. The new exposure is in the presence-review family (`.lnk_presence_measures()` and its data-raw callers), which had been one row per record.
- **What round 2's fix does.** It consolidates the record-grain readers onto `.lnk_measures_per_record()`. That moves the grain decision into one helper, which now has to choose which species' row stands for the record. That choice is the finding below.

## Findings

- **[severity: fragile]** `R/lnk_presence_measures.R:131-160` (`.lnk_measures_per_record()`): for a record read as two species, the helper keeps the row measured against a barrier set. When both rows are measured, or neither is, it keeps the first species in code order, so RB beats ST.
  - **The doc claim is false.** The doc says "Every other column is the record's own". It is not: `species_code` and `in_hist_zone` (`pm_out`: `z.species_code = o.species_code`) depend on the species, and so do `barrier_below`, `n_class_above` and `rearing_lake_ha` wherever the two rows are measured differently. So the measures a record-keyed reader sees for an `SST`/`WST` record are RB's whenever the ST row has no barrier below.
  - **`data-raw/wsg_species_presence_check.R:322-332` (recall):** the presence check measures no RB barriers, so an `SST`/`WST` known error with no ST-blocking barrier below would be written to `recall.csv` as `species_code` RB, with RB's historical-zone test in `in_hist_zone`. That is the wrong species to score a known steelhead error against. Latent today: 0 of the 67 `data_error` keys are `SST`/`WST` (round 2), and nothing asserts the species.
  - **`data-raw/rb_st_records_check.R:148-153` (the run now in flight):** with `barrier_species = c(RB = "ST")`, both rows carry the same ST barrier, so the tie always goes to RB.
    - `records.csv.gz`'s `species_read` will read RB for all 762 `SST`/`WST` records. The committed file, built at `1ec45ba5`, reads ST for them, so the rerun diffs on that column.
    - The comment at :145-147 ("every column kept here is the record's own") is false for that column.
    - No count reads `species_read`, so the class and option numbers are unaffected.
  - **The map script uses only `species_read_as`** (`data-raw/wsg_species_presence_map.R:220-224`), so it is unaffected.
  - **Fix.** Prefer the species the reader is about rather than code order: a `prefer` argument, or the target listed first for the alias. Alternatively, drop the species-dependent columns from the helper's output, or carry them per species. Then correct the two comments.
  - **Rule:** code-check.md "A guard that fails toward pass" ("A comment stating a property is an unexecuted claim … execute it over the population it quantifies over"). Also code-check.md "A fix lands in one of two callers that share a harness" ("Then walk the wiring … and every committed derived artifact").

## Enumeration

Every reader of the alias and pooling map, of the tables built through it, and of the measures:

| place | what it reads | safe? | why |
|---|---|---|---|
| `R/lnk_observation_records.R` `.lnk_record_aliases()` | `lnk_species_pooling()` | safe | one row per (group, alias, target); `lnk_species_pooling()` resolves one row per (target, obs) |
| `R/lnk_observation_records.R` `.lnk_record_aliases_everywhere()` | aliases | safe | one row per (alias, target) pair held in every group; sorted radix |
| `R/lnk_observation_records.R` `.lnk_observation_species_map()` | `lnk_species_pooling()` | safe | output grain (group, obs, target), sorted radix; consumers below join on it |
| `R/lnk_observation_records.R` `.lnk_observation_table_build()` | map via `VALUES` join | safe | already (record, species) grain (DV→BT); documented "every reader keys on the species or counts distinct keys" |
| `R/lnk_pipeline_prepare.R` `.lnk_pipeline_prep_observations()` / `_obs_province()` | map → `observations`, `observations_province` | safe | builders only |
| `R/lnk_pipeline_break.R` `.lnk_pipeline_break_obs()` | `<schema>.observations` | safe | `top_per_species` groups by `species_code`; `all` is `DISTINCT` positions |
| `R/lnk_pipeline_access.R` obs walk | `observations_province`, `observations` (gate) | safe | `result = "distinct"` per segment and species, gate is `exists` |
| `R/lnk_barrier_overrides.R` lift + evidence | `observations_province` | safe | `WHERE o.species_code IN (list)`; `lnk_bo_pairs` DISTINCT by key, recorded code, date, group; lift `count(DISTINCT observation_key)`; an alias's two rows share `species_code_recorded`, so DISTINCT collapses them; evidence PK holds |
| `R/lnk_pipeline_prepare.R:637-650` prep overrides | `observations_province` → `lnk_barrier_overrides()` | safe | as above |
| `data-raw/study_area_verify.sql:761-815` | `barrier_override_evidence` | safe | `count(DISTINCT evidence_key)` |
| `R/lnk_vocabulary.R` acc spec, `.lnk_record_rule_digest()` | map | safe | canonical rows; (group, obs, target) unique |
| `R/lnk_presence_check.R` alias merge | `.lnk_record_aliases()` | safe | `row_id` kept; one row per (record, target) by design; year-limit filter per target, raw kept only if no target passes |
| `R/lnk_presence_check.R` pooled evidence | `lnk_species_pooling()` (all present) | safe | merged on `code_recorded`, so `SST` (not a presence code) gets no pooled row, and ST gets one pooled RB row; per-cell `table()` over (group, target). An `SST` record counts as RB's *own* (`n_kept_own`) while an `ST` record counts as RB *pooled*; the owner settled this ("SST/WST count as both"), and the flag reads `n_kept` |
| `R/lnk_presence_measures.R` `pm_rec` | `pm_alias` LEFT JOIN | safe (by design) | two rows for `SST`/`WST`; doc updated |
| `R/lnk_presence_measures.R` `pm_bar` | `pm_rec` ⋈ `pm_barsp` | safe | one row per (key, species) in `pm_barsp`; `LIMIT 1` lateral |
| `R/lnk_presence_measures.R` `pm_above` | `pm_bar`, `pm_rec` | safe | grouped by barrier and `barrier_species`; `count(DISTINCT observation_key)` |
| `R/lnk_presence_measures.R` `pm_out` | joins `pm_bar` on (key, species) | safe | the join was changed from key alone to (key, species) |
| `R/lnk_presence_measures.R` zone fold | `.lnk_record_aliases_everywhere()` | safe | `merge()` gives one zone row per target. `SST`/`WST` zone rows (17 + 23 in `hist_zones.csv`) now also count as RB zones, consistent with the record rule |
| `R/lnk_presence_measures.R` `.lnk_presence_cell_measures()` | measures | safe | per (group, species); unique (key, species) rows |
| `R/lnk_presence_measures.R` `.lnk_measures_per_record()` | measures | **finding** | row choice is code order on a tie, not "the record's own" |
| `data-raw/wsg_species_presence_check.R:123-133` | measures | safe | coverage check per (key, species) |
| `data-raw/wsg_species_presence_check.R:137-143` | `cm` vs `n_kept_own` | safe | both (record, species) grain |
| `data-raw/wsg_species_presence_check.R:160-200` SQL recount | `pc_alias` LEFT JOIN | safe | `count(*)` per (group, species), the same grain as the check |
| `data-raw/wsg_species_presence_check.R:220-285` SQL measures recount | `pc_alias`, `pc_alias_zone` | safe | per (group, species); the zone `EXISTS` mirrors the R fold |
| `data-raw/wsg_species_presence_check.R:322-332` recall | `.lnk_measures_per_record()` | **finding** (latent) | key unique, guarded; but species-dependent columns are RB's on a tie |
| `data-raw/wsg_species_presence_map.R:93-128` | measures; `bars` `DISTINCT ON (observation_key)` from `pm_bar` | safe today | RB is not in `sp_barrier`, so no key has two `pm_bar` rows. Breaks only if an alias gains two measured targets: the pick then orders by group and `id_barrier`, not species |
| `data-raw/wsg_species_presence_map.R:130-190` rule layers | measures per (key, species) | safe | a record read as ST and RB is drawn once per species layer, by design |
| `data-raw/wsg_species_presence_map.R:218-224` known errors | `.lnk_measures_per_record()` `species_read_as` | safe | uses only the species list |
| `data-raw/rb_st_records_check.R:80-153` | aliases, measures (`barrier_species = c(RB = "ST")`) | **finding** (label only) | `species_read` reads RB for `SST`/`WST`; no count reads it; key-uniqueness guarded |
| `R/lnk_habitat_validate.R` `.lnk_hv_spec`, `lnk_vd_obs`, `.lnk_hv_dedup` | `species_obs` from `lnk_species_pooling()` | safe | spec unique per (group, species, obs); rows per (key, species); dedup per species and location |
| `data-raw/habitat_validate_inputs.R:154`, `habitat_validate.R`, `habitat_variants_score.R` | pooling → validator output | safe | every key comparison includes `species_code` |
| `data-raw/query_habitat_thresholds_obs.R:93-111` | `lnk_species_pooling()` | safe (fails loud) | stops if an obs species pools into two targets in a group |
| `data-raw/query_habitat_thresholds_mad.R:140` | pooling → validator | safe | per species |
| `data-raw/species_pooling_evidence.R:168` | `match()` on key for `yr` | safe | `yr` is record-level; BT/DV only |
| `data-raw/logs/record_rule_470/{lifts_426_427.R,pre_post_diff.R}` | map, obs tables | safe | (species, key) `EXCEPT`; lifts as the pipeline; ran as committed |
| `data-raw/logs/habitat_score_{284,302}/power_windows.R`, `habitat_validate_299/validate_run.R` | pooling spec joins | safe | per species; ran as committed (a rerun counts ST as RB, by the rule) |
| `data-raw/logs/rb_return_501/{compare.R,build.sh}` | `barrier_overrides` counts | safe | no alias or record reads |
| `data-raw/overrides_scope_time_349.R`, `data-raw/logs/{obs_province_401,observation_breaks_396,record_at_start_399,minimal_breaks_415}/*` | obs tables via the pipeline builders | safe | timing and walk scripts, distinct or species-keyed; ran as committed |
| `data-raw/pretest/obs_upstream.sql` | raw `bcfishobs.observations` | safe | raw count, a ranking proxy, not through the map |
| `tests/testthat/test-lnk_observation_records.R`, `test-lnk_presence_measures.R`, `test-lnk_presence_check.R`, `test-lnk_species_pooling.R` | the functions above | safe | assertions are per (group, species) or per pair; the per-record test pins the code-order tie (RB) |

Two comments still describe the old one-species rule, so they are stale but harmless:

- `R/lnk_presence_measures.R:59` ("folded only where it counts as one species in every group");
- `:102-103` ("where an alias counts as one species wherever it is listed").
