# Code-check round 2: #402 presence check (branch head a265b497)

## Checklist read

- **code-check.md:** I read the prose of all 14 H3s under `## Mechanisms`: A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice. I also read the index lines of the "Rules that stand alone", Security and Spreadsheets sections. Not read in full: about 24 headings.
- **code-check-r.md:** read in full: `stats::aggregate()` has three separate silent behaviours; `$` on a list partial-matches; Read-back shape must match write-back shape; `strsplit()` drops a trailing empty field; `ifelse()` with an all-NA test; Under `R CMD check`, tests run from a temp dir; A `data-raw/` script must load the source tree; Postgres row order is never fixed. Read as index lines only: the other headings (about 115), which I checked by their first sentence against the diff's tools (sort/order radix, paste zero-length, match NA, read.csv/write.csv round trip, nzchar).
- **code-check-shell.md:** index lines only (about 90 headings). The diff has no shell beyond one `system("git rev-parse")`.
- **code-check-spatial.md:** not read (about 95 headings). The diff has no spatial code.

## Verified, no finding

- Tests: `test-lnk_presence_check.R` 74 pass, `test-dictionaries.R` 118 pass, `test-pretest.R` 98 pass (1 skip), all with `NOT_CRAN=true` from a worktree at a265b497. The dictionary `consumed_by` refs (lines 376-384) land on the column names.
- Every number in `research/species_presence.md`, the CLAUDE.md #402 entry and the log README matches `summary.csv`, `disagreements.csv`, `alias_sensitivity.csv` and `stamp.txt`. Checked: 24/327/351; 12 cells with no record, 8 resting on releases, 4 on undated records; LPRO RB 90; UEUT 2 undated each; 82/89/156 cells and 238 since 1990; KO 137, median 11, 92 of the 156, 52 with releases; promoted 114 (PK 32, SK 34, CM 17, CO 17, CH 12, CT 2); ST 34 and 17; BT 8 all pooled-only; Mackenzie 29 flags (26 absent), 7 salmon or steelhead dated 1969 to 1998, every group's note "Mackenzie basin"; alias cells FINA, UFRT, MFRA and VICT; 1,279 present cells.
- Releases recounted in the database: 74,495 by the source test alone and 75,739 with the `source_ref` tests, out of 375,962. Years 1007 and 9999 do occur in the data.
- The release tagging matches bcfishpass's `load_observations.sql`: tagged after exclusions, colon prefix, `ILIKE` on `source_ref`. bcfishpass's filter tests the raw code (`array[o.species_code] && species_codes`), as the write-up says.
- The tracker is outside `config_hash` for both `default` and `default_tuned` (`.lnk_config_files()`). Under any other config, pretest drops changed files outside the `extends:` chain.
- `.lnk_observation_exclusion_keys()` matches the code it replaced in both callers, and the validator no longer reads `excl`.

## Findings

- **[bug]** R/lnk_presence_check.R:300-305, through `lift_readers` (:212-222). In all 8 tracker rows for BT, the story contradicts what the pipeline does.
  - **What the story says.** For an `absent_recorded` cell, the lift sentence is keyed to the cell's species. It reads: "While it reads absent, its records are dropped before the observation breaks and from the barrier lifts of BT."
  - **Why that is false for these 8 rows.** Every one of them is pooled-only (`n_kept_own == 0`): the evidence is DV records. DV is marked present in all 8 groups (CHIL, CLWR, EUCH, LKEC, LSAL, MUSK, SALR, STUL; checked in `cells.csv`).
    - Those DV records pass the observation filter and reach `observations_province`.
    - `default`'s `parameters_fresh.csv` gives BT `observation_species = BT;DV`, so the BT lifts read them.
    - Nothing the flag rests on is dropped. The write-up itself says the BT lifts count DV, so the tracker now contradicts `research/species_presence.md`.
  - **Where it lands.** The sentence is committed in `wsg_species_presence_review.csv`, the file the operator decides from.
  - **Fix.** Omit the lift sentence when `n_kept_own == 0`, or derive it from the species of the records the flag counts, and pin it with a pooled-only story test.
  - **Rule:** code-check.md "A proxy is not the property"
- **[fragile]** R/lnk_presence_check.R:250 and :289-290, with tests/testthat/test-lnk_presence_check.R:192-197. The round-1 fix gave the story's "N since YEAR" label its own `year_recent` argument.
  - **The defect.** `n_since_recent` is computed by `.lnk_presence_check(year_recent =)`. The story's label is a second, independent copy with the same default, so the label can name a year the count was not taken at.
  - **The test hides it.** It computes with 1990 and labels with 2000, and passes only because neither record (1980, 2001) falls between those years.
  - **Reproduced.** Records from 1995 and 2001 give "2 records since 1950, 1995 to 2001, 2 since 2000": only one is since 2000.
  - **Why it is not in the shipped output.** The script passes neither argument, so both use the default.
  - **Same shape elsewhere.** `n_min` and `year_min` are passed separately to the check and to the story.
  - **Fix.** Carry the check's parameters on its output (attributes or columns) and have the story read them.
  - **Rule:** code-check.md "One fact derived twice"
- **[fragile]** research/species_presence.md:85. The lift-threshold sentence ends "as in bcfishpass", which holds for only some of the species it lists:
  - **GR and KO:** bcfishpass has no access model for either. Its access scripts are `model_access_{bt,ch_cm_co_pk_sk,ct_dv_rb,st,wct}.sql`, and the `bcfishpass` bundle has no GR or KO row.
  - **RB:** it is lifted in `ct_dv_rb` by any BT, DV, CT or RB record, with no threshold row (the bundle's RB is NA).
  - **BT:** bcfishpass counts BT plus salmon and ST records, where `default` counts BT;DV.
  - **Where it holds:** the claim is true only for the salmon, ST and WCT thresholds.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (a restatement that widened its population)
- **[fragile]** data-raw/logs/presence_check_402/README.md:3. The README says "A second run reproduced every file byte for byte and left the tracker unchanged." That cannot include `stamp.txt`:
  - its `date:` line changes on every run;
  - a second seeded run writes "tracker: 0 added, 351 pending refreshed, 0 no longer flagged";
  - an unseeded run writes "not seeded";
  - the committed stamp still reads "351 added", so it is the first run's.

  The claim holds for the CSVs and the tracker. Say that.
  - **Rule:** code-check.md "Verification that reads its own output"
