# Progress — study_area_run.sh: recompute each group as soon as its downstream groups are consolidated (#374)

## Session 2026-10-26

- Plan-mode exploration — phases approved by user
- Created branch `374-study-area-run-sh-recompute-each-group-a` off main
- Scaffolded PWF baseline from issue #374 with approved phases
- Next: start Phase 1 (code reading, dependency rule, digest test, simulation; checkpoint)

- Baseline `5a5547a9`; plan review spawned (Plan agent), returned 16:2x UTC; findings in `review-plan.md`, folded into `task_plan.md` (B1 line rule, B2 view lock, headroom moved into Phase 1).
- Phase 1: `recompute_deps.R` (three rules; closure misses deps in 150/241 groups; line rule 2,211 pairs), `recompute_schedule_sim.R` (line rule saves 89.4 min as recorded, 38.1 min stall-free), headroom scratch `fresh_374r` built; A-B-A benchmark launched 16:40 UTC. Commit `1c283725`.
- Phase 2: `study_area_recompute.sh` (`recompute_landed`, `recompute_ready`, fail closed) + 26 tests; 8 of 8 mutants caught.
- Headroom (A-B-A, `-j8`): the dispatcher's modelling ~2x slower beside a full-width recompute; recompute jobs unaffected. `-j4`: 1.20x. Coupled sim on the measured curve: full width still best, 36.7 min saving stall-free (38.1 uncoupled).
- Phase 3: driver wiring (`--recompute-at-end`, pre-leg prep before the backup, dependency map before dispatch, scheduler before `legs_wait`, trap stop, final set + fallback pool, `recompute_audit.R` with its own report branch). 124 tests pass; 6 scheduler mutants caught (one only after adding the failed-dependency test).
- B2 fixed: `lnk_persist_init()` replaces `streams_habitat_long_vw` only when its definition key (md5 in the view comment) changes; live test holds a reader on the view (premise: forced replace times out). 60 persist_init tests pass.
- RUNBOOK §8d subsection; kept-host recovery wording (S2) in RUNBOOK, `study_area_hosts.sh`, `study_area_finish.sh`.
