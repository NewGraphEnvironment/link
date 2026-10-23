# Progress — Provincial run: can a drainage component be split across hosts now that the recompute settles access? (#361)

## Session 2026-10-22

- Plan-mode exploration — phases approved by user; gate decisions recorded in task_plan.md
- Created branch `361-provincial-run-can-a-drainage-component` off main
- Scaffolded PWF baseline from issue #361 with approved phases
- Next: start Phase 1

## Session 2026-10-23

- Phase 1: `study_area_buckets.R --minutes-schema=` weights by measured minutes; `--host-speeds`
  default equal. Split for the run: `data-raw/logs/provincial_361/buckets_default.md`, hosts at
  218 / 219 / 217 / 219 min (2026-10-17 packing measured 165 / 205 / 272 / 231). Segment weights
  at equal speeds reproduce the 2026-10-17 focal lists exactly; the 2026-10-17 split was not
  generated at 0.45x.
- Next: Phase 2 pre-flight, rename `fresh_default`, launch.
