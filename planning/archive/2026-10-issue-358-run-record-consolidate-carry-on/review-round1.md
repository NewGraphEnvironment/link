# Code-check round 1 — #358 (branch vs main, planning/ excluded)

Reviewer: subagent, 2026-10-18. Read: the diff; study_area_run.sh, study_area_finish.sh,
study_area_hosts.sh, schema_consolidate.R in full where touched; RUNBOOK §8d sections;
the shell and mechanism sections of the checklist (R/spatial sections by heading).
Nothing in the repo was edited; the one probe ran on copies in a scratch dir.

## Findings

- **[fragile]** data-raw/study_area_finish.sh:58-62 (run_expected_from_hosts) with
  study_area_run.sh:1526-1535 — dropping a failed source's `CY_BUCKET_DONE` from
  `RUN_SIGNALS` also drops it from the set that keeps a group out of `RUN_SKIP`
  (`RUN_SKIP = skip − RUN_SIGNALS`). So a group SKIPped on one host and finished on the
  failed host now goes into `RUN_SKIP` and out of `RUN_EXPECT`. `run_coverage` only
  excludes `excluded ∩ expected`, so that group is never classed `not_consolidated`. It is
  not named in the coverage TSV or the report; the only output is the WARN "SKIPped by a
  host ... not expected to have rows". Before this change that group stayed expected.
  Reproduced on copies of the two libs:
  `DISP_BUCKET=AAAA,XXXX; ACC_SKIP[dispatcher]=XXXX; CY_BUCKET[b]=CY_BUCKET_DONE[b]=XXXX`
  gives `RUN_EXPECT=AAAA,XXXX` with no failure, and `RUN_EXPECT=AAAA` with
  `CY_CONS_FAIL[b]` set, so `CONS_EXCLUDED ∩ RUN_EXPECT` is empty. The same gap means the
  promised non-zero exit is never tied to `CONS_FAILED` itself. It holds only because
  `COV_UNCONS` (which needs `excluded ∩ expected` non-empty) or a kept host
  (`KEPT_CAUSE_N`) happens to fire. A failed source that is released (`copy_empty`), whose
  done groups all land in `RUN_SKIP`, exits 0 after a failed consolidate. This is rare (it
  needs a SKIP/finish disagreement across overlapping buckets), but it is the
  fails-toward-pass shape. Fix: after `RUN_INCOMPLETE="$complete_fail"`, add
  `[ -z "${CONS_FAILED:-}" ] || RUN_INCOMPLETE=1`. Also either keep the failed host's done
  groups in the `RUN_SKIP` subtraction (use them for RUN_SKIP and leave them out of the
  signals passed to coverage), or pass `CONS_EXCLUDED` to coverage before `RUN_SKIP`
  narrows the expected set.

- **[fragile, pre-existing class, now with a record that is not used]**
  study_area_run.sh:663-670 / study_area_finish.sh:265-303 (`--recompute-only`) — the
  carry-on path records `not_consolidated` groups in `<TS>_coverage.tsv`. The
  recommended follow-up, `--recompute-only --run-uid=<uid>`, does not read that record.
  `schema_consolidate` does not stop at the first per-table failure: it copies tables in
  name order (barriers…, log, log_input, log_recompute, streams, …). So after a
  `dest_copy`/`source_copy` failure the dispatcher can hold that bucket's `streams` rows
  and closed newest `log` rows for this run_uid, with some other table (barriers, a
  habitat table) deleted and not replaced. A `--recompute-only` run before the kept host
  is re-consolidated classes those groups `recompute` (rows + closed log row). It
  recomputes them on the partial persist and can exit 0. The kept_hosts WARN says
  "settle first" but does not stop. The same was possible before #358 (exit path, then
  `--recompute-only` before consolidating), so this is not a regression. But the full-run
  path now excludes exactly these groups because "a failure after the DELETE can leave log
  rows copied and streams not", and the recovery path does not. Suggest: without
  `--wsgs=`, make `--recompute-only` read `${RUN_UID%-*}_coverage.tsv` and refuse, or
  exclude, groups classed `not_consolidated` unless the operator passes them explicitly.

## Checked and found sound (no finding)

- `consolidate_outcomes` fails closed: if the file is missing or unreadable, or any driver
  source (non-empty `CY_BUCKET_DONE`, the same predicate the SRC_R builder uses) has no
  row, it returns 1 and the run takes the old exit path. The set of sources comes from the
  driver, not from the TSV. `rm -f` before the Rscript call prevents reading a stale file.
  An all-ok TSV with crc≠0 also exits.
- Every `schema_consolidate` `next` sets `results[[src$host]]`, and a `stop()`/R error
  leaves no TSV, so it is not read as "recorded". The writer's escaping (`\$`, `'\\t'`) is
  right, and the test executes the extracted snippet.
- `host_release` is still decided by the measured state. A failed source's source rows
  are never deleted (step 5 runs only after every table copied and the row check passed),
  so its finished groups stay in `CY_UNCONS` and the host is kept. `CY_UNCONS[$ws]`
  unguarded is safe, because `host_split` always assigns it.
- `run_wsgs_write`: the first, bare call aborts before spend if the write fails. The
  second has `|| WARN`. `.run_wsgs_skip` uses `${ACC_SKIP[k]+x}`, and `host_account`
  sets ACC_SKIP before any return.
- `run_expected_from_file`: a header mismatch, another run_uid, or a non-group code
  returns 1 (FATAL without `--wsgs=`). awk compares strings (the run_uid holds `_`/`-`,
  so it is never numeric). SKIP is excluded only when every row for the group says `yes`.
  RUN_UID is regex-validated, so the file path cannot traverse and the SQL cannot be
  injected.
- `CONS_EXCLUDED` is referenced as `${CONS_EXCLUDED:-}` on paths that never set it.
  `CY_CONS_FAIL` is declared in the hosts lib.
