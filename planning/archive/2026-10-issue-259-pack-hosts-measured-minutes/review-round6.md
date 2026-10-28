# Code-check round 6 (link#259): closing enumeration

## Checklist read
- code-check.md.index: in full. code-check.md: the prose of all 14 H3 under `## Mechanisms`, in full (table rows skipped). "Rules that stand alone", Security, Spreadsheets/PDFs: not read (no matching shape in the diff).
- code-check-r.md.index: in full (111 headings; identical heading set to the copy loaded in CLAUDE.md, checked by diff). Full sections opened: none. Index lines on `read.delim()` quoting, `ifelse()` all-NA, `match()` NA, `$` partial matching, `vapply(USE.NAMES)`, `[[` on atomic, `paste()` zero-length checked against the code directly. 111 not opened.
- code-check-shell.md.index: in full (67 headings). Full sections opened: none (the shell in scope is run_calibrate_hint: one awk `$2 == "model"` exit and echo lines). 67 not opened.
- code-check-spatial.md.index: in full (93 headings); nothing spatial in the diff. 93 not opened.

## Findings

- **[severity: fragile, data]** data-raw/study_area_buckets.R:326-344 (minutes query) feeding data-raw/host_speeds_calibrate.R:168,196 — outside the two-source mechanism, but it biases the very first calibration the CLAUDE.md "Owed" line schedules. The weight of a group is its newest finished `log` row, and in `fresh_default` that row is KTSU's 2026-10-23 stall: 65.4 min where it takes 1.29 (data-raw/logs/packing_259/log_rows.tsv; OKAN 7.6 against 2.8). The packer and the calibrator agree on that value (it is carried in the plan), so nothing refuses it; but the next run will model KTSU in about 1.3 min, so the leg that holds it reads ~64 min fast. Through the shipped `speeds_calibrate()` with every other group predicted exactly (4 legs of 270 min, state m4 1 / cloud 1): KTSU on the dispatcher learns m4 1.070 and cloud 0.982 (an 8.9 % ratio error from one group); KTSU on a cloud host learns cloud 1.006, m4 0.982 (2.5 %). The fit that justified minutes left both stalls out (fit.md, buckets.R:314-316); the packer and calibrator do not, and `--skip` drops whole legs of a stall in *this* run, not a stalled group carried in the *previous* run's minutes. Damping decays it (×0.7 a run), but it lands in the committed state. Options: a packer `--minutes-exclude=KTSU,OKAN` that gives those groups the median and writes `minutes` blank (the calibrator then keeps the packed weight, the accepted residual), or re-model KTSU before packing, or take each group's minutes from its median over the schema's last two finished rows. At minimum, the RUNBOOK "After a run" / the calibrator's legs table should name groups whose plan minutes are a known stall.

No defect found inside the round-5 fixes:
- Role check (calibrate.R:153-160): probed on plan->run maps (dispatcher->dispatcher, job1->job3, job2->job1: pass; job1<->worker1, worker1<->worker2, dispatcher<->job1: refused; cloud keys `worker`, `dispatcherX` (legal `--cy-workspaces` names, no digits / not anchored): pass). Same regex as the driver's `--cy-workspaces` refusal (study_area_run.sh:407). The packer's keys are `worker%d` with h-1 and `dispatcher`, so a plan cannot carry a fixed-role key the regex misses. A worker-count difference between packer and run lands a worker list on a cloud key (or the reverse) and is refused.
- `--skip` (calibrate.R:193-194, 204): matches the leg's plan name or its RUN key; `unknown_skip` validates against exactly those two (legs$host_key is the run key). A plan key that is not a run key is refused loudly.
- Print before calibrate (calibrate.R:209-222): the legs table and every reason print before the all-left-out stop; the other stops in `speeds_calibrate()` (two speeds per name, non-positive time) are reachable only through a hand-edited plan or a zero-length leg and also follow the print.
- test-host_speeds_calibrate.R: 55 pass, 0 fail, 0 error (NOT_CRAN=true, test_file).

## Enumeration (derived from the four files by grep for host / name / speed / key / class / state reads)

| row | pack-time source | calibrate-time source | verdict |
|---|---|---|---|
| leg key -> its groups | buckets.R:134-138 `host_key()` positional (dispatcher, workerN, jobN) | run_wsgs `host` (driver key: dispatcher, worker1..N in `--workers` order, `--cy-workspaces` names) matched by identical group set, calibrate.R:137-148 | tied (bijection on group sets, refused otherwise) |
| leg key's role | packer position | calibrate.R:153-160 fixed-role regex | tied (dispatcher/workers must keep their key; jobN must map to a non-fixed key) |
| leg actual minutes | - | phases `model` row of the run key, later end wins, calibrate.R:100-112,182 | read once; tied to the run key above |
| leg finished its bucket | - | phases `account` row of the run key, calibrate.R:113-115,183 | read once |
| groups counted | - | run_wsgs skip=no and coverage `recompute`, calibrate.R:177-181 | read once (wsg unique per run) |
| leg left out by operator | - | `--skip` by plan name or run key, calibrate.R:193-194, validated :204 | tied (round-5 fix) |
| leg NAME | `--host-names` (required with `--plan-out`, buckets.R:184), cloud positions forced `cloud` (:161) | plan `name`, `host_names_check` again (calibrate.R:86) | accepted (operator assertion; nothing the calibrator reads ties it to the physical machine). Note: the packer forces cloud positions to `cloud` but not non-cloud positions away from it, so a dispatcher or worker typed `cloud` merges into the cloud class; same accepted assertion. The cheapest real tie is this run's `<schema>.log` rows grouped by the run key's groups (out of scope, as stated); I judge the acceptance reasonable because the legs table prints key -> name before anything is learned |
| default dispatcher name | buckets.R:142-150 own_host (`.lnk_host()` rule incl. empty alias) | never reaches a plan (`--plan-out` needs `--host-names`) | tied by refusal |
| worker name vs its log alias | operator | foreign rule, calibrate.R:185-186,191 | accepted (not learned; legs holding its groups left out, reason printed). The same holds for a dispatcher named other than its log alias (its own groups are foreign, its leg is left out, reason printed): loud, covered by the same acceptance |
| class that measured a group | buckets.R:340 `host_class(log.host)` | plan `measured_by`, `host_class()` idempotent; foreign rule against state names and the leg name | tied. NA class (log.host NULL) is median at both ends and exempt from the foreign rule, but `log.host` has been written by every insert since the table's DDL (34c5e310), so unreachable from a current schema |
| group raw minutes | buckets.R:339 newest finished log row | plan `minutes` | tied (value carried). The value itself can be a known stall: Finding 1. The plan does not carry the measuring run_uid, so a plan regenerated after the run from the run's own minutes would learn ~nothing and consume the run; incidentally guarded by the group-set match (a re-weighted LPT rarely reproduces the same assignment) |
| normalization speed of a measuring class | buckets.R:343 `weights_normalize(..., speed_state)` (`--speeds-state`) | `plan_weights_at(..., state)` at `--state`, calibrate.R:167-168 | tied (re-normalized at the calibrating state, round 3) |
| weight of an unmeasured group | buckets.R:366-370 median of pack-time weights | plan `weight` kept | accepted (median group keeps its packed weight) |
| packed speed | buckets.R:171 (`--host-speeds` > state > equal), one per name (:175-179) | plan `speed`; one per name re-checked (packing.R:152-156); cancels in projected x speed / old (packing.R:166) | tied (cancels exactly) |
| stored factor `old` | - | `speeds_resolve(name, state)`, median for an absent name, 1 with none (packing.R:165) | read once; consistent with the weights' normalization (both from the calibrate-time state) |
| a leg named by a class not in the state | median at pack time | `old` = median; own groups weighted minutes x median, so they predict themselves | tied |
| run_ratio | - | every leg not left out (packing.R:169) | consistent (left-out and foreign legs leave the pool) |
| role-key name learned | - | `PACK_ROLE_KEY` refuses (packing.R:196-199) | tied |
| empty state file (header only) | weights and speeds: equal path (`!nrow`) | foreign rule: `known = character(0)` | inconsistent zero-length vs NULL, but reachable only if a calibration learned no name (every used leg a role-key name); fails loud with reasons printed; not filed (as round 5) |
| state / history written | - | `--state` / `--history`, names from the plan's learned legs | read once |
| finish.sh hint | - | prints when phases has a `model` row (`$2` is `phase`) | prints only; the calibrator refuses a phases file with no finished model row |
| dispatcher/cloud equal state seed | data-raw/logs/host_speeds.tsv | same | accepted (seeded equal) |
| lower clamp, absolute drift | - | packing.R:201-202 | accepted |

## Verdict

The two-source mechanism is closed: every host-identity and speed row is tied (carried in the plan and re-derived or checked by the calibrator, or refused) or is one of the listed accepted tradeoffs, and the round-5 fixes hold under probing. One real input defect remains outside the mechanism (Finding 1: the previous run's KTSU stall in the minutes the first calibration will read), which is a pre-run operational fix rather than a code defect in the identity/speed plumbing.
