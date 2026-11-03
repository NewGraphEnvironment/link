# Plan review — #454 (Plan agent, 2026-11-03, synchronous, before the parked baseline)

Reviewed `task_plan.md` against the issue body, `pretest_run.sh` / `pretest.R`, `study_area_run.sh`, `study_area_buckets.R`, `rehearsal_418/check.sh`, RUNBOOK §8d and #441's plan and launch script, at `73105fbc`. Folded into `task_plan.md` in the same session; what changed is listed under each finding.

## Blocker

- **The gate command in the plan and in the issue cannot run.** `pretest.R:375-378` stops when `--history-config` equals `--config` or is not in the config's `extends:` chain; `default` has `extends: ~` (`configs/default/config.yaml:75`), so `--history-config=default` is refused, and `pretest_run.sh:92-94` refuses `--history-schema` on its own. With no flags the pick reads `<schema>.log` and refuses when it is missing (`pretest_pick.R:85-86`), which the plan's `DROP SCHEMA` would produce. The `CREATE SCHEMA IF NOT EXISTS` at `pretest_run.sh:283-284` is on the borrowed path only. **Fix (no code change):** seed m4's `fresh_default.log` with the 241-group history (`CREATE TABLE ... LIKE fresh_default_history.log INCLUDING ALL; INSERT ... SELECT`, or `pretest_history_load.sh --host=m1 --from=fresh_default_20261023 --to=fresh_default`) and run the gate with no history flags; `--since` defaults to `1d00c04c`, the scratch is built LIKE a schema holding only `log`, the verdict writes `fresh_default.log_pretest`, `pretest_check.R:49-53` finds the history complete. Old rows under another `run_uid` do not trip `study_area_verify.sql` (keyed on `run_uid`) or `verify_extra.sql` check 2 (newest row per `streams` group). *Folded: the m4 schema and gate rows of the decisions table, Phase 1's seed step, Phase 2's command, a stop-table row.*

## Gap

- `--preflight-only` prints `NOT CHECKED (workers; need the buckets or their prep): prior rows ...` (`study_area_run.sh:1594-1597`); `preflight_workers()` checks reach and identity only. The prior-rows check runs at launch before spend; a missing `fresh_default.streams` on m1 reads as empty (`study_area_hosts.sh:58-69`, non-strict at `study_area_run.sh:1389-1390`), and worker prep creates the schema (`worker_prep.sh:197`). *Folded: Phase 1 wording.*
- Phase 3's launch line omitted `BCFISHOBS_DIR=<clone>`; `launch.sh` aborts without it. *Folded.*
- The issue's "Before launch" gate box names the refused command; when ticked, the body must say what ran. *Folded: Phase 4.*

## Ordering

- The seed must sit between the drop and the gate (either side of Phase 1's `--preflight-only`, which refuses on "no gate record" in both states). *Folded.*
- fresh reinstall before the gate is right: `pretest_record_check` refuses a record whose `fresh_sha` is not the installed one (`pretest.R:579-582`).

## Assumption

- pak from the tag satisfies the pre-flight: `.lnk_pkg_git_state()` (`R/lnk_stamp.R:374-424`) reads a hex `RemoteSha` and infers `dirty = FALSE`; m1 shows the same shape. Not verified: m4's `~/.Renviron` sets no `FRESH_GIT_SHA` (#441's run on m4 argues it does not).
- The fresh checkout's branch does not matter to the pick (it diffs tags and walks a temporary worktree, `pretest.R:139-146, 521-526`); it needs both tags fetched. Not verified.
- About 11 picks: #441's gate on the same range picked 11; `default`'s changed set is that minus the minimal bundle's files.
- Timeline and spend: not verified.
- The two droplets that are not cloud hosts of this driver do not block the launch: `hosts_preflight_droplets` acts on `^cypher(-|$)` only (`study_area_hosts.sh:471-488`); `check.sh:78-80` counts `^cypher-`. Verified.

## Scope

- The parity key needs the dispatcher's `fresh_sha` equal to m1's (`R/lnk_preflight_parity.R:72-75`), so keeping the 0.52.0 pin is forced unless m1 moves too. Consistent with the decision.

## Acceptance

- Launch flags all exist and are valid (`study_area_run.sh:263-315, 340-352`); `--focal` order dispatcher, workers, cyphers (`:52-54, 436-443`). `check.sh` is generic over `<n>` and hosts; it ran for #441's 241 groups. Packer names satisfy `study_area_buckets.R:150-170, 187-194`; the state holds all three names. The calibrator refuses a run already in its history and a plan whose groups differ from `<TS>_run_wsgs.tsv`. Every issue box has a phase.

**Verdict:** not launchable as first written (one Blocker, no code change needed); launchable as folded.
