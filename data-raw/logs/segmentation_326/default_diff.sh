#!/usr/bin/env bash
# default_diff.sh — #326: `default` before (main, zz326_default_pre) against
# after (the branch, fresh_default) on PCEA, FINA, PARS and LKEL. Sums each
# species' flags straight from the persist tables: accessible (access_<sp>
# 1 or 2), spawning and rearing km. Rearing is the flag total, lake connection
# lines included on both sides; lnk_rollup_wsg() splits them but took over
# 10 min per group and species set here (its waterbody join).
# Usage: bash default_diff.sh > default_diff.csv   (run anywhere)
set -euo pipefail
q() { psql -h localhost -U postgres -d fwapg -At -F, -c "$1"; }
echo "wsg,species,schema,segments,accessible_km,spawning_km,rearing_km"
for sp in bt ch cm co gr ko pk rb sk st wct; do
  for s in zz326_default_pre fresh_default; do
    has=$(q "SELECT count(*) FROM information_schema.columns WHERE table_schema='$s' AND table_name='streams_access' AND column_name='access_$sp'")
    [ "$has" = "1" ] || continue
    q "SELECT s.watershed_group_code, '${sp^^}', '$s', count(*),
              round((sum(s.length_metre) FILTER (WHERE a.access_$sp IN (1,2)) / 1000)::numeric, 2),
              round((sum(s.length_metre) FILTER (WHERE h.spawning) / 1000)::numeric, 2),
              round((sum(s.length_metre) FILTER (WHERE h.rearing) / 1000)::numeric, 2)
       FROM $s.streams s
       JOIN $s.streams_access a USING (id_segment, watershed_group_code)
       JOIN $s.streams_habitat_$sp h USING (id_segment, watershed_group_code)
       WHERE s.watershed_group_code IN ('PCEA','FINA','PARS','LKEL')
       GROUP BY 1 ORDER BY 1"
  done
done
