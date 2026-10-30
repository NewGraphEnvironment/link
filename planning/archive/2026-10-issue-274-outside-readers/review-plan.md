# Plan review — #274 (Plan agent, 2026-10-30, against e6d6cb9a)

Written here by the parent session from the agent's reply (Plan agents cannot write files).
Verified by the parent before folding in: B3 (`R/lnk_fanout_judge.R:146-149` reports "reported but
were not asked for") and B4 (`study_area_verify.sql:332` already labels the row "recomputed but
never modelled"; the lifted RAISE at L583-598 reads `log_recompute` with no `log` join;
`study_area_verify_negative.sh:170` picks VICTIM from `log_recompute`) reproduce.

## Blockers

- **B1.** The rule never asks whether the reader's newest `log` row finished. A failed build
  leaves `date_end` NULL and can leave partial rows (`run_coverage`, study_area_finish.sh:265-303;
  RUNBOOK 1759-1761). Require it closed; else refuse `newest_build_open`.
- **B2.** The diff is against HEAD, but `recompute_one` runs the working tree under load_all
  (study_area_run.sh:743-753); a dirty dispatcher is a WARN on a dispatcher-only run and
  `--recompute-only` runs no pre-flight. Diff `<sha>` against the working tree and require
  `git status --porcelain --untracked-files=all -- <paths>` empty, else refuse every reader
  `dispatcher_tree_dirty`.
- **B3.** `fanout_judge` refuses ids it was not asked for, so the union must reach the judge
  (finish.sh:651), `recompute_final_write` (L698), the dead-scheduler fallback (L721) and
  `run_recompute_pool` (global `ALL_WSGS`, study_area_run.sh:853). Keep `ALL_WSGS` the union and
  add a compare set. A reader whose recompute fails fails the run (say so); the "PRE-consolidate
  values" report text (L913-918) is wrong for a reader. Mutation happens before the error-mode
  downstream check (wsg_recompute_one.R:172-204).
- **B4.** Verify: the label already reads "recomputed but never modelled" (not asserted). Real
  breaks: (a) the lifted RAISE (L583-598) has no `log` join, so a lifting reader fails verify with
  a remedy that pulls it into the run; (b) the habitat-settled invariant covers only `log` groups
  (L559-560); (c) the negative script's VICTIM (L170) may be a reader, so case 2 would "PASS but
  should have FAILED"; its scratch copy (L93-100) copies `streams` for `log` groups only.

## Gaps

- **G1.** Error-mode `lnk_wsg_downstream_check` reads live `cabd.dams` and needs downstream
  groups persisted, which a partial schema may lack; fails after mutation. Add `fwapg_sha`
  equality with the run's rows; dry-run the check (`on_fail = "warn"`) per candidate and refuse
  `downstream_unpersisted`.
- **G2.** `fresh_dirty` not in the rule; the stamp resolves `FRESH_GIT_SHA` env first. Compute the
  expected stamp with `lnk_stamp(cfg)` under the recompute's environment; require `fresh_dirty`
  FALSE.
- **G3.** "The run's config_hash" undefined; `--recompute-only` checks only `config_name`. Use
  `lnk_config(CONFIG)`'s hash now, and require the run's own `log` rows to carry it, else refuse
  all `config_changed_since_run`.
- **G4.** Surface the one-way gate: after the pool, read readers' `habitat_gate_lifted`; name them
  (`recomputed_lifted`) with the re-model command.
- **G5.** Failure paths name no one; the test stub writes nothing. Missing tsv or bad header is a
  failed check; then write `unchecked` candidates from the map, or say every outside group is
  unchecked if the map is missing.
- **G6.** "Outside the run" must exclude SKIPs of the run's buckets and `--wsgs=` leftovers of the
  run_uid: pass run_wsgs.tsv's full set ∪ `RUN_WSGS` ∪ groups with any `log` row of this run_uid.
- **G7.** Recovery texts (finish.sh:802-806, hosts.sh:665-669), `--recompute-only` usage, RUNBOOK
  1778-1781.
- **G8.** Refused remedy: re-model under this run_uid with `LNK_HABITAT_GATE=0
  LNK_GUARD_DOWNSTREAM=warn`, then bare `--recompute-only`; note the recursion (its own readers).

## Ordering

- **O1.** At-end mode needs a non-fatal wait in `run_finish`; `--recompute-only` starts the map in
  the background early. Text tests pin current strings (test-study_area_recompute.R:414-419, 460).
- **O2.** Phase 1's "class under the rule" needs Phase 2; avoid two implementations.
- **O3.** Verifier fixes before Phase 4.
- **O4.** Phase 4: commit first, freeze HEAD between modelling D/G and the run; add a live
  `--recompute-only` pass; optionally an unresolvable sha.
- **O5.** Empty-coverage branch (finish.sh:495-510) should still name `waiting` readers.

## Assumptions

- **A1.** No transitive readers: the recompute writes only its own access, habitat and
  mapping_code (lnk_access.R:240, lnk_habitat_gate.R:160, lnk_mapping_code.R:266-269). State and
  test one hop.
- **A2.** Cypher `link_sha` resolves (cypher_prep.sh:207-218); verify.sql comments L288-289,
  L524-526 are stale.
- **A3.** Path list misses `data-raw/study_area_run.sh`, `data-raw/study_area_finish.sh`,
  `NAMESPACE`; or say why the fixed list instead of `pretest_inputs.csv`.
- **A4.** "Full run has no readers over the map" is circular; prove on 2026-10-23's
  `run_wsgs.tsv` against `fresh_default`'s held groups.
- **(5)** `<missing>` is `COV_MISSING` exactly; precedence waiting > refused > recompute; readers
  of SKIPs or of failed run recomputes are not waiting.

## Scope

- RUNBOOK §8d class table (1746-1765), "`--recompute-only` is unchanged" (2042-2043), phases
  table recompute row (1937). Driver header text (study_area_run.sh L124-129, L165-176). Plan
  file's unclosed code fence.

## Acceptance

- "Names every" unproven on G5 paths, the coverage FATAL exit (finish.sh:473-475) and lifted
  readers. Full-run invariance: a driver test with a header-only readers tsv, byte-identical
  outputs; plus A4's real-data proof. Negative fixture from committed deps.tsv (line present,
  owner absent), with Phase 1's database evidence.
