# Code-check round 3 (terminating): #454's records against their artifacts

Reviewer: subagent, 2026-11-03. Scope: `git diff 73105fbc...HEAD` records plus the six issue bodies named in the brief. Read-only; no repo file edited but this one.

## Checklist read

- `code-check.md`, `## Mechanisms` prose (14 mechanisms, `|` rows skipped), with "Written data outlives the fix" and "One fact derived twice" read in full. The two that govern this round: *Written data outlives the fix* ("when a derived value changes, enumerate every artifact quoting it ... verify a filed body by parsing it") and *One fact derived twice* ("terminate by enumerating every derived column with its population ... and showing none disagrees with its name").

## Method

Texts extracted by script (awk on the section markers in the brief) into the scratchpad: research section (53 lines) + header lines 3, 4, 301; CLAUDE.md block (13 lines); archive README (28 lines); progress.md from "Session 2026-11-03 (resumed" (57 lines); issue bodies via `gh issue view` (#369, #371, #374, #375, #376 "Measured at the provincial `default`" paragraph; #444 "## The full build now exists"; #454 `- [x]` lines; #377 the run's table row). A regex over them (shas, clock times, numbers with units, and the words every/all/each/both/no/longest/only/none) gave 998 tokens: research 198, CLAUDE 109, README 142, progress 303, #369 43, #371 21, #374 24, #375 17, #376 32, #444 33, #454 50, #377 26. Tokens that are issue numbers, dates in paths, version numbers inside file names and the run_uid repeated were folded; the rest reduce to the 96 distinct facts below, each checked in every record that states it.

Sources: `phases.tsv` = `data-raw/logs/study_area_run/20261103_163715_phases.tsv`; `cal` = `default_run_454/checks/calibrate.log` and `data-raw/logs/host_speeds*.tsv`; `plan` = `default_run_454/plan.tsv` and `buckets.md`/`buckets.stderr`; `gate` = `data-raw/logs/pretest/20261103_153249_default/` and `checks/gate.log`; `DB` = local fwapg, `fresh_default.log`/`log_recompute` keyed by the run_uid, `fresh_default_minimal.log` keyed by `20261102_203300-60ab009d`, `fresh_default_history.log`; `git` = this worktree.

## Table

| # | item | location(s) | stated | source | recomputed | verdict |
|---|---|---|---|---|---|---|
| 1 | run_uid | all | `20261103_163715-269b585a` | DB, phases.tsv | same | ok |
| 2 | launch time | progress, research | 16:37:15 / 16:37 | `run.started`, phases prep start | 16:37:15 UTC | ok |
| 3 | prep end / prep minutes | progress, research, README | 16:47:45; 10.5 | phases.tsv | 16:47:45, 10.5 | ok |
| 4 | driver done | progress, research | 20:34:30 / 20:34 | phases compare end | 20:34:30 | ok |
| 5 | critical path | research, CLAUDE, README, progress, #375, #377 | 237.2 / 237 | run.log summary; 16:37:15 to 20:34:30 | 237.25 | ok |
| 6 | m1 leg | research, README, progress, #376, #377 | 109.8 (55) / 110 | phases.tsv | 109.8, 55 | ok |
| 7 | m4 leg | same | 121.9 (52) / 122 | phases.tsv | 121.9, 52 | ok |
| 8 | job2 leg | research, README, progress | 159.2 (45) | phases.tsv | 159.2, 45 | ok |
| 9 | job3 leg | same | 175.5 (44) | phases.tsv | 175.5, 44 | ok |
| 10 | job1 leg (longest) | research, README, progress, #375, #376, #377 | 178.6 (45) / 179 | phases.tsv | 178.6, 45 | ok |
| 11 | projected per leg | research, README | 197.2 to 198.1 | cal | 198.0, 198.0, 197.2, 198.1, 198.1 | ok |
| 12 | job1 estimate, 9.8 % under | #376, progress | 198.0; 9.8 % | cal | 1 - 178.6/198.0 = 9.80 % | ok |
| 13 | m1 ratio | research, CLAUDE, README(implied), #376, progress | 0.55 (109.8 vs 198.1) | cal | 0.554 | ok |
| 14 | m4 ratio | research, CLAUDE, #376 | 0.62 | cal | 121.9/198.0 = 0.616 | ok |
| 15 | cloud ratios | research, CLAUDE, #376, progress | 0.80 to 0.90 | cal | 0.804, 0.890, 0.902 | ok |
| 16 | run-wide ratio | research, README, progress | 0.753 | cal | 0.7531 | ok |
| 17 | packed speeds | research, README, progress | m4 1.107, m1 1.183, cloud 0.947 | host_speeds_history | 1.1071, 1.1827, 0.9471 | ok |
| 18 | updated speeds | research, CLAUDE, README, progress, #376, #454 | m1 1.310, m4 1.181, cloud 0.910 | host_speeds.tsv | 1.3097, 1.1811, 0.9103 | ok |
| 19 | "after two runs" | CLAUDE | two | host_speeds.tsv `n_runs` | 2 | ok |
| 20 | m4 ended before last cloud leg | research, CLAUDE, README, #376 | 57 | 18:49:41 vs 19:46:26 | 56.8 | ok |
| 21 | m1 ended before last cloud leg | same | 69 | 18:37:42 vs 19:46:26 | 68.7 | ok |
| 22 | +9.0 vs #441's critical path | research | 9.0 | 237.2 - 228.2 (#441 run.log) | 9.0 | ok |
| 23 | leg-minutes here / #441 | research | 745.0 / 701.6 | both phases.tsv | 745.0 / 701.6 | ok |
| 24 | group minutes summed | research | 734.0 | DB log | 734.0 | ok |
| 25 | group median | research | 2.58 | DB log | 2.58 | ok |
| 26 | QUES on job3 | research, CLAUDE, README, #371, progress | 27.0, job3 | DB log | 26.98, cypher-job3 | ok |
| 27 | GRAI, BULK, LFRA, "cloud hosts" | research | 10.3, 9.6, 8.9 | DB log | 10.28 job2, 9.56 job1, 8.94 job1 | ok |
| 28 | QUES 0.68.0 history on m1 | research, CLAUDE, README | 9.3 | `fresh_default_history.log` | 9.35, m1 | ok |
| 29 | QUES gate on m4, bound | research, CLAUDE, README, progress | 15.5; bound 28.0 | gate pretest.md | 15.5; 28.0 | ok |
| 30 | QUES in #441 | research | 20.9 on a cloud host | DB minimal log | 20.91 cypher-job3 | ok |
| 31 | QUES longest in both runs | research, CLAUDE | longest | DB both logs | QUES top in each (MORK 12.76 next in #441, GRAI 10.28 here) | ok |
| 32 | statements under 30 min bound / no timeout | research, README, #371, progress | none hit | `run_*.log` TIMEOUT and "canceling statement" counts | 0 in all five | ok |
| 33 | plan total | research | 1,015.4 | plan.tsv weight sum | 1,015.4 | ok |
| 34 | KTSU, OKAN at median | research, progress | median | buckets.stderr, plan.tsv | 3.6471 each | ok |
| 35 | per-host weights | progress | 219 / 234 / 188 / 188 / 187 | plan.tsv | 219.2 / 234.2 / 187.6 / 187.6 / 186.8 | ok |
| 36 | per-host raw minutes | progress | 215.1 / 231.5 / 186.1 / 182.2 / 189.6 | plan.tsv `minutes` | same | ok |
| 37 | groups per host in plan | progress | 52 / 55 / 45 / 45 / 44 | plan.tsv | same | ok |
| 38 | loads 197 to 198, job2 longest | progress | yes | buckets.md | 198,198,198,198,197; makespan job2 | ok |
| 39 | component atoms makespan | progress | 231 | buckets.md | 231 | ok |
| 40 | 241 modelable, 5 dropped | progress | 241 / 5 | buckets.md | 241 / 5 | ok |
| 41 | consolidate m1 | research, CLAUDE(n/a), README, progress | 42.9 (55) | phases.tsv | 42.9, 55 | ok |
| 42 | consolidate job2/job3/job1 | research, README, progress | 11.7 / 12.6 / 14.0 | phases.tsv | same | ok |
| 43 | m1 barriers / streams copy | research | 8.9 / 29.3 min | consolidate_worker1.log | 532.0 s / 1755.5 s = 8.87 / 29.26 | ok |
| 44 | #441 copies | research | 9.4 / 34.9 | 20261102 consolidate_worker1.log | 562.2 s / 2093.3 s = 9.37 / 34.89 | ok |
| 45 | tailscale before | research, #454 | direct, 87 ms | phase1_hosts.txt | direct, 87 ms | ok |
| 46 | tailscale after | research, progress, #454 | direct, 64 ms | tailscale_path.txt | `via <ip>:49680` (no DERP), 64 ms | ok |
| 47 | recompute window | research, progress, #375 | 18:26 to 20:26; 119.5 wall | phases.tsv | 18:26:40 to 20:26:10, 119.5 | ok |
| 48 | recompute summed | research, README, #377 | 156.2 / 156 | DB log_recompute | 156.2 | ok |
| 49 | recompute median, SETN | research | 0.57, 5.5 | DB log_recompute | 0.571, 5.51 | ok |
| 50 | early launches | research, README, progress, #374 | 82 | recompute_launched.tsv | 82 early, 159 final | ok |
| 51 | early before last leg end | same | 46 | launched.tsv vs 19:46:26 | 46 | ok |
| 52 | after last leg | research, #377 | 39.7 / 40 | 20:26:10 - 19:46:26 | 39.7 | ok |
| 53 | recompute tail after last consolidate | research, README, #374 | 15.6 | 20:26:10 - 20:10:33 | 15.6 | ok |
| 54 | replay tail | README, #374 | 60.6 | CLAUDE.md #374 status | 60.6 | ok |
| 55 | consolidate tail past last leg | progress, #375, #377 | 24.1 / 24 | 20:10:33 - 19:46:26 | 24.1 | ok |
| 56 | compare | progress | 8.3 | phases.tsv | 8.3 | ok |
| 57 | leg end to burn | #369 | job2 12.2, job3 13.1, job1 24.6 | phases.tsv | 12.15, 13.12, 24.57 | ok |
| 58 | job1 waited | CLAUDE, README, #369, progress | 10.0 | leg end 19:46:26 to account 19:56:29 | 10.05 | ok |
| 59 | job1 leg end | CLAUDE, #374 | 19:46 / 19:46:26 | phases.tsv | 19:46:26 | ok |
| 60 | burned within 0.5 min of consolidate | #369, progress | 0.5 each | phases.tsv | burns start at consolidate end, 0.5 each | ok |
| 61 | m1 consolidate window, overlaps | #369 | 18:37 to 19:20; job2's wholly during legs; job3's 3 min before job1's end; job1's 19:56 to 20:10 after every leg | phases.tsv | 18:37:43 to 19:20:39; 19:27-19:38 while job1/job3 modelled; 19:43:24 vs 19:46:26 = 3.0; 19:56:31 to 20:10:33 | ok |
| 62 | dispatcher leg end, 12 min into m1's copy | #369 | 18:49, 12 | phases.tsv | 18:49:41, 11.97 | ok |
| 63 | burns | research | 19:39, 19:56, 20:11 | phases.tsv | 19:39:13, 19:56:29, 20:11:00 | ok |
| 64 | cloud host-hours | research | about 9.9 | spin 16:37:15/35 to burns | 9.90 to 9.92 | ok |
| 65 | `consolidate_state.tsv` contents | #369 | "one `ok` row per host for all 241 groups" | consolidate_state.tsv | 189 rows, one per group (worker1 55, job1 45, job2 45, job3 44), all `ok`; the dispatcher's 52 groups have no row | **mismatch (F1)** |
| 66 | `kept_hosts.tsv` | #369 | "is empty" | `study_area_hosts.sh` `hosts_kept_report`; file list | absent: removed when nothing is kept, and `check.sh` passes on absence | **mismatch (F2)** |
| 67 | segments | research, CLAUDE, README, progress, #444, #377 | 5.55 M / 5,546,370 | DB streams | 5,546,370 | ok |
| 68 | ratio to 0.68.0 build | research, CLAUDE, README | 0.49 of 11.39 M | DB / prior record | 0.487 | ok |
| 69 | minimal segments, ratio | research, CLAUDE(n/a), README, #444 | 4.99 M; 1.11 | DB minimal streams | 4,987,761; 1.112 | ok |
| 70 | schema size | research, CLAUDE, README, progress | 19 GB (minimal 19 GB) | DB `pg_total_relation_size` | 19 GB / 19 GB | ok |
| 71 | tokens on run rows | research, CLAUDE, README, progress | `cut-full-top acc-v5 grad-seg q-fwapg` on 241 | DB, tokens.txt | 241 rows, one token set | ok |
| 72 | seeded rows | research, CLAUDE, README, progress, #454 | 242, token columns NULL | DB | 242 rows, run 20261023, 0.68.0, fresh 0.42.0, tokens NULL | ok |
| 73 | "Every row carries ... one link SHA, fresh 0.52.0" | #454 acceptance | every row | DB `fresh_default.log` | 483 rows; 242 carry NULL tokens, link 0.68.0, fresh 0.42.0 | **mismatch (F3)** |
| 74 | one link sha, one fresh sha, five hosts | research, README, progress | 4dfbfa49, 245c8d8d, 5 | DB | 1, 1, 5 hosts, clean | ok |
| 75 | link 0.78.2 / fresh 0.52.0 | all | — | DB, DESCRIPTION | 0.78.2 / 0.52.0 | ok |
| 76 | gate commit | research, README, progress | 68a6196f | range.txt | `1d00c04c..68a6196f`; ancestor of 4dfbfa49 | ok |
| 77 | gate window | progress | 15:32 to 16:24 | dir name 153249; elapsed sum 3,041 s | 15:32:49 to ~16:24 | ok |
| 78 | gate picks | research, README, progress, #454 | 11, all pass, 0 other sessions | gate report | 11 pass, 0 | ok |
| 79 | gate per-pick minutes | progress | SETN 7.7/16.3 ... SAJR 1.0/1.6 | gate report | all eleven match | ok |
| 80 | gate rest 0.35 to 0.80 | README | 0.35 to 0.80 | gate report | BULK 0.35 to TOAD 0.80 | ok |
| 81 | gate command | #454 | `--config=default --schema=fresh_default --minutes-exclude=KTSU,OKAN` | gate.log header | history and record schema fresh_default, excluding KTSU,OKAN | ok |
| 82 | check.sh / verifiers / audit | research, CLAUDE, README, progress, #369, #374, #454 | all PASS; 2,191 of 2,191 | check.txt, verify.log, verify_extra.log, recompute_audit.log | same; verify_extra PASS at 241 | ok |
| 83 | outside readers 0 | progress | 0 | outside_readers.tsv | header only | ok |
| 84 | coverage / recompute 241 of 241, no INCOMPLETE | research, progress | yes | run.log | coverage ok 241, `241/241`, no INCOMPLETE, `study_area_run done` | ok |
| 85 | "every phase `ok`" | research, progress | every | phases.tsv | 27 `ok`, 2 `skipped` (refresh, burn worker1) | **mismatch (F5, minor)** |
| 86 | link sha pair | CLAUDE, README, progress, #444 | 193cb8aa (0.78.1) vs 4dfbfa49 (0.78.2) | DB both logs, git | same | ok |
| 87 | diff between them | CLAUDE, README, progress, #444 | only DESCRIPTION's version under R/, inst/, tests, drivers | `git diff --stat 193cb8aa 4dfbfa49 -- R inst tests DESCRIPTION data-raw/*.R data-raw/*.sh` | DESCRIPTION only (Version and Date lines) | ok (Date rides with the version) |
| 88 | same fresh and primitives as minimal | #444, research | 245c8d8d; same load | DB both logs | fresh, fwapg_sha 9a62b0c2, bcfishobs_sha dd9a5e5d equal | ok |
| 89 | #444 parent table status | README Owed vs README Measurement, CLAUDE Owed, #444 | "now buildable" vs "guard refuses the pair" | the four records | contradictory | **mismatch (F4)** |
| 90 | "both schemas at one code" | research (bullet 5; also intro "at the code ... `fresh_default_minimal` was built at") | one code | DB link_sha | two link_shas; #444's guard refuses; research alone omits it | **mismatch (F4)** |
| 91 | m4 dev schema | CLAUDE, progress, #454 | 30 groups, 3.5 GB | DB | 30 groups, 3,501 MB | ok |
| 92 | history log has no token columns; run_id no default | progress | absent; no default | information_schema | none; NULL default | ok |
| 93 | probes | progress | 0 clients each, 283 / 287 GB, 0 droplets, bchamp ids 1790057230537 / 1793134826715, fresh 245c8d8d on both | phase1_hosts.txt | same | ok |
| 94 | bcfishobs clone | progress, #454 | dd9a5e5d | DB bcfishobs_sha | dd9a5e5d | ok |
| 95 | launch flags | progress | `--recompute-jobs=8 --statement-timeout=30 --auto-install`, `--buckets-exact`, run label | launch.sh | same | ok |
| 96 | not re-fit (#259, #261) | research section + header line 301, README, CLAUDE, #454 | owed | — | consistent in all five | ok |

Not checkable from committed artifacts or the local DB (stated as accepted, not flagged): m1's renamed schema and its 242 rows; m4's earlier fresh 0.53.0 install details (`142b34d`, 00:36 UTC); the 11.39 M of the 0.68.0 build and QUES's 63.3 km (taken from earlier records).

## Findings

1. **[severity: bug]** #369 body, "Measured at the provincial `default`" paragraph — "`<TS>_consolidate_state.tsv` holds one `ok` row per host for all 241 groups". The file holds 189 rows, one per **group**, for the groups modelled on the four consolidated hosts (worker1 55, job1 45, job2 45, job3 44), all `ok`; the dispatcher's 52 groups are never consolidated and have no row. Stated "per host ... 241" vs recomputed "per group ... 189". **Rule:** code-check.md "One fact derived twice" (a count stated over a population the artifact does not hold).

2. **[severity: fragile]** #369 body, same paragraph — "`kept_hosts.tsv` is empty". No `20261103_163715_kept_hosts.tsv` exists: `hosts_kept_report()` (`data-raw/study_area_hosts.sh`) removes the file when nothing is kept, and `check.sh`'s "no host kept" passes on its absence. The conclusion (no host kept) holds; the artifact named does not exist to be read. Say "no `kept_hosts.tsv` was written (no host kept)". **Rule:** code-check.md "One fact derived twice".

3. **[severity: fragile]** #454 body, Acceptance — "- [x] Every row carries `cut-full-top acc-v5 grad-seg q-fwapg`, one link SHA, fresh 0.52.0." `fresh_default.log` holds 483 rows: the run's 241 carry it, the 242 seeded 0.68.0 rows carry NULL tokens, link 0.68.0 and fresh 0.42.0. Round 1 scoped the same claim to "the run's 241 rows" in research, CLAUDE.md and the README; this ticked box is the copy left unscoped. **Rule:** code-check.md "Written data outlives the fix" (enumerate every artifact quoting a value, filed bodies included).

4. **[severity: fragile]** #444's state disagrees across records. (a) Archive README `## Owed` — "#444's parent table, now buildable." — contradicts its own Measurement bullet ("#444's guard as worded refuses the pair"), CLAUDE.md's Owed ("its `link_sha` guard, as worded, refuses this pair") and #444's body. (b) Research section, bullet "Segments fell to 0.49 ..." — "#444's join ... has both schemas at one code in one database" (and the intro's "at the code ... `fresh_default_minimal` was built at"): the two builds carry different `link_sha`s (`193cb8aa` vs `4dfbfa49`) and #444's guard refuses them; research is the one record that does not say so. Stated "buildable" / "one code" vs recomputed: two shas, guard refuses, only DESCRIPTION differs. **Rule:** code-check.md "Written data outlives the fix" (one fact edited in some copies and not the others).

5. **[severity: fragile]** Research intro ("every phase `ok`") and progress.md ("every phase `ok`") — `phases.tsv` and the driver's printed table carry two `skipped` rows (`refresh`, `burn worker1`) beside 27 `ok`. Both skips are by design (no `--refresh-primitives`; a worker is not burned), so "every phase that ran `ok`, refresh and the worker's burn skipped by design" is the accurate form. **Rule:** code-check.md "A guard that fails toward pass" (a quantifier checked against the population it names); minor.

96 facts checked over 998 extracted tokens; 91 agree with their artifacts in every record that states them, 5 findings above.
