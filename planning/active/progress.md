# Progress — Known and suspected km per species in the group summaries (#403)

## Session 2026-10-30

- Plan-mode exploration — phases approved by user (parked)
- Gate decisions: names `accessible_observed_km` / `accessible_unobserved_km`; no habitat split in the defaults (bcfishpass's habitat split is expert-confirmed habitat, a different axis); baseline numbers now from m4's `zz396_default_{pre,post}`; export deferred
- Created branch `403-known-and-suspected-km-per-species-in-th` off origin/main
- Scaffolded PWF baseline from issue #403 with approved phases
- Plan review (Plan agent) folded into `task_plan.md`; findings in `review-plan.md`
- Next: parked 2026-10-30; resume with the command below, then "start Phase 1"

### Resume

```bash
cd /Users/airvine/Projects/repo/link && git fetch -q origin && git checkout 403-known-and-suspected-km-per-species-in-th && git pull --ff-only && git merge origin/main
```

## Session 2026-10-30 (resume)

- Phase 1: three tests added; at `cab86f10` the exact-names test fails, the offline split test errors (no such metric) and the live test fails on the default frame, while its unrounded identity on `fresh_default` already holds (`[ FAIL 3 | PASS 58 ]`).
