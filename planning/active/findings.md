# Findings — #196 streams_access per-source flags + cross-WSG mapping_code

## The bug chain (2026-05-19)

After v0.40.0–v0.40.2 shipped the mapping_code decouple, attempting PARS-vs-bcfp parity revealed link's `mapping_code_bt` second token was `NONE` everywhere, where bcfp had `DAM`/`MODELLED`/`ASSESSED`. Three root causes, found in sequence:

### Cause 1 — persist DDL missing per-source flag columns (Phase 1)

`lnk_pipeline_mapping_code:174-194` probes the access tibble for `has_barriers_{anthropogenic,pscis,dams,remediations}_dnstr`, `dam_dnstr_ind`, `remediated_dnstr_ind` to classify the second token. #187 Phase 2 dropped these from `cols_streams_access_base` (wrong reasoning: "conditional on remediations/observations"; actually only on `barrier_sources` which pipeline_run always passes). Persist `streams_access` lacked the columns → `has()` probes FALSE → token `NONE`.

### Cause 2 — views over working not persist (Phase 2)

#187 Phase 4 set `lnk_barriers_views(barriers_table = paste0(schema, ".barriers"))` (working schema, per-WSG local). Lost cross-WSG dam visibility (PARS BT needs Bennett/Peace Canyon dams in PCEA/UPCE — the link#152 case). PARS has 0 local dams; the cross-WSG dams live only in persist. Fix: pre-persist barriers, let views default to persist (province-wide).

### Cause 3 — persist INSERT projection missing the flags (Phase 3 — THE actual NONE bug)

Even after Phase 1 added the DDL columns and Phase 2 fixed view source, persist `streams_access` flags came back ALL FALSE. Isolated repro against a surviving `working_pars_dbg` schema pinned it:

- in-memory access tibble: flags populated (anth 48559, dams 48559, dam_ind 32406) ✓
- working `streams_access` (dbWriteTable): flags populated ✓
- persist `streams_access` (lnk_pipeline_persist INSERT): flags ALL FALSE ✗

`lnk_pipeline_persist:122-123` built `access_cols_v <- c(cols_streams_access_base, .lnk_cols_streams_access_per_sp(species))` — omitting `.lnk_cols_streams_access_source_flags()`. DDL had the columns; INSERT projected only base + per-species. The 6 flag columns got their default (NULL) on every INSERT.

**Lesson**: DDL change (lnk_persist_init) and INSERT-projection change (lnk_pipeline_persist) are a matched pair. The Phase 1 code-check asserted "INSERT picks up new columns automatically (iterates names(access_cols_v))" — false, because `access_cols_v` is independently constructed and didn't include the flags. Verify DDL + INSERT together against live data, not by reading one side.

## Isolation-debug technique that worked

The killed run's `working_pars_dbg` schema survived the docker restart (data volume persists across container restart). It had all prerequisite barrier tables (`barriers_anthropogenic`, `barriers_pscis`, `barriers_bt`, etc.) but no `_unified` views or `streams_access` (died before mapping_code phase). Reproduced the mapping_code phase steps (lnk_barriers_views → lnk_pipeline_access → inspect) in ~30s instead of re-running the 16-min pipeline. Much faster bug isolation.

CAUTION: running `lnk_pipeline_persist` against the incomplete `working_pars_dbg` DELETE-WHERE-WSG'd the good PARS habitat (streams_habitat_bt 48559 → 0) and replaced with the half-built working schema's (empty) data. Debug-induced data damage — needs a clean full run to repair. Don't persist from a half-built working schema.

## Verified facts

- persist.barriers had PARS (68254 rows, 33104 BT-blockers) — data was upstream-correct throughout; bug was purely in the persist-write projection.
- `barriers_dams_unified` (view over persist) = 178 dams province-wide; PARS-local `barriers_dams` = 0. Confirms cross-WSG dams only visible via persist.
- bcfp `streams_mapping_code` has no `watershed_group_code`; JOIN `bcfishpass.streams ON segmented_stream_id`.

## Open

- Wall time 956s (~16 min) for one PARS run — double-persist overhead. See task_plan Phase 5.
- BULK also needs a clean rebuild (damaged in earlier debug churn).
