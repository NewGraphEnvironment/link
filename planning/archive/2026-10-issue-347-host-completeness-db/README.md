## Outcome

`data-raw/study_area_run.sh` counted each host's finished groups from log text with a line-start-anchored match; in run `20261017_004619-3f4c713b` an R warning flushed without a newline hid 18 finished groups, which the driver left out of consolidate and would have burned with the hosts (#347). The count now comes from each host's database (`<schema>.log` for the run_uid, `date_end` set), read over sentinel-framed probes so an unreachable host is unknown rather than empty; log `done` markers only add to the consolidate bucket. Host accounting moved to `data-raw/study_area_hosts.sh`, which tests drive in bash with stubbed ssh/psql/tofu/doctl. A cypher is held from dispatch and released only when it is settled (its session ended 0 and consolidate is not running) and its database holds no group this run finished; everything kept, or whose burn did not complete, is listed in `<TS>_kept_hosts.tsv` with measured groups and the commands to recover and burn it, the run exits non-zero, and pre-flight refuses a workspace whose droplet is still up. `cabd_blkey_xref.csv` gained its final newline in all four bundles. What was learned: every defect the review found after round 1 was one mechanism. A label on rows observed on a host ("finished", "partial", "the recompute ran without these") needs provenance (this run wrote them) and settledness (nothing is still writing). The loop ended by enumerating both: two post-dispatch writers, two row sources.

## Measurement

- Live, local fwapg: the finished probe returns 241 for run `20261017_004619-3f4c713b`, the run's group count; the cypher route's remote half (`docker exec -i fresh-db psql`) returns both sentinels and 241 rows. The ssh leg to a live cypher was not run (paid spin).
- `devtools::test()` at 5da51c9d: 3058 pass, 5 fail, none from this branch (3 need the `:63333` tunnel; 2 are the golden dams count, which fails the same on clean main). `test-study_area_hosts.R` at the end: 120 pass; 20 skip with the lib absent.
- 26 mutants of the lib, each caught by at least one test (tables in findings.md). One (m19) survived a first cut and tightened a rule; one mutant pattern did not apply and scored 0 until `cmp` flagged it.
- `config_hash` moves for all four bundles because of the CSV newline (values in findings.md); the operator called that accounting, not a gate.
- Review cost: one plan review plus five code-check rounds (six reviewers, past the five-per-task bound), 13 code-check findings fixed. The plan review overturned the first release rule: `date_end` is set by a soft UPDATE, so the database alone can undercount.

## Evidence

`planning/archive/2026-10-issue-347-host-completeness-db/review-*.md` (plan review and rounds 1-5), `findings.md` (mutation tables, live checks).

Follow-ups drafted, not filed: config_hash checks as accounting; consolidate deleting the dispatcher's earlier `log` rows per group.

Closed by: PR for branch `347-study-area-run-sh-counts-finished-groups`
