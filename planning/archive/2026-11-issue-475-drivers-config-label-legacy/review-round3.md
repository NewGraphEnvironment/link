# Round 3 review (fresh reader)

## Checklist read
code-check.md Mechanisms (all 14 H3 prose), plus "A guard's scope, escape hatches, and remedies" and "A fix lands in one of two callers that share a harness" re-read for this mechanism; code-check-shell.md (headings; read: ps/grep pipelines, wait, heredoc/dollar-quote, `a && b || c`, local assignment, ssh exit codes); code-check-r.md (headings; read: on.exit top-level, data-raw loads source tree, Rscript reads script as it runs).

## Mechanism
"A new refusal makes every previously valid invocation invalid, and each place that shows or runs one was found one at a time."

## Enumeration (grep over git ls-files, minus NEWS, planning/archive, data-raw/logs, research/, CLAUDE.md)
About 95 files name one of the 16 drivers or 9 deleted scripts. Narrowed to places that run or print an invocation (not prose about it): 41 live sites.
- Run correctly (config, and label/uid/schema where required, supplied): study_area_run.sh internals (wsg_run_one 2170, wsg_recompute_one 796, host_stamp 1489/1497, study_area_wsgs 1737/1782/1789, cypher_prep 2047 with CYPHER_PREP_CONFIG, install stage 1626 exempt); study_area_remote.sh remote leg (LNK_SCHEMA, LNK_RUN_UID); study_area_recompute.sh:273; study_area_finish.sh hints 880, 1011, 1068 (carry LNK_RUN_UID), 1030 compare, 603 barriers_views; study_area_hosts.sh:674-677; pretest_run.sh:256; recompute_parity.sh/recompute_sweep.sh (label exported, LNK_SCHEMA required, barriers_views gets config); R/lnk_wsg_downstream_check.R:710-717; RUNBOOK 430, 2651-2652, 3506; study_area_buckets.R:715-726 printed run line; both test-file greps; .github has no hits; no live reference to any of the nine deleted scripts remains (only "retired" prose in data-raw/README.md:77,147 and historical records).
- Defects (below): 7 sites in 5 groups. None blocks a run; each shows an invocation the branch now refuses.

## Findings

1. **fragile** data-raw/study_area_verify.sql:478 and :663 — the verify's printed remedies, "LNK_SCHEMA=% LNK_LOAD=loadall Rscript data-raw/wsg_recompute_one.R <WSG>" (478 has no `<config>` at all) and 663 (`<config>` but no LNK_RUN_UID or LNK_RUN_LABEL). Both are refused by the new wsg_recompute_one.R (exit 2 on config, and on label since no LNK_RUN_UID). Same defect round 2 fixed in R/lnk_wsg_downstream_check.R, left in the SQL twin. The finish.sh hints carry LNK_RUN_UID; these two do not. **Rule:** A fix lands in one of two callers that share a harness.

2. **fragile** inst/extdata/configs/default_minimal/README.md:30 and inst/extdata/configs/default_parent/README.md:25 — "LNK_SCHEMA=... Rscript data-raw/wsg_run_one.R ADMS default_minimal" has no LNK_RUN_LABEL; a standalone run now exits 2. RUNBOOK:3506 got the label, these shipped READMEs did not. **Rule:** A guard's scope, escape hatches, and remedies.

3. **fragile** usage headers still show now-required inputs as optional: data-raw/habitat_variants_score.R:29 (`[--base=default]`, empty is now refused), data-raw/habitat_variants_build.R:56-60 (no --base shown; it is required), data-raw/access_disagree_349.R:50-51 (`[--config=default]`), data-raw/study_area_compare.R:9 (`[config]`), data-raw/cypher_prep.sh:8-9 and 77-80 (`bash cypher_prep.sh`, `CYPHER_PREP_BRANCH=... bash cypher_prep.sh` with no CYPHER_PREP_CONFIG; stage `all` now exits 1). Each is a copyable invocation the branch refuses. **Rule:** Documentation Staleness.

4. **fragile** data-raw/run_label_check.R (new) is sourced by wsg_run_one.R / wsg_recompute_one.R but is not in PRETEST_LINK_PATHS (data-raw/pretest.R:109) and has no data-raw/pretest_inputs.csv row, so an edit to the refusal never voids a gate record (CLAUDE.md: "a map row alone for a new script is dead"; wsg_stall_sample.R is handled by both). It is low risk today (the gate sets LNK_RUN_LABEL=pretest), but it is a file on every pick's entry path that the gate cannot see. **Rule:** A proxy is not the property.

5. **fragile** data-raw/state_clean.sh:~113 — the live-run refusal greps all of `ps -ef` for "study_area_run", so a `tail -f data-raw/logs/study_area_run/...`, an editor on study_area_run.sh, or a pgrep on it refuses a `--tables=` drop on an idle database. It fails toward refusing, so no data is at risk; only worth anchoring on `bash .*data-raw/study_area_run.sh` if it annoys. **Rule:** A proxy is not the property.

No other bug found in the diff: state_clean per-host pid/exit handling, table regex, hosts regex, the PGPASSWORD-before-function assignment, decisions-block ordering (PRETEST_NOTE record moved after bucket resolution, before any spend), VINT_OUT capture, and the bcfishpass/LNK_SCHEMA refusals before library load all read correctly.
