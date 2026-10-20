# Progress — Validate comp_weight against measured modelling time, not just against WSG count (#259)

## Session 2026-10-20

- Plan-mode exploration — phases approved by user (parked)
- Created branch `259-validate-comp-weight-against-measured-mo` off main
- Scaffolded PWF baseline from issue #259 with approved phases
- Plan review spawned 23:18 UTC, delivered 23:25 UTC: `planning/active/review-plan.md`, folded
  into `task_plan.md` in the follow-up commit. One blocker (B1: `default`'s `pipeline.schema` is
  `fresh`, so `--schema=` is required and the commands carry `--schema=fresh_default`), one
  acceptance gap (A1: per-option out-of-sample scoring on the October run is possible now and
  is a Phase 3 task), and the rest as task edits; all cited issue numbers checked with `gh`.
- Next: parked 2026-10-20; resume with the command below, then "start Phase 1"

### Resume

```bash
cd /Users/airvine/Projects/repo/link && git fetch -q origin && git checkout 259-validate-comp-weight-against-measured-mo && git pull --ff-only && git merge origin/main
```

The parked approval covered the baseline only; the run-to-PR mandate starts with the
resume instruction. Phase 1 needs the local docker `fwapg` (`fresh_default.log` holds the
241-group run's times) and the source tree (`LNK_LOAD=loadall`).
