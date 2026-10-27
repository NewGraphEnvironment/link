-- unbroken_frontiers.sql — #326 residuals: an accessible segment (streams_access
-- access_<sp> 1 or 2) holding a barrier of the persisted access view more than
-- 1 m above its start. No barrier lies below the segment's start, so that one
-- is an access frontier the segmentation did not break at. Holder = the group
-- that persisted the barrier row; own = the segment's group holds it too.
-- Usage: psql -v schema=fresh -v view=barriers_bt_access -v acc=access_bt -v sp=bt -f unbroken_frontiers.sql
SELECT s.watershed_group_code AS wsg, :'sp' AS sp,
       count(DISTINCT (b.blue_line_key, round(b.downstream_route_measure))) AS positions,
       count(DISTINCT s.id_segment) AS segments,
       round((sum(DISTINCT s.length_metre) / 1000)::numeric, 2) AS km_upper_bound,
       bool_or(b.watershed_group_code = s.watershed_group_code) AS any_own_holder
FROM :schema.streams s
JOIN :schema.streams_access a USING (id_segment, watershed_group_code)
JOIN :schema.:view b ON b.blue_line_key = s.blue_line_key
  AND b.downstream_route_measure > s.downstream_route_measure + 1
  AND b.downstream_route_measure < s.downstream_route_measure + s.length_metre - 1
WHERE s.watershed_group_code IN ('LKEL','BULK','KISP','USKE','MORR','PCEA','FINA','PARS','LFRA','KOTR','ELKR')
  AND a.:acc IN (1, 2)
GROUP BY 1 ORDER BY 1;
