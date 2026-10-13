# Progress — Record source-artifact identity for the DB primitives (#265)

## Session 2026-10-12

- Plan-mode exploration — phases approved by user (#270 separate; log_input carriage; kind = object/api/derived)
- Created branch `265-record-source-artifact-identity-for-the` off main
- Scaffolded PWF baseline from issue #265 with approved phases
- Next: start Phase 1

- Phases 1-2: the dictionary gains `kind` / `url` (12 primitives). New `R/lnk_artifact.R`: DDL, `.lnk_artifact_head()` (never errors), `lnk_artifact_record()` (URL guard against the dictionary; a probe never overwrites a loader row), `lnk_artifact_probe()`, `lnk_artifact_read()`. `test-lnk_artifact.R`: 55 pass, with a live DB test of the probe/loader rule. Mutation: removing the WHERE guard fails 2 tests; restored.

- Phase 3: `snapshot_bcfp.sh` clears this host's loader rows, HEADs the two object fetches, pins them to `?versionId=`, writes a TSV manifest, and records via `data-raw/artifact_record.R` (fatal on failure). Live run on m1 (`--force`, local docker fwapg), 2026-10-13 04:17-04:18Z, exit 0: observations `1790057230537`, modelled crossings `1791321558612`, PSCIS / CABD `api` rows. Round trip: `?versionId=` returns 200 and the same ETag for both. RPostgres does not expand a URI given as `dbname`, so the recorder parses `DATABASE_URL` itself.

- Plan review landed (Plan agent). Verified before acting:
  - B1 is confirmed: `state_clean.sh` default mode drops `fresh`. Left for the user; the location is now one function.
  - B2 was already handled (existence probe).
  - B4 was half-right. `lit()` was already fixed; the date path was broken in a way the review did not name: `httr::parse_http_date` is all-or-nothing.
  - Scope 1 is confirmed: falls come from `falls.csv`.
  - GDAL's requests carry `?versionId=` (`CPL_CURL_VERBOSE`: HEAD + GETs).
- Phase 4: `log_input` gains the `artifact_*` columns, including `loaded_at`. A DB test covers a scratch schema with a probe row; 12 rows, with identity on the stream row.
- Live probe on m1, 04:21Z: 252 FWA artifacts in 17 s, every one with a version id. Last-Modified is 2026-04-16 for the parquet tables and 2026-01-16 for channel_width / discharge.
