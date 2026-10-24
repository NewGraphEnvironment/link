# Plan review (Plan agent, 2026-10-24) — summary and dispositions

The full findings came back as the agent's reply. Each item is listed with what was done with it. Verified here: B4 (bash 5.3.9 `wait -n -p` returns an already-returned PID again; three calls in a row returned the same PID), B1 (`pg_dump --schema=<absent>` exits 1, "no matching schemas were found"), and that every group calls `lnk_persist_init(conn, cfg, species = cfg$species)` (R/lnk_pipeline_run.R:221).

| id | finding | disposition |
|---|---|---|
| B1 | The backup fails on a schema that does not exist yet (Run A); the pg_dump exit code is ignored (schema_consolidate.R:248) | Phase 4: init the dispatcher's persist (`lnk_persist_init`, `cfg$species`, no force_recreate) before the backup. Phase 2: the backup checks the exit code and the file size |
| B2 | A cypher consolidated before the dispatcher has persist tables copies only the log tables, reports ok, and deletes the source's log rows | Same pre-dispatch init. Phase 2: refuse a source, before anything is deleted, when a source-only table is a persist table |
| B3 | Closure mode: a dispatcher/cypher bucket overlap is only a WARN, and per-host consolidate would race the dispatcher's writes for the same group | Phase 3: a cypher whose finished set overlaps the dispatcher's bucket is held in a deferred queue and consolidated once the dispatcher leg has ended (today's semantics for overlaps) |
| B4 | `wait -n -p` re-returns a finished PID | Phase 3: pending list, remove `who` after each return, stop when empty, guard an empty or unknown `who`, a per-host done flag; test one consolidate per host |
| O1 | Backup after the cypher legs start leaves held hosts billing if it fails, and puts the dump on the dispatcher's path | Phase 4: the dump runs in the background during spin and prep, and the dispatcher leg waits for it. A failure is fatal before any dispatch (the hosts are not yet held, so the trap burns them). This is still "before the dispatcher leg, with nothing writing" (the operator's choice) |
| O2 | Order inside the per-host step | Phase 3: `in_flight` before the copy; `run_wsgs_write` after each account |
| O3 | Empty bucket: today it still goes through release | Kept: skip the copy, still call `host_release`; keep only when the database did not answer |
| G1 | Each per-host burn would report the hosts still modelling as kept | Phase 3: `burn_cyphers` considers only hosts whose leg ended (`CY_LEG_DONE`) until every leg has ended; the trap considers all |
| G2 | Outcome-less failure underspecified | Phase 3: set `CY_CONS_FAIL[ws]=no_outcome`, add to `CONS_FAILED` / `CONS_EXCLUDED`, no `host_release` call (the host stays held), state stays `in_flight` |
| G3 | Every exit on the per-host path becomes carry-on; errexit rules | Phase 3: the state-write failure keeps the host and carries on; the step is called in the main shell, `|| true`-guarded at the call with its own explicit checks |
| G4 | `complete_fail` accumulates across hosts | Phase 3 |
| G5 | The consolidate log and outcome tsv need per-host names | Phase 3: `${TS}_consolidate_<ws>.log` / `.tsv` |
| G6 | The lock fix must cover the log ALTERs and log indexes too | Done in Phase 1 (`.lnk_log_create_tables`, `.lnk_log_align_columns`), tested live |
| G7 | Whole-table counts, three per host | Phase 2: count the bucket's rows; skip the final verify print for a per-host call |
| G8 | Declare the new maps at the top level of a lib | Phase 3 |
| G9 | Tests that will break | Phase 3/4: test-study_area_finish.R:646 and :687-713, test-study_area_hosts.R:734-750; the run helper sources all three libs |
| G10 | bash 5.1 needs a minor-version check | Phase 3 (setup.R `hosts_bash()`) and Phase 4 (driver) |
| G11 | Run B's future-dated log row would poison Run A's schema | Phase 5: Run B in its own schema `fresh_smoke369b` |
| A1 | No per-table copy times in the log | Phase 2: log each table's copy seconds |
| A2 | A half-copied group can be read by a dispatcher group | RUNBOOK: the recompute settles access, mapping code and the gated flags; guard warnings and `log.wsg_upstream` become timing-dependent |
| A3 | The issue's backup rationale is wrong (the recompute rebuilds only access and mapping code) | RUNBOOK: the dump's use is log history (#354) and rollback of the pre-run state |
| A4 | A dispatcher-only run takes no backup | Kept: backup only when cyphers are in the run, as today |
| A5 | Lock waits count toward the statement bound | Moot after the Phase 1 fix (no-ops take no lock) |
| A6 | `ssh-keygen -R` during other sessions | Low risk; noted |
| S1 | pg_dump lock tests moot under the chosen timing | Noted (already measured) |
| S2 | `state_utc` appended as column 5, header check updated | Phase 3 |
| S3 | Put the per-host step and `legs_wait` in the finish lib or a new one | Phase 3: new `data-raw/study_area_legs.sh` |
| AC1 | "Consolidate on the critical path" needs a new definition | Phase 4: `phases_report` prints last consolidate end minus last model end; RUNBOOK |
| AC2 | Run A must show each cypher's burn ending before the dispatcher's model row | Phase 5 check |
| AC3 | verify_extra path and `-v run_uid=` | Phase 5: `data-raw/logs/provincial_246/verify_extra.sql`, run_uid passed to both |
| AC4 | Race test: two legs ending during one copy; dispatcher first | Phase 3 tests |
