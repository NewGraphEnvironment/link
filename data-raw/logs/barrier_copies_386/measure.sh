#!/usr/bin/env bash
# measure.sh — measure copies of one barrier held by several groups (link#386).
# Usage: bash measure.sh <schema> <out dir> [bundle]
#   schema   persist schema to read (e.g. fresh_default)
#   out dir  where the CSVs go (created; refuses one holding summary.csv)
#   bundle   config bundle whose control and user-definite files are read
#            (default: default)
# Connects to the local fwapg through the PG* variables (PGHOST etc.).
set -euo pipefail
schema="${1:?schema}"; out="${2:?out dir}"; bundle="${3:-default}"
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
[ -e "$out/summary.csv" ] && { echo "refusing: $out/summary.csv exists" >&2; exit 1; }
mkdir -p "$out"; out="$(cd "$out" && pwd)"
ov="$repo/inst/extdata/configs/$bundle/overrides"
falls="$(Rscript -e 'cat(system.file("extdata", "falls.csv", package = "fresh"))')"
[ -n "$falls" ] || { echo "fresh's falls.csv not found" >&2; exit 1; }
psql -X -q -v ON_ERROR_STOP=1 -v schema="$schema" \
  -v ctrl="$ov/user_barriers_definite_control.csv" \
  -v definite="$ov/user_barriers_definite.csv" -v falls="$falls" \
  -v out_summary="$out/summary.csv" -v out_ownerless="$out/positions_ownerless.csv" \
  -v out_missing="$out/positions_missing_copy.csv" -v out_ovr="$out/overrides_differ.csv" \
  -v out_files="$out/files_filed_under.csv" -v out_ctrl="$out/control_non_owner.csv" \
  -v out_def="$out/user_definite_non_owner.csv" -v out_falls="$out/falls_non_owner.csv" -v out_ctrl_multi="$out/control_multi_group_lines.csv" \
  -f "$here/measure.sql" -f "$here/report.sql" 2>&1 | grep -v 'does not exist, skipping' || true
psql -X -At -c "SELECT 'measured_at', now()::text UNION ALL SELECT 'schema', '$schema' UNION ALL SELECT 'groups built', count(DISTINCT watershed_group_code)::text FROM $schema.log WHERE date_end IS NOT NULL UNION ALL SELECT 'link_version (newest)', max(link_version) FROM $schema.log UNION ALL SELECT 'link_sha (newest row)', (SELECT link_sha FROM $schema.log ORDER BY date_end DESC NULLS LAST LIMIT 1)" -F, > "$out/stamp.csv"
echo "fresh_version,$(Rscript -e 'cat(as.character(packageVersion("fresh")))')" >> "$out/stamp.csv"
echo "bundle,$bundle" >> "$out/stamp.csv"
[ -s "$out/summary.csv" ] || { echo "no summary written" >&2; exit 1; }
cat "$out/summary.csv"
