# Backlog move 14: primitive tables in one shape, and a parallel publish (#499)

## Outcome

Two batches, one release (0.87.0). **#494:** every host now loads `cabd.dams` in one column layout. The issue's cause was wrong: the layout does not depend on whether the table existed, but on whether GDAL had loaded into the database before. The first ogr2ogr load into a database (the one that creates `ogr_system_tables`) puts `geom` last; every later load puts it second, `OGR_TRUNCATE` or not. A first attempt (`-overwrite` alone) looked right in a scratch database that had already had a load and would have failed every new host; only a load into a brand-new database showed it. `cabd_load()` therefore stages the API and rebuilds `cabd.dams` as `ogc_fid, geom, <fields>` in one transaction, dropping without `CASCADE` (ogr2ogr's own drop takes a dependent view with it silently). **#488:** PUBLISH's checks read one listing, every put runs on a PSOCK pool of `LNK_PUBLISH_JOBS` processes answering with its `VersionId`, unchanged per-group parts take theirs from one `list-object-versions` per directory, and every result is checked before the manifest. **#334's** public read stays open (owner: not ready); its body says so. The owner answered the four gate questions with each recommendation (1a, 2a, 3 not ready, 4a). `/code-check branch` ran three rounds and ended on round 3's enumeration of 44 items (`review-verdict.md`); its fixes took a private-repo reference out of CLAUDE.md, made the put-reply parse read only a tab line, and tested the pool at 2 workers, the most `R CMD check` allows.

## Measurement

- `cabd.dams` on one saved CABD response (2,593 dams), GDAL 3.13.0: today's call into a new database `geom` at 113 of 113, md5 `cb194733…`; every later load and `cabd_load()` from three starting states `geom` at 2, md5 `6f7f44c0…`, the published run's. PSCIS: three bc2pg loads of one view, one md5.
- One `aws` call on m1: 0.55 s, 0.33 s of it start-up (#488's 2.4 s was a cloud host).
- The published tree (1,344 objects, 946 MB) published from m1: serially from main 36.5 min, on the pool (8) 4.1 min (8.9x), the same tree again 1.9 min. Both prefixes identical but for version ids. This is m1's ratio; the cloud host's 53.5 min is owed to the next real PUBLISH.

## Evidence

`data-raw/logs/cabd_shape_494/`, `data-raw/logs/publish_parallel_488/` (each with a README).

## Owed

- The cloud image swap this waited on, in the infrastructure repository (its own issue): the scheduled runs move to the new image, a provincial run goes out on it, and the old image is deleted once that run publishes.
- Every host re-snapshots (`snapshot_bcfp.sh --force`) so its `cabd.dams` is in the standard layout before the next multi-host run.
- Whether the pre-run gate must run again for this release: `R/lnk_publish.R` is mapped `none`, and `snapshot_bcfp*.sh` and `habitat_publish.R` are outside `PRETEST_LINK_PATHS` (`data-raw/pretest.R:109`), but `DESCRIPTION` changes (`parallel` in `Imports`, the version). Run `pretest_check.R` through `study_area_run.sh --preflight-only` before the next provincial run and re-run the gate if it refuses.
- The next real PUBLISH records its time against #488's 53.5 min (and, under Open decision 4b, is the first measurement).
- #334's public read, if left open: the infrastructure change after the budget and anomaly alerts.

Closed by: the PR for #499 (closes #494 and #488)
