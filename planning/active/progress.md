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
