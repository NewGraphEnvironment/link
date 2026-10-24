# Progress — study_area_run.sh: persistent worker hosts beside the dispatcher and the cloud hosts (#376)

## Session 2026-10-24

- Plan-mode exploration — phases approved by user
- Created branch `376-study-area-run-sh-persistent-worker-host` off main
- Scaffolded PWF baseline from issue #376 with approved phases
- Next: start Phase 1 (needs the worker's ssh target from the operator); Phase 2 meanwhile
- Phase 2: renamed the any-remote-host maps `CY_*` → `HOST_*` (16 names, 203 lines, 7 files); `CY_WS_ARR` kept until Phase 4 splits the host list by kind. Suites identical before and after: hosts 38/125, legs 14/68, finish 34/229, phases 16/61.
