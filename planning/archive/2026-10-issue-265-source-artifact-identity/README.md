## Outcome

The DB primitives now carry source-artifact identity.
- **The table:** `provenance.source_artifact` holds, per host and artifact, the object store's version id, ETag and `Last-Modified`.
  - `kind`: `object`, `api` or `derived`.
  - `recorded_by`: `loader` or `probe`. A probe never overwrites a loader row, and keeps the earliest probe while the row count is unchanged.
- **The snapshot:** `snapshot_bcfp.sh` writes `loader` rows, pinning each object fetch to the version it heads (`?versionId=`). A failure to record fails the snapshot. It then probes the FWA artifacts as a soft step.
- **Each run** copies what it read into `log_input.artifact_*`. Consolidate now aligns the destination's log tables first, so that survives a cypher burn.
- **The vintage gate** judges on load stamps and fails an unstamped host, which absorbs #247.
- **Docs:** the `fwapg_sha` docs were corrected (the checkout's HEAD at run time, not the loader's commit).
- **Moved to #270:** recording the fwapg commit at load time (#265's body was edited).

What was learned:
- The live runs found a defect the unit tests could not reach. `httr::parse_http_date()` is all-or-nothing, so one NA blanks every element.
- The review loop ended by enumeration, not by a quiet round. Round 2 found a defect inside round 1's fix; round 3 named the mechanism and walked 19 places. The last open place was a fix that had landed in one of two callers of `schema_consolidate()`, so it moved into the shared function.

**Schema, decided after the PR opened:** the operator moved the table from `fresh.log_source_artifact` to `provenance.source_artifact`. `fresh` is a persist schema that `state_clean.sh` drops; this table describes the database, not a run, and #270's future FWA loader rows could not be re-created. `host` stays in the key.

The move had its own three review rounds (`review-move-round{1,2,3}.md`). Living outside `fresh`, a record can now outlive its table. Round 2 found `lnk_artifact_read()` reporting such a record as `recorded` (now `table_absent`); round 3 named that mechanism, enumerated every reader and every way a table disappears, and found the same gap in `.lnk_log_inputs()` (now joins only on a table that exists). Left open, documented in RUNBOOK §6b: a restore of `fresh` alone brings back an older table under a newer record, which only `snapshot_bcfp.sh --force` corrects.

## Measurement

m1, local docker fwapg, 2026-10-13 04:17–04:25Z.
- **Snapshot (`--force`):** exit 0 with 4 loader rows.
  - observations: `1790057230537`, Last-Modified 2026-09-22, 375,962 rows;
  - modelled crossings: `1791321558612`, 2026-10-06, 524,578 rows;
  - PSCIS (19,905 rows) and CABD (2,592) as `api`.
- **Round trip:** `?versionId=` returns 200 with the recorded ETag for both. GDAL sends the id on every range GET.
- **Probe:** 252 FWA artifacts in 17 s, every one with a version id. Last-Modified is 2026-04-16 for the parquets and the 246 stream-network groups, and 2026-01-16 for channel_width / discharge.
- **Gate:** exit 0 on m1, judged by 4 stamps. Exit 1 under an unstamped alias.
- **Wrong turn:**
  - The first live snapshot recorded both version ids with NULL `last_modified`. The cause was `httr::parse_http_date()`'s all-or-nothing behaviour over a vector holding the `api` rows' NAs.
  - It was fixed, given a regression test, and the recorder now refuses a version id without its date.
- **Branch suite:** 2718 expectations. 4 fail, and the same 4 fail on origin/main against this DB:
  - the bcfp tunnel was down;
  - the prep_dams golden reads live `cabd.dams`, which the verification snapshot reloaded (7 dams against 8).
- **Mutation checks:** each guard was restored to the bug and went red, then was restored. Covered: probe-vs-loader, unstamped, keep-earliest-probe, the `n_rows` type.

## Evidence

Live outputs are in the DB, not in committed logs: `provenance.source_artifact WHERE host = 'm1'`. The ledger row is `data-raw/logs/bcfp_baselines.csv` (`snapshot-20261013`). Reviews are `review-round{1,2,3}.md` in this directory. The research verdict is `research/upstream_input_provenance.md`.

Closed by: PR (see branch `265-record-source-artifact-identity-for-the`)
