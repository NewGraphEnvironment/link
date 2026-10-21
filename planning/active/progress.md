# Progress — Through-wetland stretches: use the stream door plus a near-river test, not a free pass (#364)

## Session 2026-10-21

- Plan gate: the parked v3 plan in the issue body was presented as the draft and approved. It was verified against both repos first: no R/inst/tests commit on link or fresh main since the body was written.
- Created branch `364-through-wetland-stretches-use-the-stream` off main.
- Scaffolded the PWF baseline with the approved phases.
- Next: Phase 0 in fresh (`/planning-init fresh#263`, sequenced with fresh#262).
- Phase 0 in fresh: branch `263-inherit-near-river-from-the-thresholds-c`, three phases committed, `/code-check branch` in progress. fresh 0.42.0 is installed locally from a copy with only the version bumped; the fresh release commit comes after the review.
- Phase 1: `Imports: fresh (>= 0.42.0)`, `Remotes: NewGraphEnvironment/fresh@v0.42.0`. The tag does not exist until the fresh PR merges, so CI cannot install it before then. Preflight gains `frs_habitat_predicates(near_river_table)` and `.frs_near_river_specs`. Suite on the Phase 1 tree alone, in a worktree: 3,415 expectations, 2 failures, 0 errors, 6 skips. Both failures are the known stale golden dams pin (8 ADMS dams; `cabd.dams` gives 7; CLAUDE.md 2026-10-16), not this change.
