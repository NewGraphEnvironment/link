# Progress — #372

## Session 2026-10-28

- Plan-mode exploration — phases approved by user (enforcement chosen: study_area_run.sh refuses without a passing gate record)
- Created branch `372-a-scoped-pre-run-gate-model-the-groups-t` off main
- Scaffolded PWF baseline from issue #372 with approved phases
- Next: start Phase 1
- Installed fresh v0.44.0 at the DESCRIPTION pin (the machine held 0.42.0; `load_all()` refused)
- Phase 1: `data-raw/pretest.R`, `data-raw/pretest_inputs.csv` (136 rows), `tests/testthat/test-pretest.R` (42 pass). Seven mutations each turn the suite red (prepare marked none, a row dropped, verdict ignoring the bound, pick ignoring history, no floor, git errors swallowed, getFromNamespace not followed)
- Phase 2: six input queries (`data-raw/pretest/*.sql`) and `data-raw/pretest_pick.R`. The 0.66.6..0.68.0 pick (fresh v0.39.0..v0.42.0) chooses 10 groups, QUES and TAKL for the walk and OKAN and SAJR for dams. The 1d00c04c..HEAD pick (fresh v0.42.0..v0.44.0) chooses 8 groups, about 55 min of last-run minutes
- Plan review returned (planning/active/review-plan.md): 3 blockers, 10 gaps; B1-B3, G1-G3, G6-G10, A3, A6 adopted, the rest documented as limits
- Phase 3: `pretest_run.sh`, `pretest_verdict.R`, `--only=` subset mode. Smoke: SAJR modelled into `fresh_pretest_default` (23 tables, 62 indexes cloned) in 0.8 min. Stall: `LNK_TEST_STALL_WSG=SAJR --floor-min=1` killed at the 4.8 min bound, exit 124 -> `bound`, gate exit 1, no backend left
- Phase 4: `pretest_check.R` in `preflight_local()`, `--pretest-note` writes an override row (`pretest_override.sql`). `--preflight-only` with no record: `✗ pre-run gate not cleared: no gate record`, FATAL. 71 tests pass
- Code-check rounds 1-3 (planning/active/review-round{1,2,3}.md): round 2 found a defect inside round 1's fix (the fresh pin stood in for the installed fresh), so the loop needs an enumeration to end; round 3 named the mechanism (stand-ins filtered out when missing) and enumerated; fixes 59587cb1, 6f3b9f32, 2f7d39fc. Round 4 (the enumeration check) spawned 22:16 UTC
- First real gate (1d00c04c..20d2bc4c, worktree): FAIL, six pass at 36-68 % of last minutes, TAKL and SAJR killed at their bounds while another session ran six modelling workers (`knw_strchk_*`) on the database. SAJR had modelled in 0.8 min alone an hour before. The start check missed that load; it now refuses beside any other active client session (`--allow-busy`), and samples load per group. Evidence `data-raw/logs/pretest_372/gate_1d00c04c_loaded/`
- Next: a clean gate at the final branch HEAD once the database is quiet (waiter running), then the passing record and `--preflight-only`
