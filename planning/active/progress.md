# Progress — Break streams at a fish observation only where "observed upstream" changes: the top observation per species per line (#396)

## Session 2026-10-28

- Plan-mode exploration — phases approved by user (parked)
- Created branch `396-break-streams-at-a-fish-observation-only` off main
- Scaffolded PWF baseline from issue #396 with approved phases
- Plan review run synchronously (`review-plan.md`); its blocker (AFTER build overwriting the BEFORE state), the code-2 segment-resolution class and the overlap-join acceptance folded into `task_plan.md`
- Next: parked 2026-10-28; resume with the command below, then "start Phase 1"

### Resume

```bash
cd /Users/airvine/Projects/repo/link && git fetch -q origin && git checkout 396-break-streams-at-a-fish-observation-only && git pull --ff-only && git merge origin/main
```

## Session 2026-10-28 (resume)

- Disk checked at the operator's ask: the fwapg data directory is a bind mount on the Mac's disk, 385 GB free against a 213 GB database; Phase 4 adds about 7 GB. No table removal proposed.
- Phase 1: `build_obs.R` + four SQL files, outputs and `readers_code2.md` under `data-raw/logs/observation_breaks_396/` (`b5e4e0e4`)
- Phase 2: knob `pipeline: observation_breaks` (`all` | `top_per_species`), checked at manifest load; builder; `default` sets `top_per_species` (inherited by `default_tuned`); roxygen; tests (56 pass in the file; shape and live tests red with the bug restored)
- Full suite at `71ccc2ce` (worktree): 4,382 pass, 0 failed, 19 errors, all in `test-lnk_habitat_validate.R`, caused by my single-file run of it colliding on the shared fixture schema `zz_lnk_validate_probe`; that file re-run alone: 433 pass, 0 fail
- Phase 3: validator roxygen rewritten (which segment, buffer, break points); test pins a mid-segment observation's attachment (red with the containing branch removed)
