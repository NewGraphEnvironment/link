# Progress — Backlog move 6: What a run stamps and checks before launch, and how primitives load (#474)

## Session 2026-11-12

- Plan-mode exploration (three read-only explorers over batch 8 stamps, the pre-run gate, and primitive loading); four gate decisions asked and answered — phases approved by user
- Created branch `474-backlog-move-6-what-a-run-stamps-and-che` off origin/main
- Scaffolded PWF baseline from issue #474 with approved phases
- Next: start Phase 1
- Phase 1 (#451): bcfishobs gate and `BCFISHOBS_GIT_SHA` export removed from the driver, remote legs and worker prep; `.lnk_bcfishobs_sha()` removed, stamp slot NA, column kept. `study_area_verify.sql` reads the observations' `log_input.artifact_version_id` (sections 1, 1b, new 2c, two new assertions); the md5 is read through `to_jsonb()` because `fresh_default.log_input` predates the column. Verify passes on m1's copy of run `20261103_163715-269b585a` (241 groups, 5 hosts, one observations version), and the negative script's new cases 6 and 6a fail as they should (all 19 cases as expected).
