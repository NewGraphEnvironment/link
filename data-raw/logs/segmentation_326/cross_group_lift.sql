-- cross_group_lift.sql — #326: barrier rows a re-modelled group holds that another group's
-- override lifts and its own does not (the reduction lifts by the group's own overrides).
SELECT b.watershed_group_code wsg, sp.code sp,
       count(DISTINCT (b.blue_line_key, round(b.downstream_route_measure))) positions
FROM fresh.barriers b
CROSS JOIN (VALUES ('BT'),('CH'),('CO'),('ST'),('WCT'),('SK'),('PK'),('CM')) sp(code)
WHERE b.watershed_group_code IN ('LKEL','BULK','KISP','USKE','MORR','PCEA','FINA','PARS','LFRA','KOTR','ELKR')
  AND sp.code = ANY (b.blocks_species)
  AND b.barrier_source IN ('GRADIENT','FALLS','SUBSURFACE_FLOW')
  AND EXISTS (SELECT 1 FROM fresh.barrier_overrides o WHERE o.species_code = sp.code
              AND o.blue_line_key = b.blue_line_key AND abs(o.downstream_route_measure - b.downstream_route_measure) < 1
              AND o.watershed_group_code <> b.watershed_group_code)
  AND NOT EXISTS (SELECT 1 FROM fresh.barrier_overrides o WHERE o.species_code = sp.code
              AND o.blue_line_key = b.blue_line_key AND abs(o.downstream_route_measure - b.downstream_route_measure) < 1
              AND o.watershed_group_code = b.watershed_group_code)
GROUP BY 1,2 ORDER BY 1,2;
