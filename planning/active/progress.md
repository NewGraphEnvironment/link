# Progress — Partial runs: recompute the groups outside the run that read its barriers (#274)

## Session 2026-10-29

- `/planning-init 377`: #377's top unchecked item is #274. Plan-mode exploration; gate answered
  (measure + build now; recompute compatible readers, name the rest; exit 0 with WARN)
- Created branch `274-partial-runs-recompute-the-groups-outsid` off origin/main (`9ae7be27`)
- Scaffolded PWF baseline with the approved phases
- Next: start Phase 1
- Phase 1: `recompute_deps.R line` re-run (73.5 s) gives the line rows of #374's map exactly.
  `readers.R` measured four partial runs: held outside readers 35 (field → `fresh`), 32 (North
  Thompson → `fresh`), 0 (parity → scratch `fresh_parity361`), 1 (DUNC → `fresh_default`); 78 / 65
  / 85 / 1 against `fresh_default`. None is recompute-compatible at today's HEAD.
- Plan review (Plan agent, `review-plan.md`): 4 blockers, 8 gaps. B3 (judge refuses unasked ids)
  and B4 (verify's lifted RAISE has no `log` join; label premise wrong) reproduced; all folded
  into `task_plan.md`'s decisions and phases.
