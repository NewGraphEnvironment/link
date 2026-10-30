# Task: Read a fish record at a segment's start as not upstream of that segment (#399)

**If done:** under `default`, the last segment reading "observed upstream" for a species is the one ending at its highest record on each line, so maps and summaries show where the highest fish is. **If never:** the segment starting at a species' highest record also reads observed, so "known" runs on past the fish to the next break of any kind.

## Problem

The code-2 walk calls `fresh::frs_network_features(direction = "upstream", include_equivalents = TRUE)` (`R/lnk_pipeline_access.R:272-283`). That calls fwapg's `fwa_upstream()` with a 1 m tolerance (fresh@v0.47.0 still passes `1`). On the same line it counts a record at measure `m` as upstream of a segment starting at `s` when `m >= s - 1`. So the segment starting at a species' top record holds that record and reads 2. #396 measured the effect (`research/observation_breaks.md`): a species turns to 1 only at the first cut more than 1 m above its top, so its own top break never moves its own boundary.

With `include_equivalents = FALSE`, the same function counts the record only when `m >= s + 1` (fwapg `fwa_upstream`, read from the local database). Breaks are rounded to the metre (`frs_break_apply()`, `measure_precision = 0`), so a break at a species' top starts its segment within 0.5 m of the record. That segment then reads 1 and the one below it reads 2. The 1 m tolerance is fresh's own, so fresh needs no change.

**What exploration changed.** The issue said the `bcfishpass` bundle keeps today's reading "for parity". It does not: bcfishpass's own observation walk (`model/01_access/sql/load_streams_upstr_observations.sql`, `smnorris/bcfishpass@620dbe43`) calls `FWA_Upstream(…, False, 1)`. link's `TRUE` is a transcription error, and it is the whole of the observed-km gap #403 measured on BULK and PARS under the `bcfishpass` bundle (1.9 to 29.7 km per species, every disagreeing piece the segment above a record; `research/known_suspected_km.md`, "Against bcfishpass"). The barrier walks keep `include_equivalents = TRUE`: a barrier at a segment's start must still block it, and bcfishpass does the same on `fwa_downstream`.

## Decided at the gate (operator, 2026-10-30)

1. **No bundle key.** The observation walk reads `include_equivalents = FALSE` for every bundle, as bcfishpass does. A switch both bundles would set the same way is dead config. The issue body is edited to say why (the SQL above), and its acceptance line "`bcfishpass` builds of BULK and PARS are unchanged" becomes "move 2 → 1 only, on the segment above a record, and their observed km match the reference view".
2. **Vocabulary:** retire `acc-v1` and `acc-bcfp`, add `acc-v2` and `acc-bcfp-2` with the same specs and definitions naming the record-at-start rule (`acc-bcfp-2` is the RUNBOOK's "a new transcription of bcfishpass's rules"). `.lnk_vocabulary_match()` already prefers the live row when a retired one shares its spec.
3. **Measured on m1's local docker fwapg** (idle at planning time), in scratch schemas only: `zz399_default_{pre,post}` (LKEL, BULK, UPCE, PARS, ELKR) and `zz399_bcfishpass_{pre,post}` (BULK, PARS) via `LNK_SCHEMA`, never `fresh` or `fresh_default`. PRE from a worktree at the branch point, POST from a worktree at the branch head. No recompute step: `lnk_access()` passes `observations = NULL` and keeps a prior 2, so it cannot see the change, and the dev-schema recompute fails its dam post-condition anyway (#396's run).
4. **Parked** at the operator's word (2026-10-30): the baseline is written and pushed; the run-to-PR mandate starts when the `### Resume` block in `progress.md` is pasted into a fresh session.

## Phase 1: Fixture test (red) and the issue body

- [x] Edit #399's body: premise corrected (bcfishpass passes `False, 1`; no key; both bundles move), acceptance rewritten as above, `## Decisions` recording the gate calls. `gh issue edit 399 --body-file`.
- [x] Live-DB fixture in `tests/testthat/test-lnk_pipeline_access.R` (`skip_if_no_db()`, `pg_temp` tables as the `.lnk_walk_keys` live test uses, so nothing to drop): two segments on one line, `[100, 521)` and `[521, 900)`, species X recorded at 100 and 520.6 m, an empty `barriers_x` table. Every `fwa_upstream` arm first requires `wscode_ltree_b <@ wscode_ltree_a`, so the tables carry ltree codes (review item 4): segments `id_segment, watershed_group_code, blue_line_key, downstream_route_measure, wscode_ltree, localcode_ltree`; observations `species_code, blue_line_key, downstream_route_measure, wscode, localcode`, the same codes with `wscode = localcode` (the simple arm); `barriers_x` with `barriers_x_id` and the four keys. Call with `wsg_presence = list(x = TRUE)` (so the empty barriers table gives `has_barriers_x_dnstr` FALSE, as the pipeline does) and read the result by `id_segment`, never by row order (`segments_sql` has no ORDER BY). Expect `access_x` 2 on `[100, 521)` and 1 on `[521, 900)`; with the walk's `include_equivalents` restored to `TRUE` both read 2 (run once by hand with the defect restored and note the red in `progress.md`).
- [x] Mocked test: the observation walk is called with `include_equivalents = FALSE` and every barrier walk with `TRUE`, read from the `list(...)` the "every downstream walk is scoped" test already captures. Kept beside the fixture: the fixture skips without the docker DB, so in CI this is the only guard on the argument (review item 9).
- [x] `devtools::test()`: the two new tests fail, nothing else moves.

## Phase 2: The change, its docs and the vocabulary

- [x] `R/lnk_pipeline_access.R:280`: `include_equivalents = FALSE` on the observation walk only, with the reason in the comment (bcfishpass's call, `m >= s + 1`, breaks metre-rounded so the boundary lands on the top record). Roxygen code table: 2 = "no barriers downstream, species recorded more than 1 m above the segment's start on its line or on a tributary".
- [x] `R/lnk_pipeline_break.R`: the `observations` row of the break-source table and `.lnk_pipeline_break_obs()`'s roxygen (a species' top break now moves its own code; the species turns 2 → 1 at its top). `inst/extdata/configs/default/config.yaml` `observation_breaks` comment likewise.
- [x] `inst/extdata/vocabulary.csv`: `retired = 0.72.0` on `acc-v1` and `acc-bcfp`; new rows `acc-v2` and `acc-bcfp-2`, same specs, `introduced = 0.72.0`, definitions saying what changed. `introduced` cannot be edited once committed (`vocab_append_only`), so this commits the release to a minor bump (review item 7; Phase 4). `tests/testthat/test-lnk_vocabulary.R` "each shipped config resolves" → the new tokens; the "retired and live rows share a spec, the live one is returned" case goes into the existing retired-match test. `tests/testthat/test-lnk_log.R:797` pins `'acc-v1'` in `default_tuned`'s log INSERT → `'acc-v2'` (review item 3). `lnk_vocabulary_resolve()` examples unchanged.
- [x] RUNBOOK: §2c "What reads an observation break" and "a segment's codes depend only on where it starts" (record counts at `m >= start + 1`; a species' own top is where it turns); §3 if it states the 1 m reading; §6b acc row and the `acc-v2` / `acc-bcfp-2` example. `research/observation_breaks.md` "The rule" and its `Verified` line; `research/output_vocabulary.md` token table; `research/known_suspected_km.md:18` and `:74` state the old rule in body text (review item 10). `CLAUDE.md:42` names the shipped tokens. Correctly untouched: `R/lnk_barrier_overrides.R:165` (barriers, downstream 1 m), the validator's "segment starting within 1 m" (segmentation, not code 2), `NEWS.md` history.
- [x] `devtools::test()` green, `lintr::lint_package()` clean, `devtools::document()`, `pkgdown::check_pkgdown()` (no export changes expected).

## Phase 3: Builds before and after, compared on measure-overlap pieces

- [x] `data-raw/logs/record_at_start_399/run.sh` from `observation_breaks_396/run.sh`: PRE and POST worktrees, `wsg_run_one.R` with `LNK_LOAD=loadall`, `LNK_GUARD_DOWNSTREAM=warn`, `LNK_SCHEMA`, run uid `399_<step>`; downstream order (UPCE before PARS); BEFORE and AFTER of each group back to back; `status.tsv` with load averages; a quiet-database gate. Launch detached (`nohup … & disown`), wait with one `until` loop on the `RUN399_DONE` marker. Edit nothing in either worktree while it runs.
- [x] `build_obs.R` from #396's: the walk reads `working_<wsg>.observations`, which every run rebuilds and the two configs filter differently (presence, exclusions), so after the builds each working schema holds whichever config ran last (review item 2). Rebuild the filtered set per config and group with `.lnk_pipeline_prep_observations()` into `zz399_obs.<config>_<wsg>`; the predicate below reads that, never `bcfishobs.observations` (any group, no exclusions).
- [x] `pre_post_diff.R` from #396's, with the direction rule inverted (review item 1: #396's counts any change on an unmoved start as a violation and would abort on the first expected piece). Per schema pair, on every piece: `dir = 0` and `seg_pre = seg_post` as invariants (no cut moves); exactly one change class allowed, 2 → 1 where a same-line record of the species from `zz399_obs` lies in `[s − 1, s + 1)` (`at_record`, half-open: a record at exactly `s + 1` counts in both builds; "none further upstream" is implied by POST = 1, and a tributary record above keeps 2 in both builds, so needs no clause; review item 5). Every other difference is a violation: 1 → 2, 0 ↔ open, `has_barriers`, habitat flags, mapping codes, a 2 → 1 piece with no record at its start. Writes `pre_post_diff.csv`; stops on any violation.
- [x] Parity: `rollup.R` adapted from `known_suspected_403/rollup.R` for `zz399_bcfishpass_{pre,post}` against `fresh.streams_vw_bcfp` on m1 (`parity_bcfp.csv`; a new `parity_pieces.sql` whose header states the new rule, #403's copy left frozen). Expected: `observed_diff_km` near 0 and no `link_only, at_start` pieces after, ST excepted while the reference predates `smnorris/bcfishpass@3bd2824c`. Do not require ≈ 0: bcfishpass's `spp` CTE has no group filter on the observations side and link's walk reads the group's own records (#401), so classify any residual piece by mechanism with an `upstream_group` flag reading `observations_province` (review item 6). Record the reference view's version (`provenance.source_artifact` or `s3://fresh-bc/bcfishpass/log.json`) in `stamp.txt`; if m1's differs from m4's `v0.7.14-113-ga7373af`, say so beside the numbers.
- [x] `default` rollup on `zz399_default_{pre,post}` (observed / unobserved km per group and species) for the write-up; `segments.csv` showing segment counts identical between pre and post in every schema (no cut moves).
- [x] `README.md` (run decision written before the builds, files, what happened) and `stamp.txt` (link SHAs, fresh version, config hashes, log rows).

## Phase 4: Write-ups

- [x] `research/known_suspected_km.md`: a post-#399 section with the `default` split and the bcfishpass parity after the fix (the file says its numbers are a baseline before #399); `Verified` line; "What will move these numbers" updated.
- [x] `research/observation_breaks.md` and RUNBOOK §2c carry the measured direction (2 → 1 km per group-species, where).
- [ ] NEWS text drafted in the PR body for `/gh-pr-merge`, and the body says explicitly: bump **minor** to 0.72.0, because `vocabulary.csv` already names 0.72.0 in `introduced` / `retired` and that cell cannot be edited afterwards (review item 7). Version bump at the release step, not in the branch.

## Owed at the end (reported, done after merge)

- [ ] Every persisted group carries the old reading until re-modelled: the recompute passes no observations and keeps a prior 2. `fresh_default` (241 groups) and the `bcfishpass` schema re-model at the next provincial run (#377's runs row), stacked on #326's and #396's owed re-models. The pre-run gate (#372) must run again (`R/lnk_pipeline_access.R` changed).
- [ ] `lnk_scenario_export()`'s access-code column (#403 "Not done") still waits for #401.

## Validation

- [ ] Tests pass (`devtools::test()`, with the live fixture running against the local docker)
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved:

- **The walk reads the record as not upstream:** the live fixture (`c(2L, 1L)`), and the mocked call-log test (`FALSE` on the observation walk, `TRUE` on every barrier walk); the fixture seen red with `TRUE` restored.
- **Only the expected output moves:** `pre_post_diff.R` on five `default` groups and two `bcfishpass` groups, `n_violation = 0`: every piece `dir = 0`, every 2 → 1 piece `at_record`, zero km of habitat, mapping-code or `has_barriers` change, identical segment counts.
- **It is the bcfishpass reading:** `parity_bcfp.csv` observed-km gaps on BULK and PARS close to rounding (ST excepted and named).
- **The vocabulary rules hold:** `test-lnk_vocabulary.R`'s append-only check against `origin/main` passes in the checkout (retire allowed, no edit, no rename); each shipped config resolves to `acc-v2` / `acc-bcfp-2`.
- `research/`, RUNBOOK and the issue body say the same thing as the code (grep RUNBOOK and `research/` for "within 1 m" and "start - 1" before the PR).

Plan review (one `Plan` agent, run synchronously before this baseline): eleven findings, all verified against the files they cite and folded in above; `planning/active/review-plan.md` holds them.

Stale first-party installs (`check_pkg_stale.sh`, 2026-10-30): `link 0.68.0 → 0.71.1` is the installed copy, and every script here runs under `load_all`; nothing else listed is used by this work. No upgrade needed.
