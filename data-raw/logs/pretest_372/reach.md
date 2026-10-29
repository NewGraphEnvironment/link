# Which files the modelling path reaches (link#372)

Measured 2026-10-28, link at the #372 branch (0.69.3), fresh v0.44.0 (`22034c1`).

The map's `none` rows (`data-raw/pretest_inputs.csv`) claim a file is off the
modelling path. The claim is checked against the static call graph from the
functions `wsg_run_one.R` calls (`PRETEST_ENTRIES` in `data-raw/pretest.R`):
`codetools::findGlobals()` over each function body, plus
`getFromNamespace("<name>", ...)` strings, which is how link reaches fresh's
internals (`.frs_run_connectivity`, `.frs_habitat_models`,
`.frs_near_river_specs`, `.frs_sql_num`). Calls built at run time from strings
are not seen.

- **link:** `tests/testthat/test-pretest.R` re-runs the walk (`pretest_reach()`)
  every test run, so a `none` row on a reached file fails the suite.
- **fresh:** checked once, here, with the walk against a
  `git worktree` of fresh at `v0.44.0` (now `data-raw/pretest_reach_fresh.R <dir>`, which the pick runs itself at the range's fresh tag; it gave the same sets at v0.42.0). A fresh
  release that moves a function between files needs this re-run before the
  map's fresh rows are trusted.

## fresh v0.44.0

Reached (16 + 2 found only through `getFromNamespace`, `frs_cluster.R` and
`frs_habitat.R`): frs_barriers_minimal, frs_break, frs_candidates_pick,
frs_cluster, frs_col_generate, frs_col_join, frs_db_query, frs_edge_types,
frs_habitat, frs_habitat_classify, frs_habitat_overlay, frs_habitat_predicates,
frs_near_river, frs_network_features, frs_order_child, frs_params,
frs_wsg_drainage, utils.

Not reached (mapped `none`): fresh-package, frs_aggregate, frs_categorize,
frs_channel_width, frs_classify, frs_clip, frs_db_conn, frs_extract,
frs_feature_find, frs_feature_index, frs_lake_fetch, frs_migration_trial,
frs_network, frs_network_downstream, frs_network_prune, frs_network_segment,
frs_network_upstream, frs_order_filter, frs_point_locate, frs_point_match,
frs_point_snap, frs_stream_fetch, frs_waterbody_network,
frs_watershed_at_measure, frs_watershed_split, frs_wetland_fetch,
frs_wsg_species, zzz.

The first pass missed `frs_cluster.R` and `frs_habitat.R`: link reaches them
only through `getFromNamespace(".frs_run_connectivity", "fresh")`. That is why
`pretest_reach()` follows those strings.
