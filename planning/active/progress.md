# Progress — Check each group's species presence against its fish records (#402)

## Session 2026-10-30

- Plan-mode exploration; operator settled the rule (at least 5 records since 1950), releases out, DV pooled into BT where the tracker pools, exclusions first, and a story per group in a tracker in the bundle
- Created branch `402-check-each-group-s-species-presence-agai` off origin/main
- Scaffolded PWF baseline from issue #402 with approved phases
- Next: start Phase 1
- Rule revised before any code (operator): one record since 1950 counts, for every species, salmon and bull trout included; the count is shown, not judged. Flags renamed `present_unsupported` / `absent_recorded`.
- Plan review (Plan agent) landed: `planning/active/review-plan.md`, with its disposition. The tracker stays out of `files:` (config_hash).
- Phase 1 done: `R/lnk_presence_check.R` (check, rule, story, tracker merge), `.lnk_observation_exclusion_keys()` shared by prep and the validator, 22 tests; prep SQL identical before and after; `pretest_inputs.csv` rows for the new file and the tracker.
- Phase 2 done: empty tracker `inst/extdata/configs/default/wsg_species_presence_review.csv` (seeded in Phase 3), its dictionary, tests by path (undeclared).
- Phase 3 done: run at `feaa408c` flagged 351 cells (24 present_unsupported, 327 absent_recorded); SQL cross-check agrees (PARS, ADMS, ALBN, 39 cells, 5,423 records); a second run reproduced every output byte for byte and left the tracker unchanged. Tracker seeded, all pending. Added an alias sensitivity (SST/WST/ADV/ABT/BT-DV/RB-CT codes the pipeline drops): 4 cells would change.
- Phase 4 done: research/species_presence.md (+ index row), RUNBOOK §5 subsection, CLAUDE.md status; NEWS left to /gh-pr-merge.
- Full suite at f3b59b47: 78 files, 1,261 tests; only failures the 9 dictionary consumed_by refs round 1 found.
- /code-check round 1 (planning/active/review-round1.md): 6 findings, all fixed: dictionary refs 7 lines off (now computed from the file), the present_unsupported story wrong above n_min = 1 and "since 1990" hard-coded, and four prose errors in research/species_presence.md (release count, Mackenzie flags and years, the 114 breakdown, "never pools"). Outputs and tracker reproduce byte for byte.
- /code-check round 2 (planning/active/review-round2.md): 4 findings, all fixed. One was inside round 1's fix (the story's own year_recent could name a year the count was not taken at): the rule now rides on each row of the check. The worst: all 8 BT stories said DV-pooled records were dropped from BT lifts (they are not); the lift sentence now speaks only of the cell's own records. Also the bcfishpass lift-threshold claim and the log README's reproducibility claim. Outputs and tracker regenerated at 6aabb6f0 (stories only; other CSVs byte-identical).
