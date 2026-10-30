# Task: Partial runs: recompute the groups outside the run that read its barriers (#274, from #377)

#274 is the top unchecked item on #377 (provincial run speed-up, one change at a time). Its body,
revised 2026-10-28, makes it a correctness question: a **partial** run (a field-scope pass, a
one-area re-run, a recovery over a few groups into a schema that holds more) recomputes only the
run's own groups, so groups outside the run whose walks read the run's barrier rows keep access
computed against barriers that have since been rebuilt.

```

**Already measured in exploration** (committed `data-raw/logs/recompute_early_374/deps.tsv`, line
rule, FWA only): field scope 34 groups (2026-08-31) → 78 outside readers; North Thompson 6
(2026-09-03, LFRA in it) → 65; parity closure 17 (2026-10-23) → 85; DUNC alone → 1 (KOTL). Any
run holding a Fraser main-stem group has dozens of readers. Whether the target schema holds them
is Phase 1.

## Decided at the gate (operator, 2026-10-29)

- **Scope:** measure and build now, though #274 orders itself after the next provincial run; the
  fix lands before the first partial run that follows it.
- **Remedy:** recompute each held outside reader built at a compatible version; name the rest in
  `<TS>_outside_readers.tsv` and the summary, with the re-model command.
- **Exit status:** stale readers do not fail the run: exit as today, with a loud WARN.
- **Compatibility rule (mechanism, mine):** a reader is recomputed only if its newest `log` row has
  the run's `config_hash`, the dispatcher's installed fresh `RemoteSha` as `fresh_sha`,
  `link_dirty` FALSE, a `link_sha` git can resolve, and no change between that sha and HEAD in
  `R/`, `inst/extdata/`, `DESCRIPTION`, `data-raw/wsg_recompute_one.R` or
  `data-raw/barriers_views_build.R`. Anything unknown refuses. A spurious refusal is the accepted
  direction (an early recompute that reads wrongly cannot be undone: the gate is one-way).
  Consequence, stated: `fresh_default` is at 0.68.0 and `R/` has moved, so until the provincial
  run re-models it every reader there is named, not recomputed.
- **Waiting:** a reader of a run group that did not finish (coverage's missing classes) is named
  `waiting`, never recomputed: it would read a lost or stale barrier set. The `--recompute-only`
  that follows the re-model picks it up.

## Phase 1: Measure (acceptance 1 and 3)

- [ ] Re-run `Rscript data-raw/recompute_deps.R … line` into `data-raw/logs/partial_readers_274/`,
      check its line rows equal `recompute_early_374/deps.tsv`'s
- [ ] `readers.R`: for field scope → `fresh`, North Thompson → `fresh`, the parity closure →
      `fresh_parity361`, DUNC → `fresh_default`, and each set against `fresh_default` (the
      every-group case): outside readers, how many the schema holds, and their class under the
      compatibility rule at today's HEAD
- [ ] Negative case: find a line-but-not-owner pair, show in `fresh_default` that the reader's
      path holds a barrier row persisted by the run group on a segment that group does not own,
      and that the line rule finds the reader
- [ ] README (Measurement, Evidence); a "Groups outside a partial run" section in
      `research/study_area_run.md`; revise #274's body with the numbers

## Phase 2: The reader classifier (tests first)

- [ ] `tests/testthat/test-recompute_readers.R` (sourced like `test-pretest.R`): a full run has no
      readers (over the committed 241-group map, proven not assumed); readers the schema does not
      hold are dropped; `waiting`; each refusal reason; the co-held pair from Phase 1 is found;
      unreadable map or malformed input fails closed
- [ ] `data-raw/recompute_readers.R`: pure functions `readers_outside()` and `readers_classify()`
- [ ] `data-raw/recompute_readers_check.R <schema> <run_uid> <config> <deps> <run> <recompute>
      <missing> <out.tsv>`: held groups and readers' newest `log` rows from the database, git diff
      per distinct sha, writes `wsg  class  reason  reads` (class recompute | refused | waiting);
      exits non-zero, writing nothing, on any unknown input

## Phase 3: Driver wiring

- [ ] Dependency map in every recomputing mode: as now in early mode; in the background at
      start for `--recompute-at-end`; in the foreground for `--recompute-only`. A failed map
      there costs only the readers (WARN "readers not checked"), never the run's own recompute
- [ ] `run_finish` (`data-raw/study_area_finish.sh`): after coverage, run the check; recompute
      `COV_RECOMPUTE ∪ readers(recompute)`; compare over `COV_RECOMPUTE` only; early mode hands
      the union to `recompute_final_write`, so readers start in the final drain after every leg
- [ ] Report: WARN naming refused and waiting readers with the re-model command and the tsv;
      exit status unchanged
- [ ] `study_area_verify.sql`: label a group with this run's `log_recompute` and no `log` row as
      an outside reader, not "model started, never finished"; extend
      `study_area_verify_negative.sh` with that case
- [ ] Driver tests (`test-study_area_finish.R`, `test-study_area_recompute.R`): the union reaches
      the final set; with no readers the recompute and compare sets are today's; `recompute_audit.R`
      passes readers launched from the final set

## Phase 4: Live verification and docs

- [ ] Scratch `fresh_274` on the dispatcher: model a small pair D and its reader G at HEAD, then a
      dispatcher-only run of D (`--pretest-note` for a scratch run): G recomputed, its
      `log_recompute` carries the run_uid, both verifiers pass. Then set G's `link_sha` to an old
      sha in scratch and re-run: G named `refused`, exit status as before. Drop the scratch schema
- [ ] RUNBOOK §8d "Groups outside a partial run"; CLAUDE.md status; NEWS and version bump last
- [ ] Tick #274 on #377 with its measured line

## Owed at the end (reported, done after merge)

- [ ] The first real partial run after the provincial run exercises it; its
      `<TS>_outside_readers.tsv` is committed with that run's evidence

## Validation

- [ ] Tests pass (`devtools::test()`), lint clean
- [ ] `/code-check` clean (once over the branch with `/code-check branch`, three-round floor)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved: the classifier by its tests, including a mutation of the line rule to
the owner rule failing the co-held case; the full-run invariance over the real map; the wiring by
the driver tests and by the scratch run's two cases (recomputed, refused); the measurement by its
committed script and outputs.

Critical files: `data-raw/study_area_finish.sh` (`run_finish`), `data-raw/study_area_run.sh`
(deps launch ~L1708, `--recompute-only` ~L885), `data-raw/study_area_recompute.sh`
(`recompute_final_write`), `data-raw/recompute_deps.R`, `data-raw/recompute_audit.R`,
`data-raw/study_area_verify.sql`.

