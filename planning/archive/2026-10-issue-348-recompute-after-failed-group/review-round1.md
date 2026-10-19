# Code-check round 1 — branch 348 (git diff c902ea97...HEAD)

Reviewer: subagent, 2026-10-18. Read the full diff, the checklist, study_area_finish.sh,
the changed regions of study_area_run.sh (arg parsing, recompute-only block, moved pool
functions, consolidate tail), study_area_hosts.sh's query/set helpers, both test files,
setup.R, RUNBOOK and CLAUDE.md bullets.

Verified by running:
- `test-study_area_finish.R`: 11/11 pass, 0 skip. `test-study_area_hosts.R`: 120 pass.
- The extraction patterns in pool_probe.sh / recompute_parity.sh / recompute_sweep.sh
  (`^csv_lines() {`, `awk '/^recompute_one\(\)/,/^}/'`, `/^run_recompute_pool\(\)/,/^}/`)
  each match exactly one definition in the new driver, and the awk range still ends at the
  function's own closing brace.
- `date_start` is `timestamptz NOT NULL`, and `fresh_default.log` has 0 (group, date_start)
  ties, so the `(wsg, max(date_start)) IN (...)` newest-row pick is unambiguous.
- On the real #246 run, the coverage "closed and newest" predicate selects 241/241 groups,
  and `config_name` is `default` on all 241 rows, so `run_config_check` passes for it.
- SQL interpolation: RUN_UID regex matches the minted format exactly; SCHEMA and CONFIG are
  restricted to `[A-Za-z0-9_]`; WSGs come from `[A-Z]{4}`-validated sets.
- Fail direction: coverage returns 1 (unknown) on a missing streams table; a missing log
  table reads as "nothing finished" (everything named, nothing recomputed), and
  run_config_check fails closed. None fail toward pass.

## Findings

- **[severity: fragile]** data-raw/study_area_finish.sh, run_finish_report (the
  `RUN_INCOMPLETE` / `COV_MISSING` branch): the recovery for a missing group is always
  "re-model each under this run_uid". When a cypher is kept because its database did not
  answer at accounting (`ACC_STATE` unknown, so `CY_BUCKET_DONE` is empty and nothing of it
  was consolidated), its finished groups land in `no rows` / `earlier or partial` and are
  printed with that advice, directly under the kept-host section that says to consolidate
  them. An operator who follows the second block re-models groups that are already finished
  on the kept host (hours of work at provincial scale). If they then consolidate as well, the
  host's older build replaces the re-model. No data is lost, but the two blocks give opposite
  instructions for the same groups. Fix: in that branch, list the missing groups that belong
  to a kept host's bucket separately ("consolidate from the kept host, do not re-model"), or
  print the re-model advice only for groups outside every kept host's bucket.

- **[severity: fragile]** data-raw/study_area_finish.sh (run_finish_report's printed
  `--recompute-only` commands, both the kept-host and missing-group blocks),
  data-raw/study_area_run.sh:1463-1466 (the consolidate-failure message),
  data-raw/study_area_hosts.sh hosts_kept_report, and RUNBOOK §8d: the printed
  `bash data-raw/study_area_run.sh --recompute-only --run-uid=... --config=... --schema=...`
  never carries `--run-label=$RUN_LABEL`. The `wsg_run_one.R` line printed directly above it
  does carry `LNK_RUN_LABEL`. Following the commands as printed gives the finishing
  recompute's `log_recompute` rows (the newest per group, which describe what ships)
  `run_label` empty, while the run's `log` rows and the re-modelled groups keep the label.
  This is a provenance gap only. Fix: add `${RUN_LABEL:+--run-label=$RUN_LABEL}` to the
  printed `--recompute-only` lines.

- **[severity: fragile]** data-raw/study_area_finish.sh run_coverage, when called from the
  `--recompute-only` path with no signals (study_area_run.sh, `run_finish "$RO_EXPECT" ""`):
  the comment states that the log's `date_end` is a soft UPDATE that can fail, which is why
  signals only ever add. In a full run, the done marker rescues such a group. In
  `--recompute-only` nothing can: a group whose build finished and was consolidated, but
  whose `date_end` UPDATE failed, is reported as "an earlier run's or partial rows" on every
  `--recompute-only`. It is never recomputed, and the run cannot exit 0 without a full
  re-model of that group. This fails closed and is rare, but the diagnosis printed for it is
  wrong. A one-line note in RUNBOOK's recovery paragraph would be enough, or a
  `--wsgs`-style override for groups the operator has verified.

No bugs found in the classification logic, the set arithmetic, the arg-parsing refusals, the
moved pool functions, or the exit-status paths.
