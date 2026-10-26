# Plan review — #374 (Plan agent, 2026-10-26, against baseline 5a5547a9)

The reviewer returned its findings in its reply (Plan agents cannot write). Condensed here, each with what was done with it.

| id | finding | verdict |
|---|---|---|
| B1 | Gradient barriers are found along the whole of every line a group touches and persisted under its code (`lnk_pipeline_prepare.R:392-401`, `lnk_barriers_unify.R:208-226`, `lnk_pipeline_persist.R:98-100`); controls are AOI-filtered (`:210-213`), so copies held by different groups need not agree. A segment-owner rule is not complete. | Reproduced. 1,224 co-held positions, all gradient, up to 13 holders; copies differ at 1 barrier position; 1,864 non-owner rows of which 2 no owner matches, 285 rows on no persisted segment. Scheduler uses the **line** rule (complete by construction). |
| B2 | `lnk_persist_init()` runs `CREATE OR REPLACE VIEW streams_habitat_long_vw` unconditionally per dispatcher group (`R/lnk_persist_init.R:539-544`); every recompute reads it (`R/lnk_mapping_code.R:244`). Lock convoy against `lock_timeout 60s`. | Reproduced by reading. Phase 3, first item. |
| A1 | An early recompute that reads too little is permanent (gate one-way; access merge loses the `2`). Readiness must fail closed. | Accepted; Phase 2. |
| A2 | The digest test as planned starts from a settled state and is self-fulfilling; re-model then recompute; negative control must remove every holder of a blocking position. | Accepted; Phase 1 digest item rewritten (TOOD/NATR; closure-only negative). |
| A3 | Planner statistics during consolidate churn; a bad plan meets the 10 min statement timeout. | Watched in Phase 4. |
| A4 | Dispatcher landing rule is sound (`date_end` written last); gaps: soft `date_end` failure (fails closed to the final set), SKIP groups write no log row. | SKIPs land by rule; Phase 2. |
| G1 | Dispatcher-only runs do not init the persist before the legs. | Phase 3. |
| G2 | The view build must not overlap the background `pg_dump`; failure FATAL. | Phase 3 (init, log tables, views, then backup). |
| G3 | `run_finish_recompute` deletes `RC_DIR`, writes a second `views` row, and `RECOMPUTE_RAN` changes meaning. | Phase 3. |
| G4 | Scheduler lifecycle: `set -e` inheritance, parent liveness, fallback, atomic final set, kill semantics. | Phase 3. |
| G5 | Who writes the `recompute` phase row. | Phase 3. |
| O1 | Measure dependencies empirically first. | Done with the ownership probes (above). |
| O2 | Headroom before the checkpoint. | Moved into Phase 1. |
| O3 | Simulation inputs already exist. | Used (`fresh_default.log` / `log_recompute`, `20261023_074321_run_wsgs.tsv`, `_consolidate.log`). |
| O4 | Precompute the map per FWA vintage. | Not taken: the rule takes ~80 s and runs beside spin, so no vintage file to keep current. |
| AC1 | The a/b test must force dependencies to land late, and a weakened rule must produce a difference. | Phase 1 negative control + Phase 4 forced order. |
| AC2 | Readiness audit as a post-condition. | Phase 3. |
| AC3 | "Within one longest job of the last consolidate" is unreachable for a throughput-bound pool; define a recompute tail. | Accepted; #374's acceptance to be restated at the checkpoint. |
| S1 | Control asymmetry across holders is a latent model inconsistency; its own issue. | Phase 5 (draft shown before filing). |
| S2 | Recovery text "upstream of it" is too narrow. | Phase 5. |
