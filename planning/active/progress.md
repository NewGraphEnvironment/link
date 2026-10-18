# Progress — schema_consolidate deletes the destination's log history for every group it copies (#354)

## Session 2026-10-17

- Plan-mode exploration — phases approved by user; operator chose to restore the rows #246 lost
- Created branch `354-schema-consolidate-deletes-the-destinati` off main
- Scaffolded PWF baseline from issue #354 with approved phases
- Next: start Phase 1
- Phases 1–3 (`0a1f8534`, `79a247e0`): `.lnk_log_specs()`; consolidate DELETEs persist tables only and replaces log rows by primary key in one transaction per table. Correction to the plan: full PK, not a `run_key` (findings). Restore-the-bug: both mutations go red.
- Phase 4 (`7d85b244`): RUNBOOK. NEWS left to `/gh-pr-merge` (this repo writes NEWS in the release commit).
- Phase 5: restored 5 `log` + 60 `log_input` rows into `fresh_default` from the 22:42 pre-consolidate dump (PINE was a fifth loss); both verify scripts pass at 241; `lnk_log_read()` newest is this run for all 241.
