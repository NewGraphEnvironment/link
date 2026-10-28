# Progress — Pack hosts from measured minutes: group weights and learned host speeds (#259)

## Session 2026-10-27

- Plan-mode exploration — phases approved by user (speed key: name, cloud pooled; calibrator: script the driver prints)
- Created branch `259-pack-hosts-from-measured-minutes-group-w` off main (`998c986a`)
- Scaffolded PWF baseline from issue #259 with approved phases
- Next: start Phase 1

## Session 2026-10-28 (UTC)

- Plan review (Plan agent) returned 13 findings; dispositions in `review-plan.md`, folded into `task_plan.md` (seed equal, drift removed, per-group plan checked against run_wsgs, finish-report print, alias names, convergence test)
- Phase 1: exported both runs' log rows from m1, `packing_259/fit.R` → `fit.md`. Minutes beat segments 3.6 vs 28.9 points of share error; equal speeds as good as fitted ones; legs 11–20 % over is run-wide drift (same groups 13–16 % slower on 10-23); only 10 of 239 groups moved class, so the state seeds equal. Verdict in `research/study_area_run.md`, "How hosts are packed", and the packer's weight comment
