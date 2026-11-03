# Code-check round 3: branch `441-minimal-run` (base `552f43d6`, head `8b950222`)

## Checklist read

- `code-check.md`: the prose of every H3 under `## Mechanisms` (rows skipped), read for "A guard that fails toward pass", "A proxy is not the property", "Verification that reads its own output", "One fact derived twice" and in full "A guard's scope, escape hatches, and remedies" (including "Compression runs both ways": a sample restated as a rate, an attribution widened to a second instance).
- `code-check-shell.md` index: "Empty arrays under `set -u` on bash 3.2" (launch.sh's `"${pre[@]}"`; launch.sh runs under `$BASH`, which the header pins to Homebrew bash 5, and the driver refuses 3.2, so not a finding); "Over Tailscale SSH to a Mac, `ssh` exits 0" (context for the worker leg; no new code).
- `code-check-r.md`, `code-check-spatial.md` indexes: no pattern this branch uses (no R or spatial code changed).

Method: every quantified claim in the lines this branch adds to `CLAUDE.md`, `RUNBOOK.md`, `research/study_area_run.md`, `planning/active/{task_plan,progress,findings}.md` checked against the committed logs, the local `fresh_default_minimal` / `fresh_default_history` tables (read-only SELECTs), git, and `gh issue view`.

## Enumeration

| # | Where | Claim | Source checked | Verdict |
|---|---|---|---|---|
| 1 | CLAUDE 15, research 305 | run_uid `20261102_203300-60ab009d`, `default_minimal` into `fresh_default_minimal` | `log`: 241 rows, one run_uid | matches |
| 2 | CLAUDE 15 | m4 dispatcher, m1 worker, three cloud hosts | `log.host`: m4 48, m1 49, cypher-job1/2/3 48 each | matches |
| 3 | CLAUDE 15, research | link `193cb8aa` (0.78.1), fresh 0.52.0 `245c8d8d`, one sha of each across five hosts | `checks/tokens.txt` (n_link 1, n_fresh 1, hosts 5); `git show 193cb8aa:DESCRIPTION` 0.78.1; `log` versions | matches |
| 4 | CLAUDE 15, research | tokens `cut-min acc-v5 grad-seg q-fwapg` on every / all 241 rows | `checks/tokens.txt` count 241 | matches |
| 5 | CLAUDE 15, research | driver exit 0; critical path 228.2 min (20:33 to 00:21) | `checks/check.txt`; phases prep start 20:33:00, compare end 00:21:12 | matches |
| 6 | CLAUDE 15, research | both verifiers pass at `expected_n=241` | `checks/verify.log` (expected_n = 241), `verify_extra.log` NOTICE PASS 241 | matches |
| 7 | CLAUDE 15, research | audit 2,191 of 2,191 pairs | `checks/recompute_audit.log` | matches |
| 8 | CLAUDE 15, research | no host kept, no droplet left | `check.txt` (doctl lists no `cypher-` droplet) | matches |
| 9 | CLAUDE 15, findings | 4.99 M (4,987,761) segments over 241 groups, 19 GB | DB `count(*)` 4,987,761 / 241; `pg_total_relation_size` sum 19.97e9 B (pg_size_pretty "19 GB") | matches |
| 10 | CLAUDE 15 | "knowledge#120 can read it" | knowledge#120 open; no committed check of a read | unsupported, plausible (not raised) |
| 11 | CLAUDE 18 | Owed: knowledge#120, #418 rehearsal, calibrator 2nd/3rd runs | knowledge#120 OPEN, #418 OPEN | matches |
| 12 | CLAUDE 18 | #375, #369, #374, #376 stay open for this run's numbers | issues OPEN; #369 and #376 bodies say "next provincial `default` run"; #369 acceptance 1 (consolidate rows inside the dispatcher's modelling window) contradicted by `consolidate_state.tsv` | **mismatch** (finding 1) |
| 13 | CLAUDE 18 | #376 acceptance 2: job1 183.0 against 202.3 (within 10 %) | `calibrate.log` 202.3 / 183.0 (0.905) | matches |
| 14 | CLAUDE 18 | not done: #259 `fit.R`, #261 `predictors.R`/`correlations.R`, #446 | nothing in the evidence runs them; #446 OPEN (#259, #261 closed, items still owed per their status blocks) | matches |
| 15 | CLAUDE 18 | `fresh_default`/`fresh` not rebuilt; re-models owed by #326, #396, #399, #401, #402, #429, #432 | grep of every earlier "next provincial run" Owed (table below) | matches for re-models; #371 omitted (finding 1) |
| 16 | CLAUDE 21 | one `tailscale ping m1` about 22:36 UTC `via DERP(sea)`; direct at 00:31 | `checks/tailscale_path.txt` | matches |
| 17 | CLAUDE 21, RUNBOOK 2611 | m1's consolidate ran "at 550 to 870 kB/s by table" | measured for `barriers` (309,380,089 B / 562.2 s = 550) and `streams` (1.83e9 / 2,093.3 = 873) only; other tables' row text over their copy times: barrier_overrides 186 kB / 0.9 s ≈ 207 kB/s, streams_habitat_ch 11.45 MB / 12.8 s ≈ 895, _sk 9.61 MB / 9.4 s ≈ 1,022, _wct 1.21 MB / 1.3 s ≈ 929, streams_near_river 3.91 MB / 2.3 s ≈ 1,700, streams_mapping_code 45.1 MB / 43.6 s ≈ 1,030 | **mismatch** (finding 2) |
| 18 | CLAUDE 21, research, RUNBOOK | 47.6 min against about 13 per cloud host (12.8, 13.1, 13.3) | `phases.tsv` | matches |
| 19 | RUNBOOK 2609 | "During #441's run m4 reached m1 `via DERP(sea)`" | one probe at ~22:36 (`tailscale_path.txt`) | **mismatch** (finding 3: the widening round 2 fixed in CLAUDE.md, still here) |
| 20 | research 332-333 | "m4 reached m1 through a Tailscale relay while it ran" (the 47.6 min consolidate) | one probe at ~22:36, during the `streams` copy; none during the `barriers` copy (22:10 to 22:19) | **mismatch** (finding 3) |
| 21 | RUNBOOK 2612 | "about two hours later the same probe went direct" | 22:36 → 00:31 = 1 h 55 m | matches |
| 22 | research 334 | barriers 550 kB/s (309 MB in 9.4 min), streams 870 kB/s (1.83 GB in 34.9 min) | consolidate_worker1.log 562.2 s / 2,093.3 s; row text from DB (round 2's derivation) | matches |
| 23 | RUNBOOK, research | cloud hosts reached at droplets' public addresses, outside Tailscale | `study_area_run.sh:1824` (`tofu output droplet_ip`) | matches |
| 24 | CLAUDE 22, research | learned speeds m1 1.18, m4 1.11, cloud 0.95; observed 1.61 / 1.36 / 0.82; run-wide 0.693 | `checks/calibrate.log`, `host_speeds.tsv` | matches |
| 25 | CLAUDE 22, research | cloud legs 160 to 183, m1 87, m4 103 at equal speeds | `phases.tsv`; `buckets.md` all 1.00x | matches |
| 26 | CLAUDE 23, findings, research | FWA counts are `reltuples` estimates; range 4,898,813 to 4,910,797 | `verify_extra.log`; `R/lnk_log.R:887-893` | matches |
| 27 | CLAUDE 24 | run.log redacted before commit | no IPv4 in `minimal_run_441/*` | matches |
| 28 | research 307-310 | packed `--atom=group --minutes-schema=fresh_default_history --minutes-exclude=KTSU,OKAN`, equal speeds; `--buckets-exact`, `--recompute-jobs=8`, early recompute, burn on leg end | `buckets.md`, `buckets.stderr`, `launch.sh`, phases | matches |
| 29 | research 311 | gate record at `24b2cbb3`, 11 picks | `run.log:24` (11 groups); ancestor of `193cb8aa` | matches |
| 30 | research table | per-leg minutes and groups | `phases.tsv` | matches |
| 31 | research table | planned (packing) "202 each" | `buckets.md` worker1 203 (202, 203, 202, 202, 202); `calibrate.log` 202.2 to 202.8 | **mismatch** at stated precision (finding 4) |
| 32 | research table, findings | group minutes 690.2 summed, median 2.3; QUES 20.9, MORK 12.8, BULK 10.7, all cloud | DB `log` 690.2 / 2.32; hosts cypher-job3/job2/job1 | matches |
| 33 | research table | 1,012 = history's 1,004.4 + KTSU, OKAN at median | `plan.tsv` minutes sum 1,004.44, weight 3.72 each | matches |
| 34 | research table | recompute 21:51 to 00:15, 126.8 summed, median 0.41, HOMA 5.0 | DB `log_recompute` 241 rows: 126.8 / 0.41 / HOMA 4.98 | matches |
| 35 | research table | 29.4 min after the last leg, 12.3 after the last consolidate | 23:46:07 → 00:15:30; 00:03:11 → 00:15:30 | matches |
| 36 | research table | prep 10.0 min | phases | matches |
| 37 | research table | cloud about 9.9 host-hours (spin 20:33, burns 23:36, 23:50, 00:03) | up log stamp 1333 PDT; burns in phases; 3.06 + 3.29 + 3.51 h | matches |
| 38 | research 325 | 0.69 of the plan (701.6 / 1,012); group minutes 0.68 | arithmetic | matches |
| 39 | research 325 | no group failed, no statement bounded | coverage 241; 0 TIMEOUT lines in every leg log | matches |
| 40 | research 327 | history is `default` at 0.68.0, 11.39 M segments | `fresh_default_history.log`: 241 newest rows all 0.68.0 run 20261023; 11.39 M from research §2026-10-23 | matches |
| 41 | research 336 | "did not reach the critical path (m1 finished first)" | m1 consolidate ends 22:58, driver 00:21 | matches |
| 42 | research 301 | `fit.R` still owed, not re-fit | nothing in evidence | matches |
| 43 | progress 23-25 | merge SHAs, v0.78.0 / v0.78.1 tags; #415, #440, #442 closed, #439, #418 open | `gh pr view`, `git tag --points-at` | matches |
| 44 | progress 24 | DESCRIPTION maps to `none` | `pretest_inputs.csv:149` | matches |
| 45 | progress 31 | bchamp objects at 1790057230537 / 1793134826715 | `load_stamps.csv`; `verify_extra.log` versions on all five hosts | matches (post-run) |
| 46 | progress 32 | bcfishobs clean clone at `dd9a5e5d` | `log.bcfishobs_sha` dd9a5e5d on 241 rows | matches |
| 47 | progress 34 | no other active client at 20:31; m1 volume 112 GB free | nothing committed | unsupported (finding 5) |
| 48 | progress 35, task_plan | 48/49/48/48/48 groups, 202 to 203, 1,012 | `buckets.md` | matches |
| 49 | progress 41 | pre-flight passed in full; primitives 0.5 d | `run.log:28` | matches |
| 50 | findings 100 | "a 30 s sample of the `streams` file mid-copy read 701 KiB/s" | nothing committed | unsupported (finding 5) |
| 51 | findings 100 | planning probes measured latency and loss only | `phase0_connections.txt` | matches |
| 52 | task_plan 106 | [x] "compare S3's `log.json` with both hosts' ledger rows" just before launch | progress records a HEAD of the two bchamp objects, not a `log.json` comparison | **mismatch** (finding 6) |
| 53 | task_plan 119 | [x] "`--preflight-only` passes in full" | no committed `--preflight-only` (PREFLIGHT=1) log; the run's own pre-flight is in `run.log` | unsupported (finding 6) |
| 54 | task_plan 159-161 | [x] tests at PRs 1-5, PR 6 no code; [x] checkboxes match landed work | diff touches no `R/`; the second box falls with 52-53 | partly (finding 6) |
| 55 | progress 39, launch commit | launch decisions pushed before launch | `193cb8aa` at 20:32:14 UTC, `run.started` 20:33:00 | matches |

### Earlier "next provincial run" Owed items, against the new Owed list

| Block (CLAUDE.md line) | Item | Issue state | Applies to a `default_minimal` run? | In new Owed? |
|---|---|---|---|---|
| #432 (73), #402 (85, 123), #401 (137), #399 (151), #396 (268), #326 (310) | re-model `fresh_default` (and `fresh` for #326, #401, #399) | — | no: `default` / `bcfishpass` schemas | yes |
| #429 (96) | `fresh` UTRE, QUES re-model | — | no: `bcfishpass` | yes |
| #274 (174) | first partial run after the provincial run exercises it | CLOSED | `fresh_default_minimal` could serve, not yet run | no (closed issue; not raised) |
| #414 (189) | first builds to carry tokens | CLOSED | yes, carried here | n/a |
| #394 (202), #409 (215) | `--auto-install`; recompute minutes against 2026-10-23 | CLOSED | the comparison is network-confounded; #377 row says "not comparable" | n/a |
| #372 (229) | gate before the run | — | done (record `24b2cbb3`) | n/a |
| #259 (292), #261 (304) | calibrator, `fit.R`, `predictors.R` | CLOSED | calibrator done; re-fits not done | yes ("not done") |
| #374 (335) | provincial tail and critical path | OPEN | yes | yes |
| #376 (357) | acceptance 2, worker speed | OPEN | body says a `default` run | yes, with finding 1 |
| #369 (370) | idle minutes, consolidate inside model window, overlap vs 2026-10-23, "at the next `default` run" | OPEN | partly no: overlap vs 2026-10-23 not comparable; window item contradicted | yes, with finding 1 |
| #375 (380) | `phases.tsv` committed, #377 row | OPEN | yes | yes |
| #371 (390) | criterion 2, a full run at the default bound with no timeout, "the next provincial `default` run" | OPEN | the run used the default bound (30) with no timeout, but it is `default_minimal` | **missing** (finding 1) |

## Findings

- **[severity: fragile]** CLAUDE.md:18 — The Owed list says this run's numbers "are what #375, #369, #374 and #376 stay open for", and omits #371. Checked against the issue bodies: #369's body owes its item 3 "on the next provincial `default` run": idle cloud minutes, consolidate rows inside the modelling window, and the overlapping dispatcher groups' minutes against 2026-10-23. This run's `consolidate_state.tsv` puts every cloud host's `ok` row (23:35:59, 23:49:48, 00:03:09 UTC) after the dispatcher's model phase ended (22:26:18), so #369's acceptance 1 as written ("timestamps inside the dispatcher's modelling window") is not met here. The 2026-10-23 overlap comparison cannot come from a minimal-network run; research line 327 and #377's runs row both say this run is not comparable. #376's body says its criterion 2 waits on "the next provincial `default` run". #371 is OPEN, and its block (CLAUDE.md:390) says criterion 2 waits on the next provincial `default` run. This run used the default bound (`--statement-timeout=30`) with no group timed out, but #371 is in neither half of the Owed list. A reader of the Owed list would take #369's and #376's remaining items as satisfiable from this run, and would not know #371 is still waiting on a `default` run. Fix: say which items this run supplies (#375's `phases.tsv`, #374's tail, #376's leg ratio on a `default_minimal` run) and which still need a `default` run (#369's window and overlap items, #371's criterion 2), and add #371.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (compression: an attribution widened to a second instance, here from a `default` run to a `default_minimal` one)
- **[severity: fragile]** CLAUDE.md:21, RUNBOOK.md:2611 — "m1's consolidate ran at 550 to 870 kB/s by table" / "m1's 49 groups copied at 550 to 870 kB/s by table". The range was derived from two tables only (`barriers` 550, `streams` 873; research line 334 says so correctly). Row text of m1's 49 groups over the copy times in `20261102_203300_consolidate_worker1.log` gives other tables outside the range: `barrier_overrides` about 207 kB/s (186 kB in 0.9 s), `streams_habitat_ch` about 895, `streams_habitat_sk` about 1,020, `streams_habitat_wct` about 930, `streams_mapping_code` about 1,030 (the recompute rewrote those rows, so this one is approximate), `streams_near_river` about 1,700. "By table" states the two-table measurement as covering every table. Fix: "550 kB/s for `barriers` and 870 kB/s for `streams`", as research has it.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (compression: a sample restated over a wider population)
- **[severity: fragile]** RUNBOOK.md:2609, research/study_area_run.md:332-333 — RUNBOOK: "During #441's run m4 reached m1 `via DERP(sea)`"; research's bold lead: "m4 reached m1 through a Tailscale relay while it ran" (the 47.6-minute consolidate). The only probe is one `tailscale ping` at about 22:36 UTC (`checks/tailscale_path.txt`), during the `streams` copy. None covers the `barriers` copy (22:10 to 22:19) or the rest of the run. Round 2 fixed this widening in CLAUDE.md ("mid-copy (one `tailscale ping m1` at about 22:36 UTC)") but not in RUNBOOK or research's lead sentence. The sentence after research's lead gives the time correctly, but the lead and RUNBOOK's "During #441's run" state it for the whole span. Fix: "at about 22:36 UTC, mid-copy" in both places.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (compression)
- **[severity: fragile]** research/study_area_run.md:318 — planned (packing) "202 each". `buckets.md` gives worker1 203 (the makespan line: "makespan is set by worker1 at 203"), and `calibrate.log` projects 202.2 to 202.8. progress.md line 35 correctly says "202 to 203". Fix: "202 to 203".
  - **Rule:** code-check.md "One fact derived twice"
- **[severity: fragile]** planning/active/progress.md:34, planning/active/findings.md:100 — "no other active client on m4 or m1 at 20:31 UTC", "m1's database volume 112 GB free", and "a 30 s sample of the `streams` file mid-copy read 701 KiB/s" are in-session observations with no committed output. The 701 KiB/s sample is the figure round 2 removed from the published files as underived. It survives in findings.md, which the archive README will index as evidence, beside the derived 550 and 870 kB/s and in different units (KiB). Either commit the probe output (e.g. into `checks/`) or drop the figures. The quiet-database claim matters because the gate and the run's minutes assume a quiet database.
  - **Rule:** code-check.md "Verification that reads its own output" (a claim from an in-session observation with no artifact behind it)
- **[severity: fragile]** planning/active/task_plan.md:106, 119, 161 — The PWF checkbox contract. Line 106 is ticked with text naming "compare S3's `log.json` with both hosts' ledger rows". Review PR 4 round 2 replaced that with a HEAD of the two bchamp objects, and progress line 31 records only the bchamp HEAD. So the box names an action that, as far as anything committed shows, did not run. Line 119 ticks "`--preflight-only` passes in full", and no committed log shows a `--preflight-only` (PREFLIGHT=1) pass. What is committed is the run's own pre-flight in `run.log`, which is a different invocation and was already spending. Line 161 ("PWF checkboxes match landed work") falls with them. Fix: reword the two boxes to what ran (the bchamp HEAD against `load_stamps.csv`; the launch's own pre-flight), or commit the `--preflight-only` log if one was taken.
  - **Rule:** code-check.md "A wrapper's exit is not the work" (a box ticked on a stand-in for the named action); CLAUDE.md "PWF checkboxes are an integrity contract"
