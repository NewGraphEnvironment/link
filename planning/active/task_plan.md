# Task: Backlog move 7: Drivers: an explicit config, a labelled standalone run, and the legacy path (#475)

**If we do it:** no driver defaults to `bcfishpass`, a standalone run carries a run id, and `data-raw/` keeps one runner. **If we never do:** the next run can go out on the parity config by default, as one did on 2026-09-03.

Batch 10 of `planning/backlog.md`: #278, #281, #166, #181, #179, #110. Gate (from the backlog): retire the legacy `wsgs_*` path, which closes #179 and #110 and shrinks #176.

## Decided at the gate

No plan gate in this pane: a `/coordinator` dispatched this `park review` (`GATE=coordinator`, soul#928), so the coordinator's plan gate, or the owner, approves this plan at the resume. A Plan review ran before the baseline (`review-plan.md`); its corrections are folded in below and marked "(review)". Decisions made in drafting (mechanism, `agent-operations.md` §4), each with its reason:

- **Retire the legacy path first (Phase 1)**, so no later phase edits a file that is about to go. Retired: `wsgs_dispatch.sh`, `wsgs_run_host.R`, `wsgs_run_pipeline.sh`, `wsgs_run_m4_offline.sh`, `trifecta_15wsg.sh`, `trifecta_smoke.sh`, `runs_archive.sh`, `buckets_balance.R`, `progress_check.sh`. Nothing kept (tests, workflows, `inst/`, the `study_area_*` path) reaches them (grep, 2026-11-22; confirmed by the review). **Kept:** `wsg_compare.R` and `wsg_pipeline_run.R` (`study_area_compare.R`, `_targets.R`, `regress_dams_isolation.R` and `rule_flexibility_demo.R` source them), `cypher_prep.sh` (`study_area_run.sh` runs it), `state_clean.sh` (#181 extends it; after Phase 1 nothing calls it, it is an operator tool), `_targets.R`.
- **#179 and #110 close as retired**, not fixed: the fallback split and the RDS cache key both live in `wsgs_dispatch.sh` / `wsgs_run_host.R` (`run_provincial_parity.R` was renamed `wsgs_run_host.R` in #172). Their comments name this PR.
- **The refusal is inline in each driver**, not a shared sourced helper: a cloud host runs the drivers from a clone, and three lines per driver are cheaper than a new file every driver must find. One test pins the set (Phase 2). It sits before `load_all()` / `library(link)` in each R driver, so it needs no database.
- **The usage line is accurate about schemas (review, blocker):** `default`'s `config.yaml:93` sets `schema: fresh`, the same as `bcfishpass`; `fresh_default` exists only through `--schema=` / `LNK_SCHEMA`. So the line names the bundle and the schema it resolves to, says a bundle other than `bcfishpass` needs an explicit schema, and lists the bundles from `inst/extdata/configs/` (seven today), not "both configs".
- **`study_area_run.sh`'s guard (`:491`: a non-`bcfishpass` config needs `--schema=`) is added to `wsg_run_one.R`, `wsg_recompute_one.R` and `barriers_views_build.R`** (refuse a non-`bcfishpass` config with no `LNK_SCHEMA`) (review, blocker): once a config is required, operators will type `default` into drivers that would otherwise write it over the parity build in `fresh`. The required-config refusal comes before that guard, so an empty config reads the usage line.
- **`cypher_prep.sh` requires `CYPHER_PREP_CONFIG` only when `CYPHER_PREP_STAGE=all`**, checked at the top of the script beside the stage check (as `worker_prep.sh:70` does) (review, blocker): `study_area_run.sh:1614` runs the install stage with no config, and the old default sat inside the R heredoc after the installs.
- **Drivers that default to `default` are in scope** (review): `access_disagree_349.R:62` and `habitat_variants_build.R:142` / `habitat_variants_score.R:92` (`--base`). #278's acceptance is "every driver refuses to run without an explicit config", and a `default` default is the same shape.
- **Historical text keeps the old names:** dated `research/` files, `planning/archive/`, `data-raw/logs/` and `CLAUDE.md`'s dated status blocks are records (`planning.md`, forward-only). Living docs change: `RUNBOOK.md`, `data-raw/README.md`, `research/study_area_run.md`, `research/provincial_run_runbook.md` (listed live in `research/README.md:51`).
- **The pre-run gate:** this PR edits `R/utils.R` (a roxygen line), `wsg_run_one.R`, `wsg_recompute_one.R` and `study_area_run.sh`, all under `PRETEST_LINK_PATHS` (`pretest.R:109`), so it voids the gate record (review: `R/` counts too). The gate already owes its run from earlier releases (CLAUDE.md, 2026-11-23 status); NEWS says this adds no new owed run, only keeps the existing one owed.
- **The data-raw tests skip in CI** (`.Rbuildignore` has `^data-raw$`, and R CMD check runs on the built package), so the negative tests run only under a local `devtools::test()`; the PR records that run.

## Open decisions

None. Answered by the owner 2026-11-23, all as recommended (moved to the decisions below).

## Decided at the resume (2026-11-23, owner)

1. **#281:** `run_uid` stays NULL on a standalone run; the required label carries traceability; PUBLISH keeps refusing a standalone build unless `LNK_PUBLISH_ALLOW` gives a reason. No `R/lnk_publish.R` change.
2. **#166:** correct `data-raw/README.md` to noun-first; rename a verb-first script only when no `research/`, archive README, `R/`, `tests/`, `inst/` or `.github/` file names it; evidence-cited scripts keep their names, listed at close.
3. **#181:** `state_clean.sh --tables=` is local by default; other hosts only when named with `--hosts=<ssh target>,...` (cyphers by workspace).

## Phase 1: Retire the legacy `wsgs_*` path (#179, #110; shrinks #176)

- [x] Re-grep every reference to the nine retired scripts across the repo (code, tests, workflows, docs) and record it in `findings.md`; refuse to delete any that something kept reaches
- [x] `git rm` the nine scripts
- [x] Remove or reword live references: `state_clean.sh`'s `ps` pattern and header, `cypher_prep.sh`'s comments, `wsg_compare.R`'s header, `wsg_pipeline_run.R:5`, `query_schema_delta.R:7-8`, `study_area_buckets.R:24`, `study_area_run.sh`'s two comments, `R/utils.R:319`'s roxygen line (review added four)
- [x] `data-raw/README.md`: drop the legacy rows and the "Provincial dispatch (`wsgs_dispatch.sh`)" section; one line saying the path was retired in this release and `study_area_run.sh` is the runner
- [x] `RUNBOOK.md`: `:428`, and the "headline path" at `:3506`, which uses `wsgs_run_m4_offline.sh`: replace it with a `wsg_run_one.R` command carrying `LNK_SCHEMA`, an explicit config and (after Phase 3) a label (review)
- [x] `research/provincial_run_runbook.md` (`:23-27`, `:150-191`, `:303-305`) and `research/study_area_run.md`: remove or redirect live instructions that name the retired scripts (review)
- [x] Draft the closing comments for #179 and #110 and the shrink note for #176 (posted at merge)

## Phase 2: Every driver needs an explicit config, and the run prints its decisions (#278)

- [x] Make the config required in each driver that defaults it: `study_area_run.sh`, `recompute_parity.sh`, `recompute_sweep.sh`, `wsg_run_one.R`, `wsg_recompute_one.R`, `study_area_wsgs.R`, `study_area_compare.R`, `host_stamp.R`, `barriers_views_build.R`, `study_area_buckets.R`, `parity_crosssection.R`, `access_disagree_349.R`, `habitat_variants_build.R` / `habitat_variants_score.R` (`--base`), and `cypher_prep.sh` at `STAGE=all` only. A missing config exits non-zero with the usage line decided above
- [x] Add the schema guard to `wsg_run_one.R`, `wsg_recompute_one.R` and `barriers_views_build.R`, after the config refusal; check `recompute_parity.sh:36` and `parity_crosssection.R:56`, which default the schema to `fresh`, and give them the same rule
- [x] Re-grep `data-raw/` for any other config default, `bcfishpass` or `default`, and decide each (a script that names the parity bundle on purpose, such as `sync_bcfishpass_csvs.R` or `wsg_vignette_data.R`, keeps it)
- [x] Confirm every caller already passes a config (`study_area_run.sh` legs and `:1614`, `study_area_remote.sh`, `study_area_finish.sh`, `pretest_run.sh`, the printed re-model commands)
- [x] `study_area_run.sh`: the required-config refusal before the `:491` schema guard
- [x] `study_area_run.sh` prints a `=== decisions for this run ===` block: config with its alternative, persist schema with its alternative, focal groups, the resolved closure with its count, the species from config x presence per kept group, and the primitives' last load (refreshed or not). It prints right after the overlap block (~`:1765`), before the first write (the `PRETEST_NOTE` psql write ~`:1713`, `run_wsgs_write` `:1785`, `lnk_persist_init` `:1820`, the `pg_dump`), not only before `cypher_up` (review)
  - species: `study_area_wsgs.R` already holds `cfg`, `loaded` and the kept groups (`:46-48`); emit `lnk_pipeline_species()` per group on stderr, no extra R start
  - primitives: capture `host_vintage.R`'s last-load date (`:1290`, now console-only)
  - `--preflight-only` takes no `--focal` (`:421-423`, `:470`): resolve the closure there only when focals are given, enforcing the focal count then; otherwise print `focal/closure/species: not resolved (no --focal)`. Never index an unset `FOCAL_ARR[i+1]` under `set -u`
- [x] Test: `tests/testthat/test-driver_config.R` runs each driver with no config and expects a non-zero exit and the usage line (skipping where `data-raw/` is absent, as `test-pretest.R` does; `study_area_run.sh` through `hosts_bash()`, since it exits on bash < 5.1); a non-`bcfishpass` config with no schema refused by the three guarded drivers; restore one default and watch it fail

## Phase 3: A standalone run is labelled (#281)

- [x] Decision 1 answered (NULL `run_uid`, label required)
- [ ] Put the label and `run_uid` rule in one small function each driver sources or inlines identically, testable without a database (`wsg_run_one.R` connects at `:56`) (review)
- [ ] `wsg_run_one.R` and `wsg_recompute_one.R`: with `LNK_RUN_UID` unset, refuse an empty `LNK_RUN_LABEL` with a usage line, and apply decision 1's `run_uid` rule; with it set, behave as today. Keep the label check `study_area_run.sh` applies to `--run-label=` (`A-Z a-z 0-9 . _ -`). Under (a′), edit `lnk_publish.R` and the stall hint at `wsg_run_one.R:149-153`
- [ ] Every printed and documented standalone invocation carries a label (`RUNBOOK.md`, CLAUDE.md's current instructions); the review found the printed re-model commands and remote legs already carry `LNK_RUN_UID`, and `pretest_run.sh:256` (label, no uid) runs under every option
- [ ] Test the function (refusal, label check, stored `run_uid`), and restore the old path and watch the test fail; the stored value is checked live by the validation run

## Phase 4: `state_clean.sh --tables=` (#181)

- [x] Decision 3 answered (local by default, `--hosts=`)
- [ ] Parse `--tables=schema.table,...`; refuse an empty value and any entry outside `^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$`; combinable with `--schemas=`
- [ ] Skip step 1 (the kill step, `:87-97`: `kill -9` of matching local processes, `pkill` on M1 and every cypher) under `--tables=`, and refuse while a `study_area_run.sh` is live (review, blocker): a surgical drop during a run would end its legs
- [ ] Drop each listed table (`DROP TABLE IF EXISTS … CASCADE`) on the hosts decision 3 names, with no snapshot reload; check each host's exit status instead of the unconditional "✓ schemas dropped" after `wait` (`:146`), for `--schemas=` too
- [ ] Header says which hosts it reaches and drops the unread `/tmp/cy_ips.env` claim
- [ ] Tests with stubbed `psql`, `ssh`, `ps`, `kill` and `pkill` (so no test kills a real process): a valid list, an invalid entry, an empty value, the combined form, a stubbed `psql` exiting 1 that fails the run; one live smoke on a scratch table in local fwapg. Reconcile with #181's M4 + M1 smoke under decision 3

## Phase 5: Noun-first names (#166)

- [x] Decision 2 answered (rename only where uncited)
- [ ] List the remaining verb-first scripts and, under decision 2's rule, which are renamed and which keep their names and why; record the table in `findings.md`
- [ ] `git mv` each rename and update every reference
- [ ] Rewrite `data-raw/README.md`'s naming section to noun-first (`<noun>_<verb>[-detail]`, `newgraph.md`), with a forward-only note for the kept names

## Phase 6: Release

- [ ] NEWS entry (0.89.0: drivers refuse without a config, so a minor bump), naming the retired scripts, the new refusals and schema guards, the decision block, `--tables=`, and that the pre-run gate's owed run is unchanged
- [ ] `CLAUDE.md` status block for this release
- [ ] `devtools::test()` (local: the data-raw tests skip in CI), `lintr::lint_package()` per file and class against `origin/main`, `devtools::check()`
- [ ] `/code-check branch`; version bump last

## Owed at the end (reported, done after merge)

- [ ] Post the closing comments on #179 and #110 and the shrink note on #176
- [ ] Hosts and anything outside this repo that call a retired script or omit a config (scheduled jobs, the cloud image's scripts, operator shell history) move to `study_area_run.sh` with an explicit `--config=`: named in the PR body for the operator

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved: Phase 1 by a repo-wide grep showing no live reference to a retired script and the test suite unchanged; Phase 2 by the new test (each driver refuses with no config, the three guarded drivers refuse a non-`bcfishpass` config with no schema, and a restored default fails it) and one `study_area_run.sh --preflight-only` printing the decision block, with and without `--focal`; Phase 3 by a test of the label and `run_uid` function, plus one standalone model of a small group in a scratch schema reading its `log` row; Phase 4 by stubbed tests (no real process touched) and one live drop of a scratch table; Phase 5 by a grep showing no reference to an old name outside historical records.
