# snapshot_bcfp.sh's fallbacks, measured on m1 (link#459, link#484)

2026-11-12, m1 (GDAL 3.13.0, which has the Parquet driver, so each fallback was
forced), branch `474-backlog-move-6-what-a-run-stamps-and-che`. Every load went
into a scratch schema (`zz_lnk474`, dropped after) and was compared with the
primary path's table on m1. No primitive table was touched.

## The WFS fallback (`wfs_load()`)

- **DataBC's GeoServer pages only with a sort.** An unsorted paged GetFeature
  (`STARTINDEX=0&COUNT=5000`) answers HTTP 400: "Cannot do natural order without a
  primary key, please add it or specify a manual sort". The read is `ORDER BY
  STREAM_CROSSING_ID`, which GDAL's WFS driver sends as `SORTBY`.
- **GDAL's table differs from bc2pg's until normalised:** `gml_id` and `ogc_fid`
  added, `se_anno_cad_data` kept (bc2pg drops it), every decimal and the key as
  double precision (bc2pg: numeric, key integer primary key), geometry untyped.
  After the drops and casts, the four PSCIS views match bc2pg's columns in name,
  type and order.
- **Rows:** all four whole against the WFS's `numberMatched` (assessment 19,905,
  design proposal 147, habitat confirmation 410, remediation 177) and equal to
  m1's bc2pg tables of 2026-11-02 in every column but `objectid` (assessment,
  design proposal, remediation: 0 rows differ). Habitat confirmation: 14 rows
  differ in two free-text columns (`habconf_comments` 8, `habconf_habitat_value_rtle`
  7): PSCIS edited in the ten days between, not the loader.
- **`objectid` is renumbered when DataBC republishes,** not per request: two WFS
  loads minutes apart agreed on all 19,905, and both differ from the 2026-11-02 load
  on every row. So a fallback table equals a same-day bc2pg table; Phase 10's reload
  compares the two directly.

## The Parquet fallback (`obs_parquet_fallback()`)

- The observations parquet (version `1790057230537`, 41.8 MB, 375,962 rows) has two
  columns named `observation_key`: an int64 GDAL row index (0, 1, 2, ...) and the
  string key the `gdal:schema` metadata names as fid. The fallback keeps the string.
  `geom` is ISO WKB PointZ in BC Albers (`geo` metadata, GeoParquet 1.1.0).
- pyarrow (run by `uv run --no-project --with pyarrow`, no shared Python) writes a
  CSV; psql copies it to a staging table and inserts with the WKB decoded.
- First comparison with GDAL's load of the same version: same 375,962 rows, but
  352,766 differed in `distance_to_stream`'s last digits: GDAL writes a double at 15
  significant digits, pyarrow's CSV at 17. Writing doubles at 15 significant digits,
  the fallback's table equals GDAL's: 0 rows differ either way. Load 4 to 6 s.

## Phase 10's proof reload on m1 (2026-11-13 05:14 to 05:21 UTC)

`snapshot_bcfp.sh --with-bcfp-views --force` through the new code
(`reload_m1_20261113.log`, NOTICE lines dropped, the connection string
redacted):

- Each PSCIS view loaded by bc2pg on attempt 1 of 3, equal to the WFS's count
  (19,905 / 147 / 410 / 177); no fallback taken. The observations
  (`1790057230537`, unchanged) and modelled crossings (`1794344402364`, new since
  m1's 2026-11-02 load) recorded by version; CABD (2,593) and PSCIS with content
  md5s (`6f7f44c00794...`, `098617672acf...`).
- The ledger row `snapshot-20261113` stamps `v0.7.15-51-g3bd2824` built
  **2026-11-11T03:45:18Z**: the same version as m1's 2026-11-02 row (built
  2026-10-28), which the old version-only guard would have taken as current.
  After the reload `lnk_baseline_current()` reads TRUE (both forms), the pin reads
  this row with its date, and `host_vintage.R` passes, judging the two object
  tables by source ETag and the API tables by load age.
- **The WFS fallback against a same-day bc2pg load:** loaded minutes after, the
  assessment view equals bc2pg's by value in every row, `objectid` included
  (`EXCEPT` both ways empty). Its content md5 differs (`098617672acf` against
  `ea35d299...`): bc2pg keeps each decimal as GeoServer's JSON spells it (ids
  `55483833`, measurements `488073.0`), every field is `xsd:decimal` in
  DescribeFeatureType, and GDAL reads doubles, so the spelling cannot be
  recovered. Casting through Python's float spelling fixed the measurements and
  left the ids (`55483833.0`); reverted. So a host that fell back reads as holding
  different content and the pre-flight compare refuses it: the safe direction.
- **The pre-flight compare on real rows** (`inputs_m1_m4_before.tsv`,
  `inputs_m1_m4_after.tsv`; m4's rows read over ssh with `host_inputs.R`):
  before the reload m1 and m4 agree; after it, `.lnk_inputs_agree()` refuses,
  naming `fresh.modelled_stream_crossings` (m1 `1794344402364`, m4
  `1793134826715`). CABD and PSCIS pass on equal row counts, since m4's loads
  predate content md5s: the weaker check, and the message says so.
