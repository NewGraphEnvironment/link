# Code-check round 2 — branch 348 (git diff c902ea97...HEAD)

Reviewer: subagent, 2026-10-18. Scope: the round-1 fixes (commit 5709d87b) in every
path asked about, plus a re-read of study_area_finish.sh, the driver's arg parsing,
discharge gate, recompute-only branch and tail, and study_area_hosts.sh.

Verified by running:
- `test-study_area_finish.R`: 12 tests, 0 failed, 0 error, 0 skipped (NOT_CRAN=true).
- A direct call of `run_finish_report` (bash 5, `set -euo pipefail`, libs sourced, no DB)
  with one held host whose kept report measured CCCC as finished-on-host and DDDD as
  partial. Output: `In a kept host's bucket: consolidate these from the host ..., do NOT
  re-model them: CCCC,DDDD`, and no re-model line at all (see finding).
- Empty `CY_WS_ARR` under `set -u` (recompute-only, no cyphers): the
  `${CY_WS_ARR[@]+"${CY_WS_ARR[@]}"}` guard expands to nothing; `CY_HOLD` / `CY_BUCKET`
  are declared assoc by the hosts lib in both paths, so `${CY_HOLD[$ws]}` is never an
  indexed-array arithmetic lookup. Everything missing goes to the re-model list. Correct.
- Partly consolidated held host: groups consolidated are not in `COV_MISSING`, so the
  intersection only touches the unconsolidated ones. Correct as far as it goes.
- `--run-label`: `${RUN_LABEL:+ --run-label=$RUN_LABEL}` is well formed in all four printed
  commands (finish report x2, driver consolidate-failure, hosts_kept_report); the arg
  parser restricts the label to `[A-Za-z0-9._-]` and refuses empty, so the pasted line
  needs no quoting and a leading `-` is harmless after `=`. The `LNK_RUN_LABEL=` env form is
  likewise safe. In --recompute-only the label is exported (`LNK_RUN_LABEL`) before the
  tail, so it reaches the recompute rows.
- Ordering: `burn_cyphers` (hence `hosts_kept_report`, which re-measures `CY_UNCONS` /
  `CY_PARTIAL` / `CY_DOUBT`) runs at driver line 1484, before `run_finish` at 1496, so those
  maps are current when the report prints.

## Findings

- **[severity: fragile]** data-raw/study_area_finish.sh:395-406 (and the matching sentence
  in RUNBOOK.md "A missing group costs only itself": "A group in a kept host's bucket ...
  consolidate it from the host, do not re-model it"). The held set is the held host's whole
  `CY_BUCKET`, so every missing group in that bucket is told "consolidate these from the
  host, do NOT re-model them". But a held host's bucket also contains its genuinely failed
  builds, which `hosts_kept_report` (run just before, same maps) lists as
  `partial, do NOT consolidate: ...` (`CY_PARTIAL`), or as unknown provenance
  (`CY_DOUBT`, e.g. a failed group over a warm image's pre-dispatch rows). For those groups
  the two blocks now say "do not consolidate" and "do not re-model", so the operator is
  given no valid recovery; consolidating a partial group deletes the dispatcher's copy, per
  the kept report's own warning. This is reachable in round 1's own scenario: a host whose
  database did not answer at accounting is held, nothing of it is consolidated, and when it
  answers at report time `host_split` puts its done-marked groups in `CY_UNCONS` and its
  failed ones in `CY_PARTIAL` — the failed ones are then mislabelled. Also reachable on any
  host held for finished-left / doubt reasons that also has a failed group (partial groups
  do not hold a host, but do not release it either). Reproduced by direct call (above).
  Fix: build `held` from the measured sets rather than the bucket — union over held hosts
  of `CY_UNCONS[$ws]` (which `hosts_kept_report` sets to the full candidate set when the
  host does not answer, `measured=no`), list `CY_DOUBT[$ws]` as "check on the host first",
  and leave `CY_PARTIAL[$ws]` in the re-model list. Adjust the RUNBOOK sentence to match.

No other issues found in the held/remodel split, the `--run-label` additions, the
recompute-only path, or the exit-status paths.
