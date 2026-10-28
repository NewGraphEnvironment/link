# Progress — Break streams at a fish observation only where "observed upstream" changes: the top observation per species per line (#396)

## Session 2026-10-28

- Plan-mode exploration — phases approved by user (parked)
- Created branch `396-break-streams-at-a-fish-observation-only` off main
- Scaffolded PWF baseline from issue #396 with approved phases
- Plan review run synchronously (`review-plan.md`); its blocker (AFTER build overwriting the BEFORE state), the code-2 segment-resolution class and the overlap-join acceptance folded into `task_plan.md`
- Next: parked 2026-10-28; resume with the command below, then "start Phase 1"

### Resume

```bash
cd <link checkout> && git fetch -q origin && git checkout 396-break-streams-at-a-fish-observation-only && git pull --ff-only && git merge origin/main
```

## Session 2026-10-28 (resume)

- Disk checked at the operator's ask: the fwapg data directory is a bind mount on the Mac's disk, 385 GB free against a 213 GB database; Phase 4 adds about 7 GB. No table removal proposed.
- Phase 1: `build_obs.R` + four SQL files, outputs and `readers_code2.md` under `data-raw/logs/observation_breaks_396/` (`b5e4e0e4`)
- Phase 2: knob `pipeline: observation_breaks` (`all` | `top_per_species`), checked at manifest load; builder; `default` sets `top_per_species` (inherited by `default_tuned`); roxygen; tests (56 pass in the file; shape and live tests red with the bug restored)
- Full suite at `71ccc2ce` (worktree): 4,382 pass, 0 failed, 19 errors, all in `test-lnk_habitat_validate.R`, caused by my single-file run of it colliding on the shared fixture schema `zz_lnk_validate_probe`; that file re-run alone: 433 pass, 0 fail
- Phase 3: validator roxygen rewritten (which segment, buffer, break points); test pins a mid-segment observation's attachment (red with the containing branch removed)
- Phase 4 run (`run.sh`, 06:46 to 08:37 UTC): all model steps pass; BULK BEFORE's first attempt stalled 44.6 min in the near-river walk, cancelled, retry 5.1 min; recomputes for PARS and ELKR stop on the downstream-dam guard after committing. ELKR repeat (AFTER first): 3.80 / 3.92 min; digests identical before and after.
- Results: segments −0.7 to −3.6 %; minutes within noise; FISS fish / no-fish median segment 98 / 195 m → 411 / 385 m; acceptance `n_violation` 0, 1 → 2 at tops only (6.1 km); `bcfishpass` BULK and PARS breaks and parity identical to #326 round 2; validator counts identical.
- Code-check rounds 1 to 5 (`review-round{1..5}.md`), each round's fixes committed.
