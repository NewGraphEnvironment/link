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

## Cause 4 — METHODOLOGY, not a bug (the deepest finding)

After all 3 persist fixes, streams_access flags persist correctly (dams 48561, dam_ind 32370 for PARS) but mapping_code STILL diverges from bcfp. Root: `access_bt = 0` (BLOCKED) for ALL 48561 PARS segments, because every PARS segment has a downstream dam (Bennett/Peace Canyon in PCEA — PARS drains through them). link#152 cross-WSG barriers correctly flag this.

`lnk_pipeline_mapping_code:236` `accessible <- !has_barriers_sp & !no_data`. With every segment blocked:
- token1 (`:262-268`): `ACCESS` requires `accessible` → never fires; only SPAWN/REAR (habitat-driven) or NA
- token2 (`:276`): `ifelse(accessible, mc_barrier, NA)` → always NA → no `;DAM`
- token3 (`:277`): same → no `;INTERMITTENT`

Result: link emits `SPAWN` / `REAR` / `` (blank). bcfp emits `SPAWN;DAM` / `ACCESS;DAM` / `REAR;DAM` for the SAME segments — bcfp does NOT gate token1/token2 on downstream-dam accessibility.

This is the v0.40.0 methodology shift at the semantic level: pre-#187 access used bcfp-staged barriers → matched bcfp (98.63%). Post-#187 access uses link's own cross-WSG-aware barriers → all PARS segments read blocked → tokens collapse.

**RESOLVED — was NOT a methodology decision, was the wrong barriers table.**

Grounded in the pre-#187 matching code (`git show 0cd48d0:R/lnk_compare_wsg.R`) + the research doc canonical call sequence + reading `.lnk_pipeline_prep_minimal:574-592`:

- `barriers_<sp>_min` = gradient + falls ONLY (natural barriers, per-species, minimal-reduced). These are the correct `barriers_per_sp` for access. A segment downstream of a dam is still gradient-accessible → token1 = SPAWN/ACCESS.
- `barriers_<sp>_unified` (what #187 Phase 4 wrongly used) = ALL barriers incl dams → every dam-downstream segment reads blocked → accessible FALSE → token1/2 collapse to bare SPAWN/REAR.
- Dams belong in `barrier_sources` (cross-WSG `barriers_dams_unified`) → drive token2 (`DAM`) + `dam_dnstr_ind`, NEVER blocking `accessible`. That's how bcfp emits `SPAWN;DAM`: gradient-accessible habitat + dam noted.
- link#152 cross-WSG fix is in `barrier_sources` (untouched). Natural barriers are inherently local (gradient/falls don't cross WSG) so `_min` stays tunnel-free.

**Fix applied** (uncommitted, on branch): `lnk_pipeline_run` Phase 4 `barriers_per_sp` swapped `_unified` → `_min`. Verification run in flight (PARS, cleanup_working=FALSE). Expected: token1 ACCESS/SPAWN/REAR restored, token2 DAM/MODELLED/ASSESSED present (`SPAWN;DAM` etc.), match_pct vs bcfp back toward ~98%.

The 3 persist commits (DDL, pre-persist, INSERT projection) remain correct + necessary (the source flags must persist for token2). The `_min` swap is the 4th + final piece.

**Tunnel-free confirmed**: build path uses `_min` (local gradient/falls) + `barrier_sources` views over persist (local). NO tunnel needed for the build. Tunnel only for the parity DIFF (validation). Aligns with user direction: "we will go tunnel free eventually, cannot depend on it for testing."

### Cause 4 fix attempt #1 — `_min` swap FAILED (mechanical, 2026-05-23)

The `_min` swap broke fast: `ERROR: column b.barriers_bt_min_id does not exist`. Root: `lnk_pipeline_access:152-161` derives `feature_id_col <- paste0(table_only, "_id")` and passes the table to `fresh::frs_network_features`, which needs a surrogate feature id. The `_min` tables are **break-position specs** (`blue_line_key, downstream_route_measure, wscode_ltree, localcode_ltree` ONLY — no id) built for `frs_break_apply`, NOT feature tables. The `_unified` views ARE feature-shaped (`id_barrier AS barriers_<sp>_unified_id`, geom, blocks_species). So `barriers_per_sp` mechanically REQUIRES `frs_network_features`-shaped tables; `_min` cannot be dropped in.

**What `barriers_<sp>_unified` actually is** (live viewdef): `SELECT id_barrier AS barriers_bt_unified_id, barrier_source, ..., blocks_species, ..., geom FROM <persist>.barriers WHERE 'BT' = ANY(blocks_species)`. It's all persist barriers (cross-WSG) where the species is in `blocks_species` (#152 predicate). The over-blocking question reduces to: **is DAM in `blocks_species` for BT?** If yes, every PARS dam-upstream segment reads blocked → Cause 4 token collapse.

**Correct fix shape (not yet built):** a per-species feature view that keeps the `_unified` shape + id but filters OUT anthropogenic/dam sources — natural barriers only (`barrier_source NOT IN ('DAM', ...)` or `barrier_subtype`-based). That gives `frs_network_features` its id AND the gradient/falls-only access set. BUT this is gated on confirming bcfp's actual semantics — see below.

### RESOLVED 2026-05-23 — bcfp source read; the access set is natural-only + override-filtered

Read authoritatively from `smnorris/bcfishpass@v0.7.15` (`gh api`, read-only):
- `model/01_access/sql/model_access_bt.sql` — `bcfishpass.barriers_bt` =
  `(gradient WHERE barrier_type IN ('GRADIENT_25','GRADIENT_30') ∪ falls ∪ subsurface)`
  MINUS barriers with upstream BT/salmon/steelhead **observations** (`obs_upstr`,
  20 m tol) MINUS barriers with upstream confirmed **habitat**
  (`user_habitat_classification`, `hab_upstr` 200 m tol) ∪ ALL
  `barriers_user_definite`. **No dams / PSCIS / modelled crossings.**
- `model/01_access/sql/load_streams_access.sql` — `barriers_<sp>_dnstr` (per-sp,
  natural) is SEPARATE from `barriers_anthropogenic_dnstr` / `barriers_dams_dnstr`.
  `dam_dnstr_ind = array[barriers_anthropogenic_dnstr[1]] && barriers_dams_dnstr`.
- `model/02_habitat_linear/sql/load_streams_mapping_code.sql` — token2 gated on
  `barriers_bt_dnstr = array[]::text[]` (accessible) — identical to link.

So `SPAWN;DAM` = natural-accessible (`barriers_bt_dnstr=[]`) + spawning>0 + dam
downstream. The dam annotates access; it doesn't block it.

**link's two divergences (fully characterized):**
1. `barriers_per_sp = barriers_<sp>_unified` = ALL barriers incl dams (wrong
   content; bcfp = natural only).
2. The observation/habitat override (`lnk_barrier_overrides` →
   `<schema>.barrier_overrides`) feeds `lnk_pipeline_classify` (habitat) only —
   NOT `lnk_pipeline_access` (mapping_code accessibility). bcfp applies it to
   `barriers_<sp>`.

Note `access_<sp>` integer (lnk_pipeline_access.R:364) IS obs-aware (matches
bcfp `access_bt`) — but mapping_code uses `has_barriers_<sp>_dnstr`, not it.

**Fix shape:** per-species *feature* view (has-id) of natural-only barriers
(gradient@species-threshold + falls + subsurface) + override + user_definite =
reproduce bcfp `barriers_<sp>`. Real builder, not a swap. Full writeup in
`RUNBOOK.md` §5. Design implication: `blocks_species` binary conflates
natural-access + anthropogenic-descriptor — candidate redesign.

### (superseded) The decisive question is empirical, not theoretical — redo snapshot

Whether bcfp gates token1/token2 on dam-accessibility must be read from bcfp's ACTUAL output, not reasoned about. Tunnel is down again (stale, timed out). Per user direction ("rerun the snapshot locally") + ("cannot depend on tunnel for testing"): running `data-raw/snapshot_bcfp.sh --with-bcfp-views --force` against local docker fwapg (tunnel-free, public sources) to land this week's bcfp into `fresh.streams_bcfp`. Then row-level diff: for PARS segments above Bennett/Peace Canyon dams, what does bcfp's `mapping_code_bt` say (`SPAWN;DAM`? bare `SPAWN`? `NONE`?) AND is the segment in bcfp's accessible set? That answer dictates the fix shape.

## Open

- **Cause 4 methodology decision** — blocks PARS-vs-bcfp parity. Pending user.
- Wall time 956s (~16 min) for one PARS run — double-persist overhead. See task_plan Phase 5.
- BULK also needs a clean rebuild (damaged in earlier debug churn).
- access_bt=0 everywhere also means the rollup (spawn/rear km) may be affected — verify whether habitat km changed vs historic.
