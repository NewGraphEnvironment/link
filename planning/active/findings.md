# Findings — Backlog move 7: Drivers: an explicit config, a labelled standalone run, and the legacy path (#475)

## Issue context

**If we do it:** no driver defaults to `bcfishpass`, a standalone run carries a run id, and `data-raw/` keeps one runner. **If we never do:** the next run can go out on the parity config by default, as one did on 2026-09-03.

Move 7 of link's backlog, `planning/backlog.md`. Run `/planning-init <this issue>`: one phase per batch, one PR. `/gh-pr-merge` ticks the move on merge.

### Batch 10: Drivers

**Why here:** one pass over `data-raw/` argument handling.

#278 (drivers default `--config` to `bcfishpass`: make it required and print the resolved decision set), #281 (a standalone `wsg_run_one.R` writes NULL `run_uid` and `run_label`; decided with #278), #166 (the data-raw scripts still not noun-first, and `data-raw/README.md`'s convention), #181 (table-level drops in `state_clean.sh`), #179 (the legacy dispatcher's fallback puts every group on one host when groups do not outnumber hosts) and #110 (the legacy runner's cache key captures no code or config version). Touches about 15 `data-raw/` drivers, `data-raw/README.md`, `state_clean.sh`, `wsgs_dispatch.sh`, `wsgs_run_host.R`, RUNBOOK. Gate: retire the legacy `wsgs_*` path, which closes #179 and #110 and shrinks #176.

## Drafting notes (2026-11-22, at `5be4fb32`)

- **Config defaults found** (`grep` for `"bcfishpass"` defaults in `data-raw/`): `study_area_run.sh:224`, `recompute_parity.sh:37`, `recompute_sweep.sh:29`, `wsg_run_one.R:46`, `wsg_recompute_one.R:24`, `study_area_wsgs.R:28`, `study_area_compare.R:18`, `host_stamp.R:21`, `barriers_views_build.R:26`, `study_area_buckets.R:93`, `parity_crosssection.R:52`, `cypher_prep.sh:322` (env default), plus the legacy `wsgs_dispatch.sh`, `wsgs_run_pipeline.sh`, `wsgs_run_m4_offline.sh`, `wsgs_run_host.R`, `runs_archive.sh`, `trifecta_15wsg.sh`, `buckets_balance.R`.
- **#278's list is stale in places:** `wsgs_run_host.R` is `run_provincial_parity.R` renamed (#172), and the line numbers have moved.
- **Legacy chain:** `wsgs_run_pipeline.sh` → `wsgs_dispatch.sh` → `wsgs_run_host.R` → `wsg_compare.R` / `wsg_pipeline_run.R`. The last two are also sourced by the current `study_area_compare.R`, so they stay.
- **#166's table is mostly done:** `schema_consolidate.R`, `wsg_compare.R`, `buckets_balance.R` already carry noun-first names. Remaining verb-first names include `snapshot_bcfp.sh` (named in `R/` and tests), `sync_bcfishpass_csvs.R` (the weekly workflow), `build_rules.R` (named in `inst/extdata/`), `build_species_views.R` (named in `R/`), `build_minutes_append.R` (tests, `pretest.R`), `compare_rollups.R`, `compare_adms.R`, `regen_provenance.R`, `query_*.R`, `regress_dams_isolation.R`, `exp_gradient_extra_breaks.R`, `test_sequential_breaking.R`, `make_hexsticker.R` (soul's template name).
- **`run_uid` is read as a gate:** `R/lnk_publish.R:37,49` refuses a build or recompute with no `run_uid`; `recompute_readers_check.R` selects `log` rows by it. So what a standalone run stores there is a stored-data fork (open decision 1).
- **`LNK_RUN_LABEL` may be set but empty on the orchestrated path:** `study_area_run.sh` exports `RUN_LABEL=""` when `--run-label=` is absent, so a label requirement must apply only where `LNK_RUN_UID` is unset.
- **Spend order in `study_area_run.sh`:** buckets resolve at ~1739, `cypher_up` at ~1930, the `--preflight-only` exit at ~1688.
- **`PRETEST_LINK_PATHS`** (`data-raw/pretest.R:109`) holds `wsg_run_one.R`, `wsg_recompute_one.R`, `schema_consolidate.R`, `study_area_run.sh`, `wsg_stall_sample.R`: Phases 2 and 3 void the gate record for them.
