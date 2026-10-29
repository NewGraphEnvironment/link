# fresh files link's modelling path reaches, at the old and new pins (link#409)

`Rscript data-raw/pretest_reach_fresh.R <fresh worktree at the tag>`, run 2026-10-29 from link `8ddbffeb` (DESCRIPTION pin bumped to v0.46.0). The two sets are identical, so every `none` row in `data-raw/pretest_inputs.csv` still holds.

## fresh v0.44.0

```
REACHED: frs_barriers_minimal.R frs_break.R frs_candidates_pick.R frs_cluster.R frs_col_generate.R frs_col_join.R frs_db_query.R frs_edge_types.R frs_habitat_classify.R frs_habitat_overlay.R frs_habitat_predicates.R frs_habitat.R frs_near_river.R frs_network_features.R frs_order_child.R frs_params.R frs_wsg_drainage.R utils.R 
NOT REACHED: fresh-package.R frs_aggregate.R frs_categorize.R frs_channel_width.R frs_classify.R frs_clip.R frs_db_conn.R frs_extract.R frs_feature_find.R frs_feature_index.R frs_lake_fetch.R frs_migration_trial.R frs_network_downstream.R frs_network_prune.R frs_network_segment.R frs_network_upstream.R frs_network.R frs_order_filter.R frs_point_locate.R frs_point_match.R frs_point_snap.R frs_stream_fetch.R frs_waterbody_network.R frs_watershed_at_measure.R frs_watershed_split.R frs_wetland_fetch.R frs_wsg_species.R zzz.R
```

## fresh v0.46.0

```
REACHED: frs_barriers_minimal.R frs_break.R frs_candidates_pick.R frs_cluster.R frs_col_generate.R frs_col_join.R frs_db_query.R frs_edge_types.R frs_habitat_classify.R frs_habitat_overlay.R frs_habitat_predicates.R frs_habitat.R frs_near_river.R frs_network_features.R frs_order_child.R frs_params.R frs_wsg_drainage.R utils.R 
NOT REACHED: fresh-package.R frs_aggregate.R frs_categorize.R frs_channel_width.R frs_classify.R frs_clip.R frs_db_conn.R frs_extract.R frs_feature_find.R frs_feature_index.R frs_lake_fetch.R frs_migration_trial.R frs_network_downstream.R frs_network_prune.R frs_network_segment.R frs_network_upstream.R frs_network.R frs_order_filter.R frs_point_locate.R frs_point_match.R frs_point_snap.R frs_stream_fetch.R frs_waterbody_network.R frs_watershed_at_measure.R frs_watershed_split.R frs_wetland_fetch.R frs_wsg_species.R zzz.R
```
