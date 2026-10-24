# Progress — study_area_run.sh: persistent worker hosts beside the dispatcher and the cloud hosts (#376)

## Session 2026-10-24

- Plan-mode exploration — phases approved by user
- Created branch `376-study-area-run-sh-persistent-worker-host` off main
- Scaffolded PWF baseline from issue #376 with approved phases
- Next: start Phase 1 (needs the worker's ssh target from the operator); Phase 2 meanwhile
- Phase 2: renamed the any-remote-host maps `CY_*` → `HOST_*` (16 names, 203 lines, 7 files); `CY_WS_ARR` kept until Phase 4 splits the host list by kind. Suites identical before and after: hosts 38/125, legs 14/68, finish 34/229, phases 16/61.
- Plan review (Plan agent, unnamed, spawned 20:44 UTC) returned 4 blockers and a gap list; saved to `review-plan.md` and folded into the phases. B3 verified by probe: a user Renviron line beats an exported value, and a cwd `.Renviron` replaces `~/.Renviron`.
- Phase 3 (consolidate): `consolidate_remote()` reads every remote status from a stderr trailer, running the command in a subshell; a per-table `COPY n` check against the lines sent. Mutation: reading only ssh's rc returns 0 for `exit 3` under a stub that always exits 0 (test red); the real helper returns 3.
- Phase 3: `HOST_SSH` replaces `cypher@${CY_IP}` in the libs, the driver and the fixtures; the four suites pass at their Phase 2 counts.
- Phase 3 (driver): `data-raw/study_area_remote.sh` holds the remote calls; stamps, vintage, auto-install and the leg are judged on what the remote shell prints. Mutations: dropping the no-trailer check, or the leg end-marker check, each turn one remote test red. Structural pins in the finish and phases suites follow the leg string into the lib.
