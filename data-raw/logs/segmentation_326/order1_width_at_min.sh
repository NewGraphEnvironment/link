#!/usr/bin/env bash
# order1_width_at_min.sh — does frs_order_child(channel_width_max =) with
# the 1.5 m rearing minimum (<=) admit anything bcfishpass's < would not?
# Counts, per species, order-1 direct children of order >= 5 parents that are
# accessible and within the rearing gradient maximum, at exactly 1.5 m:
# all of them, and those not rearing in the persisted build. A line at the
# minimum passes the ordinary width test at classify time, so any not rearing
# was removed later (connectivity), which an order-child admission does not
# survive either. Reads the m4 `fresh` (bcfishpass config) build at #326.
W="'LKEL','BULK','KISP','USKE','MORR','PCEA','FINA','PARS','LFRA','KOTR','ELKR'"
printf 'species\teq_not_rearing\teq_all\tlt_rearing\teq_not_rearing_km\n'
for sp in bt:0.1049 ch:0.0549 co:0.0549 st:0.0849 wct:0.0849; do
  t=${sp%%:*}; g=${sp##*:}
  psql -h localhost -U postgres -d fwapg -AtF $'\t' -c "
WITH s AS (SELECT s.*, max(stream_order) OVER (PARTITION BY watershed_group_code, blue_line_key) AS som
           FROM fresh.streams s WHERE watershed_group_code IN ($W))
SELECT '$t',
       count(*) FILTER (WHERE s.channel_width = 1.5 AND h.rearing IS NOT TRUE),
       count(*) FILTER (WHERE s.channel_width = 1.5),
       count(*) FILTER (WHERE s.channel_width < 1.5 AND h.rearing),
       coalesce(round(sum(s.length_metre) FILTER (WHERE s.channel_width = 1.5 AND h.rearing IS NOT TRUE)::numeric / 1000, 2), 0)
FROM s JOIN fresh.streams_habitat_$t h USING (id_segment, watershed_group_code)
WHERE h.accessible AND s.stream_order = s.som AND s.stream_order_parent >= 5
  AND s.stream_order = 1 AND s.gradient <= $g"
done
