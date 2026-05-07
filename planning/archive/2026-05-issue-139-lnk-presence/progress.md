# Progress — lnk_presence (#139)

## Session 2026-05-06

- Surfaced from #135 multi-WSG sweep (HORS-st + ELKR-salmon divergences) — needed cleaner abstraction for "absent species → skip" instead of another niche check.
- Plan-mode exploration:
  - `lnk_pipeline_species` exists but is intersection-flavored, no group expansion, plain vector return.
  - bcfp's salmon + ct_dv_rb group conventions live in `load_streams_access.sql` JOIN clauses.
  - `loaded$wsg_species_presence` tibble is the canonical input — caller already has it.
- Plan approved by user. Two phases: helper + tests, then 0.30.1 release.
- Created branch `139-lnk-presence-presence-helper-with-specie` off main.
- Scaffolded PWF baseline.
- Next: start Phase 1 (`R/lnk_presence.R`).
