# Progress — Count every group's fish records when asking whether a species is observed upstream (#401)

## Session 2026-10-30

- Plan-mode exploration — phases approved by user
- Created branch `401-count-every-group-s-fish-records-when-as` off origin/main (`47bb3dfa`)
- Scaffolded PWF baseline from issue #401 with approved phases
- Next: start Phase 1
- Phase 1: tests written. Red as expected in run (access gets the province table; drop at exit, also on the no-species stop), prepare (no drop) and the token tests. The DB fixture in `test-lnk_pipeline_access.R` passes before the change: the walk never filtered records by group, so the property lives in what `lnk_pipeline_run()` passes; the fixture pins that the walk counts a record from another group.
- Deviation from the plan: the drop is an `on.exit()` in `lnk_pipeline_run()` rather than two explicit drops. The "early return" is a `stop()`, and any error between prepare and access would otherwise leave the province copy in a kept working schema. `DROP TABLE IF EXISTS` on a schema `cleanup_working` already dropped is a NOTICE (checked on m1's fwapg).
