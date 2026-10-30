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
- Full-run proof: 2026-10-23's `run_wsgs.tsv` (241 groups, no SKIPs) leaves no group
  `fresh_default` holds outside it.
- Phase 2: `data-raw/recompute_readers.R` (`readers_outside()`, `readers_classify()`) and
  `data-raw/recompute_readers_check.R`; 52 tests pass; mutants (no `held` filter, no `waiting`
  precedence, an unknown open row passing, any rule counting) each fail one. The check script
  over three measured runs gives readers.tsv's held counts (32 / 0 / 1), all refused
  (`check_*.tsv`).
- Phase 3 wiring: `recompute_readers` / `recompute_readers_lifted` (study_area_recompute.sh),
  called from `run_finish`; `ALL_WSGS` is the union, `CMP_WSGS` the compare's; the map is
  computed in every recomputing mode, waited on before dispatch only in early mode;
  `run_readers_report` names refused, waiting, unchecked and lifted readers. Finish tests 277
  pass; three one-line mutants (compare reads the union, no union, a bad class accepted) each
  fail a test.
