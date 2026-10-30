# Progress — Count every group's fish records when asking whether a species is observed upstream (#401)

## Session 2026-10-30

- Plan-mode exploration — phases approved by user
- Created branch `401-count-every-group-s-fish-records-when-as` off origin/main (`47bb3dfa`)
- Scaffolded PWF baseline from issue #401 with approved phases
- Next: start Phase 1
- Phase 1: tests written. Red as expected in run (access gets the province table; drop at exit, also on the no-species stop), prepare (no drop) and the token tests. The DB fixture in `test-lnk_pipeline_access.R` passes before the change: the walk never filtered records by group, so the property lives in what `lnk_pipeline_run()` passes; the fixture pins that the walk counts a record from another group.
- Deviation from the plan: the drop is an `on.exit()` in `lnk_pipeline_run()` rather than two explicit drops. The "early return" is a `stop()`, and any error between prepare and access would otherwise leave the province copy in a kept working schema. `DROP TABLE IF EXISTS` on a schema `cleanup_working` already dropped is a NOTICE (checked on m1's fwapg).
- Phase 2: `lnk_pipeline_run()` passes `observations_province` to the access walk and drops it in an `on.exit()`; `prep_overrides` keeps it; docs on `.lnk_pipeline_prep_observations()` and `lnk_pipeline_access(observations =)` say which table serves code 2; `acc-v2` / `acc-bcfp-2` retire at 0.73.0 for `acc-v3` / `acc-bcfp-3` (same specs). The five touched test files pass (access 69, run 32, prepare 230, vocabulary 48, log 323). Restore-the-bug: the group-only table fails the phase-order test; removing the `on.exit()` fails both run tests. Lints on changed lines: one, the file's own `sprintf(` hanging indent, kept to match it. Full suite next, in the background.
