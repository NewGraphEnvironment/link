# `cabd.dams` in one column layout (link#494)

Measured on m1, 2026-11-22, local docker fwapg (PostgreSQL 17.5, PostGIS),
GDAL 3.13.0, bcdata 0.16.0.post1, link at `500b18ac` plus the uncommitted
`cabd_load()`. Every load read **one saved CABD API response** (fetched
2026-11-23T01:31:33Z, 8,425,594 bytes, md5 `6925567423a0df7b51f2fb6e2f59ac62`,
2,593 dams; the file is not committed), so the features are held fixed and only
the load differs. Each load went into a scratch database on the same server
(`link499_*`, dropped after). `probe.sh` prints a table's columns and types,
`geom`'s position, the `ogc_fid` count and range, the content md5 exactly as
`.lnk_table_content_md5()` computes it, and an md5 of the column names and types.

## What moves `geom`

| load | database | `geom` at | content md5 | file |
|---|---|---|---|---|
| today's call (`-overwrite --config OGR_TRUNCATE YES`) | new | 113 of 113 | `cb194733619c18dfc1b674b92ad243ee` | `loads/today1.txt` |
| today's call again, over it | same | 2 | `6f7f44c007945545d5a8bf2cb91461d3` | `loads/today2.txt` |
| `-overwrite` alone, new table | same | 2 | `6f7f44c0…` | `loads/ow1.txt` |
| `-overwrite` alone, again | same | 2 | `6f7f44c0…` | `loads/ow2.txt` |
| today's call, new table, after a `DROP` | same | 2 | | (console) |
| today's call, then a second new table | new, then same | 113, then 2 | | (console) |
| `-overwrite` alone | new | 113 | | (console) |
| a 1-feature load, then `-overwrite` alone | new | 113, then 2 | | (console) |

The issue's reading was that the layout depends on whether `cabd.dams` existed
before the load. It does not: **the first ogr2ogr load into a database, the one
that creates GDAL's `ogr_system_tables` schema and its event trigger, lays its
table out `geom` last, and every later load puts it second, with or without
`OGR_TRUNCATE`.** A newly built host's first ogr2ogr load is CABD (PSCIS goes
through bcdata), which is why new cloud hosts recorded a different md5. `6f7f44c0…`
is the md5 the published run's dispatcher held (#494) and this host's fwapg
recorded for `cabd.dams` (`provenance.source_artifact`, loaded 2026-11-13), so
CABD returned the same dams on 2026-11-22.

ogr2ogr's drop under `-overwrite` takes a dependent view with it: a view over
a table was gone after the load, exit 0.

## The rebuild

`cabd_load()` (`data-raw/snapshot_bcfp_lib.sh`) loads the API into a staging
table and rebuilds the target as `ogc_fid, geom`, then the rest in GDAL's order,
in one transaction. On the same response:

| starting state | `geom` at | columns and types | `ogc_fid` | content md5 | file |
|---|---|---|---|---|---|
| new database, no table (GDAL's staging is geom-last) | 2 | `d709b8a7…` | 2,593, 1 to 2,593 | `6f7f44c0…` | `loads/p_none.txt` |
| a geom-last `cabd.dams` (today's call into a new database) | 2 | `d709b8a7…` | 2,593, 1 to 2,593 | `6f7f44c0…` | `loads/p_last.txt` |
| its own table | 2 | `d709b8a7…` | 2,593, 1 to 2,593 | `6f7f44c0…` | `loads/p_second.txt` |
| reference: today's call, reloaded | 2 | `d709b8a7…` | 2,593, 1 to 2,593 | `6f7f44c0…` | `loads/today2.txt` |
| the defect: today's call, new database | 113 | `a7bd75bc…` | 2,593, 1 to 2,593 | `cb194733…` | `loads/today1.txt` |

Index names equal the reload layout's (`dams_geom_geom_idx`, `dams_pkey`, as
this host's fwapg holds). With a view over the table, `cabd_load()` stops on the
`DROP` (exit 1) and the table and view are left as they were.

## PSCIS

`bcdata bc2pg whse_fish.pscis_remediation_svw` twice into one database and once
into a new one: 177 rows each time, one content md5 and one column signature
(`pscis.txt`). bcdata does not go through GDAL, so it never creates
`ogr_system_tables`. Not measured: a host whose PSCIS fell back to the WFS
(`wfs_load()`, an ogr2ogr load), whose md5 already differs from bc2pg's.

## Tests

`tests/testthat/test-snapshot_bcfp_lib.R`, the `cabd_load()` block: the call's
shape on stubs; a geom-last staging table (made by an `ogr2ogr` stub through the
real `psql`, the new-host case GDAL gives only on a database's first load)
rebuilt to `ogc_fid, geom, cabd_id, height_m`; one table from three starting
states on a synthetic three-dam fixture (`fixtures/cabd_494/dams.geojson`; no
CABD data is committed); and the refusal over a view. Against a copy of the
library with today's call, four of these fail; with `CASCADE` on the drop, two.
