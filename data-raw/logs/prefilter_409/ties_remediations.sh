#!/usr/bin/env bash
# ties_remediations.sh — link#409: can the new tiebreak change
# remediated_dnstr_ind? Only where the remediation set (lnk_barriers_emit():
# anthropogenic crossings UNION remediated-passable PSCIS) holds two features at
# one wscode, localcode and measure that differ in pscis_status IN
# ('REMEDIATED','PASSABLE'). That set is built per group in the working schema,
# so this reads every working_<wsg>.crossings the host kept. Read-only.
#   bash ties_remediations.sh <host>
set -euo pipefail
H=${1:?host}
q() { PGPASSWORD=postgres psql -h "$H" -U postgres -d fwapg -X -v ON_ERROR_STOP=1 -At -F' | ' "$@"; }
mapfile -t schemas < <(q -c "SELECT table_schema FROM information_schema.tables
  WHERE table_name = 'crossings' AND table_schema ~ '^working_[a-z]{4}\$' ORDER BY 1")
[ "${#schemas[@]}" -gt 0 ] || { echo "no working_<wsg>.crossings on $H" >&2; exit 1; }
{
  echo "SET statement_timeout = '900s';"
  echo "WITH r AS ("
  sep=""
  for sc in "${schemas[@]}"; do
    printf '%s\n' "$sep"
    cat <<SQL
SELECT '$sc' sch, aggregated_crossings_id::text id, wscode_ltree, localcode_ltree,
       downstream_route_measure m, (pscis_status IN ('REMEDIATED','PASSABLE')) AS passes
FROM $sc.crossings
WHERE (barrier_status IN ('BARRIER','POTENTIAL') AND blue_line_key = watershed_key)
   OR (pscis_status = 'REMEDIATED' AND barrier_status = 'PASSABLE')
SQL
    sep="UNION ALL"
  done
  cat <<'SQL'
), g AS (SELECT sch, wscode_ltree, localcode_ltree, m, count(*) n,
        count(*) FILTER (WHERE coalesce(passes, false)) n_pass
        FROM r GROUP BY 1,2,3,4 HAVING count(*) > 1)
SELECT 'working schemas', count(DISTINCT sch)::text FROM r
UNION ALL SELECT 'rows', count(*)::text FROM r
UNION ALL SELECT 'tie positions', count(*)::text FROM g
UNION ALL SELECT 'mixed-status ties', count(*)::text FROM g WHERE n_pass > 0 AND n_pass < n;
SQL
} | q -f -
