# Progress — Partial runs: recompute the groups outside the run that read its barriers (#274)

## Session 2026-10-29

- `/planning-init 377`: #377's top unchecked item is #274. Plan-mode exploration; gate answered
  (measure + build now; recompute compatible readers, name the rest; exit 0 with WARN)
- Created branch `274-partial-runs-recompute-the-groups-outsid` off origin/main (`9ae7be27`)
- Scaffolded PWF baseline with the approved phases
- Next: start Phase 1
- Phase 1: `recompute_deps.R line` re-run (73.5 s) gives the line rows of #374's map exactly.
  `readers.R` measured four partial runs: held outside readers 35 (field → `fresh`), 32 (North
  Thompson → `fresh`), 0 (parity → scratch `fresh_parity361`), 1 (DUNC → `fresh_default`); 78 / 65
  / 85 / 1 against `fresh_default`. None is recompute-compatible at today's HEAD.
- Plan review (Plan agent, `review-plan.md`): 4 blockers, 8 gaps. B3 (judge refuses unasked ids)
  and B4 (verify's lifted RAISE has no `log` join; label premise wrong) reproduced; all folded
  into `task_plan.md`'s decisions and phases.
- Full-run proof: 2026-10-23's `run_wsgs.tsv` (241 groups, no SKIPs) leaves no group
  `fresh_default` holds outside it.
- Phase 2: `data-raw/recompute_readers.R` (`readers_outside()`, `readers_classify()`) and
  `data-raw/recompute_readers_check.R`; 52 tests pass; mutants (no `held` filter, no `waiting`
  precedence, an unknown open row passing, any rule counting) each fail one. The check script
  over three measured runs gives readers.tsv's held counts (32 / 0 / 1), all refused
  (`check_*.tsv`).
- Phase 3 wiring: `recompute_readers` / `recompute_readers_lifted` (study_area_recompute.sh),
  called from `run_finish`; `ALL_WSGS` is the union, `CMP_WSGS` the compare's; the map is
  computed in every recomputing mode, waited on before dispatch only in early mode;
  `run_readers_report` names refused, waiting, unchecked and lifted readers. Finish tests 277
  pass; three one-line mutants (compare reads the union, no union, a bad class accepted) each
  fail a test.
- Verifier: an outside reader's recompute row is labelled as such; the habitat invariant covers
  `log ∪ log_recompute` groups; a reader's lifted segments are a WARNING, the run's still raise.
  `study_area_verify_negative.sh` on `fresh_default`'s 2026-10-23 run: all 19 cases right,
  including new 6h (reader present → PASS) and 6i (reader lifted → PASS, reported); against the
  old verifier 6i fails. Audit tests: a reader started from the final set → `ok`, one started
  before its run group landed → `EARLY` (57 pass in test-recompute_readers.R).
- Phase 4 live, from a worktree at `27e8089c`, scratch `fresh_274`, dispatcher only:
  run 1 `20261030_050409-473440fc` models KISK (exit 0); run 2 `20261030_050720-41d61c31`
  models LPCE and recomputes KISK as its reader (`recompute`; `log_recompute` row under run 2's
  uid; compare over LPCE only; audit ok; verify passes, KISK labelled an outside reader;
  negative script right on every case it can run, 6c skipped for one host); run 3
  `--recompute-only` after KISK's `link_sha` was set unresolvable: KISK `refused`
  (`sha_unresolvable`), named with the re-model, no recompute row, exit 0. Evidence `live/`.
- Dead ends: UPET/LPET (GR and RB only, no bcfishpass reference, so the compare fails a
  one-group run); CARP above the Peace dams a scratch schema lacks. Found: `--pretest-note`
  cannot record into a schema that does not exist yet (pre-existing; issue drafted).
- Full suite: 4815 pass, 1 failure: `test-study_area_phases.R` pinned two `( cd "$REPO_ROOT" || exit 1`
  background wrappers, and the map now launches in three modes (4). Count updated deliberately.
  Two test files were edited (lint, behaviour-neutral) while the suite ran; they and the phases
  file were re-run on the final tree: 0 bad.
- `/code-check branch` round 1 (`review-round1.md`): 2 fragile findings, both fixed. A run whose
  held readers have no log row made the check exit 1 on a scalar beside a 0-row column (old
  rc 1, new names KOTL `refused`/`no_log` on a scratch schema); and the fresh the recompute
  would run is now required clean (`dispatcher_fresh_dirty`).
- Round 2 (`review-round2.md`): Clean, round-1 fixes included. Round 3 (`review-round3.md`),
  asked for the mechanism: the check builds "now" separately from the reader's facts, so they
  agree only where both sides were written, and a "now" can be read from a stand-in. One
  defect beside round 1's fix: in `--recompute-only` (no pre-flight) fresh's sha came from the
  `FRESH_GIT_SHA` pin, not the installed fresh. Fixed: a pin the installed `RemoteSha` does not
  confirm refuses every reader (`dispatcher_fresh_pin_stale`); probed with a fake pin.
  Its enumeration of every compared fact and every empty value found the rest holding.
- Round 4 (`review-round4.md`), the terminating enumeration: every fact `readers_classify()` tests
  and every input the recompute reads, each holds, predates the branch, or was a gap. No defect
  in fixes 1 to 3. Two gaps fixed: crate's version (it shapes the overlay the one-way gate keeps)
  and the build's fresh version (a build's fresh sha can be a stale pin) are now compared; the
  unconfirmed-pin reason is renamed `dispatcher_fresh_pin_unconfirmed`. 61 classifier tests pass.
