# Findings — Backlog pass: batch the open issues into moves with umbrellas (#468)

## Issue context

**If we do it:** link's open issues are grouped into a short list of moves, each an umbrella issue carrying the batches that share files or a cost, planned with one `/planning-init` and landed in one PR, in an order kept in link's `planning/backlog.md`. The link issues that knowledge's tuning is waiting on are placed knowing what each one holds up there. **If we never do:** link's open issues are picked one at a time, and an issue that blocks knowledge's work looks no more urgent than any other from its title.

## Problem

link has 117 open issues (2026-11-09), no umbrella issues and no `planning/backlog.md`. knowledge ran the same pass on its own 58 (NewGraphEnvironment/knowledge#169), which ended in eleven move umbrellas and a backlog file. Two of those moves, and two of knowledge's tracks, wait on link issues, and that dependency is visible only from knowledge's side.

## Proposed

A backlog pass for link with `/backlog-sweep`, run as planned work under this issue (`/planning-init` on it), because of its size:

- [ ] Read every open issue body and its comments; measure the reference graph, each older premise against the code, and the state of peer issues a batch waits on.
- [ ] Group by the files a batch edits and the cost it shares (a provincial run, a config change, a release), not by topic; fold the batches into as few moves as can be held at once.
- [ ] Place each link issue in the table below knowing which knowledge move or track waits on it, and say so in its batch section, in words. A batch holding one of them ranks by what it unblocks downstream as well as by link's own needs.
- [ ] Report once at the plan gate; on the go, write `planning/backlog.md`, file one umbrella per move, close what was agreed, and open the PR.

## What knowledge waits on (2026-11-09)

| link issue | knowledge work it holds up |
|---|---|
| NewGraphEnvironment/link#434 (barriers each override lifted) | NewGraphEnvironment/knowledge#178, move 9: tuning on link's access with leave-one-out (NewGraphEnvironment/knowledge#131) |
| NewGraphEnvironment/link#400 (what counts as a known record) | the same move: which records lift a barrier |
| NewGraphEnvironment/link#402 (species presence against records) | NewGraphEnvironment/knowledge#132 in the same move: the record rules its access-gradient review reads |
| NewGraphEnvironment/link#460 (the `grad-fwa` token) | the last task of NewGraphEnvironment/knowledge#120 (archiving the Atlas-line setup) |
| NewGraphEnvironment/link#463, NewGraphEnvironment/link#462, NewGraphEnvironment/link#444 (classify on the parent gradient; the near-river distance under it; parent attributes) | link drawing NewGraphEnvironment/knowledge#120's parent-gradient pick |
| NewGraphEnvironment/link#346, NewGraphEnvironment/link#343 (threshold calibration; GR, RB and KO MAD minima on wet's flows) | NewGraphEnvironment/knowledge#139's baselines track: which method sets link's flow numbers, and grayling's baseline (NewGraphEnvironment/knowledge#140) |
| rainbow trout's return to `default` (paused under NewGraphEnvironment/link#432's tracker) | NewGraphEnvironment/knowledge#148 in NewGraphEnvironment/knowledge#177, move 8: the rainbow trout key's return through promotion |

## Keeping the two backlogs in step

- knowledge's waiting moves name the link issue they wait on; link's backlog names, in a placed issue's batch section, the knowledge move that waits on it.
- Each later pass on either side re-reads the other through the sweep's peer search (open issues and PRs on the subject), so a link issue closed or a knowledge move finished shows up at the next pass rather than by memory.

## Done when

- [ ] Every link issue open at the freeze is named in link's `planning/backlog.md`, and each one in the table above says which knowledge work waits on it.
- [ ] Every open move ticks cleanly on a copy of the file, and the next move is named.



## The read: one digest per open issue (three read-only readers, 2026-11-09)

Each reader read the body and comments and checked the premise against origin/main f8a45c29. Verified by spot check: #185, #196 (NEWS), #183 (commit fb8e6428), #95, #126, #128 (files gone), #388 (`_targets.R` read by no run), knowledge's `data/thresholds.csv` on its origin.

## Reader A: #466–#376

I checked all 39 issues. Six look closable: #444, #439 and #376 are done, #458 is mostly misattributed, #420's gradient item is replaced by #460, and #388's driver is probably stale. Every issue is by `NewGraphEnvironment`, and only #452 and #418 have comments. All paths are relative to the repository root.

#466 — Write the shared provenance receipt for scenario exports through crate, and report config_hash differences rather than refuse them
- asks: `.lnk_manifest_write()` writes crate's `receipt.json` instead of `manifest.json`, and checks report a `config_hash` difference rather than refuse it.
- author/created: NewGraphEnvironment, 2026-11-05
- state: premise holds. `R/lnk_scenario_export.R:636` still writes its own manifest and DESCRIPTION has `crate (>= 0.0.2)`. The dependency is ready: crate#43 is closed and `crt_receipt_write()` shipped in crate v0.15.0.
- files: `R/lnk_scenario_export.R`, `DESCRIPTION`, `R/lnk_log.R` (key mapping), `data-raw/study_area_verify.sql`, `R/lnk_preflight_parity.R`
- shared cost: link release (crate floor raised to >= 0.15.0); no re-model
- links: #353, #270, NewGraphEnvironment/crate#43 (closed)
- if-never: "link keeps its own manifest and log-table field names, comparisons with other packages' outputs need a hand mapping, and accounting fields keep failing verification (#353)."
- comments: none
- closure candidate: no

#465 — Export persisted barriers and input snapshots per group, so a one-group run reads downstream
- asks: add each group's persisted barriers (`fresh.barriers`, CABD) and their input snapshots to the S3 export, record their provenance in the manifest, and add a helper that lists which downstream groups' files to fetch.
- author/created: NewGraphEnvironment, 2026-11-05
- state: premise holds. `R/lnk_scenario_export.R` exports no barrier tables.
- files: `R/lnk_scenario_export.R`, `data-raw/habitat_publish.R`, a new helper in `R/`
- shared cost: republish to `s3://fresh-bc/habitat/fwa/v1` after every provincial run; link release
- links: #464
- if-never: "a one-group run on a machine that holds only some groups either refuses (once #464 lands) or, today, classifies access as though nothing downstream blocks."
- comments: none
- closure candidate: no

#464 — lnk_wsg_downstream_check() passes when the downstream groups are not loaded
- asks: refuse, naming the missing groups, when any group on the focal group's downstream path has no streams loaded, plus a fixture test that fails today.
- author/created: NewGraphEnvironment, 2026-11-05
- state: premise holds. `.lnk_dams_blocking_downstream()` still inner-joins `fwa_stream_networks_sp` (`R/lnk_wsg_downstream_check.R:325`), and nothing checks whether the downstream groups are loaded. The same check also runs as a post-condition in `data-raw/wsg_recompute_one.R`.
- files: `R/lnk_wsg_downstream_check.R`, `tests/testthat/test-lnk_wsg_downstream_check.R`
- shared cost: a partial-database fixture; live check on a partial database
- links: #465 (relates)
- if-never: "a partial database ... passes the check with no candidates, and the run writes access codes that ignore every dam downstream."
- comments: none
- closure candidate: no

#463 — Classify habitat on the full network with each segment's minimal parent's gradient (grad-parent)
- asks: a build setting that classifies habitat, and runs the connectivity pass, with `streams_parent.gradient_minimal`; log rows carry `token_grad = grad-parent`; refuse a stale parent table.
- author/created: NewGraphEnvironment, 2026-11-05
- state: premise holds. The `grad-parent` token exists (0.79.0) and `streams_parent` is built, but no classify code reads it. The only references are `R/lnk_streams_parent.R` and `data-raw/streams_parent*.R`.
- files: `R/lnk_pipeline_classify.R`, `R/lnk_pipeline_run.R`, `R/lnk_log.R` (token), `data-raw/streams_parent_build.R` (guard), RUNBOOK §6b
- shared cost: a build on the dispatcher (re-model of the full network under the new setting); link release; settle #462 first
- links: #444, #462, #414; NewGraphEnvironment/knowledge#120 (open)
- if-never: "a minimal-network tuning stays a comparison in knowledge; link draws every rule on each full segment's own gradient, which the cuts at catches shape."
- comments: none
- closure candidate: no

#462 — Under grad-parent, the near-river exception's distance does not transfer from the minimal network
- asks: decide whether full segments read the parent's near-river distance (from the minimal segment's downstream end) or whether the roughly 1,000 km gap is reported as transfer cost.
- author/created: NewGraphEnvironment, 2026-11-05
- state: premise holds. The measurement is knowledge's; `streams_parent` has no distance column.
- files: `R/lnk_streams_parent.R`, `data-raw/streams_parent_build.R`, `R/lnk_pipeline_classify.R`
- shared cost: operator decision (two options); rebuild `streams_parent` on the dispatcher
- links: #444, #414; NewGraphEnvironment/knowledge#120
- if-never: "the full network drops rearing that the minimal-network tuning credited, every time a rule carries a near-river exception."
- comments: none
- closure candidate: no

#461 — lnk_wsg_downstream_check() takes 371 s of a 975 s one-group run
- asks: time the check's steps, make the dominant one fast or cached without changing pass/fail/override, and print the check's time in `wsg_run_one.R`.
- author/created: NewGraphEnvironment, 2026-11-05
- state: premise holds. `wsg_run_one.R` starts `t0` after the check (lines 112–122). There is no per-step timing; `elapsed_s` is the whole check. The check also runs in every recompute job, so it may cost there too (not measured).
- files: `R/lnk_wsg_downstream_check.R`, `data-raw/wsg_run_one.R`, possibly `data-raw/wsg_recompute_one.R`
- shared cost: live database measurement
- links: none
- if-never: "every run of `data-raw/wsg_run_one.R` spends about 40% of its wall time in the check, whatever the group's size."
- comments: none
- closure candidate: no

#460 — A grad token for the Freshwater Atlas segment's own gradient (grad-fwa)
- asks: add a `grad-fwa` vocabulary row (`gradient=fwa_segment`) that no build writes.
- author/created: NewGraphEnvironment, 2026-11-05
- state: premise holds. `inst/extdata/vocabulary.csv` has only `grad-seg` and `grad-parent`.
- files: `inst/extdata/vocabulary.csv`, `research/output_vocabulary.md`, NEWS
- shared cost: new vocabulary token; link release (`introduced`); naming decision (knowledge waits on it)
- links: #414, #444; NewGraphEnvironment/knowledge#120
- if-never: "that setup has no token, and its archive folder and its rows in the setup tables go untokened."
- comments: none
- closure candidate: no. It replaces #420's grad bullet.

#459 — snapshot_bcfp.sh: --config KEY=VALUE fails on GDAL 3.8, and the Parquet and bcdata paths have no fallback
- asks: use the two-argument `--config` form, fall back to pyarrow when GDAL lacks the Parquet driver, and fall back to WFS when bcdata fails.
- author/created: NewGraphEnvironment, 2026-11-04
- state: premise holds. `data-raw/snapshot_bcfp.sh` uses `--config OGR_TRUNCATE=YES` (lines 213, 240, 297, 328), exits FATAL without the Parquet driver (line 107), and has no fallback for `bcdata bc2pg`.
- files: `data-raw/snapshot_bcfp.sh`
- shared cost: none (test on a GDAL 3.8 host)
- links: none
- if-never: "on such a host, preparing a run means redoing its loads by hand."
- comments: none
- closure candidate: no

#458 — A provincial run leaves the previous run's rows in <schema>.log
- asks: either clear or archive `log` per run, or state in the RUNBOOK that `log` accumulates and readers key on `run_uid`.
- author/created: NewGraphEnvironment, 2026-11-04
- state: premise partly disproved. The 242 old rows were hand-seeded for #454's gate (CLAUDE.md:28, `research/study_area_run.md:306`), and #450 describes the seeding. I found no DELETE or TRUNCATE of `log` or `log_recompute` in the driver, so the claim that a run "clears log_recompute" looks unsupported (unsure). The documentation question still stands.
- files: RUNBOOK.md (`log` section near line 1044), possibly `data-raw/study_area_run.sh`
- shared cost: operator decision
- links: NewGraphEnvironment/knowledge#145 (closed)
- if-never: none stated
- comments: none
- closure candidate: no, but one RUNBOOK sentence would close it

#456 — README: say fish habitat definitions, not rules, as the website and registry do
- asks: replace "rules" with "fish habitat definitions" in the README prose (lines 9 and 27), keeping bcfishpass's own "rules".
- author/created: NewGraphEnvironment, 2026-11-03
- state: premise holds (README.md lines 9 and 27)
- files: `README.md`
- shared cost: none
- links: NewGraphEnvironment/newgraphenvironment.github.io#70 (open)
- if-never: "the README is the one place left calling them 'rules', and the site's description and the README read like two different tools."
- comments: none
- closure candidate: no

#452 — cols_streams_near_river mirrors fresh's near_river table, which gained linear_feature_id in 0.54.0
- asks: add `linear_feature_id` to `cols_streams_near_river`, and pass `near_river_lfid` (likely TRUE) in the validator's two `frs_habitat_predicates()` calls.
- author/created: NewGraphEnvironment, 2026-11-02
- state: premise holds. `R/lnk_persist_init.R:189` has no `linear_feature_id`, and `R/lnk_habitat_validate.R:1092,1105` pass no flag. fresh 0.54.0 is not released yet (latest is v0.53.0; fresh#293 is open), and link pins fresh v0.52.0.
- files: `R/lnk_persist_init.R`, `R/lnk_pipeline_persist.R`, `R/lnk_habitat_validate.R`, `DESCRIPTION`
- shared cost: fresh pin bump (0.54.0) and link release; persist schema column change; host re-prep (the worker's pak token, from #439)
- links: NewGraphEnvironment/fresh#293 (open)
- if-never: "the persisted table keeps the shorter key, and a re-test against it cannot tell two jobs' rows apart inside one watershed group."
- comments: fresh's round-3 review: `near_river_lfid` becomes required when `near_river_table` is given, so the validator will error after the upgrade.
- closure candidate: no

#451 — The run stamps a local bcfishobs checkout's commit that no run reads, and refuses to launch when it is dirty
- asks: drop the bcfishobs checkout gate and the `BCFISHOBS_GIT_SHA` export, retire or refill `bcfishobs_sha`, move the verifier to the artifact version, and fix the `lnk_stamp()` docs and RUNBOOK §8d.
- author/created: NewGraphEnvironment, 2026-11-02
- state: premise holds. The gate is at `data-raw/study_area_run.sh:1117-1130`; `R/lnk_log.R` and `R/lnk_stamp.R:47` still stamp the checkout SHA.
- files: `data-raw/study_area_run.sh`, `data-raw/study_area_remote.sh`, `R/lnk_log.R`, `R/lnk_stamp.R`, `data-raw/study_area_verify.sql`, RUNBOOK §8d
- shared cost: operator decision (retire or refill the column); link release
- links: #264, #265, #441 (all closed); leaves `fwapg_sha` to #270
- if-never: "every row carries a `bcfishobs_sha` that describes nothing the run used, and every launch needs `BCFISHOBS_DIR` pointed at a clean clone to get past a refusal that guards that number."
- comments: none
- closure candidate: no

#450 — The pre-run gate finds its history without flags or copies
- asks: the gate takes its range from the `extends:` parent, or treats every input as changed, and reads per-group minutes from a CSV committed to the repo.
- author/created: NewGraphEnvironment, 2026-11-02
- state: premise holds. `data-raw/pretest_run.sh` still takes `--history-schema` and `--history-config`, and there is no build-minutes CSV.
- files: `data-raw/pretest_run.sh`, `data-raw/pretest_pick.R`, `data-raw/pretest.R`, `data-raw/pretest_check.R`, a new `data-raw/logs/*minutes*.csv`, RUNBOOK §8d
- shared cost: operator confirms the provisional lean; a CSV append after every provincial run
- links: #372, #442, #441 (closed), #259 (closed)
- if-never: "each new bundle needs `--history-schema`, `--history-config` and a hand-copied log, and a bundle that extends nothing gets a gate only from a hand-seeded log ... or launches on `--pretest-note`."
- comments: none
- closure candidate: no

#446 — The bcfishpass reference pin reads a CSV-sync ledger row as the loaded view
- asks: the ledger tier reads only snapshot rows that loaded the views (`--with-bcfp-views`), with a test.
- author/created: NewGraphEnvironment, 2026-11-02
- state: partly done. The parity README already names the right version (commit a2105bc0). The reader still takes the newest row of any kind (`R/lnk_log.R` ~1283). A later views-snapshot row on the worker (b05a6264) means its pin happens to be right now.
- files: `R/lnk_log.R` (`.lnk_bcfp_log_ledger()`), `tests/testthat/`, possibly the `data-raw/logs/bcfp_baselines.csv` format
- shared cost: none
- links: #440, #429, #262
- if-never: "a CSV sync run on a host relabels every later build there with a version whose views were never loaded, and a parity record quoting the pin is wrong."
- comments: none
- closure candidate: no

#444 — Parent attributes on the full network
- asks: build `<full>.streams_parent` with each full segment's minimal parent's gradient, a pair guard, and a `grad-parent` token.
- author/created: NewGraphEnvironment, 2026-11-02
- state: done. Every box and acceptance line is checked. PR #457 shipped it as release 0.79.0 (02bf6540). CLAUDE.md:14-16 records the build of all 241 groups, and knowledge reran acceptance line 1 on 2026-11-05.
- files: (done) `R/lnk_streams_parent.R`, `data-raw/streams_parent*.R`
- shared cost: none
- links: #415, #441, #414 (closed); NewGraphEnvironment/knowledge#120, #131
- if-never: "knowledge's tuning on minimal segments ... has no way to deploy on the network link ships, and the transfer cost cannot be measured."
- comments: none
- closure candidate: yes. All acceptance is met; the follow-ups are #462 and #463.

#439 — Ready the hosts for the minimal run
- asks: pin fresh 0.52.0, re-prep the cloud hosts and worker with `--auto-install`, and refresh the primitives.
- author/created: NewGraphEnvironment, 2026-11-02
- state: done in effect. Steps 1 and 3 are checked. The unchecked re-prep is overtaken: run `20261102_203300` and #454's run went across 5 hosts on fresh 0.52.0 with verifiers passing (CLAUDE.md:28,41). The one residue is the worker's refused GitHub token (CLAUDE.md:59).
- files: none left
- shared cost: operator (rotate the worker's token before the next pin bump)
- links: #441 (closed), #418
- if-never: "the verifier fails the run on hosts that disagree on fresh, or the vintage gate refuses at launch, after the spin is paid for."
- comments: none
- closure candidate: yes. The run it prepared for has happened; move the worker's token to the next pin bump (#452).

#436 — Exclude a fish record bcfishpass has not listed
- asks: pick a way to exclude link-owned records (overlay adds rows, a link-owned exclusions file, or offer them upstream), add the three keys, and test.
- author/created: NewGraphEnvironment, 2026-11-02
- state: premise holds. `.lnk_observation_exclusion_keys()` (`R/lnk_pipeline_prepare.R:364`) reads only the copy, and `R/lnk_overlay.R:62` refuses rows not in the table. The three keys appear only in the review tracker.
- files: `R/lnk_pipeline_prepare.R`, `R/lnk_overlay.R` (option 1), `inst/extdata/configs/default/config.yaml`, a new `overrides/observation_exclusions_link.csv` (option 2), tests
- shared cost: operator chooses the option; no token move expected (the issue says "should not", so unsure); takes effect at the next re-model
- links: #402, #429
- if-never: "a record link finds wrong stays counted in `default` until bcfishpass excludes it upstream."
- comments: none
- closure candidate: no

#434 — Publish the barriers each observation override lifted, with the records behind each
- asks: each build writes a table of lifted barriers with species, record ids and the rule as applied, plus a check that it reproduces `access_<sp>`.
- author/created: NewGraphEnvironment, 2026-11-01
- state: partly. `barrier_overrides` already persists lifted positions per species (`R/lnk_persist_init.R:171`), but without records or rule; nothing else is built.
- files: `R/lnk_barrier_overrides.R`, `R/lnk_persist_init.R`, `R/lnk_pipeline_persist.R`, `data-raw/study_area_verify.sql`
- shared cost: new persisted table, so a link release and a re-model (provincial) to fill it; contents move with #400
- links: #400, #236, #415
- if-never: "`access_<sp>` says a segment is accessible but not why, and a tuning that gates on it either takes records above a falls only when they caught fish or re-implements `lnk_barrier_overrides()` and drifts from it."
- comments: none
- closure candidate: no

#431 — default's presence table as bcfishpass's copy plus an overlay
- asks: make `default`'s `wsg_species_presence.csv` the synced copy, with its departures (and #402's decisions) as overlay rows with reasons.
- author/created: NewGraphEnvironment, 2026-10-31
- state: premise holds. `config.yaml` still says `source: link (hand-authored)` and there is no presence overlay in `default`. The issue's "acc-v4" is stale: `acc-v5` is current, so the next row would be `acc-v6`.
- files: `inst/extdata/configs/default/overrides/wsg_species_presence.csv`, a new `wsg_species_presence_overlay.csv`, `config.yaml`, the sync script, `inst/extdata/vocabulary.csv`
- shared cost: an acc vocabulary row if cells change; link release; operator decision on UTRE CH and QUES ST; re-model
- links: #402, #429, #106
- if-never: "`default`'s table stays a hand-edited fork of bcfishpass's. Upstream changes to it are invisible ... and link's 351 pending decisions cannot be read as a list of departures."
- comments: none
- closure candidate: no

#427 — Lift a natural barrier on fewer than 5 salmon records in default
- asks: measure and decide a lower lift threshold (or a distance or date rule) for salmon, GR and KO in `default`.
- author/created: NewGraphEnvironment, 2026-10-31
- state: premise holds. `configs/default/parameters_fresh.csv` has threshold 5 from 1990-01-01 for CH, CM, CO, PK, SK, ST, GR and KO (CLAUDE.md:155).
- files: `inst/extdata/configs/default/parameters_fresh.csv`, `inst/extdata/vocabulary.csv`, RUNBOOK §5
- shared cost: live measurement on a few groups; operator decision; acc token and version bump; provincial re-model
- links: #402
- if-never: none stated
- comments: none
- closure candidate: no

#426 — Lifts count records dated exactly 1990-01-01, which bcfishpass leaves out
- asks: decide `>=` versus `>` per bundle, count the lift changes on the parity groups, and fix RUNBOOK's "no date floor" line.
- author/created: NewGraphEnvironment, 2026-10-31
- state: premise holds. `R/lnk_barrier_overrides.R:209` uses `>=`, line 144 defaults to 1900-01-01, and RUNBOOK.md:628 still says "no date floor".
- files: `R/lnk_barrier_overrides.R` (possibly a per-bundle parameter), `inst/extdata/vocabulary.csv`, `RUNBOOK.md:628`
- shared cost: parity measurement (BULK, PARS, ADMS, BABL, ELKR); operator decision; possible acc token; re-model
- links: #402
- if-never: none stated
- comments: none
- closure candidate: no

#425 — Count steelhead and char alias codes as their species
- asks: one shared alias rule (SST/WST→ST, ADV→DV, ABT→BT, decide the two-way codes) used by the filter, the validator and the presence check, measured before and after.
- author/created: NewGraphEnvironment, 2026-10-31
- state: premise holds. Only the CT aliases are folded (`R/lnk_pipeline_break.R:240`, `R/lnk_presence_check.R:76`, `R/lnk_presence_measures.R:89,115`).
- files: `R/lnk_pipeline_break.R`, `R/lnk_pipeline_prepare.R`, `R/lnk_pipeline_access.R`, `R/lnk_habitat_validate.R`, `R/lnk_presence_check.R`, `R/lnk_presence_measures.R`
- shared cost: live measurement on FINA, UFRT, MFRA and VICT; operator decision on the two-way codes; acc token; re-model
- links: #398, #402
- if-never: none stated
- comments: none
- closure candidate: no

#423 — Habitat export: carry whether the species is recorded upstream (access code 2)
- asks: add an access-code or `observed_upstream` column per species to the export, and possibly the `acc` token in the manifest.
- author/created: NewGraphEnvironment, 2026-10-31
- state: premise holds. `R/lnk_scenario_export.R` writes no `access_<sp>` columns.
- files: `R/lnk_scenario_export.R`, `data-raw/habitat_publish.R`, the crate contract
- shared cost: crate column contract (#333); operator decision on shape; republish
- links: #333, #400, #402, #398 (all open), #403, #401 (closed)
- if-never: "that split exists only in `lnk_rollup_wsg()`'s group totals, and the export's users cannot map it."
- comments: none
- closure candidate: no

#420 — Tokens for builds older than the vocabulary, and for the Atlas-line gradient
- asks: tokens describing `default` at 0.66.0, a whole-Atlas-line `grad-` token, and a decision on a consumer's own flow read.
- author/created: NewGraphEnvironment, 2026-10-30
- state: premise holds (no token for 0.66.0's cut or access). The grad bullet is replaced by #460, which finds knowledge reads the FWA segment, not the whole line.
- files: `inst/extdata/vocabulary.csv`, `research/output_vocabulary.md`
- shared cost: new vocabulary tokens; operator decisions
- links: #414, #326, #396
- if-never: "those builds stay nameless, and every consumer that keeps runs falls back to naming them by run id."
- comments: none
- closure candidate: partly. Drop the grad bullet in favour of #460.

#418 — A rehearsal before every provincial run
- asks: a gated script (`data-raw/rehearsal_run.sh`) with a rule-based picker, checks, a `log_rehearsal` record, a launch refusal and seeded failures.
- author/created: NewGraphEnvironment, 2026-10-30
- state: partly done. A hand-run rehearsal passed (`data-raw/logs/rehearsal_418/check.sh`, 73f0220c). There is no script, picker, `log_rehearsal` or launch refusal.
- files: new `data-raw/rehearsal_run.sh`, `data-raw/study_area_run.sh` (pre-flight refusal), `data-raw/recompute_deps.R`, RUNBOOK §8d
- shared cost: a real cloud run (about 1 h, about $1); operator planning decisions
- links: #377, #372, #179, #369–#376, #274
- if-never: "the provincial run is the first test of every driver path the pre-run gate leaves out."
- comments: 2026-11-03: the minimal run launched after the hand rehearsal; the issue stays open for the gated script.
- closure candidate: no

#411 — lnk_access(): drop the scoped streams table fresh's walk now builds itself
- asks: stop creating `zz_lnk_streams_<aoi>` and pass `<schema>.streams` directly, after checking plans, times and digests.
- author/created: NewGraphEnvironment, 2026-10-29
- state: premise holds (`R/lnk_access.R:169-180`; CLAUDE.md:233,248)
- files: `R/lnk_access.R`, `R/lnk_pipeline_access.R` (`.lnk_walk_keys()`)
- shared cost: live measurement on a few groups (no output change expected)
- links: #410, #409, #394, #377
- if-never: "the recompute keeps creating, indexing and analyzing a copy of the group's segments in the persist schema that fresh then copies again."
- comments: none
- closure candidate: no

#410 — Recompute components for a default run
- asks: make the mapping-code walks and the finish compare optional for `default`, and measure the duplicate walks at model time.
- author/created: NewGraphEnvironment, 2026-10-29
- state: premise holds. `lnk_access()` always walks `barrier_sources` (`R/lnk_access.R:140`), and `run_finish_compare` always runs (`data-raw/study_area_finish.sh:521`).
- files: `R/lnk_access.R`, `data-raw/wsg_recompute_one.R`, `data-raw/study_area_finish.sh`, `R/lnk_pipeline_run.R`
- shared cost: live measurement; operator decision (does any `default` product use mapping codes?)
- links: #261, #411
- if-never: "every group runs three extra province-wide walks, and the run ends with a parity compare that a `default` run doesn't need."
- comments: none
- closure candidate: no

#402 — Check each group's species presence against its fish records
- asks: a check script plus an operator decision on each of the 351 disagreements, applied to `default`'s presence table.
- author/created: NewGraphEnvironment, 2026-10-28
- state: partly done. The script and log shipped (PR #424). Provisional decisions were applied in PR #435 (0.75.0, `acc-v4`). The tracker still has 154 pending rows (141 waiting on #432, 13 on #402), and the check has not been re-run.
- files: `inst/extdata/configs/default/wsg_species_presence_review.csv`, `overrides/wsg_species_presence.csv`, `inst/extdata/vocabulary.csv`, `data-raw/wsg_species_presence_check.R`
- shared cost: operator decisions; acc token and release; provincial re-model
- links: #436, #425, #426, #427, #431, #400, #292, #153
- if-never: "a species can be modelled in a group on the strength of one old record, or left out where the records say it is there, and nobody is told."
- comments: none
- closure candidate: no

#400 — Decide what counts as a known fish record for "observed upstream"
- asks: one written rule (date cut, pooling) for which records make code 2 and the observation breaks.
- author/created: NewGraphEnvironment, 2026-10-28
- state: premise holds. Count is decided (one record). Dates and pooling are recommended but not settled, and code 2 still matches exact codes of any date (`R/lnk_pipeline_access.R:480`).
- files: `R/lnk_pipeline_access.R`, `R/lnk_pipeline_prepare.R`, `R/lnk_pipeline_break.R`
- shared cost: operator decision; acc token; re-model
- links: #396, #398, #403, #402
- if-never: "code 2 counts every record that passes the presence and exclusion filters, by exact species code, of any date, and the known-vs-suspected summary (#403) inherits that without anyone having chosen it."
- comments: none
- closure candidate: no

#398 — Cutthroat alias records never make CT read "observed upstream"
- asks: one helper of species codes per model species, used by both the observation filter and the access walk's code-2 test.
- author/created: NewGraphEnvironment, 2026-10-28
- state: premise holds. The filter adds CCT, ACT and CT/RB (`R/lnk_pipeline_break.R:240`), but the walk tests `sp_upper %in% x` (`R/lnk_pipeline_access.R:480`).
- files: `R/lnk_pipeline_break.R`, `R/lnk_pipeline_access.R`, tests
- shared cost: acc token likely; re-model; check bcfishpass's SQL for the `bcfishpass` bundle
- links: #396, #425, #400
- if-never: "those records reach the observation tables and cut the stream, but CT still reads 'accessible, not observed' ... and any summary of known CT undercounts."
- comments: none
- closure candidate: no

#390 — The PARS vignette data cannot be rebuilt once the two configs segment differently
- asks: take the vignette's geometry from `fresh_default.streams`, join configs by measure overlap per `blue_line_key`, and remove the 1 % guard.
- author/created: NewGraphEnvironment, 2026-10-27
- state: premise holds (guard at `data-raw/wsg_vignette_data.R:84-103`)
- files: `data-raw/wsg_vignette_data.R`, the vignette data
- shared cost: live database with both schemas built
- links: #326, #226 (closed)
- if-never: "the script refuses to run after the next provincial re-model, and the vignette's figures stay at the build they were made from."
- comments: none
- closure candidate: no

#389 — default_mad: MAD in every group on wet's flows, proven on five groups
- asks: write the `configs/default_mad/` bundle (extends `default`, `mad` everywhere, wet with fill) and prove it on five groups.
- author/created: NewGraphEnvironment, 2026-10-27
- state: premise holds (no `default_mad` directory)
- files: new `inst/extdata/configs/default_mad/`, `inst/extdata/vocabulary.csv`
- shared cost: new bundle and token; 5-group build on the dispatcher (about 47 min); provincial run; blocked by #387 and #388
- links: #387, #388
- if-never: none stated
- comments: none
- closure candidate: no

#388 — Run and roll up a list of bundles in _targets.R, not two fixed ones
- asks: replace `cfg_bcfishpass` and `cfg_default` in `_targets.R` with a list of bundles.
- author/created: NewGraphEnvironment, 2026-10-27
- state: premise holds (`data-raw/_targets.R:62-84`). Unsure whether `_targets.R` is still the provincial runner: it was last touched 2026-09-25, and runs now go through `study_area_run.sh`.
- files: `data-raw/_targets.R`
- shared cost: none
- links: none
- if-never: none stated
- comments: none
- closure candidate: possibly. Confirm with the operator whether `_targets.R` is retired.

#387 — Report the stream lines whose model reads a flow the bundle's discharge source does not have
- asks: count, per group, the lines whose model reads flow but have none, log it, and print it in `lnk_preflight_discharge()`, as information only.
- author/created: NewGraphEnvironment, 2026-10-27
- state: premise holds. `lnk_preflight_discharge()` exists but checks only that the table exists and holds values.
- files: `R/lnk_preflight_discharge.R`, `R/lnk_discharge.R`, `R/lnk_log.R` (log column)
- shared cost: log schema column; link release; live check (BULK on fwapg and on wet)
- links: blocks #389
- if-never: none stated
- comments: none
- closure candidate: no

#386 — Copies of one barrier held by several groups can disagree under group-filtered controls
- asks: choose between owner-only persistence and province-wide controls by position, then add a verifier check so the owner rule is usable.
- author/created: NewGraphEnvironment, 2026-10-27
- state: premise holds. The control filter is per group in `R/lnk_pipeline_prepare.R`. `recompute_deps.R` has an `owner` rule, but the verifier has no check.
- files: `R/lnk_pipeline_prepare.R`, `R/lnk_barriers_unify.R`, `R/lnk_barriers_views.R`, `data-raw/study_area_verify.sql`, `data-raw/recompute_deps.R`
- shared cost: operator decision; outputs change, so a provincial re-model
- links: #374, #349, #361
- if-never: none stated
- comments: none
- closure candidate: no

#385 — Clear the R CMD check WARNINGs so CI gates on warnings
- asks: fix the non-ASCII characters, the missing Rd links and the undocumented `presence` arguments, then remove `error-on`.
- author/created: NewGraphEnvironment, 2026-10-26
- state: premise holds. Non-ASCII is still in all 5 files, `\item{presence}` is absent from both Rds, and `error-on` is at line 20 of `.github/workflows/R-CMD-check.yaml`.
- files: `R/lnk_access.R`, `R/lnk_barrier_overrides.R`, `R/lnk_compare_mapping_code.R`, `R/lnk_compare_rollup.R`, `R/lnk_crossings_union.R`, roxygen for `lnk_barriers_unify`, `lnk_load`, `lnk_source`, `lnk_pipeline_access`, `lnk_pipeline_mapping_code`, and the workflow
- shared cost: none
- links: #384
- if-never: "CI fails only on ERRORs, and warnings of these kinds accumulate unnoticed."
- comments: none
- closure candidate: no

#383 — lnk_points_snap() and FWA_LocateAlong callers: fwapg's tie rule and stream-head fix
- asks: sweep before and after (migration in a rolled-back transaction), adopt fwapg's tie rule or `fwa_indexpoint()`, and add gated live tests.
- author/created: NewGraphEnvironment, 2026-10-26
- state: premise holds. `R/lnk_points_snap.R:186` still orders by `linear_feature_id`, and NEWS says it is owed. fresh#266 (the fresh twin) is closed.
- files: `R/lnk_points_snap.R`, `R/lnk_pipeline_pscis_build.R`, `R/lnk_barriers_unify.R`, `data-raw/query_habitat_thresholds_obs.R`, `tests/testthat/`, `research/`
- shared cost: live database sweep; the real migration waits on NewGraphEnvironment/fwapg#41
- links: NewGraphEnvironment/fwapg#41 (open), smnorris/fwapg#201 (open), NewGraphEnvironment/fresh#266 (closed), NewGraphEnvironment/wet#127
- if-never: none stated
- comments: none
- closure candidate: no

#377 — Provincial run speed-up: one change at a time, measured
- asks: an umbrella checklist of speed changes, each measured.
- author/created: NewGraphEnvironment, 2026-10-24
- state: partly done. Every item is checked except #418. The runs table is filled through `20261103_163715`.
- files: none directly
- shared cost: provincial runs
- links: #418, #371, #375, #369, #376, #374, #326
- if-never: none stated
- comments: none
- closure candidate: no, until #418

#376 — study_area_run.sh: persistent worker hosts
- asks: a persistent worker host kind in the driver.
- author/created: NewGraphEnvironment, 2026-10-24
- state: done. PR #380 (v0.68.5) met acceptance 1 and 3. Acceptance 2 was met at `20261103_163715`: the longest leg was 9.8 % under its estimate. The worker speed was learned (`data-raw/logs/host_speeds.tsv`), and the body says "Left open for the operator".
- files: none
- shared cost: none
- links: #361, #369, #371, #347, #276, #163, #259
- if-never: none stated
- comments: none
- closure candidate: yes. All acceptance is met; the operator decides.

Pairs that edit the same files or share a cost:
- #464 + #461: `R/lnk_wsg_downstream_check.R`
- #464 + #465: the downstream-path group list (the outlets the check reads)
- #466 + #465 + #423: `R/lnk_scenario_export.R` and its manifest
- #466 + #451 + #446: `R/lnk_log.R` stamps
- #466 + #451: `data-raw/study_area_verify.sql`
- #451 + #418 + #450: `data-raw/study_area_run.sh` pre-flight
- #450 + #458: the hand-seeded `log`; RUNBOOK's `log` section
- #463 + #462: `R/lnk_streams_parent.R`, classify, and a full-network rebuild on the dispatcher
- #462 + #452: the persisted near-river distance
- #460 + #420: `inst/extdata/vocabulary.csv` grad token
- #431 + #436: `R/lnk_overlay.R` and the copy-plus-overlay mechanism
- #431 + #402: `default`'s presence table and acc token
- #398 + #425 + #400: the shared species-code and alias helper in `R/lnk_pipeline_break.R` and `R/lnk_pipeline_access.R`
- #426 + #427 + #434: `R/lnk_barrier_overrides.R` and the `default` lift parameters
- #398, #400, #402, #425, #426, #427, #431: an acc token move and a provincial `default` re-model
- #410 + #411: `R/lnk_access.R` (the recompute)
- #385 + #411 + #410: `R/lnk_access.R`
- #385 + #426 + #427: `R/lnk_barrier_overrides.R`
- #385 + #398: `lnk_pipeline_access` (code and Rd)
- #386 + #436: `R/lnk_pipeline_prepare.R`
- #386 + #383: `R/lnk_barriers_unify.R`
- #389 + #387 + #388: a chain, with #389 blocked by the other two
- #418 + #377: the next provincial run
- #452 + #439: the fresh pin bump and the worker's pak token


## Reader B: #375–#224

I checked all 39 issues against the code, CLAUDE.md, RUNBOOK, NEWS, research/, data-raw/logs and git log on origin/main (f8a45c29). The text form of `gh issue view --comments` printed nothing here, so I read bodies and comments through `--json`. Every author below is `NewGraphEnvironment`. Two findings change the picture:

- **knowledge is now public** (`gh repo view` says PUBLIC). That knocks out #295's premise.
- **A local knowledge checkout (`data/thresholds.csv` @ 91ae2f5d) already holds WCT, GR, RB and KO rows tuned on the 2026-11-03 run.** That moves #322 and #343 toward knowledge. It is unpushed-or-pushed unknown; I only read the local copy.

The four speed issues (#369, #371, #374, #375) do have their 2026-11-03 numbers recorded: in each issue body, in `research/study_area_run.md` lines 303-356, and in `data-raw/logs/study_area_run/20261103_163715_phases.tsv`.

#375 — study_area_run.sh: record each phase's start and end per host
- asks: the driver writes `<TS>_phases.tsv`, one row per phase per host, and prints the critical path.
- author/created: NewGraphEnvironment, 2026-10-24
- state: done. PR #378, v0.68.3, RUNBOOK §8d. Criterion 1 is in `data-raw/logs/phases_375/`. Criterion 2: `20261103_163715_phases.tsv` is committed and #377's runs row is filled (237.2 min). The body's 2026-11-03 Status says "Criterion 2 reads as met".
- files: none left (`data-raw/study_area_run.sh`)
- shared cost: operator decision only
- links: #377, #454 (closed)
- if-never: none stated
- comments: none
- closure candidate: yes. Both criteria are met; the issue waits only on the operator.

#374 — study_area_run.sh: recompute each group as soon as its downstream groups are consolidated
- asks: start each group's recompute once it and every group it reads have landed, instead of after the last consolidate.
- author/created: NewGraphEnvironment, 2026-10-24
- state: done except criterion 2 at scale. PR #382; `data-raw/study_area_recompute.sh` and `recompute_deps.R`. At 20261103 the recompute tail was 15.6 min against 60.6, 82 groups launched early, and the audit found 2,191/2,191 pairs in order. The per-group digest check against `--recompute-at-end` was done only on 10 groups (NEWS 0.68.x), not provincially.
- files: none left
- shared cost: the digest check would need a `--recompute-at-end` run of the same groups
- links: #369, #371, #376, #377 (open); #348, #349, #361 (closed)
- if-never: none stated
- comments: none
- closure candidate: yes, if the operator accepts the 10-group digest match.

#371 — study_area_run.sh: bound each modelling statement
- asks: `--statement-timeout` (default 30 min) through PGOPTIONS, so a runaway statement fails as a named group.
- author/created: NewGraphEnvironment, 2026-10-23
- state: done. PR #373, v0.68.2, RUNBOOK "A runaway statement fails its group". At 20261103 no group timed out; the longest was QUES at 27.0 min. The body says "Criterion 2 reads as met".
- files: none left
- shared cost: operator decision only
- links: #361, #348 (closed); #369, #377 (open)
- if-never: none stated
- comments: none
- closure candidate: yes.

#369 — study_area_run.sh: consolidate each cloud host when its own leg finishes, then burn it
- asks: consolidate and burn each cloud host as its own leg ends, with one backup taken before any leg writes.
- author/created: NewGraphEnvironment, 2026-10-23
- state: done. PR #379, v0.68.4, RUNBOOK §8d. At 20261103 each host was burned within 0.5 min of its consolidate, with 189 `ok` rows, no kept hosts and both verifiers passing. Item 3 (overlap minutes against 2026-10-23) was declared "not meaningful at this code".
- files: none left. A possible follow-on: hosts are finished one at a time, so job1 waited 10 min.
- shared cost: operator decision only
- links: #377 (open); #347, #358, #170, #361 (closed)
- if-never: none stated
- comments: none
- closure candidate: yes. Item 3 was waived in the body.

#366 — Downstream checks: review against the fwapg#34 measurement
- asks: once fwapg#36 picks the default downstream walk, compare `lnk_access` and `lnk_wsg_downstream_check` decisions under it against the ltree predicate on 1–2 groups.
- author/created: NewGraphEnvironment, 2026-10-22
- state: premise holds. Nothing in the repo cites fwapg#34 or fwapg#36.
- files: `R/lnk_access.R`, `R/lnk_pipeline_access.R`, `R/lnk_wsg_downstream_check.R`
- shared cost: a live DB measurement on 1–2 groups; a dependency decision upstream
- links: #261 (closed); NewGraphEnvironment/fwapg#34 (closed), fwapg#36 (open, the blocker), fwapg#3
- if-never: none stated
- comments: none
- closure candidate: no. It is blocked on fwapg#36.

#356 — Floating-point length sums depend on row order (threshold logs, lnk_aggregate)
- asks: sum `length_metre::numeric` in SQL, sort before reducing in R, and round values written for comparison.
- author/created: NewGraphEnvironment, 2026-10-18
- state: premise holds. `query_habitat_thresholds_obs.R:375` and `_mad.R:290` still do `sum(s.length_metre)`; `R/lnk_aggregate.R:156` still does a double SUM.
- files: `data-raw/query_habitat_thresholds_obs.R`, `data-raw/query_habitat_thresholds_mad.R`, `R/lnk_aggregate.R`, the committed CSVs under `data-raw/logs/habitat_thresholds_284|302/`, plus lower-risk `lnk_rollup_wsg.R`, `lnk_compare_*.R`
- shared cost: none (the committed CSVs change once)
- links: NewGraphEnvironment/wet#101 (closed), wet#76 (open)
- if-never: "a rerun on an unchanged database can change the last digits of committed `km` values (a diff that means nothing), and stored crossing sums vary in their last bits with the query plan."
- comments: none
- closure candidate: no. It contains #293.

#353 — config_hash is accounting: verification should record a second hash, not fail on it
- asks: verifiers report how many `config_hash` values a run carries instead of failing; decide per check whether it is a gate or accounting.
- author/created: NewGraphEnvironment, 2026-10-18
- state: premise holds, but #466 has absorbed it. `data-raw/logs/provincial_246/verify_extra.sql:39-40` still fails on more than one hash, and recent runs still call it. Open #466 says "#353's verify becomes a report".
- files: `data-raw/logs/provincial_246/verify_extra.sql`, `R/lnk_preflight_parity.R`, `data-raw/study_area_verify.sql`
- shared cost: an operator decision on which checks are gates
- links: #347 (closed), #466 (open)
- if-never: "each such change fails a one-off verify by hand, and the gate-versus-accounting question gets re-argued each time."
- comments: none
- closure candidate: yes, as superseded by #466.

#351 — lnk_access(merge = TRUE) turns an absent species' -9 into 1; lnk_mapping_code(presence = NULL) errors
- asks: the merge CASE keeps -9; `lnk_mapping_code()` builds an `lnk_presence` object when it derives presence.
- author/created: NewGraphEnvironment, 2026-10-17
- state: premise holds. The CASE at `R/lnk_access.R:236` is unchanged. `R/lnk_mapping_code.R:189-194` still builds a named vector, which `lnk_pipeline_mapping_code.R:224` reads as `presence$is_present()`.
- files: `R/lnk_access.R`, `R/lnk_mapping_code.R` (or `R/lnk_pipeline_mapping_code.R`), tests
- shared cost: none (no shipped caller is affected)
- links: #246 (closed)
- if-never: none stated
- comments: none
- closure candidate: no. It is a small, self-contained fix.

#346 — Threshold calibration read from published evidence, on the province-wide default run
- asks: `default_tuned` takes its thresholds from knowledge's published, versioned table; link retires its per-threshold ladders and reads the evidence by URL.
- author/created: NewGraphEnvironment, 2026-10-16
- state: partly done. Part 1 is done (#246; and two newer provincial `default` builds exist). Part 2 is all open. knowledge#57 is closed, and a local `knowledge/data/thresholds.csv` exists built on 20261103.
- files: `inst/extdata/configs/default_tuned/parameters_habitat_thresholds.csv`, `data-raw/habitat_variants_*.R`, `data-raw/habitat_validate.R`, `research/habitat_thresholds.md`
- shared cost: an operator decision (knowledge#139: which method sets the flow numbers); a pinned published table version; a re-model of default_tuned
- links: #322, #343 (open); #246, #295, #308, #364 (#295 open, the rest closed); knowledge#57 (closed), knowledge#139 (open, waits on this)
- if-never: "calibration keeps dropping the groups `default` was never run on, and link keeps a second calibration harness beside the evidence it reads from a local clone."
- comments: none
- closure candidate: no.

#343 — Re-tune default_tuned's GR, RB and KO MAD minima on wet's discharge
- asks: repeat #331's percentiles and ladders on wet for GR and RB; land KO as an unscored candidate.
- author/created: NewGraphEnvironment, 2026-10-16
- state: premise holds in link. `default_tuned` still has GR 0.96/0.97, RB 0.011/0.019, KO 0.57. knowledge#57's §5 says #343 transfers to knowledge, and the local `thresholds.csv` has GR rear fitted, RB `not_modelled` and KO `no_stream_rule`.
- files: `inst/extdata/configs/default_tuned/parameters_habitat_thresholds.csv`, `data-raw/query_habitat_thresholds_mad.R`, `data-raw/habitat_variants_*`, `research/habitat_thresholds.md`
- shared cost: an operator decision with knowledge#139 (tuning pick or link's size-matched rate); a variants run
- links: #331, #302 (closed); #346 (open); knowledge#139 (open, names this)
- if-never: "`default_tuned`'s GR, RB and KO minima stay fitted to fwapg's `fwa_stream_networks_discharge` while the bundle reads wet's … harmless while every group is on `cw`, and wrong for any group moved to `mad`."
- comments: none
- closure candidate: yes, as transferred to knowledge per #346 and knowledge#57 §5, once the operator confirms.

#342 — Vignette: default against default_tuned for bull trout in the Parsnip, side by side
- asks: build BT under both configs on one PARS segmentation, pick a sub-basin, write a vignette section and replace the README figure.
- author/created: NewGraphEnvironment, 2026-10-15
- state: premise holds. There is one vignette (`pars-habitat-connectivity.Rmd`) and the README still shows the grayling map. I'm unsure whether the variants-harness HEAD guard still blocks.
- files: `vignettes/pars-habitat-connectivity.Rmd` (or a new vignette), `data-raw/habitat_variants_build.R`, `data-raw/readme_figure.R`, `inst/vignette-data/`, `man/figures/readme-pars.png`
- shared cost: a PARS variants build; the BT tuned values may move under #346
- links: #338, #284, #282 (closed); #390 (open, same vignette data)
- if-never: none stated
- comments: none
- closure candidate: no.

#341 — Barrier rules as config: compare scenarios of what counts as a barrier at a crossing
- asks: one barrier predicate reading a bundle `parameters_barrier_rules.csv`; retire `lnk_thresholds()`; compare scenarios through #321's totals.
- author/created: NewGraphEnvironment, 2026-10-15
- state: premise holds. `barrier_status IN ('BARRIER','POTENTIAL')` is still at `lnk_barriers_emit.R:85,105,125` and `lnk_barriers_unify.R:200`; `inst/extdata/thresholds_default.csv` is still there; there is no rule file.
- files: `R/lnk_barriers_emit.R`, `R/lnk_barriers_unify.R`, `R/lnk_crossings_union.R`, `R/lnk_score.R`/`lnk_thresholds.R`, `inst/extdata/configs/*/parameters_barrier_rules.csv` plus a dictionary, `R/lnk_log.R`
- shared cost: a config change (new bundle file, so `config_hash` moves); a byte-identical WSG run; a recompute or re-model per scenario; operator decisions (open questions)
- links: #321 (open, step 1); #331, #11, #3 (closed)
- if-never: none stated
- comments: none
- closure candidate: no.

#335 — Webmap of published habitat: PMTiles per build
- asks: tippecanoe PMTiles per build from published rows joined to FWA lines.
- author/created: NewGraphEnvironment, 2026-10-14
- state: premise holds; nothing is built.
- files: a new `data-raw/` builder (and an `R/` export helper)
- shared cost: bucket public read and CORS (infrastructure, operator); #334 first
- links: #334 (open), #308 (closed)
- if-never: "viewing habitat needs QGIS and a database."
- comments: none
- closure candidate: no.

#334 — Gates before a floodplain item pins a habitat build: run_uid, dirty trees, versioning, public read
- asks: PUBLISH refuses builds with no run_uid or with a dirty tree; decide on thresholds_logged; bucket versioning and keep-N; public read; a per-group streams digest.
- author/created: NewGraphEnvironment, 2026-10-14
- state: premise holds. `R/lnk_scenario_export.R:253` still documents that a missing `run_uid` "is accepted". The `fresh_default` builds now carry run_uids, which helps the data but not the gate.
- files: `R/lnk_scenario_export.R`, `R/lnk_catalog.R`, `RUNBOOK.md`
- shared cost: an operator decision; a bucket versioning or public-read tofu apply (infrastructure repo)
- links: #308, #262 (closed); #466 (related, open); NewGraphEnvironment/floodplains#123 (open), "#52" (floodplains#52 is open; ambiguous which repo)
- if-never: "a consumer can record a build that has no `run_uid`, was built from a dirty tree, or has since been overwritten in place."
- comments: none
- closure candidate: no.

#333 — Register the habitat export's column contract in crate (nge/habitat/fwa/v1/segment)
- asks: copy the export YAML into crate, tag a release, and have link read the spec from crate and cite it in the manifest.
- author/created: NewGraphEnvironment, 2026-10-14
- state: premise holds. There is no `nge/habitat` in the local crate checkout; the link YAML was last changed 2026-10-19 (#349).
- files: `inst/extdata/schemas/habitat_fwa_v1_segment.yaml`, `R/lnk_scenario_export.R` (`.lnk_export_conform`), `DESCRIPTION` (crate pin), and the crate repo
- shared cost: a crate release plus a pin bump. It waits for the columns to stabilise, and open #423 proposes a new column.
- links: #308 (closed); #466 (open, a crate receipt); NewGraphEnvironment/wet#7 (closed)
- if-never: "the contract stays in link (`inst/extdata/schemas/habitat_fwa_v1_segment.yaml`), checked by link's own `.lnk_export_conform()`."
- comments: none
- closure candidate: no.

#332 — Desktop GeoPackage of the habitat export
- asks: one GPKG per WSG of export rows joined to FWA lines cut at their measures, plus a `scenarios` layer.
- author/created: NewGraphEnvironment, 2026-10-14
- state: premise holds; nothing is built.
- files: a new export writer in `R/` (next to `lnk_scenario_export.R`) or `data-raw/`
- shared cost: an operator decision with the QGIS consumer on the layer shape
- links: #308 (closed); NewGraphEnvironment/floodplains#123 (open)
- if-never: "desktop use needs fwapg and a SQL join."
- comments: none
- closure candidate: no.

#327 — default config: rear order-1 streams off larger rivers on a measured width?
- asks: measure and then decide whether `default` admits order-1 children of order ≥5 rivers on a measured width, scored against the near-river pair at `both`.
- author/created: NewGraphEnvironment, 2026-10-11
- state: premise holds. Every species in `default/dimensions.csv` has `rear_stream_order_bypass = no`. The fresh dependency (≥0.43.0) is met, since the pin is 0.52.0.
- files: `inst/extdata/configs/default/dimensions.csv` (`rear_stream_order_*`), `R/lnk_rules_build.R`, `data-raw/habitat_variants_*`, `research/habitat_thresholds.md`
- shared cost: an observation-scoring measurement; an operator decision; a provincial `default` re-model if adopted
- links: #324, #326, #364 (closed); fresh#269, fresh#234 (closed)
- if-never: "`default` keeps declining the exception by inheritance, with no recorded reason, while the `bcfishpass` config takes it."
- comments: none
- closure candidate: no.

#322 — Calibrate WCT habitat thresholds from observations, scored on held-out groups
- asks: WCT gradient, width and MAD thresholds calibrated on observations and scored on held-out groups, into `default_tuned`.
- author/created: NewGraphEnvironment, 2026-10-08
- state: premise holds in link (WCT's row is identical in `default` and `default_tuned`). knowledge#57 §5 transfers it to knowledge, and the local `thresholds.csv` has WCT rear marked `underpowered` and WCT spawn `no_response`.
- files: `inst/extdata/configs/default_tuned/parameters_habitat_thresholds.csv`, `data-raw/query_habitat_thresholds_fiss.R`, `data-raw/habitat_variants_score.R`, `research/habitat_thresholds.md`
- shared cost: the operator's decision under #346 and knowledge#139
- links: #346 (open); #284, #302, #308 (closed); knowledge#57 (closed)
- if-never: "WCT's tuned row stays a copy of `default`, its thresholds stay unscored, and every comparison involving WCT shows no difference by construction."
- comments: none
- closure candidate: yes, as transferred to knowledge (the same reasoning as #343).

#321 — Per-crossing upstream habitat per species, checked against bcfishpass, on frs_aggregate()
- asks: rebuild `lnk_aggregate()` on `fresh::frs_aggregate()` (whole upstream network, stream/lake/wetland split), add a below-upstream-barriers total, and run per-crossing parity against `crossings_upstream_habitat`.
- author/created: NewGraphEnvironment, 2026-10-08
- state: premise holds. `R/lnk_aggregate.R:160-167` still joins on the same blue_line_key with measure ≥, and nothing calls `frs_aggregate`.
- files: `R/lnk_aggregate.R`, tests, the CLAUDE.md integration snippet, a new parity script in `data-raw/`
- shared cost: live DB parity on 2 WSGs against a bcfishpass reference
- links: #341 (open); #317, #319, #324 (closed); fresh#40 (not checked)
- if-never: "a crossing's 'upstream rearing km' misses every tributary, and per-crossing tallies can't be compared with the WSG rollups."
- comments: none
- closure candidate: no.

#316 — Wetland construction lines (1200 / 1400) reach no rear rule in default
- asks: measure, then decide whether the W polygon rule admits 1200/1300/1400.
- author/created: NewGraphEnvironment, 2026-10-08
- state: measured, and the measurement shrinks the premise. 15,484 km lie in wetlands, 97% have no width, and at most 156 km would become BT rearing. The lines were left out of the #367 run (CLAUDE.md:444). `R/lnk_rules_build.R:248` is still 1000/1100/2000/2300.
- files: `R/lnk_rules_build.R`, `inst/extdata/configs/default*/rules.yaml`
- shared cost: an operator decision; a provincial `default` re-model if adopted
- links: #310, #317, #367, #320 (closed)
- if-never: "about 525 km of construction lines inside wetlands … never rear and can split rearing clusters."
- comments: the 2026-10-22 province-wide measurement on `fresh_default` (≤156 km of BT gain).
- closure candidate: yes, if the operator declines on the 156 km measurement.

#314 — lnk_points_snap(): wrap or retire in favour of the bulk fresh::frs_point_snap()
- asks: make `lnk_points_snap()` a thin wrapper of `fresh::frs_point_snap()`, or deprecate it, handling the column-name, id, hint and tie differences.
- author/created: NewGraphEnvironment, 2026-10-08
- state: premise holds. NEWS 0.69.3: "nothing in `R/` calls `fresh::frs_point_snap()`". The roxygen at `R/lnk_points_snap.R:52` still names `frs_point_snap_knn`.
- files: `R/lnk_points_snap.R`, `R/lnk_pipeline_pscis_build.R:104`, tests
- shared cost: a crossings re-snap changes model input, so a re-model of both configs
- links: #283 (closed), #383 (open, same function's tie rule); fresh#247, fresh#266 (closed)
- if-never: none stated
- comments: none
- closure candidate: no. It should be decided together with #313 and #383.

#313 — lnk_points_snap() can snap to placeholder (999.*) stream segments
- asks: replace `wscode_ltree != '999'` with `NOT wscode_ltree <@ '999'`.
- author/created: NewGraphEnvironment, 2026-10-08
- state: premise holds (`R/lnk_points_snap.R:96`, doc line 53).
- files: `R/lnk_points_snap.R`, tests
- shared cost: changes 11 PSCIS snaps, so a re-model owed for both configs
- links: #314, #383 (open); fresh#247 (closed)
- if-never: none stated
- comments: none
- closure candidate: no. It is a one-line fix, or it disappears if #314 lands.

#295 — Describe private evidence inputs generically in link's code and docs
- asks: stop naming the private evidence repo; rename `LNK_KNOWLEDGE_DIR` to `LNK_EVIDENCE_DIR`.
- author/created: NewGraphEnvironment, 2026-09-29
- state: premise disproved. NewGraphEnvironment/knowledge is now PUBLIC (`gh repo view`; #346 says 2026-11-01), and #346's checklist says "#295 is rewritten to that" (reading published tables by URL). The env var is unchanged in `habitat_validate.R` and three other scripts.
- files: `data-raw/habitat_validate.R`, `data-raw/habitat_validate_inputs.R`, `data-raw/query_habitat_thresholds_fiss.R`, `data-raw/habitat_variants_score.R`
- shared cost: none
- links: #283, #284 (closed); #346 (open); an issue in a private report repository
- if-never: "each new driver and doc repeats the name, and link keeps reading as a map of private infrastructure."
- comments: none
- closure candidate: yes. Its premise is gone, and the URL-read work lives in #346.

#293 — query_habitat_thresholds_obs.R: availability km differ run to run in the last bits
- asks: sum as numeric or round, then rerun twice and `cmp` the outputs.
- author/created: NewGraphEnvironment, 2026-09-27
- state: premise holds (`query_habitat_thresholds_obs.R:375`). It is a subset of #356, which names this exact site. CLAUDE.md:951 records it as pre-existing.
- files: `data-raw/query_habitat_thresholds_obs.R`, `data-raw/logs/habitat_thresholds_284/*.csv`
- shared cost: none
- links: #284, #277 (#284 closed; #277 not checked)
- if-never: none stated
- comments: none
- closure candidate: yes, as a duplicate of #356.

#292 — lnk_presence(): move the hard-coded presence groups into the bundle
- asks: presence-promotion groups go into a bundle file under `files:` (hashed); `bcfishpass` and `default` carry today's two groups; verify byte-identical output on ADMS and BULK.
- author/created: NewGraphEnvironment, 2026-09-27
- state: premise holds. The default is at `R/lnk_presence.R:67-70`; `lnk_pipeline_run.R:271` and `lnk_pipeline_prepare.R:655` call it with defaults. `species_groups.csv` holds SALMON and CHAR (the pooling groups). `research/species_presence.md` says promotion now only affects breaks.
- files: `R/lnk_presence.R`, `R/lnk_pipeline_run.R`, `R/lnk_pipeline_prepare.R`, `inst/extdata/configs/*/config.yaml` plus a new CSV and dictionary
- shared cost: a config change (`config_hash` moves for every bundle); 2-WSG byte-identity runs
- links: #290 (closed); #236, #189, #153, #431 (open)
- if-never: "a model input lives in code, outside `config_hash`, and a change to it is invisible to run provenance."
- comments: none
- closure candidate: no.

#288 — lnk_db_conn(): prefer standard PG* env vars to match fresh 0.36.0
- asks: `lnk_db_conn()` delegates to or mirrors `frs_db_conn()`'s order (PG* first).
- author/created: NewGraphEnvironment, 2026-09-26
- state: partly done. The roxygen (`R/lnk_db_conn.R:17-21`) now documents the reversal, but the code still reads `PG_*_SHARE` first (lines 39-48). The fresh minimum is already 0.52.0.
- files: `R/lnk_db_conn.R`, tests
- shared cost: an operator check of host env vars (risk of pointing drivers at a different DB)
- links: #222 (open, a related DB-routing mismatch); fresh#213 (closed)
- if-never: "a pipeline mixing the two helpers reads from one DB and writes to another."
- comments: none
- closure candidate: no.

#281 — Standalone wsg_run_one.R writes NULL run_uid and run_label
- asks: the standalone path mints a run_uid or requires `LNK_RUN_LABEL`, decided together with #278.
- author/created: NewGraphEnvironment, 2026-09-26
- state: premise holds. `wsg_run_one.R` has no run_uid or label handling; `R/lnk_pipeline_run.R:143-145` defaults to the env vars or NULL.
- files: `data-raw/wsg_run_one.R`, `data-raw/wsg_recompute_one.R`
- shared cost: none
- links: #278 (open); #262 (closed); NewGraphEnvironment/floodplains#90
- if-never: "`run_uid` and `run_label` mean 'this row came from `study_area_run.sh`' … and the fraction of NULLs grows every time someone models one WSG."
- comments: none
- closure candidate: no.

#279 — research/: add a README index; revise topic files instead of adding dated run records
- asks: `research/README.md` index with a naming cutover line, no renames, a topic-file parity record, and CLAUDE.md linking the README once.
- author/created: NewGraphEnvironment, 2026-09-06
- state: mostly done. `research/README.md` was added in 4916b3f0 (#284) with the cutover line (dated 2026-09-26). Item 3 moved to #362 (closed; `bcfishpass_parity.md` exists). Item 4 is not done: CLAUDE.md never links `research/README.md`, and the root README doesn't mention `research/`.
- files: `CLAUDE.md`, `README.md`
- shared cost: none
- links: #362 (closed); an issue in the skills repository (closed)
- if-never: "the largest `research/` in the fleet stays discoverable only through eight path citations in `CLAUDE.md`…"
- comments: none
- closure candidate: yes, after a one-line CLAUDE.md link.

#278 — Drivers default config to bcfishpass: make --config required and print the resolved decision set
- asks: all drivers refuse to run without an explicit config; preflight prints the resolved decisions, including the closure.
- author/created: NewGraphEnvironment, 2026-09-03
- state: premise holds. `study_area_run.sh:216`, `wsgs_dispatch.sh:51`, `runs_archive.sh:25`, `wsgs_run_m4_offline.sh:43`, `wsg_run_one.R:35`, `wsg_recompute_one.R:24` and others still default to `"bcfishpass"`. Only a missing `--schema` is refused for non-bcfishpass configs (line 460).
- files: about 15 drivers in `data-raw/` (`study_area_run.sh`, `wsgs_dispatch.sh`, `wsg_run_one.R`, `wsg_recompute_one.R`, `barriers_views_build.R`, `host_stamp.R`, `study_area_*.R`, `wsgs_run_host.R`, `cypher_prep.sh`, …)
- shared cost: none (it may break operator muscle memory and RUNBOOK commands)
- links: #276, #281 (open); an issue in the skills repository (closed); floodplains#75
- if-never: none stated as a line
- comments: none
- closure candidate: no.

#276 — Snapshot skip-guard is keyed on a code SHA and scoped per host
- asks: the guard also compares `date_completed`/ETag; the dispatcher and cyphers reach the same freshness decision; `preflight_hosts()` compares `source_artifact` across hosts before any write.
- author/created: NewGraphEnvironment, 2026-09-03
- state: partly done. #265 records `provenance.source_artifact` and `log_input.artifact_*`, so mixed inputs are detectable after the run. `lnk_baseline_current()` still compares only `model_version`. `preflight_hosts()` checks vintage only, with no cross-host artifact comparison. CLAUDE.md:58 keeps a manual "HEAD the two bchamp objects" step.
- files: `R/lnk_baseline_current.R`, `data-raw/snapshot_bcfp.sh`, `data-raw/study_area_run.sh` (`preflight_hosts`), possibly `R/lnk_artifact.R`
- shared cost: live negative tests against hosts
- links: #266, #273 (open); #247, #265 (closed); two R&D tracking issues in a private repository
- if-never: none stated
- comments: none
- closure candidate: no.

#275 — Two study-area scope docs, one declared canonical, and study_area_run.md points at the other
- asks: keep the canonical doc, reduce the other to a pointer, fix `study_area_run.md`'s two references.
- author/created: NewGraphEnvironment, 2026-09-03
- state: partly addressed. `study_area_scope_and_funders.md` now says `study_areas.md` "is GENERATED by `study_area_buckets.R --write`" and is not to be confused with it. But the generated `study_areas.md` still carries a "Scope, and who funds what" section, and `study_area_run.md:16` and `:34` still point at it for definitions.
- files: `research/study_area_run.md`, `data-raw/study_area_buckets.R` (the generator's scope text), `research/README.md`
- shared cost: none
- links: #274 (closed)
- if-never: "Two documents describe the same thing and both read as authoritative. They will diverge … Someone reads the wrong one and runs the wrong scope."
- comments: none
- closure candidate: no. It is small.

#273 — Vintage gate asks how old our copy is, not whether the source changed
- asks: `lnk_preflight_vintage()` compares the recorded loader ETag with a live HEAD, falls back to age per table, and reports a failed HEAD as unknown.
- author/created: NewGraphEnvironment, 2026-09-01
- state: partly done. The gate now judges on the load stamp in `provenance.source_artifact` (#265/#247), not `last_analyze` statistics, which fixes the "inference" half. There is still no ETag change detection, and FWA has only `probe` rows (not a baseline) until #270.
- files: `R/lnk_preflight_vintage.R`, `R/lnk_artifact.R`, `data-raw/host_vintage.R`
- shared cost: live bucket tests (no mocks); depends on #270's loader rows
- links: #270 (open); #265, #247, #246 (closed)
- if-never: "Both errors keep happening, silently, and one of them is the unsafe direction."
- comments: none
- closure candidate: no.

#270 — Capture fwapg load.sh's stderr as the primitive provenance record
- asks: a wrapper that tees `load.sh`'s `set -x` trace, extracts the URLs, HEADs each and writes `loader` rows into `provenance.source_artifact`.
- author/created: NewGraphEnvironment, 2026-09-01
- state: partly done. The destination table exists (#330, `lnk_artifact_record(recorded_by="loader")`) in a `provenance` schema that `state_clean.sh` doesn't drop (RUNBOOK §6b). There is no wrapper (`data-raw/*fwapg*` doesn't exist), and FWA rows are still `probe`.
- files: a new `data-raw/fwapg_load_capture.sh`, `R/lnk_artifact.R`, RUNBOOK §6b
- shared cost: an FWA reload on a host to take effect
- links: #273 (open); #265, #247, #246, #330 (closed)
- if-never: "Each reload silently destroys the chance to identify that generation of inputs."
- comments: 2026-10-13: the table now exists; the fwapg loader commit needs its own column; the `state_clean.sh` drop risk (since resolved by the `provenance` schema).
- closure candidate: no.

#269 — update_hosts.sh installs fresh from main while DESCRIPTION pins a tag
- asks: install the ref in DESCRIPTION's `Remotes:`, detect the local host, and use pak where it works; the 2026-11-01 addition asks for a choice between tag pins and an `Imports:` floor.
- author/created: NewGraphEnvironment, 2026-09-01
- state: premise holds. `scripts/update_hosts.sh:4,62` still resolves `commits/main`. NEWS 0.69.3 cites #269 only for pinning fresh v0.44.0. CLAUDE.md:59 says the worker's pak token is refused.
- files: `scripts/update_hosts.sh`, `DESCRIPTION` (`Remotes:`), `data-raw/study_area_run.sh` preflight messages (1140-1182)
- shared cost: an operator decision (pin or floor); host installs
- links: #264 (closed); r-lib/pak#658
- if-never: "Every use of the script is a coin flip on whether `fresh` main happens to sit at the pinned tag."
- comments: none
- closure candidate: no.

#268 — study_area_verify.sql cannot verify any run logged before v0.50.0
- asks: `-v legacy_provenance_ok=<reason>` to downgrade the `fresh_sha`/`bcfishobs_sha` NULL checks, negative-tested; or close if there is no reason to re-verify history.
- author/created: NewGraphEnvironment, 2026-09-01
- state: premise holds. There is no `legacy_provenance_ok`, and the `fresh_sha IS NULL` FAIL is at line 225. The issue's own open question now leans to close: provincial `default` runs at 0.68, 0.78.1 and 0.78.2 have replaced the 2026-08-31 run.
- files: `data-raw/study_area_verify.sql`, `data-raw/study_area_verify_negative.sh`
- shared cost: none
- links: #262, #264 (closed)
- if-never: "the verifier stops being a tool you can point at history: any pre-v0.50.0 run fails on `fresh_sha IS NULL`…"
- comments: none
- closure candidate: yes. Its own "if the honest answer is no, close this" applies.

#266 — link and flooded select the bcfp reference build by different rules against the same table
- asks: one selection rule (`model_type='LINEAR'` plus a stated sort key) carrying a run identity such as `date_completed`, documented in RUNBOOK.
- author/created: NewGraphEnvironment, 2026-09-01
- state: premise holds. `R/lnk_log.R:1247-1248` still runs `ORDER BY model_run_id DESC LIMIT 1` with no model_type filter. Open #446 is a sibling bug in the ledger tier of the same function family.
- files: `R/lnk_log.R` (`.lnk_bcfp_log_current`, `.lnk_bcfp_log_ledger`), `RUNBOOK.md`, flooded's `data-raw/wsg_vignette_data.R`
- shared cost: tunnel or live DB access to test tier 1
- links: #276, #446 (open); #262 (closed)
- if-never: "The divergence stays dormant until someone runs link against the tunnel, then produces two provenance records that disagree with no error."
- comments: none
- closure candidate: no. It could merge with #446.

#236 — Research: DV as BT access evidence — regional scope plus multi-rule observation overrides
- asks: a DV/BT co-occurrence analysis and access delta, rationale per override rule, multi-rule and WSG-scoped overrides, and a `parameters_fresh` dictionary.
- author/created: NewGraphEnvironment, 2026-08-05
- state: partly done. Deliverable 4 is done (`inst/extdata/configs/dictionary_parameters_fresh.csv`, bf7ac0e8, #233). Region-scoped pooling for evidence shipped as #290 (`species_pooling.csv`). `default` BT is still `BT;DV`, threshold 1, one rule per species.
- files: `R/lnk_barrier_overrides.R`, `inst/extdata/configs/*/parameters_fresh.csv`, `research/`
- shared cost: a config change; a re-model of `default`; operator and WLRS judgement
- links: #189, #201, #20, #75, #292, #427 (open); #290, #90 (closed)
- if-never: none stated
- comments: none
- closure candidate: no.

#232 — Confirm link-built crossings match bcfp's complete crossings table (parity)
- asks: a repeatable comparison of `<schema>.crossings` against `bcfishpass.crossings_vw` (coverage, per-branch counts, barrier_status, positions).
- author/created: NewGraphEnvironment, 2026-07-11
- state: premise holds. No such script exists; only the CLAUDE.md:1138 status from July.
- files: a new `data-raw/` parity script, `research/bcfishpass_parity.md`
- shared cost: live DB access to the bcfishpass crossings reference
- links: #231 (closed); db_newgraph#16
- if-never: none stated
- comments: none
- closure candidate: no. It could be folded into #321's per-crossing parity.

#224 — Understand bcfp dam_dnstr_ind propagation: 33% of PARS flagged dam-free
- asks: read bcfishpass's dam-downstream SQL to explain the reservoir-inflow under-flag, and raise it upstream if confirmed.
- author/created: NewGraphEnvironment, 2026-07-03
- state: premise holds. There is no work since July, and link reproduces bcfp, so it is not a link defect.
- files: none in link (a `research/` note at most)
- shared cost: reading upstream code; possibly raising it with smnorris/bcfishpass
- links: #223 (closed)
- if-never: none stated
- comments: none
- closure candidate: no, though it could be parked as an upstream question since no link change is proposed.

**Pairs that edit the same files or share a cost**
- #369 + #371 + #374 + #375: `data-raw/study_area_run.sh` and RUNBOOK §8d; the same operator close on run `20261103_163715` (#376 outside the list too).
- #278 + #281: `data-raw/wsg_run_one.R` argument handling (#281 asks to decide them together).
- #313 + #314: `R/lnk_points_snap.R`; a crossings re-snap means a re-model (also open #383).
- #293 + #356: `data-raw/query_habitat_thresholds_obs.R` sum order.
- #356 + #321: `R/lnk_aggregate.R`.
- #321 + #341: per-crossing totals and `R/lnk_barriers_emit.R`.
- #321 + #232: live per-crossing parity against bcfishpass.
- #322 + #343 + #346: `configs/default_tuned/parameters_habitat_thresholds.csv`; the knowledge#139 decision.
- #295 + #346: `data-raw/habitat_validate.R` (`LNK_KNOWLEDGE_DIR`, read by URL).
- #327 + #316: `default` rearing rules (`R/lnk_rules_build.R`, `default/dimensions.csv`); each needs a provincial `default` re-model if adopted.
- #342 + #322/#343: `data-raw/habitat_variants_build.R` on `default_tuned` (#342 also shares vignette data with open #390).
- #332 + #333 + #334 + #335: the habitat export (`R/lnk_scenario_export.R`, schema YAML); #335 needs #334's public read, and that bucket-policy decision is shared.
- #270 + #273 + #276: `provenance.source_artifact` / `R/lnk_artifact.R`; #273 needs #270's loader rows.
- #266 + #276: bcfp build identity (`model_version` is insufficient); `R/lnk_log.R` and `R/lnk_baseline_current.R` (also open #446).
- #268 + #353: verifier escape-versus-report semantics in `data-raw/study_area_verify.sql` / `verify_extra.sql` (#353 is now inside #466).
- #269 + #288: `DESCRIPTION` fresh pin/floor and host DB environment.
- #292 + #236: presence and observation species groups moving into bundle CSVs; both change `config_hash`.
- #275 + #279: `research/README.md` and `research/study_area_run.md`.
- #351 + #366: `R/lnk_access.R`.

**Closure candidates:** #369, #371, #374, #375 (operator), #353 (into #466), #343 and #322 (to knowledge, after the operator confirms), #295 (premise gone), #293 (duplicate of #356), #279 (after a one-line link), #268 (its own close clause), #316 (if declined on the 156 km).

**Unsure:**
- whether the knowledge `thresholds.csv` I read is pushed;
- whether the #342 harness guard still blocks;
- the repo of #334's bare "#52";
- the states of fresh#40, #277 and db_newgraph#16, which I didn't check.


## Reader C: #222–#2

I checked all 39 issues against the tree at `origin/main` (f8a45c29, link 0.79.0). 15 look closable, 4 of them pending your call. None of the 39 bodies or comments has an "If we never do" line.

#222 — test-lnk_wsg_resolve live tests route to wrong DB (skip-gate vs lnk_db_conn mismatch)
- asks: Pass the connection from `skip_if_no_db()` into `lnk_wsg_resolve()` in the live tests.
- author/created: NewGraphEnvironment, 2026-07-02
- state: partly done. The error no longer happens: fresh#214 removed `public.wsg_outlet`, and the CLAUDE.md "2026-08-06" Status says "the closure-mode tests pass again and the suite is clean". The mismatch is still there: the three live tests (`tests/testthat/test-lnk_wsg_resolve.R` lines 144, 154, 163) still call without `conn`.
- files: tests/testthat/test-lnk_wsg_resolve.R
- shared cost: none
- links: #221 (closed). fresh#214 CLOSED.
- if-never: none stated
- comments: none
- closure candidate: yes. The failure is gone. Either make the three-line `conn =` fix first, or close it.

#213 — lnk_compare_mapping_code: reference = "link" for link-vs-link comparisons (Comparison B)
- asks: Add `reference = "link"` so the compare can diff two link persist schemas.
- author/created: NewGraphEnvironment, 2026-05-28
- state: premise holds. `R/lnk_compare_mapping_code.R:90` still allows only `supported_references <- c("bcfishpass")`. No `wsg_compare_link_vs_link` exists.
- files: R/lnk_compare_mapping_code.R, data-raw/wsg_compare.R, data-raw/study_area_compare.R, data-raw/study_area_run.sh, tests/testthat/test-lnk_compare_mapping_code.R
- shared cost: live DB measurement; its full test needs a re-run of the 50 study-area groups after #212
- links: #212 (open)
- if-never: none stated
- comments: none
- closure candidate: no

#212 — link-authored bcfp-style rules for KO, RB, GR in bcfishpass config
- asks: Add KO, RB and GR rows to the bcfishpass bundle (marked as link's own guesses) so it models the same species as `default`.
- author/created: NewGraphEnvironment, 2026-05-28
- state: partly superseded. `bcfishpass/dimensions.csv` still has 8 species. But `default` no longer models 11: #432 paused KO and RB (`default/species_modelled.csv`), so matching it now needs only GR.
- files: inst/extdata/configs/bcfishpass/{dimensions.csv, parameters_fresh.csv, rules.yaml} (via data-raw/build_rules.R)
- shared cost: config change, plus a bcfishpass re-run of the 50 study-area groups; operator decision on the species set
- links: #207, #208 (both closed)
- if-never: none stated
- comments: none
- closure candidate: no. It needs rescoping to GR only, or a decision to drop it.

#204 — Persist+consolidate must be host-/species-count-agnostic
- asks: Have `lnk_persist_init()` detect when the species columns on the wide tables don't match, and drop and rebuild them under `force_recreate`.
- author/created: NewGraphEnvironment, 2026-05-25
- state: partly done.
  - Done: consolidate copies by column name (`schema_consolidate.R` ~426), `cypher_prep.sh` uses `cfg$species`, and paused species always get columns (#432). NEWS 0.40.5 records the first two.
  - Not done: `.lnk_validate_persist_table` (R/lnk_persist_init.R:218) still checks only GENERATED columns.
- files: R/lnk_persist_init.R, tests/testthat/test-lnk_persist_init.R
- shared cost: none
- links: #196, #197, #169, #177 (open). #185, #187, #194, #175, #432 (closed).
- if-never: none stated
- comments: none. The body has an in-place "Since #432" update.
- closure candidate: no

#203 — Make id_segment globally unique (position-derived, bcfp-style)
- asks: Derive `id_segment` from `blue_line_key` + `downstream_route_measure` so it is unique across groups.
- author/created: NewGraphEnvironment, 2026-05-24
- state: premise holds. `id_segment` is still a row number per group (`lnk_pipeline_prepare.R:878-888`, `lnk_pipeline_break.R:299-315`). CLAUDE.md and RUNBOOK keep the rule "join on the full key".
- files: R/lnk_pipeline_prepare.R, R/lnk_pipeline_break.R, R/lnk_persist_init.R, R/lnk_pipeline_persist.R, every join site (rollup, habitat_validate, habitat_gate, scenario_export, compare_*)
- shared cost: re-model of every persist schema province-wide; the habitat export key; operator decision
- links: #175 (closed)
- if-never: none stated
- comments: none
- closure candidate: no

#201 — Rethink blocks_species: carry barrier ingredients, classify access late; dam-override
- asks: Replace the precomputed `blocks_species` with barrier attributes, work out access later per species, and let evidence override dams.
- author/created: NewGraphEnvironment, 2026-05-23
- state: premise holds. `blocks_species` is still used in 6 R files. #200 (its prerequisite) is closed. RUNBOOK says dam blocking is "not rules-driven at all (universal)".
- files: R/lnk_barriers_unify.R, R/lnk_barriers_views.R, R/lnk_pipeline_access.R, R/lnk_barrier_overrides.R, R/lnk_persist_init.R
- shared cost: new `acc-` vocabulary token, provincial re-model, operator decision (deliberate departure from bcfp)
- links: #200 CLOSED
- if-never: none stated
- comments: none
- closure candidate: no

#197 — mapping_code rules engine: config-driven token classification
- asks: Move the hard-coded second-token chains into a CSV of rules plus a `.lnk_rules_eval` helper.
- author/created: NewGraphEnvironment, 2026-05-19
- state: premise holds. The chains are still hard-coded (`R/lnk_pipeline_mapping_code.R:197-210`). No `parameters_mapping_code_rules.csv` or `rules_eval` exists.
- files: R/lnk_pipeline_mapping_code.R, R/lnk_mapping_code.R, R/lnk_persist_init.R (source flags), inst/extdata/configs/*/, R/lnk_load_overrides.R, new tests
- shared cost: config/bundle file addition; a parity run to show the output is unchanged
- links: #189 (open)
- if-never: none stated
- comments: none
- closure candidate: no

#196 — lnk_persist_init: persist per-source dnstr flag columns in streams_access
- asks: Add the 6 per-source flag columns to the persisted `streams_access` table.
- author/created: NewGraphEnvironment, 2026-05-19
- state: done. `.lnk_cols_streams_access_source_flags()` is at R/lnk_persist_init.R:78. NEWS 0.40.3 and commit 46b2042b ("v0.40.3: persist per-source flags in streams_access (#196)").
- files: none
- shared cost: none
- links: #187, #194 (closed). #191 (open).
- if-never: none stated
- comments: none
- closure candidate: yes. Shipped in v0.40.3.

#191 — Add unit tests for v0.40.0 surface
- asks: Add mocked tests for `lnk_mapping_code`, the new persist_init tables, the persist write blocks, the `pipeline_run` mapping_code phase and the deprecation shims.
- author/created: NewGraphEnvironment, 2026-05-19
- state: partly done.
  - Done: test-lnk_persist_init.R covers `streams_access`, `streams_mapping_code` and `habitat_long_vw`, and test-lnk_pipeline_run.R covers `mapping_code = TRUE`.
  - Not done: there is no test file for `lnk_mapping_code` or `lnk_pipeline_mapping_code`, and no test mentions `resident_species` (the deprecation shims are untested).
- files: tests/testthat/test-lnk_mapping_code.R (new), test-lnk_pipeline_mapping_code.R (new), test-lnk_pipeline_persist.R
- shared cost: none
- links: #187 (closed)
- if-never: none stated
- comments: none
- closure candidate: no

#189 — Data-drive species residence from dimensions.csv
- asks: Add residence and spawn-only columns to `dimensions.csv` and derive the species lists from them.
- author/created: NewGraphEnvironment, 2026-05-19
- state: premise holds. Defaults are still hard-coded (`lnk_pipeline_mapping_code.R:98-100`, `lnk_mapping_code.R:102-104`). The roxygen at `lnk_mapping_code.R:222` says GR, KO and RB are "coded as residents until link#189". No `residence` column exists.
- files: R/lnk_pipeline_mapping_code.R, R/lnk_mapping_code.R, inst/extdata/configs/*/dimensions.csv, configs/dictionary_dimensions.csv, R/lnk_rules_build.R
- shared cost: config change; mapping_code re-model for GR (and KO/RB once unpaused)
- links: #187 (closed)
- if-never: none stated
- comments: none
- closure candidate: no

#185 — schema_consolidate: enumerate wgc_tables per-source, not from destination
- asks: Copy only the tables each source host has, and skip a failed table instead of stopping.
- author/created: NewGraphEnvironment, 2026-05-15
- state: done. NEWS 0.39.0 says "Closes #180 and #185". Commit e6927def. The intersection logic is at `schema_consolidate.R` ~426-436 ("link#185").
- files: none
- shared cost: none
- links: #180 (closed)
- if-never: none stated
- comments: none
- closure candidate: yes. Shipped in v0.39.0 but never closed.

#183 — Pre-flight: sibling-host parity hook with auto-install
- asks: Check that every host runs the same link and fresh version and commit, with an auto-install option.
- author/created: NewGraphEnvironment, 2026-05-15
- state: done (absorbed). Commit fb8e6428 "(#246, absorbs #183)". NEWS 0.47.0 shows `lnk_preflight_parity()` / `lnk_preflight_stamp()` and the `--auto-install` flag. R/lnk_preflight_parity.R:6 calls itself "the #183 sibling-host parity hook". #246 is closed.
- files: none
- shared cost: none
- links: #246 CLOSED
- if-never: none stated
- comments: none
- closure candidate: yes, absorbed into #246.

#181 — Add surgical table-level drops to state_clean.sh (--tables=)
- asks: Add `--tables=schema.table,...` to `state_clean.sh`.
- author/created: NewGraphEnvironment, 2026-05-15
- state: premise holds. `data-raw/state_clean.sh` parses only its two host-skip flags and `--schemas=`.
- files: data-raw/state_clean.sh
- shared cost: none
- links: #172 (closed)
- if-never: none stated
- comments: none
- closure candidate: no. Unsure whether the script is still used much since `study_area_run.sh` took over; RUNBOOK still mentions it.

#179 — LPT-fallback puts all WSGs on one host when N_WSGs <= N_hosts
- asks: Use round-robin in the no-timing fallback when there are fewer groups than hosts.
- author/created: NewGraphEnvironment, 2026-05-15
- state: premise holds, but only on the legacy path. `data-raw/wsgs_dispatch.sh:345-360` still does floor+remainder with `order(-weights)`. RUNBOOK §8 calls this "the legacy `wsgs_dispatch.sh` path". The current runner packs hosts on measured minutes (`study_area_packing.R`, #259).
- files: data-raw/wsgs_dispatch.sh
- shared cost: none
- links: #172 (closed)
- if-never: none stated
- comments: none
- closure candidate: yes if the `wsgs_*` path is retired (operator decision); otherwise no.

#177 — Reshape persist family: lnk_persist_{init, write}
- asks: Rename `lnk_pipeline_persist` to `lnk_persist_write`, keeping a deprecation shim.
- author/created: NewGraphEnvironment, 2026-05-15
- state: premise holds. NAMESPACE still exports `lnk_pipeline_persist`, called at `lnk_pipeline_run.R:283` and `:354`.
- files: R/lnk_pipeline_persist.R, R/lnk_pipeline_run.R, roxygen in lnk_barriers_unify.R / lnk_barriers_views.R / lnk_pipeline_prepare.R, tests/testthat/test-lnk_pipeline_persist.R, NAMESPACE, CLAUDE.md
- shared cost: link release (deprecation)
- links: #168 (closed)
- if-never: none stated
- comments: none
- closure candidate: no

#176 — Rename lnk_compare_wsg() -> lnk_compare_run()
- asks: Rename the compare umbrella so its name matches `lnk_pipeline_run`, with a shim.
- author/created: NewGraphEnvironment, 2026-05-15
- state: premise holds. `export(lnk_compare_wsg)` is still in NAMESPACE. It is now used mainly by the legacy `wsgs_run_host.R` path (RUNBOOK), so the rename buys less than it did.
- files: R/lnk_compare_wsg.R, data-raw/wsgs_run_host.R, data-raw/wsg_compare.R, tests/testthat/test-lnk_compare_wsg.R, @seealso in lnk_compare_rollup.R / lnk_compare_mapping_code.R / lnk_pipeline_run.R
- shared cost: link release (deprecation)
- links: #168, #162, #172 (closed)
- if-never: none stated
- comments: none
- closure candidate: no (operator call on whether it is still worth doing)

#169 — Simplify lnk_persist_init after clean cloud-host snapshot lands
- asks: Remove `force_recreate` and the drift detection once the infrastructure repository's clean snapshot ships.
- author/created: NewGraphEnvironment, 2026-05-14
- state: premise holds and is still blocked: the infrastructure repository's snapshot issue is open, and `force_recreate` / `.lnk_validate_persist_table` are still in place. Note: #204 wants to extend that same guard, so the two pull in opposite directions.
- files: R/lnk_persist_init.R, tests/testthat/test-lnk_persist_init.R
- shared cost: a snapshot rebuild in the infrastructure repository
- links: an open snapshot issue in the infrastructure repository. #162 (closed).
- if-never: none stated
- comments: none
- closure candidate: no (operator should reconcile it with #204)

#167 — bcfp tunnel drops during long provincial runs cause silent per-WSG errors
- asks: Keep the tunnel alive with autossh, or detect a dropped tunnel.
- author/created: NewGraphEnvironment, 2026-05-14
- state: superseded by #175 (closed). The body's own 2026-05-24 update says "close this when the compare is tunnel-free". `lnk_compare_mapping_code` now defaults to the local `fresh.streams_vw_bcfp`. `run_provincial_parity.R` and `trifecta_provincial.sh` no longer exist.
- files: none
- shared cost: none
- links: #175, #168 (closed)
- if-never: none stated
- comments: none. The body has the in-place update.
- closure candidate: yes. The condition the issue set for closing is met.

#166 — data-raw: rename scripts to noun-first convention
- asks: Rename the data-raw scripts noun-first and fix the README convention section.
- author/created: NewGraphEnvironment, 2026-05-13
- state: partly done.
  - Done: #172 (commit 0cd48d09) renamed 8 scripts. `schema_consolidate.R`, `wsg_compare.R`, `buckets_balance.R` and `runs_archive.sh` exist, and `run_provincial_parity.R` / `compare_bcfishpass_wsg.R` are gone.
  - Remaining: `snapshot_bcfp.sh`, `trifecta_smoke.sh` and `trifecta_15wsg.sh` keep their old names, and `data-raw/README.md:6` and `:254` still state a verb-first convention.
- files: data-raw/README.md, data-raw/snapshot_bcfp.sh, data-raw/trifecta_*.sh, RUNBOOK.md
- shared cost: none
- links: #162 (closed)
- if-never: none stated
- comments: none
- closure candidate: no (rescope to what remains)

#159 — compare_bcfishpass_wsg / compare_bcfp_mapping_code: tryCatch finally cleanup
- asks: Drop the working schema even when a group errors.
- author/created: NewGraphEnvironment, 2026-05-12
- state: partly superseded. Both named functions are gone. The same gap now sits in `R/lnk_pipeline_run.R:381-383`, which drops the schema only at the end of a successful run. `wsg_run_one.R:139` passes `cleanup_working = FALSE`. Cloud hosts are now destroyed after each run (#369), which reduces the risk.
- files: R/lnk_pipeline_run.R (on.exit), tests/testthat/test-lnk_pipeline_run.R
- shared cost: none
- links: #119, #157 (closed)
- if-never: none stated
- comments: none
- closure candidate: no (retarget to `lnk_pipeline_run`)

#153 — lnk_pipeline_species vs lnk_presence: align presence definitions
- asks: Treat missing `spawning_`/`rearing_` columns as 0 rather than NA, and keep all 8 species columns in the persisted wide tables.
- author/created: NewGraphEnvironment, 2026-05-10
- state: partly superseded (unsure). The NA fallback is still there (`lnk_pipeline_mapping_code.R:238-247`). But mapping_code is now built only for active species, with absent ones reading `""` (`lnk_mapping_code.R` ~238-240). The compare only scores species active on the link side. The driver workaround file `compare_bcfp_mapping_code.R` is gone.
- files: R/lnk_pipeline_mapping_code.R, R/lnk_mapping_code.R, roxygen on lnk_pipeline_species.R / lnk_presence.R
- shared cost: mapping_code re-model if changed
- links: none
- if-never: none stated
- comments: none
- closure candidate: unsure (operator should confirm `""` for absent species is the intended design)

#133 — Thread non-FWA column names through link pipeline once fresh#44 ships
- asks: Have link read stream column names from `getOption("fresh.*")` once fresh supports it.
- author/created: NewGraphEnvironment, 2026-05-05
- state: premise holds and is blocked. fresh#44 is open and link has no column-option helper.
- files: R/lnk_pipeline_*.R, R/lnk_persist_init.R, R/lnk_match.R, R/lnk_override.R, data-raw/build_species_views.R (not checked; not in the `ls data-raw` listing above)
- shared cost: fresh release + pin
- links: fresh#44 OPEN, fresh#41 OPEN
- if-never: none stated
- comments: none
- closure candidate: no

#132 — Thread known_habitat through lnk_pipeline_classify once fresh#189 ships
- asks: Pass `user_habitat_classification` to fresh's classifier as `known_habitat`.
- author/created: NewGraphEnvironment, 2026-05-05
- state: premise holds and is blocked. fresh#189 is open, and `lnk_pipeline_classify.R` has no `known_habitat`.
- files: R/lnk_pipeline_classify.R
- shared cost: fresh release + pin, provincial re-model
- links: fresh#189 OPEN. fresh#186 and fresh#187 CLOSED.
- if-never: none stated
- comments: none
- closure candidate: no

#131 — Province-wide parallel habitat pipeline (crew.aws.batch + RDS)
- asks: Run the provincial pipeline on AWS Batch workers against an RDS database.
- author/created: NewGraphEnvironment, 2026-05-05
- state: superseded in practice. Nothing uses crew or Batch. Provincial runs now go through DigitalOcean cloud hosts plus persistent workers (`study_area_run.sh`, #369/#376); the 241-group `default` build took 237 min (CLAUDE.md Status 2026-11-03).
- files: none today
- shared cost: infrastructure work (no issue filed), operator decision
- links: fresh#76 CLOSED. The infrastructure issue was never filed.
- if-never: none stated
- comments: none
- closure candidate: yes, as an operator decision (approach overtaken).

#130 — SK upstream-spawning over-credits multi-lake drainages
- asks: Explain BULK SK's +2.68 km over-credit on blue_line_key 360846413. The issue itself parks it until more groups are checked.
- author/created: NewGraphEnvironment, 2026-05-05
- state: premise holds and is parked. CLAUDE.md (#221 Status) says "habitat holds (parked BULK SK = fresh#190)". No wider check of other groups found.
- files: none until diagnosed (likely fresh-side)
- shared cost: live DB measurement
- links: fresh#190, fresh#186, fresh#187, fresh#147 all CLOSED
- if-never: none stated
- comments: none
- closure candidate: no (or close as an accepted known divergence: operator decision)

#129 — Auto-sync parameters_habitat_rules.yaml from link to fresh
- asks: Add a GitHub workflow that pushes link's rules.yaml to fresh.
- author/created: NewGraphEnvironment, 2026-05-05
- state: premise holds. `.github/workflows/` has no dispatch workflow. CLAUDE.md:1415 says nothing syncs it and that fresh's copy still read `Generated: 2026-04-28` on 2026-10-28.
- files: .github/workflows/ (new), data-raw/build_rules.R
- shared cost: fresh-side workflow and release
- links: fresh#185 CLOSED (per CLAUDE.md, "not planned")
- if-never: none stated
- comments: 1 (2026-05-29). Records the direction: rules.yaml goes link → fresh; parameters_fresh column drift is covered by `audit_configs.R` §3b.
- closure candidate: no

#128 — run_provincial_parity.R resume check fails open
- asks: Skip a group only if the persist schema has rows for it; re-run error stubs; add `--force`.
- author/created: NewGraphEnvironment, 2026-05-05
- state: done. The script became `data-raw/wsgs_run_host.R` (#172). Its resume gate (#168) uses `.lnk_wsg_persisted`, `.is_error_stub` and `--force` (lines 8-19, 270-283). The only missing piece is the skip line naming its reason.
- files: none
- shared cost: none
- links: none
- if-never: none stated
- comments: none
- closure candidate: yes

#126 — consolidate_schema() hardening
- asks: Make consolidation safer: `via` default, pg_dump version check, dynamic host lookup, and a guard on the source drop.
- author/created: NewGraphEnvironment, 2026-05-05
- state: superseded. `consolidate_schema.R` is gone. `schema_consolidate.R` now streams COPY by group over SSH, with no pg_dump → restore → DROP of the source (its header lines 19-30). Hosts are passed in at run time. The local destination backup stops if it produces an empty file (lines 260-281).
- files: none
- shared cost: none
- links: none
- if-never: none stated
- comments: none
- closure candidate: yes

#115 — Auto-derive default gradient_classes from parameters_fresh$access_gradient_max
- asks: Replace the hard-coded `.lnk_classes_bcfp` fallback with classes derived from each species' `access_gradient_max`.
- author/created: NewGraphEnvironment, 2026-05-04
- state: premise holds. `.lnk_resolve_classes` (R/lnk_pipeline_prepare.R:170-173) still falls back to `.lnk_classes_bcfp`. #326 since added a check that refuses classes outside the bcfp set (lines 660-680), so any change has to fit inside that set.
- files: R/lnk_pipeline_prepare.R, R/lnk_barriers_unify.R
- shared cost: possibly a `cut-` vocabulary token and a provincial re-model if `default`'s cuts move
- links: #45 (closed)
- if-never: none stated
- comments: none
- closure candidate: no (low value now; operator call)

#110 — run_provincial_parity.R cache key doesn't capture code/config version
- asks: Store a version/config stamp beside each per-group RDS and treat a mismatch as stale.
- author/created: NewGraphEnvironment, 2026-05-03
- state: partly superseded. The named file is gone. Its successor `wsgs_run_host.R` decides by persist rows (#128), still with no version or config stamp. The current `study_area_run.sh` keeps no per-group cache. Runs record `config_hash` and vocabulary tokens (#127, #414) and face a pre-run gate (#372).
- files: data-raw/wsgs_run_host.R (if kept)
- shared cost: none
- links: #103, #106, #112 (closed). an R&D tracking issue in a private repository (open).
- if-never: none stated
- comments: 1 (2026-05-03). A workaround: move old baseline RDS files out of the resume path.
- closure candidate: yes if the `wsgs_*` path is legacy (operator decision)

#95 — Parameterize network_schema (lift hardcoded fresh.streams)
- asks: Add a `network_schema` parameter so the pipeline stops hard-coding `fresh.streams`.
- author/created: NewGraphEnvironment, 2026-05-01
- state: done in effect. The pipeline steps now write `paste0(schema, ".streams")` (e.g. `lnk_pipeline_classify.R:120-121`). The persist schema comes from config (`pipeline.schema`: fresh, fresh_default_*). `fresh.streams` now appears only in comments and roxygen. Unsure whether running on db_newgraph was ever tested.
- files: none (roxygen examples only)
- shared cost: none
- links: fresh#158 CLOSED
- if-never: none stated
- comments: none
- closure candidate: yes

#86 — lnk_config_audit + crt_schema_audit
- asks: Add audit functions in crate and link that check bundled CSVs for shape, type, row count, checksum and row count in the peer DB.
- author/created: NewGraphEnvironment, 2026-04-30
- state: partly done by other means. `lnk_config_verify()` checks byte and shape checksums, `data-raw/audit_configs.R` runs a pre-run audit, and `sync-bcfishpass-csvs.yml` plus #429 keep the copies synced. Neither `crt_schema_audit` nor `lnk_config_audit` exists. Row-count and peer-DB checks are absent.
- files: R/lnk_config_verify.R (extend), crate R/
- shared cost: crate release + pin
- links: no numbered issues. crate#2 (from #2's commit trail) is CLOSED.
- if-never: none stated
- comments: none
- closure candidate: no (rescope to row counts only, or close)

#84 — Investigate remaining bcfishpass-config departures: ST rearing cluster + SK spawning edges
- asks: Explain the MORR ST, MORR/KISP SK and BABL ST gaps over 5%.
- author/created: NewGraphEnvironment, 2026-04-30
- state: done. The fix, fresh#186, is CLOSED. #130's body (2026-05-05) says that after fresh#186/#187, BULK SK is the "only outlier >5% across 10-WSG × 2-config", with KISP at 0.0% and MORR at +1.8%.
- files: none
- shared cost: none
- links: fresh#186, fresh#133, fresh#147, fresh#107, fresh#153 all CLOSED. an R&D tracking issue in a private repository (open).
- if-never: none stated
- comments: 1 (2026-04-30). Reopened to wait for fresh#186 and a MORR ST re-run.
- closure candidate: yes. fresh#186 shipped, and #130's measurement shows the gaps closed.

#83 — Species-dependent dam-class handling in dimensions.csv
- asks: Decide whether dams should block some species and not others, possibly via a `dams_block` column.
- author/created: NewGraphEnvironment, 2026-04-30
- state: premise holds; this is a thinking issue. There is no dam column in `dimensions.csv`. `default/config.yaml:150` says "Dams never block access". RUNBOOK ~1403 says making it per-species is "a new per-source-per-species column + `lnk_barriers_unify` change".
- files: inst/extdata/configs/*/dimensions.csv, R/lnk_barriers_unify.R, R/lnk_barriers_views.R
- shared cost: operator decision, `acc-` token, provincial re-model
- links: an R&D tracking issue in a private repository (open)
- if-never: none stated
- comments: none
- closure candidate: no (could fold into #201)

#75 — dimensions_columns.csv as source-of-truth: auto-gen README + lnk_rules_build validation
- asks: Generate a README from the column dictionary and have `lnk_rules_build()` warn on unknown columns.
- author/created: NewGraphEnvironment, 2026-04-28
- state: partly done.
  - Done: the CSV was renamed `configs/dictionary_dimensions.csv` (#233, v0.44.3), and `tests/testthat/test-dictionaries.R` plus `audit_configs.R` check the shipped bundles against it.
  - Not done: there is no README generator (`configs/README.md` is absent), and `lnk_rules_build()` checks only required columns, with no unknown-column warning or `strict`.
- files: R/lnk_rules_build.R, a new data-raw README script
- shared cost: none
- links: #74 (merged PR). an R&D tracking issue in a private repository (open).
- if-never: none stated
- comments: none
- closure candidate: no (rescope)

#52 — Research: channel-class break positions vs gradient thresholds
- asks: Test whether cutting streams at channel-class changes gives better habitat maps than gradient thresholds.
- author/created: NewGraphEnvironment, 2026-04-24
- state: premise holds; the research has not been done. Related work exists: the minimal network (#415, `cut-min`) and the parent-gradient table (#444) already separate access cuts from the segments habitat is read on. There is no channel classification.
- files: research/ (new), possibly configs and fresh
- shared cost: research runs; a `cut-` token if adopted
- links: #21 (open)
- if-never: none stated
- comments: none
- closure candidate: no

#21 — Growing season degree days and thermal energy as intrinsic potential variables
- asks: Add growing-season degree days and thermal tolerance as habitat variables, eventually.
- author/created: NewGraphEnvironment, 2026-04-09
- state: premise holds; nothing has started. No temperature, degree-day or ragnar code anywhere in R/, data-raw/ or research/.
- files: future fresh classify, parameters CSVs
- shared cost: an outside temperature model (Poisson); a fresh release
- links: #20 (open). #19, #18 (closed).
- if-never: none stated
- comments: none
- closure candidate: no

#20 — Literature and observation evidence for habitat eligibility departures
- asks: Gather literature and observation evidence for each place link departs from bcfishpass, one issue per departure.
- author/created: NewGraphEnvironment, 2026-04-09
- state: partly done.
  - Done: the dimensions table and its YAML generator shipped (#19 and #22 closed), and observation validation and calibration exist (#283, #284; research/habitat_validation.md, dimensions_audit.md).
  - Not done: no literature evidence table or per-departure issues found. Unsure about evidence kept in other repos.
- files: research/
- shared cost: none
- links: #19, #18, #22 (closed). #2 (open). fresh#113 CLOSED.
- if-never: none stated
- comments: none
- closure candidate: no (or close as superseded by the validation work: operator decision)

#2 — Build fish passage connectivity literature RAG store
- asks: Build a ragnar store at `data/rag/fish_passage_connectivity.duckdb`.
- author/created: NewGraphEnvironment, 2026-04-06
- state: premise holds; not done. There is no `data/` directory and no `.duckdb` file in the repo.
- files: data/rag/ (new; it probably belongs outside the package)
- shared cost: none
- links: none
- if-never: none stated
- comments: none
- closure candidate: no (operator call: a store may exist in another repo; unsure)

**Pairs that edit the same files or share a cost**
- #204 + #169: R/lnk_persist_init.R `force_recreate` and the drift guard; they want opposite changes.
- #204 + #177: R/lnk_persist_init.R (the persist family).
- #204 + #197: `.lnk_cols_streams_access_source_flags()`, the hard-coded source-flag list.
- #197 + #189: R/lnk_pipeline_mapping_code.R, R/lnk_mapping_code.R, bundle CSVs.
- #197 + #153: R/lnk_pipeline_mapping_code.R.
- #189 + #153: R/lnk_mapping_code.R and R/lnk_pipeline_mapping_code.R.
- #191 + #189 / #197 / #153: the missing test-lnk_mapping_code.R and test-lnk_pipeline_mapping_code.R.
- #212 + #213: Comparison B; the 50-group bcfishpass re-run.
- #212 + #189: inst/extdata/configs/*/dimensions.csv.
- #212 + #75: dimensions.csv, dictionary_dimensions.csv, R/lnk_rules_build.R.
- #129 + #75: data-raw/build_rules.R, the rules.yaml generator.
- #201 + #83: R/lnk_barriers_unify.R and R/lnk_barriers_views.R; `acc-` token, provincial re-model, operator decision (bcfp departure).
- #203 + #115: R/lnk_pipeline_prepare.R; provincial re-model.
- #203 + #201 + #83 + #115 + #132: provincial re-model.
- #176 + #177: NAMESPACE and deprecation shims; one link release.
- #176 + #213: the R/lnk_compare_* family and data-raw/wsg_compare.R.
- #177 + #159: R/lnk_pipeline_run.R.
- #110 + #128: data-raw/wsgs_run_host.R resume gate.
- #179 + #110 + #176: the legacy `wsgs_*` path; one operator decision on retiring it.
- #166 + #179 + #181: data-raw shell scripts (wsgs_dispatch.sh, state_clean.sh, trifecta_*).
- #132 + #133: waiting on fresh releases and a pin bump in DESCRIPTION.
- #95 + #133: hard-coded literals across the R/lnk_pipeline_*.R steps.
- #84 + #130: bcfp habitat parity checks; live DB measurement.
- #86 + #75: config validation (audit_configs.R, dictionaries).
- #2 + #20 + #21 + #52: literature and research work (Zotero/ragnar, research/).

