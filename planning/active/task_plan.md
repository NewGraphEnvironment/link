# Task: Provincial run: can a drainage component be split across hosts now that the recompute settles access? (#361)

`study_area_buckets.R` packs whole drainage components onto hosts (union-find over per-group `frs_wsg_drainage()` closures), and each host models its component downstream-first. On run `20261017_004619-3f4c713b` (241 groups, `fresh_default`):

| | host-minutes |
|---|---|
| modelling, all groups | 873 |
| Fraser component (68 groups) | 205 |
| next largest (Peace, 26 groups) | 107 |
| slowest single group (SETN) | 16.5 |

So the dispatcher's Fraser bucket sets the floor, and four cloud hosts already fill the other 668 min under it (`research/study_area_run.md`, "Hosts against wall clock").

The rule was written for two reasons (`study_area_buckets.R` header):
1. Cross-group `;DAM` and access need downstream groups' barriers persisted first.
2. Overlapping closures would model a group on two hosts, and consolidate would keep whichever finished last.

## Context

`study_area_buckets.R` packs whole drainage components onto hosts, so a province-wide run's
modelling cannot finish before its largest component (the Fraser, 205 of 873 host-minutes).
The rule was written for cross-group `;DAM` / access (reason 1) and against two hosts modelling
one group (reason 2). Since #175 the post-consolidate recompute settles access, mapping code and
(since #349) the habitat flags from every group's persisted barriers, and the run already models
with `LNK_GUARD_DOWNSTREAM=warn` and `LNK_HABITAT_GATE=0`, so the rule may protect nothing.
That is untested; in particular `lnk_access(merge = TRUE)` keeps a prior `access_<sp> = 2`.

The same issue owns the next provincial `default` run (the re-model #364 and #367 owe, at link
0.68.0 on fresh 0.42.0) and the bcfishpass parity re-score after it.

**What exploration changed about the issue's framing (put to the operator at the gate, 2026-10-22):**

- Only three cypher tofu workspaces exist (`job1`–`job3`). At 4 hosts, 873 host-minutes is 218 min
  each, above the Fraser's 205, so splitting the Fraser gains nothing on *this* run. The last run's
  hosts took 165 / 205 / 272 / 231 min (`fresh_default.log`, newest row per group) against an ideal
  ~218, because the generator weighted by segment count with cloud hosts at 0.45× m1's speed, and
  the 2026-10-17 run measured them at about m1's rate. The gain available now is **packing on
  measured minutes with equal speeds** (~272 → ~230 min). Splitting pays at 5+ hosts.
- Model-time inputs that could depend on order, as read: `<working>.observations` is AOI-scoped
  from `bcfishobs.observations` (`R/lnk_pipeline_prepare.R:292`), and `observations_province` is
  rebuilt from the primitive each run, so the kept `2` should not differ by order. Measured, not
  assumed: that is the test.
- `lnk_wsg_resolve(expand = FALSE)` already keeps input order after the species filter
  (`R/lnk_wsg_resolve.R:113`), which is what an exact per-host list needs.
- `data-raw/logs/provincial_prep_367/run.sh` (two lanes, a lock per group, `LNK_SCHEMA` scratch
  schemas) and `compare.R` (per-group per-table digests, geometry as EWKB, barriers with and
  without id) are the harness to reuse for the split test.

## Decided at the gate (operator, 2026-10-22)

| decision | choice | alternative refused |
|---|---|---|
| today's `fresh_default` | `ALTER SCHEMA fresh_default RENAME TO fresh_default_20261017` before launch; keep for a before/after diff; drop later | build over it |
| primitives | **revised 2026-10-23 (operator): `--refresh-primitives`.** The first choice (keep the 10-17 load, `--vintage-max-days=10`) is not achievable on a multi-host run: `cypher_prep.sh` runs `snapshot_bcfp.sh`, which pulls PSCIS and CABD with no version handle and bchamp objects at their current version (`modelled_stream_crossings` moved on 2026-10-20, version `1792530487154`), so the hosts would model on different inputs and `verify_extra.sql` would fail. Every host takes one load at launch, as on 2026-10-17; the parity re-score runs on that load and its moves include input moves, named by `log_input` and `override_diff.csv`. | dispatcher-only on the 10-17 load (~17 h) |
| hosts | 3 cloud hosts (`job1,job2,job3`) + m1, launch now; component packing on measured minutes | create `job4` in the infra repo first |
| split test | after the run, on m1; the run's own Peace build (one host, DS-first) is the reference | before the run |
| config / schema / closure / species | `default` → `fresh_default`; all 246 focal → 241 modelable (as 2026-10-17); species from `default` × presence; `dams` and `mapping_code` on (driver defaults); recompute `-j8` (1.43× over 4, #349 status) | — |
| other session | another session's jobs (`knowledge` repo `0320-tune-run.R`, `0330-compare.R`) read `fresh_default` live and share the database VM: wait for both to exit, then rename and launch (operator, 2026-10-23); nothing is done to their processes | stop them; launch into a temporary schema |
| run from | the feature branch, tree clean, pushed (cyphers pull the ref); link stays 0.68.0 (only `data-raw/` changes before the launch) | main |
| `default`'s parameters | unchanged for this run. Every recent knob already carries a measured `default` decision (#364 door on wetland lines, #367 placeholders on, #310 10 km, #307 MAD ranges, all groups on `cw`); calibrated values stay in `default_tuned`, the staging bundle, and promoting one is its own scored decision for which this run is the baseline (#346). The only default that moves is the driver's host-speed assumption (Phase 1). | fold a `default_tuned` value into `default` before the run |

## Phase 1: Pack hosts on measured minutes (before the run)

`data-raw/study_area_buckets.R`:
- [x] New `--minutes-schema=<schema>`: weight each modelable group by its newest finished `log` row
      (`extract(epoch from date_end - date_start)/60`, `date_end IS NOT NULL`, newest `date_start`
      per group), median for a group with no row, and print how many took the median. Without the
      flag, the segment-count weights stay, and the report says which weighting was used.
- [x] `--host-speeds` default becomes equal (`1,1,…`), with the 2026-10-17 measurement in the
      comment replacing the 2026-08-31 pilot's 0.45. The report prints each host's estimated
      minutes, not only a share.
- [x] Generate the run's split: `LNK_LOAD=loadall Rscript data-raw/study_area_buckets.R
      --config=default --hosts=4 --minutes-schema=fresh_default --focal=<all 246>
      > data-raw/logs/provincial_361/buckets_default.md` (stderr beside it). Record the estimated
      makespan against the component floor (Fraser 205 min).
- [x] Commit; push the branch (cyphers pull it).

## Phase 2: The provincial `default` run (operator-attended, ~7 h wall, ~$5 cloud)

- [x] Pre-flight without spend: `bash data-raw/study_area_run.sh --preflight-only
      --cy-workspaces=job1,job2,job3 --config=default --schema=fresh_default` (passed on 2026-10-23 04:43 UTC, `/opt/homebrew/bin/bash`).
      Tree clean on the pushed branch; `lnk_preflight_fresh()` passes locally (fresh 0.42.0).
- [x] Rename the old schema (`ALTER SCHEMA fresh_default RENAME TO fresh_default_20261017`),
      after checking no process holds it (`pg_stat_activity`) and disk (`df` on the colima
      volume: 174 G free, not the ~253 G the plan assumed). Done 2026-10-23 07:41 UTC, after the
      other session's two jobs exited at 07:40 UTC; no backend held the schema.
- [x] Launch detached (`nohup … & disown`, never a tool-managed background process) with the
      four `--focal=` lines from `buckets_default.md`, `--config=default --schema=fresh_default
      --run-label=provincial-241-default-361 --recompute-jobs=8 --refresh-primitives`.
      Cyphers are re-prepped on spin by `cypher_prep.sh` (installs link + fresh from the
      DESCRIPTION pin and asserts `lnk_preflight_fresh()`); the host-parity gate confirms it
      before any write. Nothing in the repo is touched while it runs. Launched 07:43:21 UTC
      2026-10-23, run_uid `20261023_074321-24d85e8c` (attempt 1 at 07:42:33 refused by bash 3.2,
      no spend; `launch.sh` fixed in `1d00c04c`).
- [x] Watch it against the clock (`date -u`; `data-raw/progress_check.sh`; each host's database
      count, never log text). On a failed group: `--recompute-only --run-uid=<uid>` after the
      re-model, per RUNBOOK §8d. Cloud legs 249 / 264 / 259 min wall; m1 560 min wall for 306 of
      modelling: KTSU 65.4 min and OKAN stalled 4 h in one statement, cancelled 13:30 UTC under an
      operator-approved 30 min role statement timeout (reset after the run). OKAN re-modelled under
      the run_uid (7.6 min) and finished with `--recompute-only --wsgs=OKAN` (no group drains through it).
- [x] Verify: `study_area_verify.sql` and `data-raw/logs/provincial_246/verify_extra.sql` with
      `-v schema=fresh_default -v run_uid=<uid> -v expected_n=241`; one link SHA in `log` and
      `log_recompute`; the `kept_hosts.tsv` empty; cyphers burned. Both pass at 241 (`run_verify.log`,
      `run_verify_extra.log`); `1d00c04c` on all 241 + 241 rows, `link_dirty` f; no `kept_hosts.tsv`;
      cyphers burned (0 tofu resources each). The verifier was patched so OKAN's failed attempt, superseded
      by its finished row, is a NOTICE (negative cases 6f/6g; `verify_negative.log` 15/15).
- [x] Copy the wrapper logs to `data-raw/logs/provincial_361/` (`run.log`, `run_verify*.log`), plus
      `run_attempt1_bash32.log`, `okan_remodel.log`, `okan_recompute.log`, `verify_negative.log`;
      addresses redacted by hand (the driver's trap covers only `study_area_run/<TS>_*`).

## Phase 3: The split test (m1, after the run, ~2 h)

Harness `data-raw/logs/provincial_361/split_test.sh` + `split_compare.R`, from the #367 pair:
- [x] Peace's 26 groups in DS-first order from `study_area_wsgs.R <the 26> default`; interleave
      odd/even positions onto two "hosts" (scratch schemas `fresh_361a`, `fresh_361b`), and
      **reverse** each host's list so upstream groups run first. Model with `LNK_SCHEMA`,
      `LNK_GUARD_DOWNSTREAM=warn`, `LNK_HABITAT_GATE=0`, one `LNK_RUN_UID`, same link SHA as the
      run, two lanes (one per schema). Count the guard's warnings per group: evidence the order
      was bad.
- [x] "Consolidate" b → a as the real one does for persist tables: per table with
      `watershed_group_code`, `DELETE … WHERE group IN (b's bucket)` then `INSERT … SELECT`
      (log tables by primary key, as `schema_consolidate.R` does since #354).
- [x] Recompute all 26 in `fresh_361a`: `barriers_views_build.R` once, then
      `wsg_recompute_one.R` per group (`LNK_VIEWS_PREBUILT=1`), which runs the downstream guard
      in **error** mode and the habitat gate. A guard failure here is a finding, not a retry.
- [x] Digest every persisted table per group (`streams`, `barriers` with and without id,
      `barrier_overrides`, `streams_access`, `streams_mapping_code`, every `streams_habitat_<sp>`;
      log tables excluded) in `fresh_361a` against `fresh_default` → `split_test.csv`.
- [x] Verdict, one of two:
  - identical on every table and group → Phase 4a;
  - not → name the differing table, groups and columns (a segment-level diff on the first
    differing table), which says what the component rule protects → Phase 4b.

  **Verdict: Phase 4a.** 387 of 442 digests identical; the 55 differing are all cross-host
  arithmetic (≤ 3.7e-9 m in `length_metre`, geometry and 62 barrier positions; the reference Peace
  was built on a cloud host, the split on m1) or the test's 26-group scope (NATR: 2 segments on a
  Fraser-coded line, TOOD: 2 with FROG's barriers below them; 11 digests). MILL and LPCE rebuilt on m1 alone are
  identical to the split build in every model-time table but the gate-blanked habitat rows. `data-raw/logs/provincial_361/split_verdict.md`. Boxes above: run 20:33–21:32 UTC from a
  worktree at `1d00c04c` (the branch had moved on); guard warned on 18 of 26 at open, passed on all
  26 in the recompute.

## Phase 4a: Group-level packing for province-wide runs (if identical)

- [x] `study_area_buckets.R --atom=group`: LPT over single modelable groups (measured minutes),
      each host's list ordered by the global DS-first order (cheap, fewer guard warnings); the
      drainage-closed and within-host DS-first assertions are skipped in this mode and the report
      says the recompute is the guarantee, citing `provincial_361/split_test.csv`. Default stays
      `--atom=component`; `--write` refuses `--atom=group` (`research/study_areas.md` describes
      components). The report prints the makespan under both atoms for the same hosts.
      Done: the within-host order check is kept (it holds by construction and is cheap); only the
      drainage-closed assertion is skipped. On the 246 at this run's minutes (1,077 host-min):
      4 hosts 270 vs 270, 5 hosts 216 vs 231 (`provincial_361/buckets_group{4,5}.md`); `--write`
      and a bad `--atom` refuse.
- [x] `data-raw/study_area_wsgs.R --exact`: `lnk_wsg_resolve(expand = FALSE)`, input order kept;
      `study_area_run.sh --buckets-exact` uses it for every `--focal=` list, keeps the overlap
      check (now fatal in exact mode: a group on two hosts is operator error, not a closure
      property) and records the mode in the banner and `run_wsgs.tsv`. Proved: `--exact NATR,OKAN,TAKL`
      keeps the order and `--exact BASH,NATR` drops BASH; `--buckets-exact --focal=OKAN,OKAN` exits 1
      with `FATAL: --buckets-exact lists overlap on: OKAN` before anything is dispatched;
      `--preflight-only --buckets-exact` passes and prints `buckets: exact`; `--recompute-only` refuses
      the flag; `run_wsgs.tsv` gains `bucket_mode` (tests 296/296).
- [x] Header comments in `study_area_buckets.R` and `study_area_run.sh`, RUNBOOK §8d "Host
      buckets are derived, not chosen", and `research/study_area_run.md` "Hosts against wall
      clock" say when each atom applies and why. (The research entry sits in the 2026-10-23 run's
      section, which revisits "Hosts against wall clock".)

## Phase 4b: Keep the component rule (if not identical)

- [ ] Write the differing input into RUNBOOK §8d and `research/study_area_run.md`, with the
      digest table; file nothing new unless the difference is a defect (then an issue, drafted
      for review first). `study_area_run.sh` and the buckets script keep component mode; the
      measured-minute weighting from Phase 1 stays.

## Phase 5: bcfishpass parity re-score (m1, ~1 h)

- [ ] `bash data-raw/study_area_run.sh --focal=ADMS,BULK,BABL,ELKR --config=bcfishpass
      --schema=fresh_parity361 --run-label=parity-4-bcfishpass-361 --recompute-jobs=8`
      (no refresh: the run's load, within 7 days); verify at `expected_n=17`.
- [ ] `LNK_LOAD=loadall LNK_SCHEMA=fresh_parity361 LNK_CONFIG=bcfishpass
      LNK_PARITY_OUT=data-raw/logs/parity_0.68.0/parity_annotated.csv
      Rscript data-raw/parity_crosssection.R ADMS BULK BABL ELKR`; write `expected.txt` first
      (the #367 prediction: CO −0.22 km ADMS, −1.45 km BULK; 656 PSCIS picks move province-wide).
- [ ] `moves.R` (copied from `parity_0.66.6/`, schemas `fresh_parity362` → `fresh_parity361`),
      matching segments on start **and** length. Revise `research/bcfishpass_parity.md` (table,
      what moved, the run line). Drop `fresh_parity246`; keep `fresh_parity362` as the previous
      build.

## Phase 6: Records

- [x] `research/study_area_run.md`: a section for this run (table as for 2026-10-17: per-host
      minutes against the Phase 1 estimate, consolidate, recompute at `-j8`, wall clock, cost,
      schema size) and the split verdict under "Hosts against wall clock" (the verdict sits in the
      new section's last bullet, which revisits that heading).
- [x] `CLAUDE.md` status block (what the run is, the split answer, facts not worth re-deriving);
      `NEWS.md` entry for the driver changes (0.68.1); `data-raw/logs/provincial_361/README.md`
      indexing the evidence; `data-raw/logs/README.md` rows for `provincial_<issue>/` and
      `parity_<version>/`.
- [ ] Issue #361 body: tick the "Before the run" list, record the verdict and the run_uid; #364
      and #367 bodies: the owed re-model is done. (Drafted; applied once the parity score is in.)
- [x] `lnk_habitat_validate()` no longer refuses `fresh_default` under `default`: run
      `data-raw/habitat_validate.R --bundles=default:fresh_default --wsgs=ADMS` once as the check.
      Passed 21:56 UTC (both buffers); run without `--out=`, which rewrote `habitat_validate_283/`
      (restored from HEAD; lesson in findings).

## Owed at the end (reported, done after merge)

- [ ] Drop `fresh_default_20261017` once no before/after diff needs it (operator's call).
- [ ] A `job4` tofu workspace in the infra repo, if a 5-host run is wanted; group-level packing is
      worth ~30 min there and more beyond.

## Validation

- [x] Tests pass (`devtools::test()`; `tests/testthat/test-study_area_hosts.R` and
      `test-study_area_finish.R` cover the driver's sourced parts; new `--exact` / `--atom` paths
      get a test where a function exists to test, else the generated report is the evidence).
      3805 pass, 0 fail, 0 skip (22:06 UTC 2026-10-23); `run_wsgs.tsv`'s `bucket_mode` has tests;
      `--exact`, `--atom=group` and `--buckets-exact` are proved by the generated reports and the
      refusals recorded in Phase 4a.
- [x] `lintr::lint_package()` clean on changed R: 5 lints, all pre-existing in test files outside
      this branch's hunks (`hosts_bash` from `setup.R`, one indentation in `test-schema_consolidate.R`).
- [ ] `/code-check branch` clean (three-round floor; the harness and driver hunks are shell)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, then `/gh-pr-push`

How each change is proved:
- Phase 1: the report's per-host minutes sum to the measured 873 ± rounding, the makespan is
  under the 2026-10-17 run's 272, and `--hosts=4` without `--minutes-schema` reproduces today's
  segment-weighted answer.
- Phase 2: both verifiers pass at 241; one `config_hash`; every group's newest `log` row from
  this run_uid; `log_recompute` rows for all 241 at `-j8`.
- Phase 3: `split_test.csv` has a row per (group, table) for 26 groups; the guard warned on the
  split build (so the order was bad) and passed in the recompute; a deliberate check that the
  compare can fail (digest `fresh_361a` against `fresh_default_20261017` for one group: must
  differ, since the link version differs).
- Phase 4a: `--atom=group` on the 246 prints a makespan near 873 / hosts; `--buckets-exact`
  with an overlapping pair refuses; `--preflight-only` passes with exact lists.
- Phase 5: 17 groups verified; `parity_annotated.csv` scored; every move in `pair_moves.csv`
  explained in `moves.log`.

