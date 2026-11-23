# Code-check round 2 — branch 501 (RB back in `default`)

Reviewed HEAD `ce39fbd8` against merge-base `b89d3150`, and round 1's fix `77328eba` on its own.

## Checklist read

- **code-check.md**: I read the prose under `## Mechanisms` without its table rows. Four H3s I read closely: "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property" and "Verification that reads its own output". I also read "A guard's scope, escape hatches, and remedies", "A fix lands in one of two callers that share a harness" and "Restore the bug and prove the guard fires". I skimmed the other seven Mechanisms H3s. I read none of the "Rules that stand alone" headings (about 24).
- **code-check-r.md**: I applied these headings from the index lines and round 1's reading.
  - "`paste()` with a zero-length argument returns length ONE, not zero"
  - "`sort()` and `order()` collate by `LC_COLLATE`, so a canonical form is locale-dependent"
  - "Postgres row order is never fixed unless the query fixes it, so a pick, a float sum and a presence check can each depend on it"
  - "A `data-raw/` script must load the source tree, not the installed package"

  About 126 headings not read in full.
- **code-check-shell.md**: none apply to the code that changed since round 1. All 75 headings unread in full.
- **code-check-spatial.md**: none apply. All 96 headings unread.

## Round 1's fix

`data-raw/rb_st_records_check.R:148-154` (`77328eba`) is correct.

- **What `m` holds per record.** It keeps the columns `observation_key`, `species_code`, `counting`, `yr`, `elevation_m`, `barrier_below` and `major_drainage`. For an SST or WST record, the ST row and the RB row agree on every column except `species_code`:
  - `counting`, `yr`, `elevation_m` and `major_drainage` come from `pm_rec`'s per-record expressions.
  - `barrier_below` is measured against ST's barriers for both rows, because `barrier_species = c(RB = "ST")`.
- **Which row the reorder keeps.** The order puts `FALSE` ahead of `TRUE` on `species_read == "RB"`, so the ST row is kept.
- **The other codes give one row each:**
  - `RB` stays RB.
  - `ST` is no alias, since it is a presence column, and `.lnk_record_aliases()` drops those.
  - `CT/RB` becomes CT.
  - `RB/CT` and `" RB"` stay as raw codes.
- **The new guard.** `!anyDuplicated(rec$observation_key)` after the merge catches any second target added later.

Other readers of the measures and the alias resolution:

- **`R/lnk_presence_check.R`.** The alias `merge()` keeps every hit with its `row_id`, so a record gets one row per target. Pooled evidence matches on `code_recorded`, so an alias does not chain. The flag reads `n_kept`.
- **`.lnk_observation_table_build()`, `lnk_barrier_overrides()` and `lnk_habitat_validate()`.** All three key on (record, species). The lift counts `count(DISTINCT observation_key)`.
- **`.lnk_record_aliases_everywhere()` and the zone fold in `.lnk_presence_measures()`.** Each gives one row per (alias, target), and the check script's SQL recount was rewritten as `EXISTS`.
- **`wsg_species_presence_check.R`.** The coverage check and `cm` are per (key, species). `wsg_species_presence_map.R`'s `stopifnot` is per (key, species). Its `bars` query is `DISTINCT ON` key, which holds: no record maps to two species in its `sp_barrier`.
- **`compare.R` and `build.sh`.** Neither reads aliases or measures.

## Findings

- **[severity: fragile]** `data-raw/wsg_species_presence_check.R:322`: the recall merge is a third caller with the grain round 1 fixed.
  - **The line.** `recall <- merge(errs, meas, by = "observation_key", all.x = TRUE)` joins one-row-per-record `errs` (bcfishpass's `data_error` exclusions) to `meas` by key alone.
  - **What happens.** `meas` is now one row per record and species. A `data_error` row on an SST or WST record therefore appears twice in `recall.csv`, as ST and as RB.
  - **The count it inflates.** The stamp line `recall set: %d data_error records ..., %d of them in bcfishobs` counts `sum(!is.na(recall$watershed_group_code))`, which would come out above the record count (for example, "68 of them" against 67).
  - **Why it is latent today.** None of the 67 `data_error` keys is an SST or WST record: 0 of 762 in local bcfishobs, and the committed `presence_check_501/recall.csv` has no duplicate key.
  - **Why it can bite.** `observation_exclusions.csv` is a bcfishpass copy synced weekly, so a new `data_error` row on a summer- or winter-run steelhead record makes the next run inflate the recall set silently. Nothing asserts the recall grain.
  - **The map script has the same shape.** `data-raw/wsg_species_presence_map.R:219` merges `meas[, c("observation_key", "species_code", "watershed_group_code")]` into `err` by key, which would draw such a known error twice, once labelled RB.
  - **Fix.** Merge only the measured species' row, or keep one row per key as `rb_st_records_check.R` now does. Then assert `!anyDuplicated(recall$observation_key)`.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness"
