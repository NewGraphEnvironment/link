# provincial_361 — the province-wide `default` run of 2026-10-23 and the split test (link#361)

run_uid `20261023_074321-24d85e8c`: 241 groups into `fresh_default` at link `1d00c04c` (0.68.0) on
fresh `e9793047` (0.42.0), m1 + three cloud hosts, `--refresh-primitives`, `--recompute-jobs=8`. The
2026-10-17 build was renamed `fresh_default_20261017` before the launch and kept as the control. Both
verifiers pass at `expected_n=241`. The record: `research/study_area_run.md`, "The province-wide
`default` run (2026-10-23)"; the story, `planning/archive/2026-10-issue-361-*/`.

The driver's own files for the run are `../study_area_run/20261023_074321_*` (and `20261023_202311_*`
for the `--recompute-only --wsgs=OKAN` finish); addresses are redacted by the driver's EXIT trap. The
files here were written by hand or by the harness, and redacted by hand.

## The run

| file | what it holds |
|---|---|
| `buckets_default.md`, `.stderr` | the split the run used: `study_area_buckets.R --minutes-schema=fresh_default --hosts=4` on the 246 focal groups, component atoms, ~218 min per host |
| `launch.sh` | the launch command (four `--focal=` lines); re-execs the driver under the launching bash |
| `run_attempt1_bash32.log` | attempt 1, refused by bash 3.2 before any spend |
| `run.log`, `run.started` | the driver's stdout for the run (launch 07:43:21 UTC, exit 20:04 UTC, INCOMPLETE on OKAN by design) |
| `okan_remodel.log`, `okan_recompute.log` (+ `.started`) | OKAN re-modelled under the run_uid after the driver exited (7.6 min), then `--recompute-only --wsgs=OKAN` (no BC group drains through OKAN) |
| `run_verify.log`, `run_verify_extra.log` | `study_area_verify.sql` and `provincial_246/verify_extra.sql` at `expected_n=241`: PASS, with OKAN's failed attempt noted as superseded |
| `verify_negative.log` | `study_area_verify_negative.sh` on this run: 15 of 15 cases, including the new 6f / 6g (an open log row superseded, or not) |

What happened on m1: KTSU took 65.4 min (1.3 on 2026-10-17) and OKAN sat from 09:19 UTC in one
statement, fresh's near-river walk, until the operator cancelled it at 13:30 under a 30 min role
statement timeout (reset after the run). Re-run afterwards on the working tables the run left, the same
statement takes 59 s (OKAN) and 3 s (KTSU) with the same plan; the mechanism was not identified
(`planning/archive/…/findings.md`, "The KTSU / OKAN stall"). The cloud hosts finished by 12:27 UTC and
idled until the consolidate at 17:24: link#369.

## The split test (Phase 3) and its verdict

| file | what it holds |
|---|---|
| `split_test.sh`, `split_compare.R` | the harness: Peace's 26 groups on two "hosts" in the worst order (odd positions of the DS-first order reversed onto `fresh_361a`, even reversed onto `fresh_361b`), B consolidated into A, all 26 recomputed with the guard in error mode, then per-group per-table digests against the reference |
| `split_stamp.txt`, `split_status.txt`, `split_test_run.log`, `split_test.started` | provenance and the timeline (20:33–21:32 UTC; run from a worktree at `1d00c04c`, the reference's SHA) |
| `split_guard_warnings.tsv` | the downstream guard's warnings at open: 18 of 26 groups, the evidence the order was bad |
| `split_test.csv`, `split_test_summary.txt`, `split_compare.log` | 442 digests, 387 identical, 55 differing; the control schema differs as it must |
| `split_test_diff_streams_access_NATR.csv`, `split_test_diff_streams_access_TOOD.csv` | the two access differences, per column: NATR 2 segments, TOOD 2 |
| `split_tood_probe.csv` | TOOD's two segments and the 140 natural barriers downstream of them in `fresh_default` (FROG, LKEC, UKEC, ULRD), none in the scratch schema |
| `split_column_joins.csv` | the per-column join of the split build on the reference: rows joined, rows differing and the largest difference for `streams` lengths and geometry and `barriers` positions; the gate-blanked habitat rows in MILL and LPCE |
| `hostcheck_build_MILL.log`, `hostcheck_build_LPCE.log` | the same-host control: MILL and LPCE rebuilt on m1 alone into `fresh_361c` |
| `split_verdict.md` | every differing digest traced: cross-host arithmetic at ≤ 3.7e-9 m (the reference Peace was built on an amd64 cloud host), or the test's 26-group scope (NATR's two Fraser-coded segments and TOOD's two, whose downstream barriers are TAKL's and FROG's, LKEC's, UKEC's and ULRD's). Nothing attributable to the order. **Verdict: a component can be split across hosts.** |

## Group atoms (Phase 4a)

| file | what it holds |
|---|---|
| `buckets_group4.md`, `buckets_group5.md` (+ `.stderr`) | `study_area_buckets.R --atom=group` on the 246 at this run's minutes (1,077 host-minutes; largest component 231): four hosts 270 min under either atom; five hosts 216 under group atoms against 231 under components |

Scratch schemas `fresh_361a`, `fresh_361b`, `fresh_361c` and the worktree were kept until the PR merged.
