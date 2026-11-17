# Progress — Backlog move 5: The habitat export's contract, and one-group runs that read downstream (#473)

## Session 2026-11-17

- Plan-mode exploration; phases and gate decisions approved by the operator
- Move 2 (#470) merged as 0.84.0 during the gate; branch cut after it
- Created branch `473-backlog-move-5-the-habitat-export-s-cont` off origin/main (a974f988); claimed #473 (`in-flight`)
- Scaffolded PWF baseline from issue #473 with the approved phases
- Next: start Phase 1
- Plan review (Plan agent, `review-plan.md`): two blockers, fifteen gaps; folded into task_plan.md. B1 (the v1 contract and the loader) went to the operator: additive v1.
- #461 measured on m4: full DB 0.20 s, a six-group DB from rtj's cloud loader (`fwapg473`) 0.18 s; the 371 s does not reproduce here (findings.md). The fix makes the probe independent of the cause.
- Phase 1 done: the check computes its closure from its own outlets (an error refuses), refuses a downstream group with no FWA streams (`wsgs_unloaded`, note `link#464 guard(...)`), snaps only dams within 65 m of the downstream groups' polygons, and times its steps (`steps_s`); the drivers print its seconds. Proof: 246-group sweep identical before/after on m4 (two schemas + overrides); HARR 273 s to 8 s with no index on `fwapg473`; the #464 tests fail on main and pass here (59 of 59).
- Phase 2 (link side): `access` in the export (#423), the token summary per config, the additive v1 loader (B1) and versioned fetch (G14), carry-forward refused across a contract change (G11), the contract read from crate with a tag URL and a names-and-types md5 (#333), `log.streams_md5` and the export's digest check (#334), `.lnk_publish_refusals()` / `.lnk_publish_gate()` and versionIds in PUBLISH (#334), RUNBOOK §6d, the gate map row for `R/lnk_publish.R`. 312 export/loader/publish/digest assertions pass; the pre-run gate's tests pass. crate's side is committed on its branch (0.19.0), not yet pushed.
- Phase 3: BUILD of ADMS and BULK from `fresh_default` (1.5 min, verifies); round trip: a published 2026-11-14 CO part loads with `access` NULL, a table without the column gains it, ADMS `access` equals `streams_access` for BT, CO and CH (0 differ); the export cites crate v0.19.0's file; no PUBLISH refusal. NEWS, 0.85.0, CLAUDE.md status. `fwapg473` dropped.
- Full suite: 6,007 assertions, 2 failed and 2 errored in 3 tests, all failing identically on main (`study_area_run.sh models with the gate off on both legs (#349)`; two `lnk_wsg_resolve` closure tests that connect through the default `PG_*_SHARE` connection). Lint: no new lint but indentation, which the files already carry (183 on main); the long message line and an unqualified mock in a test helper fixed.
