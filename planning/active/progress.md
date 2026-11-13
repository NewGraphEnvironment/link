# Progress — Backlog move 6: What a run stamps and checks before launch, and how primitives load (#474)

## Session 2026-11-12

- Plan-mode exploration (three read-only explorers over batch 8 stamps, the pre-run gate, and primitive loading); four gate decisions asked and answered — phases approved by user
- Created branch `474-backlog-move-6-what-a-run-stamps-and-che` off origin/main
- Scaffolded PWF baseline from issue #474 with approved phases
- Next: start Phase 1
- Phase 1 (#451): bcfishobs gate and `BCFISHOBS_GIT_SHA` export removed from the driver, remote legs and worker prep; `.lnk_bcfishobs_sha()` removed, stamp slot NA, column kept. `study_area_verify.sql` reads the observations' `log_input.artifact_version_id` (sections 1, 1b, new 2c, two new assertions); the md5 is read through `to_jsonb()` because `fresh_default.log_input` predates the column. Verify passes on m1's copy of run `20261103_163715-269b585a` (241 groups, 5 hosts, one observations version), and the negative script's new cases 6 and 6a fail as they should (all 19 cases as expected).
- Plan review returned (5 blockers, 11 gaps); saved to `review-plan.md`, dispositions folded into `task_plan.md` before Phase 2 committed.
- Phase 2 (#446, #266): `bcfishpass.log` read from `smnorris/bcfishpass@3bd2824` source (tunnel down): `model_type` LINEAR|LATERAL, `date_completed` timestamp without zone. db tier filters LINEAR by `date_completed`; ledger tier reads only `snapshot-` rows with `--with-bcfp-views`; env tier gains `LNK_BCFP_DATE_COMPLETED`; `log.bcfp_date_completed` (timestamptz, log only). Driver exports version and date to every leg. Proven against local fwapg: column created fresh and re-added on an existing log, insert lands the date. Verify section 2 reports the date (through `to_jsonb`, older logs lack it); verify still passes on the 241-group run.
- Phase 3 (#458): measured that no code clears `log_recompute` (`fresh` holds four runs in both tables); `fresh_default`'s 483 `log` rows against 241 `log_recompute` rows come from #454 seeding `log` with the gate's history. RUNBOOK §6b: a build is the rows of one `run_uid`; `log` row of the table brought up to date (run ids, retired `bcfishobs_sha`, tokens, the bcfp pin with its date).
