# Code-check round 4: branch `441-minimal-run` (base `552f43d6`, head `68f82ce5`)

## Checklist read

- `code-check.md.index` in full. In `code-check.md`: "A guard's scope, escape hatches, and remedies" in full (prose and instance table), with its "Compression runs both ways" paragraph (a condition dropped, a sample restated as a rate, an attribution widened) and its terminating rule (enumerate every claim by axis and subject, execute each; a justification never measured is a third state with no tell). The prose (rows skipped) of every other H3 under `## Mechanisms`: a guard that fails toward pass, a fixture that cannot reach the failure mode, a proxy is not the property, verification that reads its own output, a fix lands in one of two callers, restore the bug and prove the guard fires, a shared working tree, a wrapper's exit is not the work, zero-length/empty/unset, the probe is broken before the world is, written data outlives the fix, serialization loses meaning, one fact derived twice.
- Round 3's review (`review-run-round3.md`) and its fix commit `68f82ce5` (`git show`).
- No R or spatial code changed on the branch (`git diff --name-only 552f43d6...HEAD` outside `data-raw/logs/`: CLAUDE.md, RUNBOOK.md, research, planning only), so `code-check-r.md` / `-spatial.md` patterns do not apply; `launch.sh`'s shell was read against `code-check-shell.md`'s index (bash 3.2 empty arrays: launch.sh runs under `$BASH`, which the driver requires to be >= 5.1, `study_area_run.sh:209`).

Method: every quantitative or quantified claim in the lines the branch adds to CLAUDE.md, RUNBOOK.md, `research/study_area_run.md`, `planning/active/{task_plan,progress,findings}.md` and `launch.sh`'s comments, executed against the committed logs, read-only SELECTs on m4's local `fwapg` (`fresh_default_minimal`, `fresh_default_history`, `whse_basemapping`), git, and `gh`. Positive controls: the IPv4 grep matched a planted `10.1.2.3`; the DB byte sums reproduced round 2's 309,380,089 B.

## Enumeration

| # | Where | Claim | Source checked | Verdict |
|---|---|---|---|---|
| 1 | CLAUDE 15 | run_uid `20261102_203300-60ab009d`, `default_minimal` into `fresh_default_minimal` | DB `log`: 241 rows, 1 run_uid, 241 groups | matches |
| 2 | CLAUDE 15 | m4 dispatcher, m1 worker, three cloud hosts | `log.host`: m4 48, m1 49, cypher-job1/2/3 48 each | matches |
| 3 | CLAUDE 15 | link `193cb8aa` (0.78.1), fresh 0.52.0 | DB distinct row: 0.78.1 / 193cb8aa…, 0.52.0 / 245c8d8d… | matches |
| 4 | CLAUDE 15 | tokens on every row | DB count with all four tokens = 241; `checks/tokens.txt` | matches |
| 5 | CLAUDE 15 | driver exit 0 in 228.2 min | `run.log` `DRIVER_EXIT=0`, "critical path: 228.2 min" | matches |
| 6 | CLAUDE 15 | both verifiers pass at `expected_n=241` | `checks/verify.log:10,568`; `verify_extra.log` NOTICE PASS 241 | matches |
| 7 | CLAUDE 15 | audit 2,191 of 2,191 pairs | `checks/recompute_audit.log` | matches |
| 8 | CLAUDE 15 | no host kept, no droplet left | `checks/check.txt` (`check.sh:80` lists droplets with doctl); run.log "burn clean" x3 | matches |
| 9 | CLAUDE 15 | 4.99 M segments, 19 GB | DB 4,987,761 rows / 241 groups; `pg_total_relation_size` sum 19,973,988,352 B, `pg_size_pretty` "19 GB" | matches |
| 10 | CLAUDE 15 | knowledge#120 can read it | tokens on `log` (241); knowledge#120 body: `knw_build_record()` reads tokens from `log` | matches (plausible; nothing read yet) |
| 11 | CLAUDE 18 | Owed: knowledge#120, #418's rehearsal script, calibrator runs 2 and 3 | knowledge#120 OPEN, #418 OPEN; task_plan 153-155 | matches |
| 12 | CLAUDE 18 | #375 answerable (`phases.tsv` committed) | #375 acceptance 2: "next provincial run's `phases.tsv` committed … #377 row filled"; both present | matches |
| 13 | CLAUDE 18 | #374 tail 12.3 min past the later of last leg and last consolidate | 00:03:11 → 00:15:30 (phases; DB max `log_recompute.date_end` 00:15:29); #374 defines the tail this way | matches (number); see finding A for "can answer" |
| 14 | CLAUDE 18 | #376: job1 183.0 against 202.3, within 10 % | `calibrate.log` 202.3 / 183.0 = 0.905 | matches (number); see finding A |
| 15 | CLAUDE 18 | "#369 (idle cloud minutes, against 2026-10-23)" waits on a `default` run | #369 body owes three items on that run: idle cloud minutes per host, consolidate rows inside the modelling window, overlapping dispatcher groups' minutes against 2026-10-23 | **mismatch** (finding A) |
| 16 | CLAUDE 18 | #371 criterion 2 waits on a `default` run, while #376's is answerable | #371 criterion 2 text "A full run at the default bound completes with no group timing out" is met here (`--statement-timeout=30`, 0 TIMEOUT lines in five leg logs); #376's body names "the next provincial `default` run" exactly as #371's does | **mismatch** (finding A) |
| 17 | CLAUDE 18 | not done: #259 `fit.R`, #261 `predictors.R`/`correlations.R`, #446 | nothing in the evidence runs them; #446 OPEN | matches |
| 18 | CLAUDE 18 | `fresh_default`/`fresh` not rebuilt; re-models of #326, #396, #399, #401, #402, #429, #432 still owed | the run wrote only `fresh_default_minimal`; round 3's table of earlier Owed blocks | matches |
| 19 | CLAUDE 21 | one `tailscale ping m1` at about 22:36 UTC `via DERP(sea)`, mid-copy | `checks/tailscale_path.txt`; consolidate 22:10:31–22:58:06 | matches |
| 20 | CLAUDE 21 | `barriers` and `streams` at about 550 and 870 kB/s | DB row text of m1's 49 groups: 309,380,089 B / 562.2 s = 550; 1,826,786,754 B / 2,093.3 s = 873 (`consolidate_worker1.log:18,22`) | matches |
| 21 | CLAUDE 21 | 47.6 min against about 13 per cloud host | phases 47.6; 13.1, 13.3, 12.8 | matches |
| 22 | CLAUDE 21 | direct at 00:31 UTC | `tailscale_path.txt` | matches |
| 23 | CLAUDE 22 | m1 1.18, m4 1.11, cloud 0.95 | `host_speeds.tsv` 1.1827 / 1.1071 / 0.9471 | matches |
| 24 | CLAUDE 22 | at equal speeds cloud legs 160 to 183, m1 87, m4 103 | `buckets.md` all 1.00x; phases 159.8–183.0, 87.4, 103.3 | matches |
| 25 | CLAUDE 23 | per-host FWA counts are `reltuples` estimates | `R/lnk_log.R:887-893`; `verify_extra.sql:82-86` | matches |
| 26 | CLAUDE 23 | "so their spread … is planner statistics, not different FWA data" | no committed measurement of FWA content per host; m4 `count(*)` 4,907,441 vs its `reltuples` 4,910,797 (read now); m1 and cloud counts unmeasured | **unsupported** (finding B) |
| 27 | CLAUDE 24 | `run.log` redacted before commit | IPv4 grep over `minimal_run_441/` and `20261102_20*`: only `0.0.0.0` (firewall rule in up/burn logs) | matches |
| 28 | RUNBOOK 2608-9 | workers by ssh target (may relay); cloud hosts at droplets' public addresses | `study_area_run.sh:646` (`HOST_SSH` from worker targets), `:1824` (`tofu output droplet_ip`) | matches |
| 29 | RUNBOOK 2609-11 | mid-copy, one `tailscale ping m1`, DERP(sea), no direct | `tailscale_path.txt` (one `ping -c 3`) | matches |
| 30 | RUNBOOK 2611 | `barriers`/`streams` about 550 and 870 kB/s | as 20 | matches |
| 31 | RUNBOOK 2612 | 47.6 min against about 13 for each cloud host's 48 | phases; groups 48 each | matches |
| 32 | RUNBOOK 2612-3 | about two hours later the probe went direct | 22:36 → 00:31 = 1 h 55 m | matches |
| 33 | research 3-5 | Verified / Issues / Produced-by additions | paths exist | matches |
| 34 | research 301 | `fit.R` still owed after the minimal run | nothing re-fit | matches |
| 35 | research 305-6 | run_uid; tokens on all 241 `log` rows | as 1, 4 | matches |
| 36 | research 307 | m4 dispatcher, m1 worker, three cloud hosts | as 2 | matches |
| 37 | research 308-9 | packed `--atom=group --minutes-schema=fresh_default_history --minutes-exclude=KTSU,OKAN`, equal speeds | `buckets.stderr:5,7`; `buckets.md:75,77` | matches |
| 38 | research 309-10 | `--buckets-exact`, `--recompute-jobs=8`, early recompute, each cloud host burned as its leg ended | `launch.sh`; run.log banner; phases (burns follow each consolidate) | matches |
| 39 | research 311 | link `193cb8aa`, fresh `245c8d8d`, one sha of each across five hosts | `tokens.txt` n_link 1, n_fresh 1, hosts 5 | matches |
| 40 | research 312 | gate record at `24b2cbb3`, 11 picks, borrowed history | DB `log_pretest`: 24b2cbb3, pass, `fresh_default_history`/`default`, 11 groups; ancestor of `193cb8aa` | matches |
| 41 | research 313-4 | both verifiers, audit 2,191, no host kept, no droplet | as 6-8 | matches |
| 42 | research 319 | per-leg minutes and groups | phases | matches |
| 43 | research 319 | planned 202 to 203 each | `buckets.md:80-84`; `calibrate.log` 202.2–202.8 | matches |
| 44 | research 320 | 690.2 summed, median 2.3; QUES 20.9, MORK 12.8, BULK 10.7, all cloud | DB 690.2 / 2.32; hosts cypher-job3 / job2 / job1 | matches |
| 45 | research 320 | 1,012 = history's minutes with KTSU, OKAN at the median | `plan.tsv`: minutes 1,004.44, weights 1,011.89, KTSU and OKAN 3.72 each | matches |
| 46 | research 321 | consolidates m1 47.6 (49), job2 13.1, job3 13.3, job1 12.8 | phases | matches |
| 47 | research 322 | recompute 21:51 to 00:15, 126.8 summed, median 0.41, HOMA 5.0 | DB `log_recompute`: 241 rows, 126.8 / 0.41 / HOMA 4.98 | matches |
| 48 | research 322 | 29.4 min after last leg, 12.3 after last consolidate | 23:46:07 → 00:15:30; 00:03:11 → 00:15:30 | matches |
| 49 | research 323 | 228.2 min (20:33 to 00:21); prep 10.0 | phases | matches |
| 50 | research 324 | about 9.9 host-hours; spin 20:33, burns 23:36, 23:50, 00:03 | up logs `202611021333`; burns in phases; 3.06 + 3.29 + 3.51 h | matches |
| 51 | research 325 | 19 GB, 4.99 M segments | as 9 | matches |
| 52 | research 327-8 | 0.69 of the plan (701.6 / 1,012); group minutes 0.68 | 701.6 / 1,011.9 = 0.693 (= calibrator ratio); 690.2 / 1,011.9 = 0.682 | matches |
| 53 | research 328-9 | no group failed, no statement bounded | coverage 241/241 `recompute`; 0 `TIMEOUT`/bound lines in five leg logs | matches |
| 54 | research 329-30 | history is `default` at 0.68.0, 11.39 M segments, before #326 and #396 | DB `fresh_default_history`: newest row per group all 0.68.0, run 20261023; 11.39 M from research §2026-10-23 table | matches |
| 55 | research 331-3 | observed 1.61 / 1.36 / 0.82; moved to 1.18 / 1.11 / 0.95 | `calibrate.log`; `host_speeds_history.tsv` | matches |
| 56 | research 333-6 | relay mid-copy at about 22:36; 550 kB/s (309 MB in 9.4 min), 870 kB/s (1.83 GB in 34.9 min) | as 19, 20 | matches |
| 57 | research 336-7 | 00:31, after the run, direct | `tailscale_path.txt` | matches |
| 58 | research 338 | cloud hosts at droplets' public addresses | as 28 | matches |
| 59 | research 338-9 | did not reach the critical path (m1 finished first) | m1 model ends 22:10 (first), consolidate ends 22:58 before any cloud leg | matches |
| 60 | research 340 | `fwa_stream_networks_sp` 4,898,813 to 4,910,797, as in October | `verify_extra.log`; `provincial_361/run_verify_extra.log` (m1 4,907,804, cloud 4,898,813) | matches |
| 61 | research 341 | "planner statistics, not different FWA data" | as 26 | **unsupported** (finding B) |
| 62 | progress 23 | merge SHAs; v0.78.0 tag; each merged after the previous merge's CI went green | `gh pr view`; `git tag --points-at`; `gh run list --commit`: each predecessor's runs end before the next merge (13:01:40 < 13:02:19, 13:07:45 < 13:09:01, 13:13:19 < 13:14:38, 13:19:05 < 13:20:21) | matches |
| 63 | progress 23 | the four after #443 ship only a RUNBOOK paragraph and a test; v0.78.1 `fd91d1b7`, no code change | non-`.Rbuildignore`d diff `57cb86e3..fd91d1b7`: RUNBOOK +2 lines, `test-worker_prep.R`, version files | matches |
| 64 | progress 23 | #415, #440, #442 closed; #439, #418 open | `gh issue view` | matches |
| 65 | progress 24 | gate record an ancestor of `main`; DESCRIPTION maps to `none` | `merge-base --is-ancestor`; `pretest_inputs.csv:149` | matches |
| 66 | progress 25 | filed #450 | #450 OPEN | matches |
| 67 | progress 26 | branch cut from `main` at `552f43d6` | 552f43d6 ancestor of origin/main | matches |
| 68 | progress 32 | bchamp objects HEAD at 20:30 UTC to `load_stamps.csv` versions | not labelled in-session; corroborated: cloud hosts snapshotted from S3 at prep (~20:35–20:42) and loaded exactly those version ids (`verify_extra.log`) | matches (indirect) |
| 69 | progress 33 | operator bcfishobs "still holds the two files"; clean clone at `dd9a5e5d` | `log.bcfishobs_sha` dd9a5e5d on all rows; "two files" has no committed source and no in-session label | **unsupported** (finding C) |
| 70 | progress 34 | quiet at 20:31, 112 GB free | labelled "read in-session, not saved to a file" | acceptable as labelled |
| 71 | progress 35 | 246 focal; 241 modelable, 5 dropped; 48/49/48/48/48; 202 to 203; 1,012; m4 at the median speed | `buckets.stderr:1`; `buckets.md:75,80-91`; `plan.tsv` | matches |
| 72 | progress 36 | launch decisions (flags, label, schema, groups) | `launch.sh`; run.log banner | matches |
| 73 | progress 37; task_plan 120 | nothing in the worktree changed while the run was in flight | commits `193cb8aa` 20:32:14 UTC then `42969705` 00:23:33 UTC (after exit 00:21:12); `link_dirty` f on all 241 rows | matches |
| 74 | progress 41 | pre-flight passed in full at `193cb8aa`; gate 11 picks; primitives 0.5 d; credentials, tofu, worker | `run.log:28-42` | matches |
| 75 | progress 42 | host pre-flight passed on all five | `run.log` "host parity - OK across 5", four "primitives within 7 d" plus the dispatcher's | matches |
| 76 | progress 42 | legs, no failed group, no statement bound | phases; coverage; 0 TIMEOUT | matches |
| 77 | progress 42 | consolidates m1 47.6, cloud 12.8 to 13.3; each cloud host burned as its leg ended | phases | matches |
| 78 | progress 42 | recompute 21:51–00:15; exit 0 at 00:21; 228.2 | phases; run.log | matches |
| 79 | progress 43 | `check.sh` all PASS (items listed) | `check.txt` | matches |
| 80 | progress 43 | `verify_extra.sql` exit 0; 241 rows, one fresh sha, one link sha, clean | `verify_extra.log` PASS; `tokens.txt` dirty f | matches |
| 81 | progress 44 | calibrator values, ratio 0.693 | `calibrate.log` | matches |
| 82 | progress 45 | research, RUNBOOK, CLAUDE, #377 runs row written | diff; #377 body line 56 holds the row | matches |
| 83 | progress 46 | run.log held three droplet addresses, redacted | three `cy[jobN] = <host>` lines | matches |
| 84 | findings 100 | bold lead: "The m4 to m1 path was a Tailscale DERP relay during m1's consolidate" | one probe at about 22:36; consolidate 22:10:31–22:58:06; nothing covers the `barriers` copy (22:10–22:19) | **mismatch** (finding D) |
| 85 | findings 100 | 309 MB in 562 s, 1.83 GB in 2,093 s, about 550 and 870 kB/s; 47.6 vs 13 | as 20, 21 | matches |
| 86 | findings 100 | planning's probes measured latency and loss only | `minimal_run_441/phase0_connections.txt` (ping, ssh round trip, API time) | matches |
| 87 | findings 101 | 4,987,761 / 241, 19 GB; 690.2, median 2.32, QUES 20.9 on job3; recompute 126.8, 0.41, HOMA 5.0 | DB | matches |
| 88 | findings 102 | per-host counts m4 4,910,797, m1 4,907,804, cloud 4,898,813 are estimates, "not data" | counts match `verify_extra.log`; "not data" as 26 | **unsupported** (finding B) |
| 89 | launch.sh 3-5 | 246 focal groups, history minutes, KTSU/OKAN at median, plan.tsv for the calibrator | `buckets.stderr`; `calibrate.log` reads the plan | matches |
| 90 | launch.sh 6 | first `--focal` dispatcher (m4), then worker1 (m1), job1, job2, job3 | `buckets.md` DS-first lists; run.log resolve lines | matches |
| 91 | launch.sh 7-8 | the pre-flight refuses a dirty bcfishobs | `study_area_run.sh:1121` | matches |
| 92 | launch.sh 9 | bash >= 5.1 | `study_area_run.sh:209` | matches |
| 93 | launch.sh 15 | `PREFLIGHT=1` runs `--preflight-only` (no spend) | launch.sh lines 20-21; `preflight_only.log` MODE line | matches |
| 94 | launch.sh 2 | "exactly as launched" | run.log focal strings and banner flags equal launch.sh's | matches |
| 95 | task_plan 119 [x] | branch from `main`, pushed; `--preflight-only` passes in full (`preflight_only.log`); decisions pushed before launch | 552f43d6 on main; log `20261102_203222` (after `193cb8aa` at 20:32:14, before launch 20:33:00), "origin … at HEAD", "local gates passed"; its own NOT CHECKED lines (host parity, cypher vintage, worker rows) were checked by the launch's host pre-flight (run.log) | matches |
| 96 | task_plan 120 [x] | pack, launch detached, end marker and foreground re-read, nothing edited | run.log `DRIVER_EXIT=0`; `check.txt` "driver exit PASS"; as 73 | matches |
| 97 | task_plan 121 [x] | second launch not needed: no group failed | coverage 241/241 | matches |
| 98 | task_plan 122 [x] | verifiers, audit, calibrator, research, #377 row, RUNBOOK, CLAUDE Status | all present | matches |
| 99 | task_plan 106 [ ] note | check 5 passed after the run | `verify_extra.sql:14-16,69` (check 5 = loader version ids agree across hosts); PASS | matches |
| 100 | task_plan 159 [x] | "Tests pass (full suite at PRs 1 to 5 …)" | #443 test plan: full suite 5,232 expectations; #449 test plan: `test-worker_prep.R` only (25 expectations, a test file and `worker_prep.sh` changed); #445, #447, #448 test plans record no suite; nothing in `planning/` records one; CI R-CMD-check green on 55c2b616, 481dc8d3, 794ddd0e, fd91d1b7 (skips the live-DB tests) | **unsupported** (finding E) |
| 101 | task_plan 161 [x] | PWF checkboxes match landed work | falls with 100 | **unsupported** (finding E) |

**Count: 101 claims — 92 matches (one of them acceptable as labelled in-session), 3 mismatches (15, 16, 84), 6 unsupported (26, 61, 69, 88, 100, 101).**

Round 3's eleven: finding 1 (Owed list) is rewritten and is finding A here (the rewrite created a new inconsistency). Finding 2 (550 to 870 by table) holds in CLAUDE, RUNBOOK, progress. Finding 3 (relay widened) holds in RUNBOOK and research, not in findings.md (finding D). Finding 4 (202 to 203) holds. Finding 5 (in-session figures) holds for the quiet/112 GB line (labelled) and the 701 KiB/s sample (removed); progress line 33's "two files" was not in round 3's list (finding C). Finding 6 (boxes): 106 unticked with the note, 119 now cites a committed `--preflight-only` log; 161 is ticked again and falls with 159 (finding E).

## Findings

- **[severity: fragile]** CLAUDE.md:18 — The Owed list's partition between "this run can answer" and "waits on a provincial `default` run" is not derived from the issues. (1) #376's body says criterion 2 waits on "the next provincial `default` run", exactly as #371's does, yet #376 is listed as answerable and #371 as waiting. #371's criterion 2 as written ("A full run at the default bound completes with no group timing out") is met by this run: `--statement-timeout=30` (the default), 0 `TIMEOUT` lines in all five leg logs. Either both wait on a `default` run, or both can be answered here with the operator deciding. (2) "#369 (idle cloud minutes, against 2026-10-23)" compresses #369's owed item 3, which has three parts: idle cloud minutes per host, consolidate rows inside the dispatcher's modelling window, and the overlapping dispatcher groups' minutes against 2026-10-23. The window part is dropped, and this run's `consolidate_state.tsv` puts every cloud `ok` row (23:35:59, 23:49:48, 00:03:09) after the dispatcher's model phase ended (22:26:18), so it does not meet it, which is information a reader of the Owed list needs. (3) #374's acceptance is a tail "shorter than with `--recompute-at-end` on the same groups", reported beside the 2026-10-23 replay; this run gives the tail (12.3 min) but neither comparison is on the minimal network, which is the same reason #369's "against 2026-10-23" is said to wait. Fix: list what each issue's acceptance needs and which part this run supplies, using each body's own wording, and treat #371 and #376 the same way.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (compression drops a condition; a partition written down that the next reader will get wrong)
- **[severity: fragile]** CLAUDE.md:23, research/study_area_run.md:339-341, planning/active/findings.md:102 — "their spread across hosts is planner statistics, not different FWA data" / "not data". That the counts are `reltuples` estimates (`R/lnk_log.R:887-893`) shows the spread *could* be planner statistics; it does not show the hosts hold the same FWA rows, and nothing committed measures that (`fwapg_sha` is a checkout sha, not a data version, per CLAUDE.md's 2026-10-12 block; host parity does not compare FWA content). Read now on m4: `count(*)` is 4,907,441 against `reltuples` 4,910,797, so m4's estimate is 3,356 high; m1's and the cloud hosts' true counts are unmeasured. The cloud estimate is 8,628 below m4's true count. Round 3 checked the claim against the estimate code only. Fix: "are estimates, so the spread does not by itself show different FWA data", or measure `count(*)` on each host (the cloud hosts are gone; m1 and m4 can be counted).
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (a justification never measured: the third state with no tell)
- **[severity: fragile]** planning/active/findings.md:100 — The bold lead "The m4 to m1 path was a Tailscale DERP relay during m1's consolidate" states one probe (about 22:36 UTC, during the `streams` copy) for the whole consolidate (22:10:31 to 22:58:06), including the `barriers` copy no probe covers. This is round 3's finding 3: its fix landed in RUNBOOK.md and research's lead ("relay mid-copy"), and CLAUDE.md had it from round 2, but findings.md, which the archive README will index as the evidence record, still carries the widened form. Fix: "was a Tailscale DERP relay mid-copy (one `tailscale ping m1` at about 22:36 UTC …)".
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness" (one fact written in four places, fixed in three); "A guard's scope, escape hatches, and remedies" (compression)
- **[severity: fragile]** planning/active/task_plan.md:159, 161 — `[x] Tests pass (full suite at PRs 1 to 5; …)`. Only PR 1 (#443) records a full suite (5,232 expectations, 0 failed). PR 5 (#449) added `tests/testthat/test-worker_prep.R` and changed `data-raw/worker_prep.sh`, and its test plan records that one file only (25 expectations). #445, #447 and #448 record no suite run, and nothing under `planning/` does. CI's R-CMD-check went green on each merge commit (55c2b616, 481dc8d3, 794ddd0e, and fd91d1b7 for #449's code), which runs the tests with the live-database ones skipped, so it is not the local full suite the box names. Line 161 ("PWF checkboxes match landed work") falls with it. Fix: reword to what ran ("full suite at PR 1; `test-worker_prep.R` at PR 5; CI R-CMD-check green on every merge; PR 6 changes no code"), or run the suite now and record it.
  - **Rule:** code-check.md "A wrapper's exit is not the work" (a box ticked on a stand-in for the named action); CLAUDE.md "PWF checkboxes are an integrity contract"
- **[severity: fragile]** planning/active/progress.md:33 — "still holds the two files that are not this work's": the count has no committed source and, unlike line 34, no "read in-session" label. Line 32's 20:30 UTC HEAD of the bchamp objects is also unlabelled, but the committed `verify_extra.log` corroborates it (cloud hosts snapshotted from S3 at prep and loaded exactly those version ids). Fix: label both as read in-session, or drop "two".
  - **Rule:** code-check.md "Verification that reads its own output" (an in-session observation with no artifact behind it, unlabelled)
