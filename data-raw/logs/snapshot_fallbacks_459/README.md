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
