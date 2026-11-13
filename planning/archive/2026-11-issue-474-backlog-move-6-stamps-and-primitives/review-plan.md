# Plan review — #474 (Plan agent, 2026-11-12, against HEAD b2ef9df8)

Findings as returned; dispositions in task_plan.md ("Plan review folded in").

## Blocker
- B1 (#270) artifact_record.R manifest mode refuses anything but the four snapshot tables (:103-106); lnk_artifact_record() refuses URLs not in the dictionary (R/lnk_artifact.R:219-235). Wrapper must map traced URLs to tables, drop non-primitive URLs, and call lnk_artifact_record(recorded_by="loader") directly or via a new --fwa mode.
- B2 (#450) "range starts at the bundle's first commit" fails for default (9cc30fcf: no fresh@ pin, unmapped deleted files; since_sha NOT NULL). Fix: no diff when no history; every data-raw/pretest/*.sql input; since_sha = until_sha; range_source column (own | ancestor | every_input).
- B3 (#450) pretest_record_check() refuses with no history (pretest.R:583); pretest_record_history() returns NULL without history_schema (:393-395). Add explicit every_input acceptance; verdict always writes the resolved history source.
- B4 (#450) pretest_run.sh derives SHAPE_SCHEMA, record-schema creation and verdict args from flags only (:103,193-220,282-288). Pick writes $OUT/history.txt; run.sh reads it.
- B5 (#459) WFS GeoJSON via ogr2ogr ≠ bc2pg table shape (geom name, MultiPoint, pk, types, column order); content md5 over t::text would never match. Match bc2pg's shape (GEOMETRY_NAME=geom, PROMOTE_TO_MULTI, srsName=EPSG:3005, sortBy pk), record path in notes, live forced-fallback comparison.

## Gap
- G1 LNK_BCFP_DATE_COMPLETED must cross ssh (REMOTE_LEG_VARS, leg export, regex, test).
- G2 log_recompute has no bcfp columns; put bcfp_date_completed on log only (ADD COLUMN path fine; consolidate, finish, export pad all OK).
- G3 (#273) FWA tables are not in the vintage set; etag rule covers 2 object tables, not 9. Use loader-row etags only; extend .lnk_vintage_stamp().
- G4 skip guard with --with-bcfp-views must require a views row.
- G5 Phase 7 compare: fetch via remote_run plain SQL to TSV; scope to the four snapshot tables; not downgradable by --preflight-note.
- G6 PSCIS changes often: compare fails most multi-host launches unless the dispatcher loaded in this dispatch; refuse/force before spin in preflight_local.
- G7 (#269) link has no pin; on pak path remove FRESH_GIT_SHA/DIRTY from ~/.Renviron.
- G8 new R/ file needs a pretest_inputs.csv row.
- G9 (#450) minutes scaling (divide dispatcher-equivalent by gate host factor); eligibility = modelable; 60 is minutes or bound; keep --minutes-exclude.
- G10 (#266) log.json carries no model_type; say so in RUNBOOK.
- G11 parity_0.78.0 README already right.

## Ordering
- O1 verify (SQL over log_input) and pre-flight (source_artifact) cannot share one R implementation; keep two with shared fixture semantics.
- O2 snapshot_bcfp.sh calls installed link (link::, library(link)); needs source-tree load or install.

## Assumption
- A1 bcfishobs_sha safe to retire (no other reader incl. knowledge, flooded, fresh).
- A2 recorded etag is the loaded version's (HEAD then ?versionId=).
- A3 (#270) HEAD after load: flag Last-Modified later than load start.
- A4 (#484) exact numberMatched can fail falsely (edits between count and load); 0 count unreadable; re-query once on mismatch; to_regclass before count; fallback trigger = attempts exhausted.
- A5 (#450) short ancestor still refused vs every-input on empty DB: consider fall-through.
- A6 ledger dates mixed formats; parse to POSIXct.
- A7 m1 reload safe for md5; moves m1 off fresh_default's versions and m1 vs m4 will fail Phase 7 until all reload.

## Scope
- S1 wet install in update_hosts.sh is new capability.
- S2 Parquet via pyarrow is the largest new surface.
- S3 Phase 9 no live run: do not close #270 as done.

## Acceptance
- AC1 force each fallback on m1 and compare n_rows/columns/geometry.
- AC2 run new verify + negative read-only against 20261103_163715-269b585a.
- AC3 run the Phase 7 comparator on real m1-vs-m4 dumps.
- AC4 pretest_run.sh --pick-only for default_minimal (no flags) and a parentless bundle on an empty schema.
- AC5 update_hosts.sh --dry-run on m1.
- AC6 live etag test skip_if_offline(); Phase 6 red-first needs the function in its own file first.
