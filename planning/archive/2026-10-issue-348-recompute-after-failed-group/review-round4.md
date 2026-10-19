# Code-check round 4 (terminating enumeration): branch 348 (git diff c902ea97...HEAD)

Reviewer: subagent, 2026-10-18, at HEAD `1a5bcdee`. I re-walked round 3's 25-row table
against the current code and added every printed recovery instruction it missed. Sources:
every `echo` that prints a command or an instruction to act in `data-raw/study_area_finish.sh`,
the `--recompute-only` branch, accounting and consolidate banner of `data-raw/study_area_run.sh`,
`host_release`, `hosts_preflight_droplets` and `hosts_kept_report` in `data-raw/study_area_hosts.sh`,
the usage header, and the RUNBOOK passages under "A missing group costs only itself".

## Verified by running

- `test-study_area_finish.R` with NOT_CRAN=true: 67 expectations, 0 failed, 0 skipped, no
  error. `git status --short` was empty before and after.
- I re-ran round 3's two repro scripts (`unsettled.sh`, `unmeasured.sh`), copied to
  `<scratchpad>/r4/` with LOG_DIR moved to `<scratchpad>/r4w/`, against the current libs
  (bash 5, `set -euo pipefail`). In both, the report puts the held host's missing groups under
  "In a kept host's bucket: settle these per T_kept_hosts.tsv first ...". Neither prints a
  consolidate or re-model instruction for them, and the TSV row carries `groups_measured`
  (`unsettled`, `no`). Round 3's finding 1 is closed.
- I tested the `RO_KEPT` probe (`<scratchpad>/r4/ro.sh`) with no TSV at all (the glob stays
  literal), with a TSV for another uid, and with a TSV for this uid. On bash 5 and bash 3.2
  under `set -euo pipefail`, every case exits 0, and only the matching file is printed.
- The consolidate-failure banner's `cf_wsgs` loop sits inside `if [ "$N_CY" -gt 0 ]`, so
  `CY_WS_ARR` cannot be empty there. Line 1409 already reads `${CY_BUCKET[$WS]}` unguarded for
  every `WS`, so the banner adds no new `set -u` exposure. `DISP_BUCKET` is set at
  driver:1194.
- Quoting is not a problem. `RUN_LABEL` is restricted to `[A-Za-z0-9._-]`, `CONFIG` and `SCHEMA`
  to `[A-Za-z0-9_]`, `RUN_UID` and `--wsgs` to fixed formats, and `${RUN_LABEL:+...}` is exempt
  from nounset. So every printed command pastes as one valid line.

## Findings

- **[severity: fragile]** data-raw/study_area_run.sh:650-656 with data-raw/study_area_finish.sh:399-420.
  This is what is left of round 3's finding 5; that round's suggested minimum fix was the one
  applied.
  - Under `--recompute-only`, `CY_WS_ARR` is empty, so `held` is empty. Every missing group is
    therefore printed at the bottom of the report as "Re-model each of these under this
    run_uid", with the ready-to-paste `wsg_run_one.R` command.
  - The only qualifier is the WARN printed at the top, before coverage: "settle their groups per
    these files first". The instruction the operator acts on, and the one the WARN must agree
    with, are now in different parts of the output, and the actionable one is unqualified.
  - Scenario: host `a` is kept with BBBB finished on it (`groups`, measured `yes`). The operator
    runs `--recompute-only` before consolidating `a`. BBBB is listed to re-model. Re-modelling it
    makes a later consolidate of `a` refused whole (`dest_log_newer`), which also blocks `a`'s
    other finished groups.
  - The mechanism is the same as rounds 1-3: the split reads a set (`CY_HOLD`/`CY_BUCKET`) that
    is empty in this process, while the source of truth (`*_kept_hosts.tsv` for this uid) has
    already been read by the same process (`RO_KEPT`).
  - Fix: when `RO_KEPT` is non-empty, fill `held` from those files' `groups`, `groups_partial`
    and `groups_unknown` columns on rows whose `run_uid` column is `$RUN_UID`:
    `awk -F'\t' -v u="$RUN_UID" '$4 == u { print $6 "," $7 "," $8 }'`. For `measured=no`,
    `groups` is already the whole candidate set. The existing `on_kept` lines then cover this
    case too.
  - Minimum alternative: when `${RO_KEPT:-}` is set, prefix the re-model line with "hosts were
    kept for this run (see the WARN above): settle per those files first; some of these may be
    on them".

- **[severity: fragile, narrow]** data-raw/study_area_run.sh:1471-1476. The consolidate-failure
  banner's `--wsgs=$cf_wsgs` is `DISP_BUCKET ∪ CY_BUCKET[*]`. That still includes `RUN_SKIP`:
  groups a host SKIPped and no host finished. The full run's report passes `RUN_WSGS =
  RUN_EXPECT`, which `run_expected_from_hosts` builds with those groups removed.
  - With the banner's set, `--recompute-only` reports a SKIPped group as `no rows` and says to
    re-model it. `wsg_run_one.R` SKIPs it again and writes no row, so the run exits 1 on every
    attempt until the group is dropped from `--wsgs` by hand.
  - Reachable only when a host's config or overrides disagree with the dispatcher's, which
    `run_expected_from_hosts` already WARNs about.
  - Fix: call `run_expected_from_hosts` at the banner and print `--wsgs=$RUN_EXPECT`. Every input
    it reads (`ACC_*`, `CY_BUCKET_DONE`) is set by the accounting at driver:1403-1417, before
    consolidate.

No other defects. The round-3 fixes are correct as written: the `.hosts_inter`/`.hosts_minus`
calls with an empty `held`, the `else` branch for accounting against coverage, the `--wsgs` on
each `--recompute-only` line, `LNK_RUN_UID`/`LNK_RUN_LABEL` on both one-group recompute lines,
and the RUNBOOK rewrite.

## Observations (not defects)

- An earlier session's `*_kept_hosts.tsv` is never removed once its host has been settled and
  burned by hand (`hosts_kept_report` removes only its own `${TS}` file). So every later
  `--recompute-only` for that uid repeats the WARN. That errs on the safe side (a WARN, exit
  status unchanged), and the operator can clear it by moving the file.
- The probe globs only `$LOG_DIR`. If a run's logs are moved into a campaign subdirectory
  (`data-raw/logs/<campaign>/`, as for #246), the WARN goes silent.
- `hosts_kept_report` prints `--config=<config>` as a placeholder, although `CONFIG` is in scope
  when the driver calls it. `${CONFIG:-<config>}` would print the real value. A wrong config
  is refused by `run_config_check`, so a paste fails loudly.

## Enumeration: every recovery instruction, what it is computed from, and its source of truth

Line numbers are at HEAD `1a5bcdee`. "R3 verdict" is round 3's verdict, and "Verdict now" is
this round's.

| # | Where | Instruction | Computed from | Source of truth | R3 verdict | Verdict now |
|---|---|---|---|---|---|---|
| 1 | finish:367-372 | kept hosts: consolidate `groups` only where measured=yes, never partial | text, `KEPT_CAUSE_N` | TSV / hosts_kept_report / RUNBOOK §8d | agrees | agrees |
| 2 | finish:373-379 | recompute each kept group + upstream (or every group) | `RECOMPUTE_RAN` at report time | hosts_kept_report text | superseded, harmless (accepted) | unchanged (accepted) |
| 3 | finish:380-382 | `--recompute-only ... --wsgs=$RUN_WSGS` | `RUN_WSGS` | the run's expected set | **disagreed** (no `--wsgs`) | **agrees**: `--wsgs` added; label carried |
| 4 | finish:386-391 | class lists | `COV_*` | coverage | agrees | agrees (it is the source) |
| 5 | finish:407-411 | kept host's bucket: settle per TSV, re-model only what is still missing | `COV_MISSING ∩ ∪held CY_BUCKET` | TSV `groups_measured` | **disagreed** | **agrees**: it defers to the TSV and claims nothing measured-state-dependent. Repro confirmed for unsettled and unmeasured |
| 6 | (was finish:412-415) | unknown provenance: check first | — | — | agreed for yes | removed; the TSV's `groups_unknown` and the kept block's line hosts:505-506 carry it |
| 7 | finish:412-413 | re-model the rest | `COV_MISSING − held bucket` | released hosts / dispatcher | **disagreed** on unsettled | **agrees** in a full run: a released host exited 0 and holds nothing finished. **Disagrees** under `--recompute-only` (row 23, finding 1) |
| 8 | finish:417-419 | re-model command env | `RUN_UID`, `RUN_LABEL`, `SCHEMA`, guard=warn | dispatch legs' env | agrees | agrees (SHA exports fall back: accepted) |
| 9 | finish:421-424 | `--recompute-only --wsgs=$RUN_WSGS` | `RUN_WSGS` | run's expected set | agrees | agrees |
| 10 | finish:425-433 | accounting short, coverage complete: nothing to re-run | `RUN_INCOMPLETE` with `COV_MISSING` empty | coverage | **disagreed** | **agrees**: unreachable under `--recompute-only` (RUN_INCOMPLETE starts 0 there); tested |
| 11 | finish:435-439 | compare re-run alone | `COMPARE_CSV`, `ALL_WSGS`, `CONFIG`, `SCHEMA` | run_finish_compare's call | agrees | agrees |
| 12 | finish:456-458 | one-group recompute | `RUN_UID`, `RUN_LABEL`, `SCHEMA`, `CONFIG` | pool env (driver:389-390) | **disagreed** | **agrees** |
| 13 | finish:188-191 | recompute SKIPPED: nothing to settle | `ALL_WSGS` empty | coverage | agrees | agrees |
| 14 | hosts:504-519 | per-host measured / unsettled / not-answered text | local `measured`, `CY_UNCONS/PARTIAL/DOUBT` | itself | agrees | agrees (source of truth) |
| 15 | hosts:521-529 | consolidate only `groups`, measured=yes, never partial | text | RUNBOOK §8d | agrees | agrees |
| 16 | hosts:530-536 | recompute kept + upstream / every group | `RECOMPUTE_RAN` at call time | row 2 | agrees per call | agrees per call |
| 17 | hosts:537-538 | `--recompute-only ... --wsgs=<the run's groups>` | placeholder (no `RUN_WSGS` in the lib) | the run's buckets | **disagreed** | **agrees**: the placeholder tells the operator to add it, and finish:382 prints the value in the same run |
| 18 | hosts:539-540 | one-group recompute | `RUN_UID`, `RUN_LABEL`, `SCHEMA` | pool env | **disagreed** | **agrees** |
| 19 | hosts:541-542 | burn commands | `$@` (kept list) | the TSV | agrees | agrees |
| 20 | hosts:373-375 | preflight: consolidate an earlier kept droplet, then burn | workspace match | `*_kept_hosts.tsv` | agrees | agrees |
| 21 | driver:1470-1477 | consolidate failed: `--recompute-only --wsgs=$cf_wsgs` once consolidated | `DISP_BUCKET ∪ CY_BUCKET` | `RUN_EXPECT` (buckets less `RUN_SKIP`) | agreed; lacked `--wsgs` | **agrees**, except that it includes `RUN_SKIP` (finding 2, narrow). Exits before coverage (accepted follow-up) |
| 22 | driver:664-667 | `--wsgs` subset WARN | `RO_LOGGED − RO_EXPECT` | run's log groups | agrees | agrees |
| 23 | driver:650-656 → finish:399-420 | the `--recompute-only` report's split | `CY_WS_ARR` empty, so every missing group is re-modelled; WARN at top | the earlier session's `*_kept_hosts.tsv` for this uid | **disagreed** | **partly**: a pointer WARN was added, but the bottom re-model line is unqualified (finding 1) |
| 24 | RUNBOOK 1252-1258 | recovery code block | doc | report rows 8, 9 | **disagreed** mildly (no guard=warn) | **agrees**: `LNK_RUN_LABEL`, `LNK_GUARD_DOWNSTREAM=warn` added |
| 25 | RUNBOOK 1276-1280 | missing group in a kept host's bucket: settle per TSV, consolidate only `groups` where measured=yes | doc | RUNBOOK §8d, row 5 | **disagreed** | **agrees** |
| 26 | driver:650-656 | `--recompute-only` WARN: hosts kept for this uid, settle per files | `grep -l -F $RUN_UID $LOG_DIR/*_kept_hosts.tsv` | the TSVs | (new) | agrees; it can go stale after manual settlement, and is blind to logs moved to a subdirectory (observations) |
| 27 | driver:670-672 | "pass the run's groups with --wsgs= to have it named" | text | run_expected_from_log's limit | not listed | agrees |
| 28 | driver:1418-1421 | completeness WARN: run finishes, then exits non-zero | `complete_fail` | `RUN_INCOMPLETE=$complete_fail` at driver:1502 → `exit 1` | not listed | agrees |
| 29 | finish:181-185 | NOTE: recomputing only the N above, the run will exit non-zero | `COV_MISSING` | `RUN_INCOMPLETE=1` → report `exit 1` | not listed | agrees |
| 30 | finish:58-59 | WARN: SKIPped by a host, not expected | `RUN_SKIP` | `RUN_EXPECT` | not listed | agrees (row 21 is where `RUN_SKIP` is not applied) |
| 31 | hosts:347-348 | released host: partial groups left there, "rebuild them" | `CY_PARTIAL` after release | report row 7 (they are `COV_MISSING`, outside `held`) | not listed | agrees: a released host's partials are printed under "Re-model" |
| 32 | hosts:351 | `KEEPING it (groups: ...)` | `CY_UNCONS` after `host_split` | the TSV, rewritten in the trap | not listed | agrees: informational; the action text is the kept block |
| 33 | hosts:292 / 311 | completeness ✗ lines "(see $log)" | `ACC_*` | — | not listed | agrees: diagnostic, no action |
| 34 | driver:1439 / 1452 | nothing to consolidate from a host / from any host | `CY_BUCKET_DONE` | — | not listed | agrees: no action; the hosts stay held through host_release |
| 35 | RUNBOOK 1272-1275 | `--recompute-only` cannot rescue a soft-failed `date_end`: re-model it | doc | run_coverage newest-row rule | not listed | agrees (accepted) |
| 36 | RUNBOOK 1282-1288 | no lock; verify red for an open dispatcher row | doc | — | not listed | agrees (accepted) |
| 37 | driver:82-90 (usage) | `--recompute-only --run-uid=<uid> [--wsgs=A,B]` | doc | arg parsing (237-264, 286-295) | not listed | agrees: `--config`/`--schema` are not in the line, but a missing one is refused loudly (schema guard, `run_config_check`) |

Result: of the 37 rows, 34 agree, row 6 was removed with its instruction, row 21 agrees except for one narrow case, and row 23
disagrees in part. All 9 rows that disagreed in round 3 now agree, apart from row 23.
