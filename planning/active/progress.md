# Progress — #372

## Session 2026-10-28

- Plan-mode exploration — phases approved by user (enforcement chosen: study_area_run.sh refuses without a passing gate record)
- Created branch `372-a-scoped-pre-run-gate-model-the-groups-t` off main
- Scaffolded PWF baseline from issue #372 with approved phases
- Next: start Phase 1
- Installed fresh v0.44.0 at the DESCRIPTION pin (the machine held 0.42.0; `load_all()` refused)
- Phase 1: `data-raw/pretest.R`, `data-raw/pretest_inputs.csv` (136 rows), `tests/testthat/test-pretest.R` (42 pass). Seven mutations each turn the suite red (prepare marked none, a row dropped, verdict ignoring the bound, pick ignoring history, no floor, git errors swallowed, getFromNamespace not followed)
