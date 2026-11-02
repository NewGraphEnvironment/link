-- pick_groups.sql — candidate proof groups (#415): those with the most chinook
-- records and the most modelled crossings. The README names the picks and why.
-- psql -h localhost -U postgres -d fwapg -f data-raw/logs/minimal_breaks_415/pick_groups.sql
WITH ch AS (
  SELECT watershed_group_code AS wsg, count(*) AS n_ch,
         count(DISTINCT (blue_line_key, round(downstream_route_measure))) AS n_ch_sites
    FROM bcfishobs.observations
   WHERE species_code = 'CH' AND watershed_group_code IS NOT NULL
   GROUP BY 1),
x AS (
  SELECT watershed_group_code AS wsg, count(*) AS n_crossings
    FROM fresh.modelled_stream_crossings
   GROUP BY 1)
SELECT ch.wsg, ch.n_ch, ch.n_ch_sites, x.n_crossings,
       rank() OVER (ORDER BY ch.n_ch_sites DESC) AS rank_ch,
       rank() OVER (ORDER BY x.n_crossings DESC) AS rank_crossings
  FROM ch JOIN x USING (wsg)
 ORDER BY rank_ch + rank_crossings
 LIMIT 15;
