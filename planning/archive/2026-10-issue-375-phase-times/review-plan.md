# Plan review (Plan agent, 2026-10-24 UTC) — #375

Findings as returned (condensed; verified one by one in findings.md):

- B1 burn row always `ok`: `burn_cyphers` returns the caller's `$?`, not its result.
- B2 killed run: `phases_close_open` writes `failed` for a leg/prep that already wrote its row (forgotten only after each serial wait).
- G1 finish lib unwired; finish tests' harness must source the phases lib.
- G2 the "no rows" branch writes no tail rows.
- G3 views/recompute boundaries on a failed stage; recompute skipped when views fail; compare still runs.
- G4 early exits (consolidate total failure, coverage FATAL, kills) never print the table: report from `on_exit` once.
- G5 model status is the session exit only (local leg always exits 0); say so, or count WARN lines.
- O1 trap: `phases_close_open || true`; guard empty array for bash < 4.4.
- O2 a failed `date` aborts the driver: `now=$(.phase_now) || now=""`.
- O3 wrappers correct; keep ssh on one line (`test-lnk_pipeline_prepare.R:1145`), don't wrap `run_finish` call lines (`test-study_area_finish.R:657,661`).
- A1 rows overlap (prep contains refresh and per-cypher prep): say so in RUNBOOK.
- A2 kill leaves legs running; later row wins; kill test must pkill the leg.
- A3 atomicity reason is O_APPEND single write, not PIPE_BUF; `LC_ALL=C` on awk `%.1f`.
- S1 `--recompute-only` preamble untimed.
- S2 plan text stale (account not skipped on N_CY=0; signature).
- S3 file shape only guaranteed for runs reaching the report.
- X1 dispatcher-only run starts with no cyphers (gates listed); commit before running from a worktree.
- X2 cypher wrappers untested by the acceptance run: add structural/stub-ssh test.
- X3 kill-test expectations: dispatcher `failed` row, exit 143, later `ok` row unless the leg is killed.
