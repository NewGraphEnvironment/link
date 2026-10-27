-- classify_scope_residual.sql — #326: in-AOI positions of working_<w>.barriers_<sp> that
-- frs_barriers_minimal() pruned, whose every pruner (a same-set barrier downstream,
-- fwa_upstream tolerance 1 as the reduction uses) lies outside the AOI.
-- Usage: psql -v w=pcea -v tbl=working_pcea.barriers_bt -v tbl_min=working_pcea.barriers_bt_min -f classify_scope_residual.sql
-- Output: tbl, n_all, n_out_aoi, n_pruned_in_aoi, pruned_only_out_aoi. A row is not
-- upstream of itself (fwa_upstream(a, a) is false), so no self-exclusion is needed.
WITH t AS (
  SELECT x.*, EXISTS (SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp s
                      WHERE s.blue_line_key = x.blue_line_key
                        AND x.downstream_route_measure >= s.downstream_route_measure
                        AND x.downstream_route_measure < s.upstream_route_measure
                        AND s.watershed_group_code = upper(:'w')) AS in_aoi
  FROM :tbl x
), pruned AS (
  SELECT t.* FROM t WHERE in_aoi AND NOT EXISTS (
    SELECT 1 FROM :tbl_min m WHERE m.blue_line_key = t.blue_line_key
      AND abs(m.downstream_route_measure - t.downstream_route_measure) < 0.01)
)
SELECT :'tbl' tbl, (SELECT count(*) FROM t) n_all, (SELECT count(*) FROM t WHERE NOT in_aoi) n_out_aoi,
       (SELECT count(*) FROM pruned) n_pruned_in_aoi,
       (SELECT count(*) FROM pruned a WHERE NOT EXISTS (
          SELECT 1 FROM t b WHERE b.in_aoi
            AND whse_basemapping.fwa_upstream(b.blue_line_key, b.downstream_route_measure, b.wscode_ltree, b.localcode_ltree,
                                              a.blue_line_key, a.downstream_route_measure, a.wscode_ltree, a.localcode_ltree, false, 1))) AS pruned_only_out_aoi;
