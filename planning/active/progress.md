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
