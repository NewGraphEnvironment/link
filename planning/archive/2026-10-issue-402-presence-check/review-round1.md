# Code-check round 1 — #402 presence check (branch diff a6331dea...f3b59b47)

## Checklist read

- code-check.md: every H3 under `## Mechanisms`, prose only (table rows skipped). The tail of "One fact derived twice" was cut off by the read limit. `## Rules that stand alone`, `## Security` and `## Spreadsheets and PDFs`: index lines only, none read in full.
- code-check-r.md: read in full "Read-back shape must match write-back shape", "A `data-raw/` script must load the source tree, not the installed package", "Cross-function consistency for label/string normalization", "`stats::aggregate()` has three separate silent behaviours…", "Postgres row order is never fixed…", "`match()` treats NA as a matchable VALUE…", "`paste()` with a zero-length argument returns length ONE…", "`ifelse()` with an all-NA test returns a logical vector…" (8). About 115 other headings: index only.
- code-check-shell.md: index only. The diff has no shell beyond one `system("git rev-parse …")`.
- code-check-spatial.md: index only. The diff has no spatial code.

## What I checked

- I ran `test-dictionaries.R` and `test-lnk_presence_check.R` with `NOT_CRAN=true` in a scratch worktree at HEAD (since removed). Presence check: 71 passed, 0 failed. Dictionaries: 9 failures (finding 1).
- I re-derived every number in research/species_presence.md, CLAUDE.md, the RUNBOOK subsection, README.md and stamp.txt from the committed CSVs, and the DB-backed numbers read-only from local fwapg.
- The release tag matches `load_observations.sql` in the local bcfishpass-15 checkout (lines 115–134).
- Confirmed:
  - the code-2 / lift filter reads the table as written: `.lnk_wsg_species_present` / `observations_province`;
  - `lnk_pipeline_species()` also reads it as written;
  - the `acc` spec excludes `notes`;
  - the lift thresholds are in `parameters_fresh.csv`;
  - the prep refactor keeps the old semantics.

## Findings

- **[severity: bug]** inst/extdata/configs/dictionary_wsg_species_presence_review.csv:2-10 — every `consumed_by` ref is stale by 7 lines.
  - The refs read `R/lnk_presence_check.R:358` … `:366`. At HEAD those lines are `ri <- hit[pend]`, `tracker$flag[ri] <- …`, …, `add <- data.frame(`, `watershed_group_code = …`, `species_code = …`.
  - The column lines are now 365–373 (`watershed_group_code = flagged$…` at 365 through `issue = rep(issue, sum(new)),` at 373).
  - f3b59b47 ("Tidy … for lint") moved them, and the refs were not re-pointed.
  - This branch adds the stem to the loop in test-dictionaries.R ("… consumed_by refs land on their column"), and that test fails 9 assertions at HEAD (reproduced: `failed 9`).
  - Fix: shift each ref by +7 (358→365 … 366→373).
  - **Rule:** code-check.md "One fact derived twice"

- **[severity: fragile]** R/lnk_presence_check.R `.lnk_presence_story()` (present_unsupported branch) — the story assumes `n_min = 1`, while the driver accepts `--n-min` and passes it through to the tracker.
  - With `n_min > 1`, a present cell can hold counting records and still be flagged, and the story then reads `"Marked present; 2 records of BT, none counting: ."` (reproduced with `n_min = 5`). That is false, and its reason list is empty.
  - `--n-min=5 --seed-tracker` would write that sentence into pending tracker rows.
  - The absent branch also hard-codes "since 1990" while `n_since_recent` follows `year_recent`. That is harmless today, since the driver never passes `year_recent`.
  - Fix: count `n_kept` against `n_min` in the sentence, or refuse `--n-min` other than 1 until the stories handle it.
  - **Rule:** none

- **[severity: bug]** research/species_presence.md:22 — "Releases are 74,495 of the 375,962 records" counts only the `source` test (`Releases Database:` → 74,495).
  - The sentence follows the whole tag set. That set (source, `BC RELEASE RECORDS DATABASE` 582, `STOCKING` 744) tags 75,739 records on local fwapg, before `release_include` rows.
  - (planning/active/findings.md:41 has the same figure, correctly described there as "such records" of the source test.)
  - Fix: state 75,739 for the tag set, or say the 74,495 is the source test alone.
  - **Rule:** none

- **[severity: bug]** research/species_presence.md:59 (Mackenzie bullet) — "every one from one or two records from 1980 to 1998" is wrong for TURN ST.
  - disagreements.csv has TURN ST `year_oldest` 1969, `year_newest` 1981, and its story says "1969 to 1981".
  - The span is 1969 to 1998.
  - "Of its 26 flags" is also loose: groups.csv puts 29 flags in the Mackenzie (26 absent_recorded, 3 present_unsupported: CARP KO, LPRO RB, UPET RB). It reads right only as "its 26 absent flags".
  - **Rule:** none

- **[severity: bug]** research/species_presence.md:57 — "114 absent cells are present through their group anyway. All 32 PK cells, 34 SK, 17 CM, 17 CO and 12 CH are made present by another salmon member".
  - The listed counts sum to 112.
  - The other 2 are CT cells, promoted through `ct_dv_rb`, not salmon (summary.csv `absent_recorded_promoted` CT = 2).
  - Add the CT pair or reword.
  - **Rule:** none

- **[severity: bug]** research/species_presence.md:26 — "The pipeline itself never pools, so a BT flag resting on DV records alone would…" overstates.
  - The pipeline's barrier lifts do pool: `parameters_fresh.csv` gives BT `observation_species = BT;DV`, and the salmon and ST rows count every salmon species. `lnk_barrier_overrides()` reads these.
  - The check's own `lift_readers` column and stories say exactly this ("barrier lifts of CH, CM, CO, PK, SK, ST" on ADMS PK).
  - What holds is that the pipeline does not apply `species_pooling.csv`, and the observation filter does not pool DV into a BT cell. Say that instead.
  - **Rule:** none

No other issues.
- The SQL cross-check, the tracker merge (pending refresh, decided rows untouched, stale reporting, empty `flagged`), zero-record paths, NA handling in source/source_ref (matching SQL `coalesce`), year bounds, the CT fold, pooling with `obs_year_max` and the `.lnk_observation_exclusion_keys()` refactor all behave as described.
- The remaining prose numbers match the committed outputs and the database:
  - 351 / 24 / 327, 12 + 8 + 4, UDEN 6, LPRO 90, UEUT;
  - 82 / 89 / 156, 238; KO 137, median 11, 92, 52; ST 34 / 17; BT 8 pooled-only;
  - 132,502 / 157 codes, the alias counts, the 4 alias cells;
  - 39 cells / 5,423 records; the 2026-10-10 newest date.
