# snapshot_bcfp_lib.sh — the loads data-raw/snapshot_bcfp.sh makes that need to
# survive a flaky service or an older GDAL (link#484, link#459). Sourced, not
# run; kept apart so tests/testthat/test-snapshot_bcfp_lib.R can drive each
# function with stubs on PATH. Runs under macOS /bin/bash 3.2 and bash 5: no
# mapfile, no ${var,,}, no arrays.
#
# Reads: PSQL (the psql command line, word-split on use), DATABASE_URL.
# Tunables (environment):
#   SNAPSHOT_BCFP_BC2PG_ATTEMPTS  bc2pg attempts per table before the WFS fallback (3)
#   SNAPSHOT_BCFP_BC2PG_BACKOFF   seconds x attempt number between attempts (30)
#   SNAPSHOT_BCFP_WFS             the WFS endpoint (DataBC's)
#
# Why a row check and not only bc2pg's exit status (link#484): bcdata reads the
# WFS feature count from any HTTP 200, so a transient count of 0 comes back as a
# valid answer. bcdata 0.16.0 then crashes on it (IndexError), which the exit
# status happens to catch; a bcdata that handled a zero count would load an
# empty table and exit 0. So every load is held to the rows the table holds,
# against the WFS's own numberMatched when that can be read.

SNAPSHOT_BCFP_WFS="${SNAPSHOT_BCFP_WFS:-https://openmaps.gov.bc.ca/geo/pub/wfs}"

# Rows in a table, or -1 when it does not exist. Asked in two queries, because a
# count over a table a crashed load never created would fail the whole statement.
snap_rows() {   # $1 = schema.table
  local present
  present=$($PSQL -At -c "SELECT to_regclass('$1') IS NOT NULL") || return 1
  if [ "$present" != "t" ]; then
    echo -1
    return 0
  fi
  $PSQL -At -c "SELECT count(*) FROM $1"
}

# The WFS's own feature count for a layer (numberMatched), or nothing when it
# cannot be read. A 0 is a reading the service has been seen to give
# transiently (link#484), so it is returned as nothing too.
snap_wfs_count() {   # $1 = layer, e.g. WHSE_FISH.PSCIS_ASSESSMENT_SVW
  local n
  n=$(curl -s --max-time 60 \
        "${SNAPSHOT_BCFP_WFS}?service=WFS&version=2.0.0&request=GetFeature&typeNames=$1&resultType=hits" \
      | grep -o 'numberMatched="[0-9]*"' | head -1 | grep -o '[0-9][0-9]*') || n=""
  case "$n" in ""|0) return 0 ;; esac
  printf '%s' "$n"
}

# Is a loaded table whole? Sets SNAP_N (its rows) and, when not, SNAP_WHY.
# Zero rows is never whole. Where the WFS gives a count, the rows must equal it;
# a mismatch is asked once more, since PSCIS can be edited between the count and
# the load.
snap_check() {   # $1 = schema.table, $2 = layer
  local expect
  SNAP_WHY=""
  SNAP_N=$(snap_rows "$1") || { SNAP_WHY="could not count rows"; return 1; }
  if [ "$SNAP_N" = "-1" ]; then SNAP_WHY="table not created"; return 1; fi
  if [ "$SNAP_N" = "0" ]; then SNAP_WHY="0 rows"; return 1; fi
  expect=$(snap_wfs_count "$2")
  [ -n "$expect" ] || return 0
  [ "$SNAP_N" = "$expect" ] && return 0
  # The first count disagreed, so an unreadable re-count is a failure too: the
  # same flaky service that left a short table can blank the second answer.
  local first="$expect"
  expect=$(snap_wfs_count "$2")
  if [ -n "$expect" ] && [ "$SNAP_N" = "$expect" ]; then return 0; fi
  SNAP_WHY="$SNAP_N rows, the WFS reports ${expect:-$first (re-count unreadable)}"
  return 1
}

# A layer read straight from the WFS by GDAL, paged, then put in bc2pg's shape
# (link#459). Measured on m1, 2026-11-12, against bc2pg's PSCIS tables:
#   - DataBC's GeoServer pages only with a sort ("Cannot do natural order without
#     a primary key"), so the read is ORDER BY the key, which GDAL sends as SORTBY;
#   - GDAL adds gml_id and ogc_fid, keeps SE_ANNO_CAD_DATA (bc2pg leaves it out),
#     reads every decimal as double precision, the key too, and leaves the
#     geometry untyped.
# After the load the extra columns go, doubles become numeric, the key becomes an
# integer primary key, and the geometry is typed. The four PSCIS views then match
# bc2pg's columns in name, type and order, and on 2026-11-13 the assessment view
# loaded minutes after bc2pg held the same 19,905 rows by value (EXCEPT both
# ways empty, objectid included; objectid is renumbered when DataBC republishes).
# Its content md5 still differs: bc2pg keeps each decimal as GeoServer's JSON
# spells it (an id 55483833, a measurement 488073.0), and every field is
# xsd:decimal, so GDAL's doubles cannot recover which. A host that fell back
# therefore reads as holding different content, and the pre-flight's
# compare_inputs refuses the run until it reloads: the safe direction.
wfs_load() {   # $1 = layer, $2 = schema.table, $3 = key column (stream_crossing_id), $4 = geometry type (MULTIPOINT)
  local layer="$1" tbl="$2" key="${3:-stream_crossing_id}" gtype="${4:-MULTIPOINT}" ukey
  ukey=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')
  ogr2ogr -f PostgreSQL "PG:$DATABASE_URL" -overwrite \
    --config OGR_WFS_PAGING_ALLOWED ON \
    --config OGR_WFS_PAGE_SIZE 5000 \
    --config PG_USE_COPY YES \
    -nln "$tbl" -lco GEOMETRY_NAME=geom -nlt "$gtype" -t_srs EPSG:3005 \
    -sql "SELECT * FROM \"pub:$layer\" ORDER BY $ukey" \
    "WFS:${SNAPSHOT_BCFP_WFS}?version=2.0.0" || return 1
  $PSQL -q <<SQL || return 1
DO \$\$
DECLARE c record;
BEGIN
  EXECUTE 'ALTER TABLE $tbl DROP COLUMN IF EXISTS gml_id, DROP COLUMN IF EXISTS ogc_fid,
           DROP COLUMN IF EXISTS se_anno_cad_data';
  FOR c IN SELECT column_name FROM information_schema.columns
            WHERE table_schema = split_part('$tbl', '.', 1) AND table_name = split_part('$tbl', '.', 2)
              AND data_type = 'double precision' AND column_name <> '$key' LOOP
    EXECUTE format('ALTER TABLE $tbl ALTER COLUMN %I TYPE numeric', c.column_name);
  END LOOP;
  EXECUTE 'ALTER TABLE $tbl ALTER COLUMN $key TYPE integer, ADD PRIMARY KEY ($key)';
END
\$\$;
SQL
}

# One BC Data Catalogue table by `bcdata bc2pg`, retried, then from the WFS.
# Each attempt drops the table, loads it, and is held to snap_check(). Sets
# SNAP_PATH ("bcdata bc2pg" or "WFS fallback") on success. Returns 1, after a
# FATAL line, when every attempt and the fallback failed.
bc2pg_load() {   # $1 = schema.table (the catalogue's dataset name, lower case)
  local tbl="$1" layer attempts backoff i=1 last="" rc
  attempts="${SNAPSHOT_BCFP_BC2PG_ATTEMPTS:-3}"
  backoff="${SNAPSHOT_BCFP_BC2PG_BACKOFF:-30}"
  case "$attempts" in ""|*[!0-9]*) echo "FATAL: SNAPSHOT_BCFP_BC2PG_ATTEMPTS must be a whole number" >&2; return 1 ;; esac
  case "$backoff" in ""|*[!0-9]*) echo "FATAL: SNAPSHOT_BCFP_BC2PG_BACKOFF must be a whole number of seconds" >&2; return 1 ;; esac
  [ "$attempts" -ge 1 ] || { echo "FATAL: SNAPSHOT_BCFP_BC2PG_ATTEMPTS must be at least 1" >&2; return 1; }
  layer=$(printf '%s' "$tbl" | tr '[:lower:]' '[:upper:]')
  SNAP_PATH=""
  while [ "$i" -le "$attempts" ]; do
    $PSQL -q -c "DROP TABLE IF EXISTS $tbl;" >/dev/null || return 1
    # Inside an `if`, so a failing load is an attempt, not the end of the script.
    if bcdata bc2pg "$tbl" --db_url "$DATABASE_URL"; then
      if snap_check "$tbl" "$layer"; then
        echo "bc2pg $tbl: $SNAP_N rows on attempt $i of $attempts"
        SNAP_PATH="bcdata bc2pg"
        return 0
      fi
      last="$SNAP_WHY"
    else
      rc=$?
      last="exit $rc"
    fi
    echo "bc2pg $tbl: attempt $i of $attempts failed ($last)" >&2
    if [ "$i" -lt "$attempts" ]; then sleep $((backoff * i)); fi
    i=$((i + 1))
  done
  echo "bc2pg $tbl: $attempts attempts spent (last: $last); loading from the WFS directly" >&2
  $PSQL -q -c "DROP TABLE IF EXISTS $tbl;" >/dev/null || return 1
  if wfs_load "$layer" "$tbl" && snap_check "$tbl" "$layer"; then
    echo "WFS $tbl: $SNAP_N rows (fallback after $attempts bc2pg attempts)"
    SNAP_PATH="WFS fallback"
    return 0
  fi
  echo "FATAL: bc2pg $tbl: $attempts attempts, last: $last; WFS fallback: ${SNAP_WHY:-load failed}" >&2
  return 1
}

# Does this GDAL read Parquet? grep without -q reads all of ogr2ogr's output:
# with -q under pipefail, ogr2ogr took SIGPIPE and the check misread a present
# driver as absent (link#160).
snap_has_parquet() {
  ogr2ogr --formats 2>/dev/null | grep -i parquet > /dev/null
}

# The observations parquet into an existing bcfishobs.observations-shaped table
# when GDAL has no Parquet driver (link#459). pyarrow, run by uv in a
# throwaway environment (never a shared Python), writes a CSV in the table's
# column order: of the file's two `observation_key` columns it keeps the
# string one (the key; the int64 one is GDAL's row index, measured on version
# 1790057230537), and the WKB `geom` goes as hex. psql copies it into a
# staging copy of the table with `geom` as text, then inserts with the WKB
# decoded in BC Albers.
obs_parquet_fallback() {   # $1 = local parquet file, $2 = schema.table (already created)
  local f="$1" tbl="$2" csv py
  command -v uv >/dev/null 2>&1 || {
    echo "FATAL: this GDAL has no Parquet driver and uv is not installed to read it with pyarrow" >&2
    return 1
  }
  csv="$f.csv"
  py="$f.py"
  cat > "$py" <<'PY'
import sys
import pyarrow as pa
import pyarrow.csv as pc
import pyarrow.parquet as pq

src, dst, cols = sys.argv[1], sys.argv[2], sys.argv[3].split(",")
t = pq.ParquetFile(src).read()
names = t.column_names
keep = {}
for i, n in enumerate(names):
    c = t.column(i)
    if n == "observation_key" and not pa.types.is_string(c.type):
        continue  # GDAL's int64 row index, not the key
    if n == "geom":
        c = pa.array([None if v is None else v.hex() for v in c.to_pylist()], pa.string())
    elif pa.types.is_floating(c.type):
        # GDAL writes a double to Postgres at 15 significant digits; pyarrow's CSV
        # would write all 17, and the two readers' tables would then differ in
        # distance_to_stream's last digits (352,766 rows, measured).
        c = pa.array([None if v is None else format(v, ".15g") for v in c.to_pylist()], pa.string())
    keep[n] = c
missing = [n for n in cols if n not in keep]
if missing:
    sys.exit("the parquet lacks " + ",".join(missing))
pc.write_csv(pa.table([keep[n] for n in cols], names=cols), dst)
PY
  local cols sel
  cols=$($PSQL -At -c "SELECT string_agg(attname, ',' ORDER BY attnum) FROM pg_attribute
                        WHERE attrelid = '$tbl'::regclass AND attnum > 0 AND NOT attisdropped") || return 1
  # The select list, the WKB decoded where the column is geom; built by Postgres
  # from the same catalog rows, so it names exactly the columns copied.
  sel=$($PSQL -At -c "SELECT string_agg(CASE WHEN attname = 'geom'
                            THEN 'ST_SetSRID(ST_GeomFromWKB(decode(geom, ''hex'')), 3005)'
                            ELSE quote_ident(attname) END, ', ' ORDER BY attnum)
                        FROM pg_attribute
                       WHERE attrelid = '$tbl'::regclass AND attnum > 0 AND NOT attisdropped") || return 1
  (cd "$(dirname "$f")" && uv run --no-project --quiet --with pyarrow python -I "$py" "$f" "$csv" "$cols") || {
    echo "FATAL: reading $f with pyarrow failed" >&2
    return 1
  }
  $PSQL -q <<SQL || return 1
CREATE TEMP TABLE obs_stage AS SELECT * FROM $tbl WITH NO DATA;
ALTER TABLE obs_stage ALTER COLUMN geom TYPE text;
\\copy obs_stage FROM '$csv' WITH (FORMAT csv, HEADER true)
INSERT INTO $tbl SELECT $sel FROM obs_stage;
SQL
  rm -f "$csv" "$py"
}
