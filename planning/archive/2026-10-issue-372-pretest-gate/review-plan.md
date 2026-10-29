# Plan review, #372 (Plan agent, 2026-10-28; returned after Phases 1-2 landed)

Findings as returned, condensed; disposition in the right column.

| id | finding | disposition |
|---|---|---|
| B1 | exact HEAD-SHA match breaks on merge commits, version bumps, CITATION bot commits | adopted: a record is valid while every file changed between its SHA and HEAD maps to `none` (an R function in pretest.R, called from preflight_local) |
| B2 | record does not prove the range it gated; `--since=HEAD~1` passes trivially | adopted: until must be the modelled SHA (already); preflight requires `since` to be an ancestor-or-equal of every link_sha among the history's newest finished rows |
| B3 | `--preflight-note` is never recorded; LNK_RUN_LABEL cannot carry text | adopted: `--pretest-note` writes a `log_pretest` row `verdict='override'` with the note and run_uid (not under --preflight-only) |
| G1 | pathspec misses data-raw/wsg_run_one.R, DESCRIPTION, inst/extdata outside the bundle | adopted: pathspec is R/, inst/extdata/, DESCRIPTION and the run's data-raw entry points; coverage test extends to inst/extdata |
| G2 | recompute / consolidate / habitat gate unexercised but would map `none` | adopted: new special input `unexercised`, named in pretest.md and the record's notes; lnk_access.R moves from none to unexercised |
| G3 | empty scratch never runs the existing-table DDL branch of persist_init / log | adopted: scratch tables created `LIKE <persist>.<table> INCLUDING ALL` before modelling |
| G4 | inputs ignore the config (near_river off under bcfishpass) | not adopted: costs picks, not correctness; stated in RUNBOOK |
| G5 | no barrier-positions input for #326 | not adopted: `gradient` is the proxy; stated |
| G6 | nothing kills a group slow across many statements | adopted: wall-clock watchdog at the bound, backends terminated by application_name, verdict `bound` |
| G7 | gate shares working_<wsg>; a live run would be corrupted | adopted: refuse while the persist log has an open row started in the last 24 h |
| G8 | one-sample history; KTSU's is the stall | adopted: `--minutes-schema` and `--minutes-exclude`, as the packer has |
| G9 | where the record's values come from | adopted: scratch log rows; newest record per key wins; to_regclass |
| G10 | preflight_local is not testable in place | adopted: the check is `pretest_record_check()` in pretest.R |
| A1 | access cost under-exercised (scratch barriers hold only the picks) | stated as a limit |
| A2 | k=3 misses 2x regressions (QUES 4.9 -> 9.3) | stated |
| A3 | acceptance should bound against pre-0.68 minutes | adopted: acceptance uses `--minutes-schema=fresh_default_20261017` |
| A4 | KTSU is not picked by any input | recorded in evidence with each 10-23 group's rank |
| A5 | fresh range from what ran, not pins | not adopted: the pin at since equals the history's fresh and the driver checks installed = recorded; diff limited to R/ |
| A6 | --since default should be the oldest of the newest rows | adopted |
| S1, O2 | enforcement scope; --refresh-primitives after the gate | documented |
| S2 | union size | measured: 8 groups for 1d00c04c..HEAD |
