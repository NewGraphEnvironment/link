# Progress — study_area_run.sh counts finished groups from log text (#347)

## Session 2026-10-17

- Plan-mode exploration — phases approved by user; operator calls: add the CSV newline (hashes are accounting, not a gate); keep any host that may hold unconsolidated work, on abort too, with loud accounting
- Created branch `347-study-area-run-sh-counts-finished-groups` off main
- Scaffolded PWF baseline from issue #347 with approved phases
- Phase 1-2: lib `data-raw/study_area_hosts.sh` + `tests/testthat/test-study_area_hosts.R`, 39 pass; 5 mutants all caught (findings)
- Plan review folded in (B1/G1 verified: soft date_end, consolidate deletes source rows); release now measured after consolidate
- Phase 3-4: driver wired, droplet pre-flight in the lib; 66 tests pass; 9 mutants caught; live checks against local DB and preflight-only run (findings)
- Phase 5: final newline on the four cabd_blkey_xref.csv copies; warning gone; config_hash moves per bundle (findings)
- Full suite run (5 failures, none from this work; findings); test file lint-clean (styler + qualified testthat helpers)
- Phase 6: RUNBOOK §8d "Which host may be burned", CLAUDE.md #246 fact updated, two follow-up issues drafted
- Next: /code-check branch
