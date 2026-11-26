-- onegroup.sql — what a one-group run into an empty schema no longer holds
-- (link#386). Run after measure.sql in the same session (psql -f measure.sql
-- -f onegroup.sql), on a build from before the change, which still holds
-- every non-owner copy. Each (holder, position) pair a group held without
-- owning is what that group, built alone from 0.93.0 on, no longer holds. It
-- matters only where the holder has segments upstream of the position (its
-- own walk reads it); the owner touches the line, so the line rule lists it
-- among the holder's dependencies, and lnk_downstream_load() of those
-- dependencies' rows restores it.
DROP TABLE IF EXISTS m386_np;
CREATE TEMP TABLE m386_np AS
SELECT g.holder, g.blue_line_key, g.drm, p.owner
  FROM m386_g g JOIN m386_pos p USING (blue_line_key, drm)
 WHERE g.holder <> p.owner;
ALTER TABLE m386_np ADD COLUMN ws ltree, ADD COLUMN lc ltree;
UPDATE m386_np n SET ws = s.wscode_ltree, lc = s.localcode_ltree
  FROM whse_basemapping.fwa_stream_networks_sp s
 WHERE s.blue_line_key = n.blue_line_key
   AND n.drm >= s.downstream_route_measure AND n.drm < s.upstream_route_measure;
DROP TABLE IF EXISTS m386_np_up;
CREATE TEMP TABLE m386_np_up AS
SELECT n.holder, n.blue_line_key, n.drm, n.owner,
       (SELECT round(sum(st.length_metre)::numeric / 1000, 1)
          FROM :"schema".streams st
         WHERE st.watershed_group_code = n.holder
           AND whse_basemapping.fwa_upstream(n.blue_line_key, n.drm, n.ws, n.lc,
                 st.blue_line_key, st.downstream_route_measure,
                 st.wscode_ltree, st.localcode_ltree, false, 1)) AS holder_km_upstream
  FROM m386_np n WHERE n.ws IS NOT NULL;
COPY (SELECT holder,
             count(*) AS non_owner_copies,
             count(*) FILTER (WHERE holder_km_upstream > 0) AS with_holder_segments_upstream,
             count(DISTINCT owner) AS owners,
             string_agg(DISTINCT owner, ';' ORDER BY owner) AS owner_groups,
             round(max(holder_km_upstream), 1) AS max_holder_km_upstream
        FROM m386_np_up GROUP BY holder ORDER BY holder) TO STDOUT CSV HEADER \g :out_onegroup
COPY (SELECT count(*) AS non_owner_copies,
             count(*) FILTER (WHERE holder_km_upstream > 0) AS with_holder_segments_upstream,
             count(DISTINCT holder) AS holders
        FROM m386_np_up) TO STDOUT CSV HEADER \g :out_onegroup_total
