# Task: Partial runs: recompute the groups outside the run that read its barriers (#274, from #377)

#274 is the top unchecked item on #377 (provincial run speed-up, one change at a time). Its body,
revised 2026-10-28, makes it a correctness question: a **partial** run (a field-scope pass, a
one-area re-run, a recovery over a few groups into a schema that holds more) recomputes only the
run's own groups, so groups outside the run whose walks read the run's barrier rows keep access
computed against barriers that have since been rebuilt.

```
recompute set = run ∪ { G held by the schema, G ∉ run : some line-rule dep of G is in the run }
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
- **Compatibility rule (mechanism, mine; revised after the plan review, `review-plan.md`):**
  a held outside reader is recomputed only if its newest `log` row (max `date_start`) is closed;
  carries the `config_hash`, `fresh_sha` and `fwapg_sha` that `lnk_stamp(cfg)` gives now under
  the recompute's own environment, with `link_dirty` and `fresh_dirty` FALSE; has a `link_sha`
  git resolves, with no difference between that sha and the **working tree** in `R/`,
  `inst/extdata/`, `DESCRIPTION`, `NAMESPACE`, `data-raw/wsg_recompute_one.R`,
  `data-raw/barriers_views_build.R`, `data-raw/study_area_run.sh` or
  `data-raw/study_area_finish.sh`; and its error-mode downstream check would pass (dry-run
  `on_fail = "warn"`). Every reader is refused when the run's own `log` rows do not carry the
  current config hash, or the dispatcher tree has untracked or uncommitted files on that path.
  A fixed path list rather than `pretest_inputs.csv`: the csv maps files to inputs the gate
  models, not to what the recompute reaches. Anything unknown refuses; a spurious refusal is the
  accepted direction (the gate is one-way). Consequence, stated: `fresh_default` is at 0.68.0
  and `R/` has moved, so until the provincial run re-models it every reader there is named.
- **Waiting:** a reader of a run group in `COV_MISSING` (no rows, not this run's, lost, not
  consolidated) is named `waiting`, never recomputed. Precedence waiting > refused > recompute.
  Readers of SKIPs or of a run group whose recompute failed are not waiting (they read barriers,
  not access). The `--recompute-only` that follows the re-model picks them up.
- **"The run"** for "outside" is `run_wsgs.tsv`'s full set (SKIPs included) ∪ `RUN_WSGS` ∪ any
  group with a `log` row of this run_uid, so `--wsgs=` leftovers and SKIPs are never readers.
- **One hop:** the recompute writes only its own group's access, habitat and mapping codes, never
  barrier rows, so readers of readers are not needed.
- **Consequences of the review, reported:** a reader whose recompute fails fails the run, as any
  recompute failure does (the judge sees the union); a reader whose recompute lifts segments the
  gate had blanked is named `recomputed_lifted` with the re-model command, and the verifier
  reports it rather than raising on it.

## Phase 1: Measure (acceptance 1 and 3)

- [x] Re-run `Rscript data-raw/recompute_deps.R … line` into `data-raw/logs/partial_readers_274/`,
      check its line rows equal `recompute_early_374/deps.tsv`'s (identical, 73.5 s)
- [x] `readers.R`: for field scope → `fresh`, North Thompson → `fresh`, the parity closure →
      `fresh_parity361`, DUNC → `fresh_default`, and each set against `fresh_default`: outside
      readers, how many the schema holds, and each held reader's facts against today's HEAD (raw
      facts, not the classifier's verdict, so the two derive the rule independently; O2)
- [ ] Negative case: find a line-but-not-owner pair, show in `fresh_default` that the reader's
      path holds a barrier row persisted by the run group on a segment that group does not own,
      and that the line rule finds the reader
- [ ] Full-run proof on real data (A4): 2026-10-23's `run_wsgs.tsv` against `fresh_default`'s held
      groups leaves no outside group, and its SKIPs hold no rows
- [ ] README (Measurement, Evidence); a "Groups outside a partial run" section in
      `research/study_area_run.md`; revise #274's body with the numbers

## Phase 2: The reader classifier (tests first)

- [ ] `tests/testthat/test-recompute_readers.R` (sourced like `test-pretest.R`): readers the
      schema does not hold are dropped; the run's SKIPs and log-row groups are never readers;
      `waiting` precedence; each refusal reason (open newest row, config, fresh, fwapg, dirty,
      unresolvable sha, path changed, tree dirty, downstream check); one hop only; the co-held
      pair (line present, owner absent in the committed map) is found, and fails under the owner
      rule; malformed input fails closed; the verdicts reproduce `readers.tsv`'s facts
- [ ] `data-raw/recompute_readers.R`: pure functions `readers_outside()` and `readers_classify()`
- [ ] `data-raw/recompute_readers_check.R`: reads the map, the run sets and the database, stamps
      under the recompute's environment, diffs per distinct sha, dry-runs the downstream check;
      writes `<TS>_outside_readers.tsv` (`wsg class reason reads`); exits non-zero, writing
      nothing, on any unknown input

## Phase 3: Driver wiring

- [ ] Dependency map in every recomputing mode: early as now; at-end in the background with a
      non-fatal wait in `run_finish`; `--recompute-only` in the background before
      `run_expected_recompute_only`. Update the pinned text tests deliberately
- [ ] `run_finish`: after coverage (the empty-coverage branch too, for `waiting`), run the check;
      `ALL_WSGS` becomes the union (judge, final set, fallback, pool all see it); a new
      `CMP_WSGS=$COV_RECOMPUTE` drives the compare and its report lines
- [ ] A failed check, or a missing or malformed tsv, is `unchecked`: candidates written from the
      map in awk (held unknown), or "every group outside the run in <schema> is unchecked" when
      the map is missing; never treated as "no readers"
- [ ] After the pool: readers' `habitat_gate_lifted` → `recomputed_lifted`. Report: WARN naming
      refused, waiting, unchecked and lifted readers with the remedy (re-model under this run_uid
      with `LNK_HABITAT_GATE=0 LNK_GUARD_DOWNSTREAM=warn`, then a bare `--recompute-only`; its
      own readers surface on that pass) and the tsv; exit status unchanged for named readers
- [ ] Recovery texts (finish.sh, hosts.sh "each run group that reads it"), driver header text,
      `--recompute-only` usage
- [ ] `study_area_verify.sql`: relabel the no-`log` row "outside reader of this run"; extend the
      habitat-settled invariant to `log ∪ log_recompute` groups; readers with lifted segments get
      their own reported message (not the run groups' RAISE); `study_area_verify_negative.sh`:
      VICTIM from `log` groups, scratch copy covers readers, new cases (reader present → PASS;
      reader lifted → the new message)
- [ ] Driver tests: the union reaches the final set, judge and pool; compare stays the run's;
      with a header-only readers tsv every output (FINAL line, judge and compare arguments,
      phases rows, summary, exit code) is byte-identical to today's; `recompute_audit.R` passes
      readers launched from the final set; the stub writes the tsv

## Phase 4: Live verification and docs

- [ ] Commit first, then freeze HEAD. Scratch `fresh_274` on the dispatcher: model a small pair D
      and its reader G, then a dispatcher-only run of D (`--pretest-note`): G recomputed, its
      `log_recompute` carries the run_uid, both verifiers pass. Then set G's `link_sha` to an
      unresolvable sha in scratch and run `--recompute-only`: G named `refused`, exit status as
      before. Drop the scratch schema
- [ ] RUNBOOK §8d "Groups outside a partial run", its class table, the `--recompute-only` lines and
      the phases row; CLAUDE.md status; NEWS and version bump last
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

