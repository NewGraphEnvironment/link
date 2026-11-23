# Findings — Backlog move 8: The rules builder and dimensions.csv as the source of truth (#476)

## Issue context

**If we do it:** the dictionary documents and validates the columns, residence comes from `dimensions.csv`, fresh's copy of the rules stays current, and the two open rearing questions are answered. **If we never do:** residence stays hard-coded and fresh's sample rules keep drifting from link's.

Move 8 of link's backlog, `planning/backlog.md`. Run `/planning-init <this issue>`: one phase per batch, one PR. `/gh-pr-merge` ticks the move on merge.

## Batch 11: The rules builder and `dimensions.csv`

**Why here:** one rules regeneration and diff.

#75 (the column dictionary documents and validates: a generated README, and `lnk_rules_build()` warns on an unknown column), #86 (config audit: row counts are what remains), #129 (sync `parameters_habitat_rules.yaml` to fresh on rules-build), #189 (residence and spawn-only from `dimensions.csv`, not code), #212 (bcfishpass-style rows for GR in the `bcfishpass` bundle; KO and RB are paused), #316 (wetland construction lines reach no rear rule in `default`: at most 156 km of BT rearing, measured) and #327 (order-1 streams off larger rivers on a measured width in `default`). Touches `R/lnk_rules_build.R`, `data-raw/build_rules.R`, `inst/extdata/configs/*/dimensions.csv`, `configs/dictionary_dimensions.csv`, `R/lnk_config_verify.R`, a workflow to fresh. Gate: #212 to GR only or dropped; #316 and #327 adopt or decline on measurement; #86 cut to row counts or closed. One rules regeneration and diff; a `default` re-model if #316 or #327 is adopted.

## Exploration, 2026-11-22 (origin/main 8c40e192)

- **#75:** the dictionary is `inst/extdata/configs/dictionary_dimensions.csv`, with 36 columns. It was renamed from `dimensions_columns.csv` in #233. `test-dictionaries.R` already checks that it covers every bundle's `dimensions.csv` and has no extra rows. What is missing is the rendered README and run-time validation in `lnk_rules_build()`, which today reads only its own required list. There are nine `dictionary_*.csv` files in that directory.
- **#189:** `.lnk_mapping_code_persist()` (`R/lnk_mapping_code.R:229`) hard-codes the sets. Anything not BT, WCT or anadromous is resident (KO, RB, GR, CT, DV). It is called from `lnk_pipeline_run()` (`R/lnk_pipeline_run.R:406`, which has `cfg`) and from `data-raw/wsg_recompute_one.R:121` through `getFromNamespace`. The exported `lnk_mapping_code()` and `lnk_pipeline_mapping_code()` default to bcfishpass's sets.
- **#129:** `inst/extdata/parameters_habitat_dimensions.csv` is built separately from `default/dimensions.csv` and is stale. It lacks `rear_stream_order_parent_min`, `_child_min`, `_child_max`, `_distance_max`, `spawn_connected_lake_adjacent`, `rear_wetland_flow` and `rear_near_river`, though the values in their shared columns are identical. The top-level sample is built with fresh's thresholds, not `default`'s. fresh's copy reads `Generated: 2026-04-28` and differs from link's sample by 338 diff lines below the header. fresh and link are both public. Neither holds an Actions secret. The existing `sync-bcfishpass-csvs.yml` uses `GITHUB_TOKEN`.
- **#212:** both `bcfishpass/dimensions.csv` and `bcfishpass/parameters_fresh.csv` are `source: link (hand-authored)`, so no overlay is needed. The bundle's thresholds already hold GR, and its presence copy (bcfishpass's own) has a `gr` column with 83 groups. 68 of those groups have no CH, CO or ST, and 15 have none of CH, CO, ST, BT or WCT. GR's `access_gradient_max` is 0.15. bcfishpass upstream has no `load_habitat_linear_gr.sql` (main, 2026-11-22), though `example_newgraph` thresholds list GR.
- **#316:** measured on 2026-10-22 (the issue comment): 1200 is 10,294 km and 1400 is 5,190 km in wetlands. 97 % of it has no width, and at most 156 km would become BT rearing through the stream door.
- **#327:** `lnk_rules_build()` emits the bypass with `width_known_below_min = TRUE` on every bypass (#326), and `default` sets `rear_stream_order_bypass = no` for every species. The variants harness takes `dims` variants (#364).
- **#86:** no manifest holds a `row_count`. `lnk_config_verify()` checks sha256 bytes and header shape against provenance.

## Errors Encountered

| Error | Resolution |
|-------|------------|
