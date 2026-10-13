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

- Phase 5: `lnk_preflight_vintage(stamp =)` judges on the newest loader `loaded_at`; unstamped is FATAL; the message names the source per table. Mutation: dropping `unstamped` from `ok` fails 2 tests; restored.
- Live, m1, 04:23-04:25Z: snapshot re-run exit 0. Both loader rows now carry `last_modified` (obs 2026-09-22, crossings 2026-10-06). `host_vintage.R` exits 0 for this host, judged by 4 stamps. With `LNK_HOST_ALIAS=nostamp265` it exits 1, `unstamped` x4, statistics age shown as context.
- Phase 6: `fwapg_sha` roxygen and `lnk_stamp()` corrected (70 commits, verified `git rev-list --count e6e1eb0..f9718cb`). The falls doc line now names `falls.csv`. RUNBOOK §6b / §8d and the CLAUDE.md status updated. #265 body edited.
- /code-check branch, round 1: 3 fragile findings, all fixed.
  - A probe no longer overwrites an earlier probe that named a different version while the row count is unchanged. The RUNBOOK says FWA identity is evidence, not proof.
  - `artifact_record.R` takes its set from `.lnk_vintage_primitives()`.
  - `lnk_artifact_read()` has one shape whether or not anything is recorded.
  - Mutation of the keep-earliest rule fails 1 test; restored.
- Full suite on the branch: 2718 expectations, 2 failed and 2 errored. All four also fail on origin/main against this DB (tunnel down; the prep_dams golden reads live `cabd.dams`, reloaded by verification). See findings.md.
- Round 2: 2 fragile findings, both fixed. **One sat inside round 1's fix #3**, so from here only an enumeration ends the loop.
  - `lnk_artifact_read()`'s real path returned `n_rows` as integer64 against the numeric empty frame; now `::float8`. A DB test was added, and its mutation fails it.
  - `study_area_run.sh` now aligns the destination's log tables before `schema_consolidate()`, so a dispatcher that modelled nothing cannot drop the cyphers' `artifact_*` columns.
- Round 3 was asked for the mechanism and an enumeration. The mechanism: one fact in two places kept in step by hand, with no single source or guard. It walked 19 places; 18 hold.
  - The one that did not: `wsgs_run_pipeline.sh`, the second caller of `schema_consolidate()`, had not received round 2's fix (code-check.md, "A fix lands in one of two callers that share a harness").
  - Fixed at the shared function: `schema_consolidate()` now aligns the destination's log tables first, and the per-caller copy in `study_area_run.sh` is removed.
  - Callers measured by grep: exactly 2, and both go through the function.
  - Loop ended by enumeration (19 places plus a 2-caller count), not by a reviewer's "clean". Agents spent: 1 plan review and 3 code-check rounds.
