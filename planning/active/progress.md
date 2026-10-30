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
- Phase 2: the two default metrics, roxygen (codes, identity, NA/0, bcfishpass counterpart, `@examples` splitting spawning / rearing by code, the "resolves to 0" sentence corrected to `NA`); validator roxygen and the driver's `cols_km` / `cols_cmp`; RUNBOOK §2c's "nothing in link tells 2 from 1" corrected and a bullet beside #319's. Rollup tests 65 pass, validator tests 433 pass; lint unchanged on the touched files (the driver's 26 are pre-existing).
- Phase 3: README block re-run on m1's local `fresh_default` (0.68.0 build) at width 80, two printed blocks. The old block was stale: it read `rearing_km` 2635.01 / 1366.32 and connection km 0, against 2632.99 / 1397.78 and 40.16 / 30.09 from the same build now (so it came from an earlier build; GR rearing rose by 31.46 km, which the connection split alone cannot do). BT 841.45 + 6041.59 = 6883.04 against 6883.03.
