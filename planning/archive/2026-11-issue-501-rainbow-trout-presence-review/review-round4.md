# Code-check round 4: branch 501 (RB back in `default`)

This round reviewed HEAD `ecc01da3` against the merge-base `b89d3150`, with round 3's fix (`ecc01da3`) read on its own.

What I ran:
- The helper's test file (`tests/testthat/test-lnk_presence_measures.R`), in a detached worktree of HEAD (since removed), under `NOT_CRAN=true`: 16 tests, 0 failed, 0 errors, 0 skipped. Its one live test only reads the database.
- Two ad-hoc probes of the helper: `prefer` naming neither of a record's species, and a 0-row input.
- One read-only count of `bcfishobs.observations`.

## Checklist read

- **code-check.md**: I read the prose (table rows skipped) of all 14 H3s under `## Mechanisms`. I read none of the "Rules that stand alone" headings (about 24); none matched a tool or shape in this diff.
- **code-check-r.md**: I read these in full:
  - "`match()` treats NA as a matchable VALUE, so two unknowns join to each other"
  - "`sort()` and `order()` collate by `LC_COLLATE`, so a canonical form is locale-dependent"
  - "`data.frame()` recycles a scalar against a zero-length column"
  - "A `data-raw/` script must load the source tree, not the installed package"
  - "`paste()` with a zero-length argument returns length ONE, not zero"

  About 128 headings not read.
- **code-check-shell.md**: none apply. No shell changed since round 3. About 73 not read.
- **code-check-spatial.md**: none apply. About 96 not read.

## Findings

- **[severity: fragile]** `data-raw/wsg_species_presence_check.R:425-428`. The stamp writes `nrow(meas)` under the label "measures: %d records".
  - Since this branch, `meas` has one row per record and species, so the number counts rows, not records.
  - The committed stamps carry the wrong figure: `data-raw/logs/presence_check_501/stamp.txt:10` and `after/stamp.txt:10` both read "measures: 376724 records".
  - Line 5 of the same file reads "bcfishobs.observations rows: 375962". A read-only count today gives 375,962 records, 762 of them `SST`/`WST`. 376,724 − 375,962 = 762 exactly: the published stamp counts each alias record twice.
  - `data-raw/rb_st_records_check.R:88` has the same reading: `cat("measures:", nrow(meas), "records in", …)`. That one goes to the console and the run log only, not to a committed stamp.
  - No other count reads either figure, so this misstates a published number and changes no result.
  - Fix: write `length(unique(meas$observation_key))` as records, or label the figure as record-species rows. Then correct the two committed stamps, or regenerate them at the next run.
  - Rounds 1 to 3 missed it because they enumerated record-keyed joins (`merge`, `match`, `DISTINCT ON`), not counts meant as records. Round 3's mechanism names "`count(*)` meant as records" but its table did not look for `nrow()`.
  - **Rule:** code-check.md "Written data outlives the fix" (enumerate every artifact quoting a derived value), and code-check.md "A proxy is not the property" (row count standing for record count).

Round 3's fix is otherwise sound.

- **Required `prefer`.** `stopifnot` refuses a missing, non-character, empty or NA-holding value. The test's `expect_error()` call without `prefer` pins this.
- **A preferred species missing from a record.** It falls back to code order. The probe gave `CT` for a `{RB, CT}` record under `prefer = c("CH", "ST")`, and the test pins `RB` under `prefer = "CH"`.
  - This cannot reach a caller today. The only codes that read as two species are `SST` and `WST` (ST and RB): `.lnk_record_aliases()` drops every code that is a species column, so ST→RB pooling and DV never multiply rows.
  - All three callers put ST in `prefer`.
- **Empty input.** It returns a 0-row frame with `species_read_as` as `character(0)`. Each caller's column selection and `merge()` work on it (probed).
- **Restored defect.** Under the old code order the test's first assertion (`ST` for k1 under `prefer = "ST"`) goes red, since code order picks RB.
- **Scope in each caller, on every path:**
  - `data-raw/rb_st_records_check.R:148` takes a literal "ST", on its single path. `counting`, `yr`, `elevation_m` and `major_drainage` do not depend on the species. `barrier_below` is ST's on both rows (`barrier_species = c(RB = "ST")`), so `rec` is the same whichever row is kept. `species_read` now reads ST for `SST`/`WST` again, as the committed `records.csv.gz` does.
  - `data-raw/wsg_species_presence_check.R:324` uses `sp_barrier`, assigned unconditionally at :116 on the script's only path. ST is in it, and RB is not measured there, so a known `SST`/`WST` error scores as ST, with ST's barrier and zone test.
  - `data-raw/wsg_species_presence_map.R:220` uses `c(anad, "KO")`. `anad` is global (:63), so the call works on the cached and uncached paths alike. `sp_barrier` exists only in the `else`. The map reads only `species_read_as` and `watershed_group_code`, neither of which depends on the species.
- **The doc's list of species-dependent columns is complete against `pm_out`.** `counting`, `yr`, `waterbody`, `site`, `code_other_group`, `elevation_m`, `major_drainage`, `gradient`, `barriers_known`, `lake_*` and `through_main_stem` come from `pm_rec`'s record columns or the record's group, not from the species.

## Enumeration

The table comes from grep over `R/`, `data-raw/` (including `data-raw/logs/*/`), `tests/` and `inst/`:

- every call of the four functions;
- in each file that calls one, every `merge(`, `match(`, `DISTINCT ON`, `USING (observation_key)`, `= x.observation_key`, `%in%` on `observation_key`, `duplicated`, `count(*)` and `nrow(meas)`.

In `data-raw/logs/*/`, the only file that mentions any of the four is `rb_st_497/README.md`, as prose; no log script calls them.

| place | what | keyed on | safe with two species rows per record? |
|---|---|---|---|
| `R/lnk_observation_records.R:216` | `.lnk_record_aliases()` definition | (group, obs, target) | yes: one row per target by design |
| `R/lnk_observation_records.R:254` | `.lnk_record_aliases_everywhere()` definition | `unique(species_obs, species_code)` | yes: one row per pair |
| `R/lnk_presence_check.R:95` | `.lnk_record_aliases()` call | merge on (group, code), `row_id` | yes: per (record, target); counts are tallied per cell |
| `R/lnk_presence_check.R:124,132` | `observation_key %in% excl / keys_incl` | per row | yes: a row-wise test, so a duplicate key gets the same answer |
| `R/lnk_presence_check.R` pooled merge | `merge(r[kept], p, by = (group, code_recorded))` | code_recorded | yes: no pool row has `SST`/`WST` as `obs_species` (filtered to `sp_all`) |
| `R/lnk_presence_measures.R:84` | `.lnk_presence_measures()` definition | n/a | yes: returns (key, species) rows by design |
| `R/lnk_presence_measures.R:107` | `.lnk_record_aliases_everywhere()` call; `merge(z, one, by species)` | species | yes |
| `R/lnk_presence_measures.R:237,239` (SQL) | `pm_excl` and `pm_incl` joins | `observation_key` | yes: the exclusion keys are `unique()`; `pm_incl` is `SELECT DISTINCT` |
| `R/lnk_presence_measures.R:241` (SQL) | `pm_alias` join | (group, code) | yes: two rows for SST/WST, by design |
| `R/lnk_presence_measures.R` `pm_bar` | `JOIN pm_barsp ON species` | (key, species) | yes |
| `R/lnk_presence_measures.R:292` `pm_above` | `count(DISTINCT observation_key)` | barrier, barrier_species | yes |
| `R/lnk_presence_measures.R:372` `pm_out` | `pm_bar` join | (key, species) | yes |
| `R/lnk_presence_measures.R:145` | `.lnk_measures_per_record()` definition | key, rank by `prefer` | yes (round 3's fix; probed above) |
| `R/lnk_presence_measures.R:160` | `!duplicated(observation_key)` | key, after the `prefer` order | yes: intended to collapse |
| `R/lnk_presence_measures.R` `.lnk_presence_cell_measures()` | `nrow(d)` per (group, species) | (group, species) | yes |
| `data-raw/rb_st_records_check.R:80,83` | aliases, measures calls | n/a | yes |
| `data-raw/rb_st_records_check.R:88` | `cat("measures:", nrow(meas), "records …")` | row count | **no (label only)**: counts rows as records; console only |
| `data-raw/rb_st_records_check.R:144,226` (SQL) | `USING (observation_key)` | key, `rs_rec`/`rs_block` (raw records) | yes: neither table is built from the measures |
| `data-raw/rb_st_records_check.R:148,152-153` | per-record helper, `merge(rec, m, by key)`, `!anyDuplicated` guard | key | yes: `prefer = "ST"` |
| `data-raw/rb_st_records_check.R:159` | `observation_key %in% excl` | row-wise | yes |
| `data-raw/rb_st_records_check.R:298` (SQL) | `count(DISTINCT r.observation_key)` over `rs_rec` | raw records | yes |
| `data-raw/wsg_species_presence_check.R:123,131-133` | measures call; `setequal` on keys plus `anyDuplicated(key, species)` | (key, species) | yes |
| `data-raw/wsg_species_presence_check.R:135-140` | `cm` against `n_kept_own` | (group, species) | yes |
| `data-raw/wsg_species_presence_check.R:160-162` | `pc_alias`, `pc_alias_zone` | n/a | yes |
| `data-raw/wsg_species_presence_check.R:177-190` (SQL) | `pc_excl`/`pc_incl`/`pc_alias` joins, `count(*)` per (group, species) | (group, species) | yes: the same grain as the check |
| `data-raw/wsg_species_presence_check.R:228-268` (SQL) | the same joins; `count(*)` and `count(DISTINCT …)` per (group, species) | (group, species) | yes |
| `data-raw/wsg_species_presence_check.R:324-326` | per-record helper, `merge(errs, …, by key)`, `!anyDuplicated` guard | key | yes: `prefer = sp_barrier` |
| `data-raw/wsg_species_presence_check.R:425-428` | stamp: `nrow(meas)` as "records" | row count | **no**: committed stamps say 376,724 records against 375,962 (finding) |
| `data-raw/wsg_species_presence_check.R:433` | `sum(!is.na(recall$watershed_group_code))` | recall (one row per key) | yes |
| `data-raw/wsg_species_presence_map.R:93,97` | measures and aliases calls | n/a | yes |
| `data-raw/wsg_species_presence_map.R:105-112` (SQL) | `DISTINCT ON (p.observation_key)` over `pm_bar` | key | yes today: `pm_barsp` holds only `sp_barrier` (no RB, no `barrier_species`), and no code reads as two of `sp_barrier`, so there is one `pm_bar` row per key; the guard at :129 would stop otherwise |
| `data-raw/wsg_species_presence_map.R:127-129` | `anyDuplicated` guards | (key, species); key for pts and bars | yes |
| `data-raw/wsg_species_presence_map.R:183` | `merge(d, got$pts, by key)` per rule layer | key (pts unique) | yes: `d` is per (key, species) by design, and no layer holds a key twice (SST's ST row is anad, its RB row is not) |
| `data-raw/wsg_species_presence_map.R:210,213` | bars `%in%` keys; `duplicated` by position | key, position | yes |
| `data-raw/wsg_species_presence_map.R:218-222` | known errors: merge on pts, then the per-record helper | key | yes: `prefer = c(anad, "KO")` |
| `tests/testthat/test-lnk_observation_records.R:82-92,229,283-288` | aliases tests | (group, obs, target) | yes |
| `tests/testthat/test-lnk_presence_measures.R:180,187-198` | SQL text test; per-record helper test | n/a | yes: passes, and goes red under the old code order |
| `data-raw/pretest_inputs.csv:86`, `data-raw/logs/{pretest/*,gate_borrow_442}/*.md`, `data-raw/logs/rb_st_497/README.md` | file-path or prose mentions | n/a | not readers |
