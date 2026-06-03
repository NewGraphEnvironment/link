# link 0.42.0

First package vignette: `vignettes/pars-habitat-connectivity.Rmd` — bull trout and Arctic grayling habitat and connectivity classification for the Parsnip River Watershed Group (`PARS`, FWCP Peace), rehearsed end-to-end so it can transfer into the Fish Passage Peace 2025 report appendix ([#215](https://github.com/NewGraphEnvironment/link/issues/215)). Two analyses: (1) **parity** — link's `bcfishpass` config reproduces bcfishpass's per-segment `mapping_code` for bull trout at 99.04%; (2) **extension** — link's `default` config models Arctic grayling, which bcfishpass does not model at all. Map symbology reuses the bcfishpass symbology registry bundled in `gq` (`gq::gq_reg_main()` + `gq_tmap_classes()`, the same recipe `fresh` uses), so stream colours match a bcfishpass QGIS project exactly. The vignette is tunnel-free: the model run + comparison run once locally in `data-raw/wsg_vignette_data.R`, which caches artifacts to `inst/vignette-data/` (`pars.gpkg`, `pars_parity.rds`); the vignette only loads those, so pkgdown CI builds it with no Postgres and no bcfishpass snapshot. New Suggests (`bookdown`, `gq`, `knitr`, `rmarkdown`) + `VignetteBuilder: knitr` + `gq` Remote.

# link 0.41.4

`data-raw/audit_configs.R` is now a trustworthy pre-trifecta gate. The script grew an end-of-run rollup that aggregates every finding and exits non-zero when any fired (previously findings scrolled past inline and the script always exited 0, so the trifecta could not gate on a clean audit), plus a section comparing fresh's canonical `parameters_fresh.csv` column set against each link bundle's copy (flags engine params fresh added that link is missing; treats `observation_*` as expected link-only extensions — the `parameters_fresh` half of the fresh↔link config-drift gap, rules.yaml half tracked in #129). All 30 findings the audit had been emitting were audit-side defects, not config drift (`lnk_config_verify` reports 0 byte/shape drift in both bundles): §1 now calls the canonical `lnk_config_verify()` rather than a divergent homegrown checksum recipe; §2 regenerates rules.yaml with `edge_types="explicit"` to match how the committed copy is built; §3 splits species-axis mismatches into flagged defects vs informational expected asymmetries; §4 resolves declared paths against the bundle dir and compares full relative paths instead of basenames. Audit now reports "No findings — config layers aligned." and exits 0.

# link 0.41.3

`lnk_wsg_resolve()` gains an optional `conn` argument so callers can control the DB connection rather than relying on env-var-driven `lnk_db_conn()`. When `conn = NULL` (default), behaviour is unchanged — `lnk_db_conn()` is used as before. The change matters in environments where `PG_*_SHARE` env vars (or `~/.Renviron`) point at a tunnel that isn't reachable: `data-raw/study_area_wsgs.R` now opens a local docker fwapg connection explicitly and passes it through, matching every other driver script's `localhost:5432/fwapg postgres/postgres` pattern (and the pre-#207 inline behaviour). Strict mode and province mode remain DB-free; `conn` is consulted only in closure mode (`wsgs` non-`NULL` + `expand = TRUE`). Latent on the v0.41.0 release; exposed by the v0.41.1 study-area run when the dispatcher's `~/.Renviron` was pinned to the dead db_newgraph tunnel.

# link 0.41.2

`data-raw/study_area_run.sh` pre-flight bug fix exposed by v0.41.1's `--schema=` flag. The pre-flight check for the bcfp reference view was looking in `$SCHEMA.streams_vw_bcfp` (the override-able persist schema), but the bcfp reference is hard-coded to `fresh.streams_vw_bcfp` in `R/lnk_compare_mapping_code.R:78` — it's a constant comparison reference, not a per-run output. The coincidence held while `$SCHEMA` was always `"fresh"`; the new flag exposed the latent bug. Now the pre-flight always checks `fresh.streams_vw_bcfp`, independent of `$SCHEMA`.

# link 0.41.1

`data-raw/study_area_run.sh` gains a `--schema=<persist-schema>` flag for side-by-side bundle compares. Without the flag, behaviour is unchanged (config's YAML `pipeline$schema` default). With the flag, the driver exports `LNK_SCHEMA` so all per-WSG R scripts (`wsg_run_one.R`, `wsg_recompute_one.R`, `study_area_compare.R`) override `cfg$pipeline$schema` at runtime. The propagation works through SSH to cyphers too (each remote shell exports `LNK_SCHEMA` before its WSG loop). Use case: `--config=default --schema=fresh_default` lets a default-config run land in `fresh_default` without clobbering an earlier `--config=bcfishpass` baseline in `fresh`. Empty `--schema=` value errors loudly rather than silently falling through to the YAML default. Live-validated on ADMS (2.2 min, 11 species habitat tables landed in `fresh_default`, `fresh` untouched).

# link 0.41.0

New exported function `lnk_wsg_resolve()` — the bundle-aware "what WSGs should we model?" resolver ([#207](https://github.com/NewGraphEnvironment/link/issues/207)). Composes the FWA drainage closure (now a fresh primitive: `fresh::frs_wsg_drainage()`, [NewGraphEnvironment/fresh#211](https://github.com/NewGraphEnvironment/fresh/pull/212) / fresh v0.32.0) with the bundle's `wsg_species_presence` filter (link#157). Three call patterns dispatched by `(wsgs, expand)`: province mode (`wsgs = NULL` → all bundle-species WSGs, sorted alphabetically), closure mode (`wsgs = c(...), expand = TRUE` → focal + drainage closure, DS-first preserved), strict mode (`wsgs = c(...), expand = FALSE` → species-filter input verbatim). Validation mirrors `lnk_pipeline_species`; closure mode opens its own DB conn via `lnk_db_conn()` with `on.exit` cleanup; closure + strict modes emit `message()` listing any species-less WSGs dropped from the result (parity with the previous inline diagnostic). New `@family wsg` — pre-stages a `lnk_wsg_*` family for follow-on topology helpers (e.g. cross-host DS-first bucketing).

`data-raw/study_area_wsgs.R` shrinks 76 → 33 lines — pure CLI shim now, delegating to `lnk_wsg_resolve()`. Stdout is **byte-identical** for the regression baseline (`PARS,BULK` → the exact 15-WSG closure `KISP, KLUM, LKEL, LSKE, MSKE, USKE, BULK, FINA, LBTN, LPCE, MORR, PARA, PCEA, UPCE, PARS`), so `data-raw/study_area_run.sh` and downstream consumers are unchanged. fresh dependency pin: `Remotes: NewGraphEnvironment/fresh@v0.31.0 → @v0.32.0`. 22 tests added (`tests/testthat/test-lnk_wsg_resolve.R`): arg validation, stub-based province/strict (stub deliberately non-alphabetical so `sort()` is load-bearing), live-DB closure + province (gated on `skip_if_no_db()`).

# link 0.40.5

Tunnel-free per-segment `mapping_code` parity for the 3 FWCP study areas ([#175](https://github.com/NewGraphEnvironment/link/issues/175)) — 50 drainage-closed WSGs across Peace / Fraser / Skeena, authoritative median match 99.66% / mean 99.11% / 130 of 148 rows ≥99%. Built around a new `lnk_access()` export ([#205](https://github.com/NewGraphEnvironment/link/issues/205)) — the portable access builder that's the missing twin of `lnk_mapping_code`. Its `merge = TRUE` mode is the cheap post-consolidate recompute: rebuild only access + mapping_code from persisted streams/habitat/barriers (no streams segmentation or habitat classification re-derived), ~8× faster than the full-pipeline path (FINA 11.9 s wall vs ~90 s, identical bcfp parity). Methodology is now correctness-regardless-of-bucketing — distribute (any bucketing) → consolidate → recompute → compare — with the recompute as the correctness guarantee, bucketing as a speed knob.

New runner `data-raw/study_area_run.sh` + helpers (`study_area_wsgs.R`, `wsg_run_one.R`, `wsg_recompute_one.R`, `study_area_compare.R`) drives the whole flow tunnel-free on M1 + N cyphers (no `:63333`, no M4). Bug classes addressed along the way: persist + consolidate are now host- and species-count-agnostic ([#204](https://github.com/NewGraphEnvironment/link/issues/204) — shape-tolerant `schema_consolidate` + `cypher_prep` aligned to `cfg$species`); `lnk_mapping_code`'s access read no longer goes cartesian against persist when `id_segment` repeats across WSGs ([#203](https://github.com/NewGraphEnvironment/link/issues/203) symptom narrowed — filter by `watershed_group_code` when present); persist `streams` + `barriers` get the `wscode_ltree` / `localcode_ltree` GIST/btree indexes `frs_network_features` traversal needs (matches `fresh::utils.R` pattern). New `RUNBOOK.md` §6 gotchas (orphaned `frs_network_features` backends + `statement_timeout` / `lock_timeout`, view-vs-table planner direction, the per-tenant cartesian) and a cross-repo soul `code-check.md` Postgres + R-client section.

Two recompute-stable divergences remain as taxonomy candidates, not regressions: SETN salmon ~94% (SK-geography class), UNRS BT 61.8% (Kenney reservoir / dam-override). Validated against `bcfishpass@v0.7.15-14-ge12c1a5`.

# link 0.40.4

Reproduce bcfp's per-species accessibility so dam-downstream segments emit the dam descriptor ([#200](https://github.com/NewGraphEnvironment/link/issues/200)). The mapping_code phase previously drove `accessible` from `barriers_<sp>_unified` (all barriers, including dams), so every segment below a dam read inaccessible and lost its `;DAM`/`;MODELLED`/`;ASSESSED` second token — emitting a bare `SPAWN`/`REAR` where bcfp emits `SPAWN;DAM`. It now uses a new per-species `barriers_<sp>_access` view that reproduces bcfp's `barriers_<sp>`: natural barriers only (gradient at the species threshold ∪ falls ∪ subsurface), minus the observation/habitat override, plus all user-definite barriers (override-exempt). Dams stay in `barrier_sources` and annotate token2 only.

All three access inputs are now persisted province-wide so the cross-WSG downstream walk is correct in every watershed group, not just the run's own: natural barriers (already), `user_barriers_definite` (new `USER_DEFINITE` family in `lnk_barriers_unify`, ltree-resolved via the FWA join like falls), and the observation/habitat override (new `<persist_schema>.barrier_overrides` table). Validated against `bcfishpass@v0.7.15`: PARS BT 98.95%, LFRA BT 97.77% / CO 97.90% per-segment mapping_code match. See `RUNBOOK.md` §5.

# link 0.40.3

Persist the per-source downstream-barrier flag columns in `streams_access` so `lnk_pipeline_mapping_code`'s second token (`DAM`/`MODELLED`/`ASSESSED`/`REMEDIATED`/`NONE`) populates from persisted state instead of defaulting to `NONE`. Three coupled fixes ([#196](https://github.com/NewGraphEnvironment/link/issues/196)): `lnk_persist_init` adds the six flag columns to the `streams_access` DDL; `lnk_pipeline_run` pre-persists barriers before the mapping_code phase for cross-WSG dam visibility (link#152); `lnk_pipeline_persist` projects the flag columns in the INSERT (the DDL/INSERT pair must match — the missing projection was the actual `NONE`-token bug).

Adds `RUNBOOK.md` — the durable mental model of the barrier → access → mapping_code machinery, including the authoritative bcfp access-set mechanism (read from `smnorris/bcfishpass@v0.7.15`). Note: the per-species *accessibility* set still carries dams (it should be natural-only + observation/habitat-overridden, per bcfp); dam-downstream segments therefore still emit a bare habitat token rather than `SPAWN;DAM`. Characterized in RUNBOOK §5 with a scoped fix (follow-up issue).

# link 0.40.2

Hotfix for wide-table species-set evolution in v0.40.0/v0.40.1's `lnk_pipeline_run(mapping_code = TRUE)` path. Closes [#194](https://github.com/NewGraphEnvironment/link/issues/194).

v0.40.1 made the mapping_code phase use `active_species` (per-WSG subset of bundle species) for working schema's `streams_access` columns — matching the persist DDL because `lnk_persist_init` was also passed `active_species`. But persist is province-wide. When WSG #2 has a different active subset than WSG #1, the persist table is locked to #1's column set and #2's INSERT projection fails:

```
ERROR: column "has_barriers_ch_dnstr" of relation "streams_access" does not exist
```

Live smoke 2026-05-19: PARS ran first (default config, active = bt/gr/ko/rb) → 4-column persist DDL. BULK next (default config, active = bt/ch/co/pk/sk/st/rb — BULK is salmon-bearing in the Skeena) → 7-column INSERT projection against 4-column table → fail.

Fix: `lnk_pipeline_run` passes `cfg$species` (full bundle, 11 species for `default` config) to `lnk_persist_init` instead of `active_species`. Persist DDL is bundle-sized; per-WSG INSERTs in `lnk_pipeline_persist` continue using `active_species` for projection so unused species' columns get NULL. Per-species habitat tables (`streams_habitat_<sp>`) similarly created for the full bundle — extras stay empty until populated.

Verified live: PARS + BULK now coexist in `fresh_default.streams_access` / `fresh_default.streams_mapping_code` with their respective active subsets, NULL for non-active columns.

**Migration**: existing persist tables created with narrower DDL do NOT auto-grow. Drop `<persist_schema>.streams_access`, `<persist_schema>.streams_mapping_code`, and `<persist_schema>.streams_habitat_long_vw`, then re-run `lnk_pipeline_run(mapping_code = TRUE)` to recreate them with the bundle-wide DDL.

No regression in bcfishpass bundle: `cfg$species` = bcfp 8 = active for most bcfp-bundle WSGs → identical INSERT projection.

# link 0.40.1

Hotfix for v0.40.0's `lnk_pipeline_run(mapping_code = TRUE)` path on non-bcfp bundles. Closes [#192](https://github.com/NewGraphEnvironment/link/issues/192).

v0.40.0's mapping_code phase hardcoded `sp_set <- c("bt","ch","cm","co","pk","sk","st","wct")` (the bcfp 8 species) and called `lnk_barriers_views` without a `species` arg (uses the same bcfp 8 default). Working schema's `streams_access` got bcfp-8-species columns, but persist `streams_access` was created by `lnk_persist_init(species = active_species)` with the bundle's species — for the `default` config that's bt/gr/ko/rb. The persist `INSERT ... SELECT` projects persist's column list against working → fails with `column a.has_barriers_ko_dnstr does not exist`.

Effect: `lnk_pipeline_run(mapping_code = TRUE)` worked only for the bcfishpass bundle (full 8-species). Every other bundle (including the `default` operator-facing one) errored on persist.

Fix: pipeline_run's mapping_code phase now uses `active_species` (bundle-driven) for both `lnk_barriers_views(species = ...)` and `lnk_pipeline_access(barriers_per_sp = ...)`. Passes `species_<role>` to `lnk_mapping_code` filtered against `active_species` — species in active_species that don't appear in any bcfp residence category (GR/KO/RB) fall through to `species_resident` (placeholder; the data-driven categorization lands via #189).

Caught by live smoke 2026-05-19 on PARS with default bundle. Pre-merge unit tests didn't cover this path; #191 tracks the test catch-up.

# link 0.40.0

Mapping_code tunnel decouple + portable `lnk_mapping_code()` build + `<type>_<role>` rename sweep. Closes [#187](https://github.com/NewGraphEnvironment/link/issues/187). Major architectural shift in how access semantics flow through the parity diff. **BC: parameter and CLI-flag renames (deprecation shims for one release; removal v0.41.0).**

- **Persist `streams_access` + `streams_mapping_code` + long-form habitat view.** `lnk_persist_init()` now creates two new per-WSG per-species persist tables (`streams_access`, `streams_mapping_code`) and one VIEW (`streams_habitat_long_vw` = `UNION ALL` across `streams_habitat_<sp>` tables, presents the per-species split as long-form for any consumer that prefers it). Per-species column generators (`.lnk_cols_streams_access_per_sp()`, `.lnk_cols_streams_mapping_code_per_sp()`) are species-driven — pass a different species set, get matching columns. `lnk_pipeline_persist()` extended with `streams_access` + `streams_mapping_code` write blocks, gated by presence of the working-side tables (skip cleanly when the mapping_code path didn't run).

- **`lnk_mapping_code()` — new exported portable build entry point.** Schema-aware wrapper around `lnk_pipeline_mapping_code()` (the pure data transform). Takes explicit `table_<role>` args (`table_access`, `table_habitat`, `table_streams`) — function works against working-schema tables (mid-pipeline) or persist-schema tables (ad-hoc rebuild). Caller can invoke it directly against persist data with the tunnel down to rebuild `streams_mapping_code` without re-running the full pipeline — the headline use case unblocking QGIS bcfp-shape symbology via `data-raw/build_species_views.R --bcfp`.

- **`lnk_pipeline_run(..., mapping_code = TRUE)` — tunnel-free mapping_code phase.** New optional phase that runs `lnk_barriers_views` (over working `<schema>.barriers`, tunnel-free, link-canonical) + `lnk_pipeline_access` + `lnk_mapping_code` between `lnk_barriers_unify` and `lnk_pipeline_persist`. Persist phase copies both new tables to `<persist_schema>`. **Methodology shift:** ACCESS now uses link's own per-species barriers (derived from `<schema>.barriers`'s `blocks_species` predicate per link#152) instead of bcfp's barriers tables staged via the tunnel. Pre-#187 the only path that built `streams_mapping_code` was `lnk_compare_wsg`, and access there used bcfp-staged barriers — so link's `streams_mapping_code` reflected link's habitat + bcfp's access. Post-#187 it reflects link's habitat + link's access. The parity diff vs `bcfishpass.streams_mapping_code` becomes more meaningful (surfaces real link-vs-bcfp divergence that was artificially suppressed before). Expect non-trivial parity-number deltas on the next provincial run vs pre-#187 baselines.

- **`lnk_compare_wsg()` refactored.** Build delegated to `lnk_pipeline_run(mapping_code = TRUE)`; only the diff stays in compare. `.lnk_compare_wsg_mapping_code_diff()` rewritten to read from `<persist_schema>.streams_mapping_code` instead of working schema. The orphan helpers (`.lnk_compare_wsg_mapping_code`, `.lnk_compare_wsg_stage_reference_barriers`) deleted — ~200 lines simpler.

- **BC: parameter rename `with_mapping_code` → `mapping_code`** in `lnk_compare_wsg()` and `lnk_pipeline_run()`. Old name accepted with `.Deprecated()` warning for one release; removal in v0.41.0.

- **BC: parameter rename `<role>_species` → `species_<role>`** in `lnk_pipeline_mapping_code()` (three params: `resident_species` → `species_resident`, `anadromous_species` → `species_anadromous`, `spawn_only_species` → `species_spawn_only`). Matches the documented `<type>_<role>` convention (`col_<role>`, `table_<role>`, `exp_<role>`, now `species_<role>`). Old names accepted with deprecation warning until v0.41.0.

- **BC: CLI flag rename `--with-mapping-code` → `--mapping-code`** in `wsgs_run_pipeline.sh`, `wsgs_dispatch.sh`, `wsgs_run_m4_offline.sh`, `trifecta_smoke.sh`, `wsgs_run_host.R`. Old flag accepted with stderr deprecation warning until v0.41.0.

- **`lnk_barriers_views()` gains `barriers_table` arg.** Default `NULL` preserves the existing `<persist_schema>.barriers` source. Pass a working-schema table to build views over a per-WSG working barriers table — used by the new `mapping_code` phase. Backward-compatible.

- **Follow-up filed:** [#189](https://github.com/NewGraphEnvironment/link/issues/189) — data-drive species residence categorization (`species_resident` / `species_anadromous` / `species_spawn_only`) from `dimensions.csv`. Today the defaults are hardcoded to bcfp's species residence model; #189 moves them to bundle data so custom species (sea-run cutthroat, Dolly Varden, future mixes) work without monkey-patching function defaults.

# link 0.39.1

Fail loud on transient cypher prep failures. Closes [#182](https://github.com/NewGraphEnvironment/link/issues/182). Trip-mode hardening before M1 takes over cypher dispatch while the user is in Europe.

- **`data-raw/cypher_prep.sh`** — replace `set -e` with `set -euo pipefail`; wrap three `| tail -N` pipelines with tempfile + exit-check pattern (`bash snapshot_bcfp.sh`, `Rscript pak::local_install`, `Rscript lnk_persist_init`). Before: `tail`'s exit 0 masked upstream failures, script printed `=== READY` while cypher was half-prepped, umbrella's downstream marker-grep caught it but the failure was opaque on the cypher itself. After: each failure mode dumps its full log to stderr and exits 1, ssh-back to the umbrella surfaces the non-zero exit, marker-grep continues to work as belt-and-suspenders. Hit twice in 2026-05-15 (Peace Tier 2 retry + post-#185 re-spin; transient bcdata openmaps WFS timeout in both cases). Sibling fix shipped in [rtj#163](https://github.com/NewGraphEnvironment/rtj/pull/163) for the cypher orchestration scripts; this is the link-side complement covering the per-cypher prep script.

# link 0.39.0

Additive multi-host runs + two coupled fixes to `schema_consolidate.R`. Closes [#180](https://github.com/NewGraphEnvironment/link/issues/180) and [#185](https://github.com/NewGraphEnvironment/link/issues/185). Validated end-to-end via Peace Tier 2 retry (2026-05-15): 16 Peace WSGs additively dispatched into an existing 13-WSG `fresh_default`, all 16 land with complete per-species habitat tables, M4 final state = 29 WSGs.

- **Additive Step 0 (BC).** `wsgs_run_pipeline.sh`'s Step 0 (`state_clean.sh --schemas=$SCHEMA` wipe) now requires `--reset-schema` to fire. Default is additive — pipeline writes rely on `lnk_pipeline_persist`'s per-WSG DELETE-WHERE-WSG idempotency to replace cleanly without losing other WSGs in the schema. Enables adding a new WSG set (e.g. Peace 16) to an in-flight schema without rebuilding everything.

- **Bucket-filtered COPY-streaming (BC).** `schema_consolidate.R` replaces `pg_dump`+`scp`+`pg_restore` with per-table `ssh <host> 'docker exec psql -c "COPY (SELECT * FROM <t> WHERE wsg IN (bucket)) TO STDOUT"' > /tmp/<f>` + local `psql -c "COPY <t> FROM STDIN" < /tmp/<f>`. Source-side row filter eliminates the over-fetch class where leftover WSGs outside the bucket collided with destination data. `bucket=` is now REQUIRED per source. DROP SCHEMA on source replaced with bucket-scoped DELETE so out-of-bucket WSGs on source are preserved.

- **Fix: `dest_conn` default routed to wrong DB.** `schema_consolidate(..., dest_conn = link::lnk_db_conn())` default routed verification queries to M4's tunnel `:63333/bcfishpass` while the COPY shellouts hardcode local `:5432/fwapg`. `wgc_tables` returned 0 rows → silent skip of every source. Default now `NULL`; function constructs its own `localhost:5432/fwapg` connection internally to match the COPY hardcodes. Caught Peace Tier 2 first attempt — 12 of 16 Peace WSGs lost from consolidate (M1's 5 recoverable post-fix; 7 from burned cyphers lost).

- **Fix: per-source `wgc_tables` enumeration ([#185](https://github.com/NewGraphEnvironment/link/issues/185)).** Previously enumerated tables on destination only. When source's habitat-table set was a strict subset (cyphers' Peace bucket = BT/GR/RB; M4 destination carried `streams_habitat_ch/sk/st` residue from prior runs), the loop hit `streams_habitat_ch` on source → `relation does not exist` → `break` → silently dropped `_gr` / `_rb` data. Now enumerates `wgc_tables` on BOTH source AND destination via parallel `information_schema` queries; iterates the intersection. Per-table failures use `next` over `break` — one bad table no longer poisons the rest. Source-side post-COPY cleanup DELETEs only successfully-copied tables (errored tables stay intact for retry). Per-source result gains `copied`, `errored`, `skipped_source_only`, `skipped_dest_only`.

# link 0.38.1

* `wsgs_run_pipeline.sh`: `--cy-workspaces=A,B,C` passthrough for #178 Tier 1/2 cypher integration tests (was hardcoded for the full `job1,job2,job3` set). CY_WS_ARR threaded through Steps 3/4/5/7/9 + trap-EXIT burn. Step 9 SOURCES_R built dynamically per-cypher. Tier 1 (1 cypher) validated live: 13/13 study-area WSGs, 22m wall, exit 0, cy1 burn clean.

# link 0.38.0

Provincial-run autonomy CLI + 8 operational-script renames to noun_verb convention. Closes [#172](https://github.com/NewGraphEnvironment/link/issues/172). Builds on v0.37.0's #168 decouple — with PG-state resume in place, the autonomy surface stays thin and the renames stay mechanical.

- **Single-command autonomous run.** `wsgs_run_pipeline.sh` (was `province_run.sh`) accepts `--wsgs=A,B,C`, `--config=<name>`, `--schema=<name>`, `--no-cyphers`, `--force`, forwards to `wsgs_dispatch.sh` (was `trifecta_provincial.sh`) which intersects the WSG subset in its LPT split. M4+M1-only baseline validated end-to-end: 16-WSG default-bundle dispatch lands 16/16 in `fresh_default.streams` on M4, ~20 min wall, no operator prompts.
- **Step 0 pre-clean.** When `--schema=` is set, umbrella fires `state_clean.sh --schemas=<schema>` on every host before Step 1. Drops only the target schema (skips the canonical-fresh heuristic + snapshot reload). Eliminates a class of consolidate failures where stale leftover WSGs on a source host collided with destination data during pg_restore.
- **Scoped `state_clean.sh` (was `province_clean.sh`).** New `--schemas=A,B,C` mode drops only the listed schemas. Empty `--schemas=` rejected loud to prevent dynamic-arg silent fall-through to the destructive default mode.
- **Phantom-cy + error-surface fixes in `wsgs_dispatch.sh`.** R's `paste0("cy", integer(0))` returns `"cy"` length-1 (constant recycling) — would put a non-existent cypher in the host plan under `--no-cyphers`. Three-branched `cy_host_keys`. Empty `CY_WORKSPACES` init via explicit `CY_WS_ARR=()` (was `read -r -a` yielding single-empty-element). `SPLIT_OUT=$(Rscript ...)` wrapped with explicit `||` block so R-side `stop()` messages reach the operator (e.g. `--wsgs=BOGUS` surfaces the R error verbatim instead of silent abort).
- **8 rename mapping (`git mv` preserves `git log --follow`).** Names now describe scope honestly — these scripts work for any list of WSGs / any host count / any reference:

| Old | New |
|---|---|
| `data-raw/province_run.sh` | `data-raw/wsgs_run_pipeline.sh` |
| `data-raw/province_clean.sh` | `data-raw/state_clean.sh` |
| `data-raw/province_progress.sh` | `data-raw/progress_check.sh` |
| `data-raw/trifecta_provincial.sh` | `data-raw/wsgs_dispatch.sh` |
| `data-raw/run_provincial_parity.R` | `data-raw/wsgs_run_host.R` |
| `data-raw/consolidate_schema.R` | `data-raw/schema_consolidate.R` |
| `data-raw/archive_provincial_runs.sh` | `data-raw/runs_archive.sh` |
| `data-raw/balance_provincial_buckets.R` | `data-raw/buckets_balance.R` |

The `wsg_*` (singular, per-WSG functions from #168) vs `wsgs_*` (plural, collection-level orchestrators) distinction is now load-bearing in the naming. `compare_bcfishpass_wsg.R → wsg_compare.R` was renamed in #168.

Filed-but-not-closed follow-ups: cypher integration testing (issue #172 Phase 2 + 3 acceptance — defer until M4+M1 baseline lands repeatably); LPT-fallback empty-bucket edge case when N_WSGs ≤ N_hosts without timing CSVs (pre-existing, not a #172 regression).

# link 0.37.0

Decouple bcfp comparison from the modelling pipeline. Closes [#168](https://github.com/NewGraphEnvironment/link/issues/168). The link package's deliverable — the per-WSG model in `<persist_schema>.streams` + per-species habitat + barriers — now runs and is observable independently of any comparison framework. Comparison vs bcfishpass (or any future reference) is a diagnostic overlay that reads the persisted state and never gates whether the model itself ran.

- New exported `lnk_pipeline_run(conn, aoi, cfg, loaded, schema, dams, cleanup_working)` — modelling-only umbrella over the 7 `lnk_pipeline_*` phases plus persist_init + barriers_unify + persist. Writes per-WSG segment data to PG. `lnk_barriers_unify` is promoted from gated-behind-with_mapping_code to always-on so `<persist_schema>.barriers` is canonical state for any future reader.
- New exported `lnk_compare_rollup(conn, aoi, cfg, reference, conn_ref, species)` — reads persisted state + reference DB, returns the long-format rollup tibble. Reference-agnostic via the `reference` arg (`"bcfishpass"` today). Species auto-discovered from PG via `information_schema` probe.
- `lnk_compare_wsg()` refactored as a thin wrapper over both new functions. Bundled behavior preserved for `with_mapping_code = TRUE` (mapping_code decoupling deferred — follow-up). Active-species set is now PG-state-derived (post-persist) rather than `cfg$species ∩ wsg_species_presence` (pre-persist); equivalent on a fresh single-call run, future-proofs callers against config drift.
- `data-raw/compare_bcfishpass_wsg.R` split into `data-raw/wsg_pipeline_run.R` (modelling) + `data-raw/wsg_compare.R` (compare). 4 callers updated to the explicit two-call pattern (`_targets.R`, `regress_dams_isolation.R`, `rule_flexibility_demo.R`, `run_provincial_parity.R`).
- `data-raw/run_provincial_parity.R` resume gate uses PG state as canonical: probes `<persist_schema>.streams` via internal `.lnk_wsg_persisted()`; RDS files are diagnostic side-artifacts that no longer silently mask an empty pipeline. Four-branch logic (force / fully-cached / compare-only / pipeline+compare). New `--force` CLI flag bypasses all caching. New helpers `.is_error_stub` (re-runs WSGs whose previous attempt failed) and `.rollup_has_mapping_code` (invalidates bare-rollup cache when the mapping_code lens is requested). Closes the 2026-05-14 incident where 4 of 16 WSGs were silently skipped due to stale error-stub RDS files.
- Phase 7 smoke matrix validates against live DB on DEAD WSG: empty state (57s pipeline+compare) → pipeline-cached (9s compare-only, ~6× speedup) → fully cached (2s skip) → `--force` (56s re-fire). Confirms the resume gate value and the decoupled boundary.

Filed-but-not-closed follow-ups: `lnk_compare_mapping_code` as its own family member (promotes the `with_mapping_code = TRUE` flag to a stand-alone export), `lnk_compare_wsg → lnk_compare_run` family rename, persist family naming pass, the 8 `data-raw/` script renames (stay in #172).

# link 0.36.1

Operational hardening from the 2026-05-13 → 2026-05-14 provincial dispatch session. No `R/` API changes — patches landed in `data-raw/` operational tooling. Closes [#171](https://github.com/NewGraphEnvironment/link/pull/171).

- `data-raw/trifecta_provincial.sh`: M1 reverse-forward tunnel (`ssh -R 63333:127.0.0.1:63333`) — M1 no longer needs its own (passphrase-protected) `db_newgraph` identity to reach bcfp. M4 idempotent inline-tunnel block. LPT fallback uses host_speeds-weighted alphabetical split when no `_per_wsg_times.csv` exists (was equal-split, ignored host_speeds). `HOST_SPEEDS` recalibrated to time-multiplier semantics: `m4=1.0,m1=0.79,cy=1.23` (larger=slower=fewer WSGs assigned). Calibrated from per-WSG medians on the 5-host 2026-05-13 dispatch.
- New `data-raw/province_run.sh` — top-level 10-step wrapper (pre-flight, snapshot, spin, prep, archive, smoke, dispatch, acceptance, consolidate, burn) with trap-EXIT cypher burn that fires regardless of mid-flight failure. Drafted ready for a `--smoke-only` regression-test mode in a follow-up.
- New `data-raw/province_clean.sh` — idempotent multi-host state wipe (kills `R --no-echo` + `Rscript` + `run_provincial`, drops `fresh` + `working_*` + `fresh_<bundle>*` schemas, reloads `fresh.modelled_stream_crossings` via `snapshot_bcfp.sh --force`). <5 min wall.
- New `data-raw/province_progress.sh` — mtime-based per-host progress probe. Cross-host TZ-glob hell solved by using `find -mmin -N` and `ls -t` (newest by mtime, not filename) — cypher logs use UTC, M4/M1 use local; date-globbing across hosts broke at TZ rollover.
- `research/post_compact_provincial_handoff.md` — tunnel architecture gotcha section (how each host reaches bcfp) + LPT fallback gotcha section.
- `planning/active/{task_plan,findings,progress}.md` — full PWF capture: 12 distinct gotchas surfaced during the session, including `pkill -f Rscript` missing the `R --no-echo` subprocess (caused concurrent dispatches), RDS-cache-skip in `run_provincial_parity.R`, stale cypher snapshot `fresh.*` data, M1 SSH key passphrase + Keychain-only unlock, and M4 PG over-tuning. Wrapper test strategy documented.

Follow-up issues filed (not closed here): [#167](https://github.com/NewGraphEnvironment/link/issues/167) tunnel autossh, [#168](https://github.com/NewGraphEnvironment/link/issues/168) decouple bcfp compare from pipeline, [#169](https://github.com/NewGraphEnvironment/link/issues/169) simplify `lnk_persist_init` after rtj#145, [#170](https://github.com/NewGraphEnvironment/link/issues/170) S3-based consolidate. Plus rtj#145 (rebuild cypher snapshot with fwa-dump tables ONLY) and fresh#199 (reopened — M4 PG over-tuning evidence).

Run result: 217-WSG BC stream network model in M4 `fresh` schema. Annotated parity CSV at `data-raw/logs/provincial_parity/20260514_0622_*_annotated.csv` — 91 `UNEXPLAINED` rows at `|diff_pct| >= 2%` (acceptance bar still not met; investigation queue for next session).

# link 0.36.0

Closes [#162](https://github.com/NewGraphEnvironment/link/issues/162). Lifts two scattered `data-raw/` scripts (linear rollup parity + per-segment mapping_code parity) into one package-level `lnk_compare_wsg()`, adds an annotated CSV pipeline (`lnk_parity_annotate()` against a YAML divergence taxonomy), modernizes the multi-host orchestrator to 5-host (M4 + M1 + N cyphers via tofu workspaces), and hardens the spin-up + smoke flow so failures fail loud + fail fast. Full per-phase summary: `planning/archive/2026-05-link162-lnk-compare-wsg-annotated-csv/README.md`.

- New exported `lnk_compare_wsg(conn, aoi, cfg, loaded, reference, with_mapping_code, ...)`. Per-WSG convenience wrapper around the existing `lnk_pipeline_*` phases. Returns `list(rollup, mapping_code)`. `reference = "bcfishpass"` only initially; `with_mapping_code = TRUE` adds the per-segment lens additive on top of the same network state (no double-pipeline). Defensive empty-merge handling for the 36 WSGs bcfp doesn't model (warning + NA-filled tibble, not error). `data-raw/compare_bcfishpass_wsg.R` collapses from 432 → 77 lines as a thin wrapper; `data-raw/compare_bcfp_mapping_code.R` deleted.
- New exported `lnk_parity_annotate(rollup, taxonomy, to, tolerance)`. First-match-wins lookup against `research/bcfp_divergence_taxonomy.yml`. Tags each rollup row with `taxonomy_id, class, mechanism, status, refs` columns. Unmatched rows: `class = UNEXPLAINED (|diff_pct| >= tolerance) | WITHIN_TOLERANCE | NOT_APPLICABLE`. Accepts both `ref_value` and `bcfishpass_value` column names. Optional CSV write.
- New `research/bcfp_divergence_taxonomy.yml` — single source of truth for known patterns. 11 entries covering Classes A (SETN stale), B (HORS fresh#158 bypass), C (SK new-geographies fresh#190/#191), D (BBAR + small 2026-05-11 residuals), MEASUREMENT_ASYMMETRY (lake/wetland centerline-vs-polygon).
- `data-raw/trifecta_provincial.sh` extended for M4 + M1 + N cypher workspaces (`--cy-workspaces=job1,job2,job3`). Inline greedy LPT bucket allocation (reads prior `_per_wsg_times.csv`, uses CLI `--host-speeds=m4=1.0,m1=0.83,cy=1.83` for projection + back-normalization — no feedback loop). Pre-flight version check across all hosts before dispatch. Post-pull aggregate annotation against the taxonomy. Empty-bucket guard. Cypher-side R log pull-back at run end so cross-repo log boundary doesn't hide errors. Truth-in-headline reports OK vs error-stub RDS counts (was misleading `N/N pulled`).
- `data-raw/trifecta_smoke.sh` rewritten as a 77-line shim over the production orchestrator — one small WSG per host (m4=DEAD, m1=ELKR, cyN=ADMS/BABL/BULL), passes `--fail-fast` automatically, asserts every smoke RDS is a successful tibble (not error stub) before declaring pass. Exits non-zero with clear message + pointer to the cypher R log when any WSG fails. "Smoke passed" now means every smoke WSG produced a valid tibble, not just "scripts exited 0".
- `data-raw/archive_provincial_runs.sh` — new helper. Moves prior-run `_per_wsg_times.csv` + `*.rds` + `*_annotated.csv` into `archive/<TS>/` so the LPT planner uses the most recent run only.
- `data-raw/balance_provincial_buckets.R` — dedup `(wsg, host)` and cross-host before LPT so multi-run CSV accumulation no longer double-assigns WSGs to buckets. Superseded for the N-host orchestrator (which computes LPT inline) but kept for standalone planning.
- `data-raw/consolidate_schema.R` — bucket-aware destination cleanup (`DELETE FROM <schema>.<table> WHERE watershed_group_code IN (<bucket>)` on each `watershed_group_code`-bearing table before pg_restore — prevents duplicate-key violations on re-consolidation). Pre/post row-count delta verification: `ok = TRUE` requires `count(*)` post-restore > pre-restore (NOT `pg_stat_user_tables.n_live_tup` which lags asynchronously).
- `lnk_persist_init(force_recreate = FALSE)` — new flag + DDL drift detection via `.lnk_validate_persist_table()`. Errors loud when an existing target table has unexpected `GENERATED ALWAYS` columns (catches cypher snapshots baked when `fresh::frs_col_generate()` had been run on `fresh.streams`). `force_recreate = TRUE` DROPs+recreates with correct DDL. 6 new tests cover detection, force-recreate, no-op, and arg validation.
- `data-raw/run_provincial_parity.R` — `--with-mapping-code` flag passthrough; new `--fail-fast` flag (default FALSE preserves soft-fail for full provincial runs; smoke runner injects it automatically so WSG #1 failure on a host stops the loop instead of confirming the same failure 30 more times); post-loop annotation step writes `<TS>_<host>_annotated.csv`.
- Updated `research/provincial_run_runbook.md` for the 5-host flow + smoke-first cadence + DDL drift handling. The runbook is now the operational source of truth; `data-raw/README.md#provincial-dispatch` is the CLI reference.
- 2026-05-12 → 13 live provincial run results in `research/provincial_parity_2026_05_12.md`. Acceptance bar (zero `UNEXPLAINED` at `|diff_pct| >= 2%`) NOT YET MET (56 surviving UNEXPLAINED rows; 93 cypher WSGs lost to DDL drift now fixed by `lnk_persist_init` hardening — next provincial run should hit 217/217 OK and provide the full picture). Operational lessons documented in `planning/archive/2026-05-link162-lnk-compare-wsg-annotated-csv/findings.md`.

Filed follow-up: [#163](https://github.com/NewGraphEnvironment/link/issues/163) — adaptive `host_speeds` learning from observed wall times (LPT refinement; currently uses static CLI defaults).

# link 0.35.1

* `data-raw/snapshot_bcfp.sh`: replace `grep -qi parquet` with `grep -i parquet > /dev/null` in the Parquet prereq check ([#160](https://github.com/NewGraphEnvironment/link/issues/160)). Under `set -euo pipefail`, `grep -q` closes the pipe on first match, `ogr2ogr` gets SIGPIPE (exit 141), `pipefail` propagates, `!` flips it, and the script FATALs even though the Parquet driver IS present. Originally chased as a non-interactive ssh / conda env issue (NewGraphEnvironment/rtj#129) — that was a misdiagnosis; PATH from rtj#66/#123 was always correct.

# link 0.35.0

Closes [#152](https://github.com/NewGraphEnvironment/link/issues/152). New unified province-wide `<persist_schema>.barriers` table with a pre-computed `blocks_species text[]` predicate. Closes the cross-WSG `dam_dnstr_ind` defect — PARS BT mapping_code parity jumped from 60.64% → 98.63% (+38 pp) because dam barriers in upstream-of-PARS WSGs (Bennett in PCEA, Peace Canyon / Site C in UPCE) now resolve correctly via FWA-topology walks over the province-wide table. Other Phase A WSGs maintained ≥99% across all species (full 6-WSG matrix in `research/bcfp_compare_mapping_code.md`).

- New exported `lnk_barriers_unify(conn, aoi, cfg, loaded, schema)`. Consolidates four per-WSG barrier source families into `<schema>.barriers`: anthropogenic (PSCIS / CABD / MODELLED_CROSSINGS with `barrier_status IN ('BARRIER','POTENTIAL')`), gradient (per-class, `blocks_species` derived from `parameters_fresh$access_gradient_max`), falls, and opt-in subsurface_flow. Per-source `id_barrier` namespacing keeps rows unique within a WSG without coordinating sequence IDs (anthropogenic = `aggregated_crossings_id`; others get `<SOURCE>-<rownum>` text prefixes).
- New exported `lnk_barriers_views(conn, schema, cfg)`. Emits per-species (`<schema>.barriers_<sp>_unified` for the 8 mapping_code species) + per-source (`<schema>.barriers_{anthropogenic,pscis,dams}_unified`) `CREATE OR REPLACE VIEW`s over `<persist_schema>.barriers`. Each view re-exposes `id_barrier AS barriers_<x>_unified_id` so the existing `lnk_pipeline_access` `feature_id_col = "<table>_id"` convention works unchanged. `_unified` suffix avoids name collisions with the per-WSG tables `.lnk_pipeline_prep_minimal` + `lnk_barriers_emit` already build (those stay — they're useful primitives).
- `lnk_persist_init()` extended with `cols_barriers` DDL: 13 columns, PK on `(id_barrier, watershed_group_code)`, GIN index on `blocks_species`, btree indexes on `(watershed_group_code, barrier_source)` and `(blue_line_key, downstream_route_measure)`, GIST on `geom`.
- `lnk_pipeline_persist()` extended with a `<schema>.barriers` → `<persist_schema>.barriers` DELETE-WHERE-WSG + INSERT branch (gated on staging-table presence so older orchestrators that don't yet call `lnk_barriers_unify` keep working without behaviour change).
- `data-raw/compare_bcfp_mapping_code.R`: `barrier_sources$anthropogenic` + `barrier_sources$dams` now point at the unified views. `barriers_per_sp` keeps the bcfp-tunnel staging fallback (the unified-table `blocks_species` predicate doesn't encode per-species minimal-position semantics — that's a separate scope expansion).



Closes [#154](https://github.com/NewGraphEnvironment/link/issues/154). `lnk_pipeline_crossings()` now reproduces bcfp's PSCIS-to-modelled auto-snap layer byte-identically via the fresh primitive composition (`lnk_points_snap(num_features = 5L)` + `fresh::frs_candidates_pick()` + bcfp-shape scoring/dedup SQL). Phase A `mapping_code` parity hits ≥99% on every in-WSG species across ADMS, BULK, WILL, PARS — BULK jumped ~80% → ~99.5%, WILL ~86% → ~99.7%. PARS BT 60% remains cross-WSG `dam_dnstr` territory (tracked under [#152](https://github.com/NewGraphEnvironment/link/issues/152)).

- New private helper `.lnk_pipeline_pscis_build(conn, aoi, schema, loaded, …)` mirrors bcfp's `02_pscis_streams_150m.sql` + `04_pscis.sql` at `smnorris/bcfishpass@v0.7.14-125-g6e9cf1c`. Five-step composition: multi-stream snap → enrich + score (`name_score`, `width_order_score`) → b-side modelled-collision dedup → per-PSCIS pick via `frs_candidates_pick` + AOI filter + DBSCAN 5m cluster + UNIQUE(blue_line_key, downstream_route_measure) dedup → xref-driven INSERT (two-branch UNION ALL: `modelled_crossing_id` lookup vs `linear_feature_id` lookup, mirroring `referenced_modelled_xing` + `referenced_streams` CTEs). `lnk_pipeline_crossings()` now calls this helper in place of the bare `lnk_points_snap()`; minimum `snap_tolerance` clamped to 150 m to match bcfp.
- `lnk_points_snap()`: bug fix in the segment-offset `downstream_route_measure` formula. Previous form `ST_LineLocatePoint * ST_Length(s.geom)` computed position WITHIN the candidate segment, not the absolute drm on the blue line. Now adds `+ s.downstream_route_measure` and uses `s.length_metre` with `GREATEST/LEAST/FLOOR/CEIL` clamping per bcfp's pattern. New `num_features = 1L` arg (backwards-compatible) returns up to N candidate streams per input point for downstream scoring workflows.
- `.lnk_crossings_union`: modelled branch now LEFT JOINs `<schema>.crossing_fixes` (staged `user_modelled_crossing_fixes`) and filters `WHERE cf.structure IS NULL OR cf.structure = 'OBS'` — bcfp parity with `load_crossings.sql:634`. Without this filter, 275 NONE-fixed modelled crossings leaked through in BULK / 103 in WILL, breaking per-segment `mapping_code` parity for non-wct species. PSCIS branch now reads from `<schema>.pscis` (the canonical output of `.lnk_pipeline_pscis_build`); modelled-branch xref exclusion sources from the same table.



Closes [#148](https://github.com/NewGraphEnvironment/link/issues/148). Wednesday-morning sync chain shifted earlier so a fully-fresh local fwapg lands before workday-start, and `data-raw/snapshot_bcfp.sh` is now schedulable per host without manual install gymnastics.

- `.github/workflows/sync-bcfishpass-csvs.yml` cron: Wed 6 AM PDT (13:00 UTC) → Wed 4 AM PDT (11:00 UTC). Runs 1 h after the upstream dump in `NewGraphEnvironment/db_newgraph#7` (which itself shifted to Wed 3 AM PDT).
- New exported `lnk_baseline_current(log, host, path)` predicate. Returns `TRUE` when this host's most-recent `data-raw/logs/bcfp_baselines.csv` row already stamps the upstream `bcfp_model_version` carried in `log`. Per-host scoped — M4 stamping a SHA must not gate M1 from snapshotting its own fwapg.
- `data-raw/snapshot_bcfp.sh` updates: self-anchors to repo root via `cd "$(dirname "$0")/.."` (so cron-default `$HOME` cwd doesn't break the relative ledger path); skip-guard runs FIRST via `lnk_baseline_current()` before any DB-credential resolution (a host with a stale env file can skip cleanly when this week's ledger already matches); sources `~/.config/snapshot-bcfp.env` for per-host `DATABASE_URL` / `PG*` vars; xtrace removed from `set -euxo pipefail` → `set -euo pipefail` to keep credentials out of `~/.local/state/snapshot-bcfp/*.log`.
- New `data-raw/scheduler/` directory with launchd plist (`com.newgraph.snapshot-bcfp.plist` for M4 + M1, fires Wed 5 AM local), Linux crontab line (`snapshot-bcfp.cron` for cypher, `0 12 * * WED` UTC), and `README.md` documenting per-host install + uninstall + env file format.

# link 0.32.1

Post-merge `/code-check` follow-up on `#138` (v0.32.0). Three fragility fixes (no behaviour change for valid inputs) plus a stashed snapshot-script fix:

- `.lnk_crossings_union`: cast `modelled_crossing_id` to `bigint` before adding `1e9` so values past int4 max can't overflow. Override path (`.lnk_crossings_apply_overrides`) already did this; the union branch matches now.
- `.lnk_crossings_union`: switch CABD + modelled FWA joins from `LEFT JOIN` to `INNER JOIN`. Missing `linear_feature_id` (FWA refresh drift) previously NULL'd `watershed_key` and the row got silently dropped much later by `barriers_emit`'s `blue_line_key = watershed_key` filter — drop at the union step instead so the count discrepancy is observable upstream.
- `lnk_points_snap`: pre-flight check on input columns. `pts.*` would otherwise produce a `CREATE TABLE AS` error from a column-name collision deep in a 100-line statement; now errors out with a clear list of colliding columns before any DDL runs.
- `data-raw/snapshot_bcfp.sh`: `bcdata bc2pg --refresh` requires the target table to already exist — drop-then-load instead so first-time snapshots succeed.

# link 0.32.0

Closes [#138](https://github.com/NewGraphEnvironment/link/issues/138). New `lnk_pipeline_crossings()` builds `<schema>.crossings` + `<schema>.barriers_*` from public-source primitives (BCDC PSCIS via `bcdata bc2pg`, CABD via the public API, bchamp `modelled_stream_crossings.gpkg.zip`) — no tunnel, no `bcfishpass.barriers_*` reads. Phase B of the self-sufficiency roadmap (`#117` csv-sync + `#137` snapshot script were Phase A).

Four new exports — three are generic enough that they may relocate to a future `pac` package once that's scaffolded:

- `lnk_inputs_verify(conn, required)` — fail-loud existence check for `<schema>.<table>` preconditions. Single round-trip via `information_schema.tables`.
- `lnk_points_snap(conn, table_in, table_out, ...)` — bulk lateral-KNN snap to FWA. Wraps the same `CROSS JOIN LATERAL ... ORDER BY <-> ... LIMIT 1` pattern used by bcfp's `load_dams.sql` and link's existing CABD path. One SQL round-trip; scales province-wide. Handles MultiPoint inputs via `ST_GeometryN(..., 1)`.
- `lnk_barriers_emit(conn, schema)` — emits `<schema>.crossings_lookup` (slim id + statuses projection) plus four `<schema>.barriers_*` tables (`anthropogenic`, `pscis`, `dams`, `remediations`). Filters mirror bcfp's `model/01_access/sql/barriers_*.sql` and `remediations_barriers.sql`.
- `lnk_pipeline_crossings(conn, aoi, cfg, loaded, schema, snap_tolerance, pscis_table, modelled_table, dams_table)` — exported pipeline phase. Composes input verification + PSCIS snap + source-precedence union + override application + barriers emit. Source tables configurable via the `*_table` args.

Lean column set: only what `lnk_barriers_emit()` consumes — `aggregated_crossings_id`, `crossing_source`, `crossing_feature_type`, `barrier_status`, `pscis_status`, `dam_name`, network position columns, geom. Drops bcfp's road tenure / FTEN / OGC / rail / UTM metadata that downstream non-barrier consumers need.

Live ADMS smoke against local fwapg loaded with `data-raw/snapshot_bcfp.sh` (link#137): 67 PSCIS + 3,584 modelled = 3,651 crossings unioned in <1s; barriers_emit produces 3,616 anthropogenic / 33 PSCIS / 5 remediations.

Tests: 94 new mocked unit-test expectations across the four exports + two internal helpers (`.lnk_crossings_union`, `.lnk_crossings_apply_overrides`). 903 PASS / 0 FAIL total.

# link 0.31.1

Closes [#137](https://github.com/NewGraphEnvironment/link/issues/137). New `data-raw/snapshot_bcfp.sh` shell script loads bcfp dependencies into a local Postgres from public sources only — no SSH tunnel, no DB pg_dump. Prepares the local fwapg for `lnk_pipeline_crossings()` (link#138, in flight) and parity comparisons.

- BCDC PSCIS via Python `bcdata bc2pg --refresh` → `whse_fish.pscis_*` (4 tables).
- CABD dams via `ogr2ogr` from CABD's public GeoJSON API → `cabd.dams`.
- bchamp `modelled_stream_crossings.gpkg.zip` via `curl` + `ogr2ogr` → `fresh.modelled_stream_crossings`.
- bchamp `observations.parquet` via `ogr2ogr /vsicurl/...` → `bcfishobs.observations` (same artifact bcfp's `jobs/load_observations` consumes).
- Optional `--with-bcfp-views`: pulls Simon's bcfp output views (`crossings_vw`, `streams_vw`) from `s3://newgraph/` for parity comparison.
- Stamps `data-raw/logs/bcfp_baselines.csv` with the bcfp build identifier from `s3://fresh-bc/bcfishpass/log.json` via `lnk_baseline_append()`.

Documented in `data-raw/README.md` under a new `## Bootstrap` section.

# link 0.31.0

Closes [#117](https://github.com/NewGraphEnvironment/link/issues/117). csv-sync flips from GitHub-API SHA-walking to reading from `s3://fresh-bc/bcfishpass/` (populated weekly by NewGraphEnvironment/db_newgraph). Cadence drops from daily to weekly Wed afternoon. Eliminates the 1–7 day drift between bundle CSVs and the upstream tunnel rebuild SHA.

Four new exports support csv-sync + downstream parity drivers + future multi-build comparison (grayling / rainbow / ko / etc.):

- `lnk_bucket_get(name, prefix, to)` — fetch any artifact from a versioned S3 prefix. Returns raw bytes by default (caller decodes — `read.csv()`, `jsonlite::fromJSON()`, `arrow::read_parquet()`); writes to disk when `to` is supplied. Default prefix is NGE's bcfp dump. Format-agnostic.
- `lnk_bucket_log(prefix)` — sugar for the most common read: parses `<prefix>/log.json` into a list with `model_version`, `date_completed`, `head_sha`. Validates required keys.
- `lnk_baseline_read(path)` — read the run-tracking ledger (`data-raw/logs/bcfp_baselines.csv` by default) as a tibble. Validates `cols_baseline` shape on read.
- `lnk_baseline_append(log, run_label, ...)` — append a stamped row from a `lnk_bucket_log()` result. Used by csv-sync to record which build each sync ran against; reusable by parity-run drivers.

`data-raw/sync_bcfishpass_csvs.R` rewritten to consume the new exports; integrates a `crate::crt_schema_validate()` gate for provenance entries with `canonical_schema:` declared (escalates `drift_kind` to `"shape"` on validation failure).

httr + jsonlite added to `Imports`.

# link 0.30.2

Closes [#135](https://github.com/NewGraphEnvironment/link/issues/135). `lnk_pipeline_access()` now computes `dam_dnstr_ind` and (optionally) `remediated_dnstr_ind` from the same primitives that drive the per-species access codes, eliminating the bcfp-merge-in step needed for full BT/WCT parity in 0.30.0. Both `lnk_pipeline_access()` and `lnk_pipeline_mapping_code()` consume the new `lnk_presence()` helper (v0.30.1) to short-circuit absent species cleanly.

- `dam_dnstr_ind` is sequence-aware: TRUE iff the next-downstream anthropogenic barrier is also a dam. Mirrors bcfp's `array[barriers_anthropogenic_dnstr[1]] && barriers_dams_dnstr` overlap check. Both `barriers_anthropogenic` and `barriers_dams` populate their primary key from `crossings.aggregated_crossings_id`, so the IDs returned by `frs_network_features` are in a shared space and `%in%` works directly. ADMS parity vs `bcfishpass.streams_access.dam_dnstr_ind`: 11803 FALSE / 3960 TRUE, zero off-diagonal differences.
- `lnk_pipeline_access()` gains an optional `crossings_table = NULL` arg. When supplied alongside `barrier_sources$remediations`, computes `remediated_dnstr_ind` per the bcfp-intended logic — TRUE iff the next-downstream remediation is a crossing where `pscis_status = 'REMEDIATED' AND barrier_status = 'PASSABLE'`.
- bcfp's own `streams_access.remediated_dnstr_ind` is FALSE for every row in the build due to a 2-year-old contradictory clause in `load_streams_access.sql` (introduced by [smnorris/bcfishpass#339](https://github.com/smnorris/bcfishpass/pull/339) and inlined in v070 by [smnorris/bcfishpass#690](https://github.com/smnorris/bcfishpass/pull/690)). link computes the bcfp-intended dual-column semantics so `mapping_code_<bt|wct>` may emit `REMEDIATED` tokens where bcfp's current output emits `DAM` / `MODELLED` / `ASSESSED`. Upstream fix filed as [smnorris/bcfishpass#891](https://github.com/smnorris/bcfishpass/issues/891) + [smnorris/bcfishpass#892](https://github.com/smnorris/bcfishpass/pull/892).
- `lnk_pipeline_access()` and `lnk_pipeline_mapping_code()` accept an optional `presence` arg (an `lnk_presence` object). When supplied, absent species short-circuit cleanly: `lnk_pipeline_access` skips the `frs_network_features` query and emits `access_<sp> = -9`; `lnk_pipeline_mapping_code` emits `""`. Eliminates the salmon-group-absent over-emission caught in the multi-WSG sweep on ELKR + HORS.
- ADMS validation, no bcfp merge-in: `mapping_code_bt` 15733/15763 (30 REMEDIATED divergences, all the bcfp v070 regression), `mapping_code_ch/cm/co/pk/sk` 15761/15763 (2 each), `mapping_code_st/wct` 15763/15763. Stamped logs under `data-raw/logs/<TS>_link135_parity_*.txt`.

# link 0.30.0

Closes [#124](https://github.com/NewGraphEnvironment/link/issues/124). Reproduces bcfishpass's three classification surfaces (`crossings.barrier_status`, `streams_access`, `streams_mapping_code`) as additive layers — link's existing `severity` and 5-bucket `mapping_code` are unchanged.

- **`lnk_pipeline_access(conn, segments, aoi, ...)`** — composes [`fresh::frs_network_features()`](https://github.com/NewGraphEnvironment/fresh/blob/main/R/frs_network_features.R) (fresh 0.29.0+) calls across species + observations into a `streams_access`-shape wide tibble. Per-segment per-species `access_<sp>` integer codes (`-9 / 0 / 1 / 2`) for absent / blocked / modelled / observed. Caches per-table dnstr queries — 5 species pointing at one grouped barriers table run the SQL once. Auto-NA propagation when a barriers source has zero rows in the AOI mirrors bcfp's `barriers_<sp>_dnstr IS NULL` semantics for absent species.
- **`lnk_pipeline_mapping_code(access, habitat, feature_code, ...)`** — pure R derivation over the bcfp-shape access columns. Resident-flavor (BT, WCT) vs anadromous-flavor (CH/CM/CO/PK/SK/ST) handling for `mapping_code_barrier`. Spawn-only species (CM, PK) emit only `ACCESS` / `SPAWN` token1 (no REAR per bcfp). `feature_code = "GA24850150"` flags `INTERMITTENT`. Optional `to=` arg writes `<schema>.streams_mapping_code` for downstream views.
- **ADMS parity validation: 15762 / 15762 byte-identical to `bcfishpass.streams_mapping_code` for all 8 species** (BT, CH, CM, CO, PK, SK, ST, WCT). Per-species `access_<sp>` ≥99% match (1-row totals diff + ~13-row obs/modelled drift attributable to bcfp's life_stage / activity / point_type observation filters not yet applied in link).
- **`barrier_status` (Phase 1)** — already populated correctly by `lnk_pipeline_load` via `.lnk_pipeline_apply_fixes` + `.lnk_pipeline_apply_pscis`. Roxygen note added distinguishing `barrier_status` (bcfp-parity, PSCIS-field + CSV override) from `severity` (link's culvert-geometry scoring). Both can coexist on the same crossings row.
- **`build_species_views.R --bcfp`** sibling view per species — `streams_<sp>_bcfp_vw` carries the bcfp-shape `mapping_code_<sp>` string for QGIS A/B comparison against the existing `streams_<sp>_vw` (link's 5-bucket categories). Both views co-exist; symbology hint covers each.
- **`scripts/update_hosts.sh`** — pak-bug-bypass updater for trifecta hosts. Uses `R CMD INSTALL` from a GitHub source tarball, sidesteps [r-lib/pak#658](https://github.com/r-lib/pak/issues/658) which mis-reports cypher's permission-denied installs as "empty archive" when the user's first `.libPaths()` entry isn't writable.
- **`data-raw/trifecta_provincial.sh`** — `--rds-dir=` pass-through arg for recovery runs that need to bypass the resume RDS cache (e.g. running cypher's bucket on M4 after cypher destroy).
- Caveat for full BT/WCT parity: `mapping_code_<bt|wct>` uses bcfp's pre-computed `dam_dnstr_ind` / `remediated_dnstr_ind` via merge-in. Computing those from link primitives requires sequence-aware "next downstream barrier IS a dam" logic — tracked as a follow-up issue. Anadromous species + non-resident BT/WCT in non-overlap WSGs are byte-identical without the merge.

# link 0.29.1

Closes [#121](https://github.com/NewGraphEnvironment/link/issues/121). Auto-stamps the bcfp comparison reference (`model_run_id` + version SHA + completion timestamp) into `data-raw/logs/bcfp_baselines.csv` from inside `data-raw/run_provincial_parity.R`. Tuesday weekly `bcfishpass.*` rebuilds shift the comparison reference; un-stamped runs were ambiguous after the fact. Orchestration tooling only — no public R API changes.

- New inline `stamp_bcfp_baseline()` helper in `data-raw/run_provincial_parity.R`, called once per invocation between the per-WSG-timings setup and the WSG loop. Same wiring covers single-host and trifecta-dispatched per-host runs.
- `data-raw/logs/bcfp_baselines.csv` gains a `host` column between `run_started_pdt` and `run_label`. Three existing rows backfilled to `host=m4` (single-host M4 runs). Trifecta runs now produce three rows per run, one per host, all with the same `bcfp_model_run_id`.
- Host alias resolves via `LNK_HOST_ALIAS` env var (e.g. `LNK_HOST_ALIAS=m4` in `~/.Renviron`); falls back to `Sys.info()[["nodename"]]` when unset.
- Tunnel-tolerant: connection failure or unset `PG_PASS_SHARE` logs a warning and the build proceeds (per-WSG comparisons further down would fail too if the tunnel were genuinely broken, so the stamp is not the actual blocker). Idempotent on `(host, link_schema, bcfp_model_run_id, run_started_pdt)` — same-minute re-runs (resume scenarios) skip silently rather than duplicate.

# link 0.29.0

Closes [#118](https://github.com/NewGraphEnvironment/link/issues/118). DB hygiene to prevent the disk-full incident that crashed cypher's `fresh-db` container during the 2026-05-04 `default_extrabreaks` provincial trifecta. Two-tier orchestrator-level cleanup; no in-package API changes.

- `compare_bcfishpass_wsg()` gains `cleanup_working = TRUE` parameter — drops `working_<aoi>` schema after the rollup tibble is built. Default-on; pass `FALSE` for interactive debug. Saves ~10–15 GB per provincial run on every host (60+ working schemas accumulated otherwise).
- `consolidate_schema()` gains `keep_source = FALSE` parameter — drops source schema on each remote host after a successful pg_restore. Default-on; rc-guarded (failed restore leaves source for retry); warn-but-don't-fail on drop rc != 0. Saves ~25–30 GB per consolidated bundle on M1 + cypher.
- `data-raw/README.md` documents per-worker disk capacity: rough footprints (~30 GB single-bundle persistent + 10–15 GB per-WSG scratch + 30–40 GB fwapg base), 60 GB minimum free recommendation, 2026-05-04 cypher incident as cautionary tale.
- Bit-identical bcfp parity by default. ADMS rollup tibble post-cleanup `identical()` to pre-cleanup baseline (RDS file metadata differs but deserialized object is identical).
- Approach: orchestrator-level cleanup, NOT in-package — `lnk_pipeline_persist` stays scoped to one job; the rollup query reads working schema in long-form AFTER persist returns, so the natural lifecycle owner is the orchestrator script.

# link 0.28.0

Orphan-class break source — fed-vector experiments now Just Work without a separate knob. When `cfg$pipeline$gradient_classes` (or the caller's `classes` arg) contains thresholds below every modelled species's `access_gradient_max`, those positions enter `gradient_barriers_minimal` as a `barriers_orphan` table — no per-species filter, no minimal reduction (every detected position splits the network for segmentation precision). Access semantics are unaffected: fresh's per-species access label filter at classify time rejects any `gradient_NNNN` label below the species's threshold, so orphan classes never block any species.

- New experimental bundle `inst/extdata/configs/default_extrabreaks/` extends `default` with `pipeline.gradient_classes` set to the union of access (0.15/0.20/0.25) + per-species spawn / rear gradient maxima from fresh's `parameters_habitat_thresholds.csv` (0.0249–0.1049). Persists to `fresh_default_extrabreaks` schema for side-by-side compare against the `fresh_default` reference.
- ADMS smoke test on the bundle: BT spawning **+11.2 km (+3.1 %)** vs default-bundle baseline; SK spawning **+13.9 km (+6.4 %)**; RB spawning **+8 km (+2.6 %)**. Rear shifts much smaller (±5 km). Effect is the "ceiling sub-segment" mechanism: when a generally-flat reach is broken at a low spawn/rear gradient threshold, the steep pocket separates and the remaining majority averages to a lower local gradient that newly passes the per-segment spawn predicate.
- Provincial run: `./trifecta_provincial.sh --config=default_extrabreaks --schema=fresh_default_extrabreaks` (~2.5h wall, same shape as the v0.26.0 default trifecta).
- Bit-identical to v0.27.0 on bcfp + default config (no orphans — both default vectors live at-or-above each species's access threshold). Suite: 735 PASS / 0 FAIL.

# link 0.27.0

Closes [#45](https://github.com/NewGraphEnvironment/link/issues/45). Two coupled hardcodes in `R/lnk_pipeline_prepare.R` — the bcfishpass gradient class break vector and the per-model class filter list — are now configurable. Unblocks alternative-methodology experiments that need different break thresholds (e.g. breaking the network at the union of unique per-species rearing/spawning/access gradient values, or finer 0.05-step bins) while preserving bit-identical bcfishpass parity by default.

- `lnk_pipeline_prepare()` gains a `classes` argument — a named numeric vector of gradient class break thresholds. When `NULL`, falls back to `cfg$pipeline$gradient_classes` if set in the bundle, otherwise to the bcfishpass default `c("1500" = 0.15, "2000" = 0.20, "2500" = 0.25, "3000" = 0.30)`. Optional `pipeline.gradient_classes` knob documented (commented-out) in `bcfishpass/config.yaml` and `default/config.yaml`.
- `.lnk_pipeline_prep_minimal()` replaces the hardcoded per-model `models` list with per-species derivation: for each species in `cfg$species` (with `loaded$parameters_fresh$species_code` fallback), classes whose value is `>= access_gradient_max` form that species's barrier filter. Per-species barrier tables become `barriers_<sp>` (lowercase species code, validated). Species with NA / zero / missing `access_gradient_max` are skipped.
- Bit-identical bcfp parity verified on ADMS/HARR/BABL/BULK (same digests as pre-#45 baseline). Override mechanism end-to-end demonstration: dropping the 0.25 break on ADMS expands BT habitat ~30% (BT@0.25 loses its barrier filter when no class >= 0.25 exists), CH/CO/SK unchanged.
- Empty species set (no presence-flagged species + no override) yields a structurally valid empty `gradient_barriers_minimal` table so downstream phases find the expected name. Defensive `sp_amax[1L]` handles the (unlikely) case of duplicate `species_code` rows in `parameters_fresh.csv` — would otherwise trip R 4.3+ length-1 enforcement on `||`.
- 5 new + 2 updated mocked tests (`prep_gradient` classes threading; `prep_minimal` per-species derivation, skip path, custom-vector path; `.lnk_resolve_classes` precedence; YAML→R round-trip through `lnk_config()`). Full suite: 728 PASS / 0 FAIL.

# link 0.26.0

Closes [#112](https://github.com/NewGraphEnvironment/link/issues/112). Per-WSG output now persists into province-wide `<schema>.streams` + `<schema>.streams_habitat_<sp>` tables, mirroring bcfp's `bcfishpass.streams` + `bcfishpass.habitat_linear_<sp>` pattern. Queryable across WSGs for cartography, intrinsic-potential maps, per-crossing rollups, and methodology comparisons — no more re-running 232 WSGs to look at one.

- New `lnk_persist_init(conn, cfg, species)` — idempotent `CREATE SCHEMA IF NOT EXISTS` + `CREATE TABLE IF NOT EXISTS` for the persistent tables. DDL driven by `cols_streams` (21 columns mirroring bcfp.streams + link's `id_segment`) and `cols_habitat` (7 columns: id_segment + watershed_group_code + 5 booleans accessible/spawning/rearing/lake_rearing/wetland_rearing). `geom geometry(MultiLineStringZM, 3005)` — FWA streams are XYZM (X, Y, elevation, measure).
- New `lnk_pipeline_persist(conn, aoi, cfg, species, schema)` — DELETE-WHERE-WSG + INSERT for streams + per-species streams_habitat_<sp>. Long→wide pivot: per-species INSERT filters `working_<aoi>.streams_habitat WHERE species_code = '<sp>'` and projects `cols_habitat` (drops species_code from SELECT). Idempotent re-runs replace cleanly.
- Pipeline rewire: per-WSG segment-level data (`streams`, `streams_habitat`, `streams_breaks`) now lives in `working_<aoi>` (the per-WSG schema where every other staging table already lived) instead of the previously-shared `fresh` schema. ~12 hardcoded literals updated across `lnk_pipeline_prepare/break/classify/connect` + `compare_bcfishpass_wsg.R`.
- New `pipeline.schema` config knob (REQUIRED, default `fresh`) — enables side-by-side bundle compare (`schema: fresh_bcfp` vs `schema: fresh_default`), within-host parallelism (`schema: fresh_w1`/`fresh_w2`), branch isolation, centralized vs distributed write target.
- `compare_bcfishpass_wsg.R` orchestrator now calls `lnk_persist_init` + `lnk_pipeline_persist` after `lnk_pipeline_connect`.
- Trifecta provincial run end-to-end (M4 + M1 + cypher, ~2h wall, pg_dump consolidation onto M4): **217 WSGs / 5.3M segments** persistently in `fresh.streams`. 5/5 test WSG rollups byte-identical to pre-#112 baseline (LRDO/SETN/ADMS/BULK/HARR on SK spawn+rear+lake).
- New tests: `test-lnk_persist_init.R` (28), `test-lnk_pipeline_persist.R` (4). Updated 3 stale literal-string assertions in `test-lnk_pipeline_prepare.R` + `test-lnk_pipeline_classify.R`. Full suite: 710 PASS / 0 FAIL.
- Removed `data-raw/run_nge.R` — superseded by `compare_bcfishpass_wsg(wsg, lnk_config("default"))`.

# link 0.25.1

Pre-trifecta config homework — catches staleness in the config layer before the 3-host distributed run, so we're not chasing ghosts later.

- Both bundles' `rules.yaml` regenerated via `lnk_rules_build()` (date-stamp diff only — semantically identical to what was committed).
- `provenance:` checksums recomputed in both `config.yaml` for the 4 files modified across v0.21–v0.25 (rules.yaml, dimensions.csv, parameters_fresh.csv, overrides/wsg_species_presence.csv). `lnk_config_verify` now reports drifted = 0 / 12 for both bundles.
- Closes [#108](https://github.com/NewGraphEnvironment/link/issues/108) — `compare_bcfishpass_wsg` returns `bcfishpass_value = NA` (not 0) when bcfp doesn't model a species. Distinguishes "real measured zero" from "not modelled by bcfp"; `diff_pct` cleanly resolves to NA. PARS run proves GR / KO / RB classify end-to-end on the default bundle (KO 377 ha lake-rearing, RB 1,839 ha lake + 7,796 ha wetland, GR 1,566 ha lake).
- `compare_bcfishpass_wsg` adds a `species` filter parameter — pass `c("BT","CH",…)` to drop GR/KO/RB from the rollup entirely.
- 4 stale tests in `test-lnk_rules_build.R` updated for the `stream_order` → `stream_order_min`/`stream_order_max` rename (fresh#198) and the per-species `in_waterbody` semantics. Full suite: 668 PASS / 0 FAIL.
- New `data-raw/audit_configs.R` reports drift across all layers — re-runnable before any trifecta or provincial run.

# link 0.25.0

Closes [#106](https://github.com/NewGraphEnvironment/link/issues/106). Drops the hardcoded species-presence column list in `lnk_pipeline_species` + `lnk_pipeline_break` — both now derive the column list from the `wsg_species_presence.csv` header via the new `.lnk_wsg_species_present()` helper. Adding a new species column propagates to every callsite without a code edit.

- Adds `ko` (Kokanee) column to both bundles' `wsg_species_presence.csv` with sentinel `t` for PARS, KOTL, NATR, CARP — interim until upstream `bcfishpass.wsg_species_presence` ships authoritative coverage (NewGraphEnvironment/bcfishpass#12).
- Adds GR + KO species rows to `default/parameters_fresh.csv` (already in `default/dimensions.csv` and `rules.yaml`).
- New tests assert column-propagation for newly-added species and `notes`-column ignoring.

# link 0.24.0

Closes [#103](https://github.com/NewGraphEnvironment/link/issues/103). Ingests CABD dams as a parallel reporting dimension. `.lnk_pipeline_prep_dams()` replicates bcfishpass's `model/01_access/sql/load_dams.sql` against the `cabd.dams` source over the db_newgraph tunnel and writes `<schema>.dams` mirroring `bcfishpass.dams` column-for-column. Both `bcfishpass` and `default` bundles ingest — the data is methodology-agnostic at the data layer.

- New optional `conn_tunnel = NULL` arg to `lnk_pipeline_prepare()`. When NULL, `prep_dams` short-circuits to `DROP TABLE IF EXISTS <schema>.dams` — zero-cost opt-out for CI / non-reporting workflows.
- Four CABD edit CSVs (`cabd_exclusions`, `cabd_blkey_xref`, `cabd_passability_status_updates`, `cabd_additions`) ship in both bundles' `overrides/` and are loaded through `lnk_load_overrides()` like any other override.
- **Habitat output is unchanged.** `<schema>.dams` and `<schema>.cabd_*` are not consumed by any break / classify / connect phase. HARR dams-ON / dams-OFF rollup is byte-identical to fp precision; confirms the parallel-data invariant.
- LFRA verification: 65 dams / 59 barriers / 15 named, with Stave Falls (26 m), Alouette (22.5 m), Ruskin (59.4 m), Coquitlam (30.5 m), Northwest Stave + Upper Stave variants all present at the same `(blue_line_key, downstream_route_measure)` as `bcfishpass.dams` within fp precision.
- Per-species methodology — "should some dam classes block which species in the default bundle?" — is intentionally out of scope; tracked at [#83](https://github.com/NewGraphEnvironment/link/issues/83).

# link 0.23.0

Closes [#96](https://github.com/NewGraphEnvironment/link/issues/96). `falls` added as a segmentation break source — the FWA stream network is now broken at every fall position. Previously the `<schema>.falls` table was loaded and used for access gating + obs/habitat lift but **not** for segmentation, so close-paired falls (no other break source between them) produced segments that spanned the second fall and incorrectly classified its upper portion as accessible.

- New entry in `R/lnk_pipeline_break.R`'s `source_tables` and the default `break_order`. Both bundle configs (`bcfishpass`, `default`) opt in via `pipeline.break_order`.
- Falls are NOT minimal-reduced — each fall is its own barrier (unlike gradient barriers which go through `frs_barriers_minimal`).
- Closes the implementation drift from the docstring at `R/lnk_pipeline_break.R:10-13` which already documented the bcfp order as `observations → gradient_minimal → falls → barriers_definite → habitat_endpoints → crossings`.
- 4-WSG regression vs pre-fix baseline (HARR/HORS/LFRA/BABL): all four show small expected reductions (BT ~0.6–1.5 km on HARR/HORS; 7 species × ~0.43 km each on LFRA; 4 species × 0.94–1.59 km each on BABL). All deltas negative — segments above falls correctly become inaccessible. See `research/bcfishpass_comparison.md` § "falls in break_order (#96)".
- HORS BLK 356357296 evidence case: pre-fix segment 12671 (1447 m straddling the fall at DRM 67565) split into 12677 (17 m below) + 12678 (1429 m above, `accessible=FALSE`).
- Map cache helper `data-raw/maps/_lnk_map_compare.R` hardened — stale 0-row caches (left when the pipeline runs for one WSG and the map is rendered for another) now refetch instead of erroring on missing CRS.

# link 0.22.0

Wires `fresh::frs_order_child` into the pipeline as link methodology — small streams plugging directly into large rivers can be credited as rearing despite low/missing FWA channel-width estimates. Closes [fresh#158](https://github.com/NewGraphEnvironment/fresh/issues/158) on the link side.

- Four new per-species columns in `dimensions.csv` (both bundles), all opt-in via `rear_stream_order_bypass: yes/no`:
  - `rear_stream_order_parent_min` — min order at the trib BLK's mouth confluence (default 5, matches bcfp)
  - `rear_stream_order_child_min` — lower bound on segment's own stream_order (default 1)
  - `rear_stream_order_child_max` — upper bound on segment's own stream_order (default 1)
  - `rear_stream_order_distance_max` — cap (m) on distance from trib mouth (empty = no cap)
- `lnk_rules_build` emits the values into a `channel_width_min_bypass:` block on the rear stream-edge rule. `lnk_pipeline_classify` reads the block and calls `frs_order_child` per species post-classification, gated on `rear_stream_order_bypass`.
- Both bundles ship `bypass: no` for all species — infrastructure is parametric and tested but disabled by default. Re-enable per species via `dimensions.csv`. The 4-WSG regression (HARR / HORS / LFRA / BABL) is byte-identical to the pre-#96 baseline with bypass=off, confirming the wiring is purely additive when disabled.
- Updates `inst/extdata/configs/dimensions_columns.csv` xref doc with all four new columns and refreshes the `rear_stream_order_bypass` entry (was stale — said "currently inert").
- Bumps fresh dep to `>= 0.27.5` for the renamed bypass YAML schema (`stream_order` → `stream_order_min` + `stream_order_max`).

Related: [link#23](https://github.com/NewGraphEnvironment/link/issues/23) (CH spawning misread, closed not-a-bug). PWF for the wire-up at `planning/active/`.

# link 0.21.0

Closes [#87](https://github.com/NewGraphEnvironment/link/pull/94). Default-bundle SK upstream-spawn now credits any spawn-eligible segment upstream of and accessible from a qualifying rearing waterbody, dropping bcfishpass's restrictive cluster + lake-adjacency gate. bcfishpass-bundle SK keeps the gate (parity preserved).

- New `spawn_connected_lake_adjacent` column on both `dimensions.csv` schemas. SK row: `yes` (bcfishpass) / `no` (default). Empty for non-SK species — inherits fresh's `TRUE` default.
- `lnk_rules_build` emits `<sp>.spawn_connected.lake_adjacent` when the dimension is non-empty. Older rules.yaml files without the key remain valid.
- Bumps fresh dep to `>= 0.26.0` (knob lives there).

# link 0.20.1

Closes [#92](https://github.com/NewGraphEnvironment/link/pull/93). Per-AOI observations filter mirrors bcfp's `wsg_species_presence` + `observation_key` exclusions.

- New `.lnk_pipeline_prep_observations()` builds `<schema>.observations` per AOI, mirroring bcfp's `model/01_access/sql/load_observations.sql`. Filters `bcfishobs.observations` by the WSG's species set (only species marked present count) and applies QA exclusions (`data_error` / `release_exclude` rows removed, keyed on `observation_key` — was `fish_observation_point_id`, never present in the CSV; the empty intersect silently dropped all 1,182 exclusions).
- Downstream consumers updated: `prep_overrides` reads `<schema>.observations` (no longer takes `observations` param); `lnk_pipeline_break_obs` simplified to a thin reader; `lnk_barrier_overrides` uses `observation_key`.
- TWAC pre-flight: BT spawning/rearing/rearing_stream collapsed from +21–30% over-credit to 0.0% across the board. 15-WSG `tar_make`: HARR + LFRA BT tightened toward parity (LFRA BT rearing_stream -3.75% → -0.93%; HARR BT rearing_stream -4.19% → -1.29%); other 13 WSGs unchanged. HORS BT stays -7.68% (fresh#158 stream-order bypass — distinct mechanism).
- Default bundle also tightens (6 rows on HARR/LFRA BT) — methodology correctness improvement, not a regression.

# link 0.20.0

Closes [#88](https://github.com/NewGraphEnvironment/link/pull/89). Subsurfaceflow folded into the natural-barrier set so per-species observation/habitat upstream lift fires on it.

- `.lnk_pipeline_prep_natural()` now builds the full bcfishpass natural-barrier union (gradient + falls + opt-in subsurfaceflow). Subsurfaceflow positions land in `<schema>.natural_barriers`, which `lnk_barrier_overrides()` consumes — so per-species observation/habitat upstream lift applies to subsurfaceflow exactly as it does to falls and gradient.
- `.lnk_pipeline_prep_subsurfaceflow()` deleted; its body absorbed into `prep_natural`. Six prep helpers → five.
- Default-bundle off-switch unchanged: omit `subsurfaceflow` from `cfg$pipeline$break_order` and the entire code path skips. Verified bit-identical default rollup (0 of 581 rows changed).
- bcfishpass-bundle parity: HARR CH/CO/ST rearing_stream gaps closed from -14.8/-13.3/-11.6% to within ±0.32%. LFRA CH/CO/ST closed to within ±0.6%. HARR blkey 356286055 BT credits 6.509 km (was 0).
- Reproducibility: two consecutive 15-WSG `tar_make` runs produced byte-identical rollup (`digest::digest(link_value)` matches across runs).
- HORS rearing_stream gap (~7% on BT/CH/CO) is unchanged by this fix — separate mechanism, follow-up.

# link 0.19.0

Closes [#82](https://github.com/NewGraphEnvironment/link/pull/82). Subsurface-flow access barriers + parity claim retraction.

**Subsurface-flow as opt-in access barrier**. Closes the largest single gap surfaced when expanding the bcfishpass-config rollup from 5 to 10 watershed groups: NATR BT spawning +15.2% → +1.5%, NATR BT rearing +13.0% → -0.6% (10-WSG `tar_make` log: `data-raw/logs/20260429_02_tar_make_subsurf.txt`).

- New `.lnk_pipeline_prep_subsurfaceflow()` materialises `<schema>.barriers_subsurfaceflow` from `whse_basemapping.fwa_stream_networks_sp` filtered to `edge_type IN (1410, 1425)`. Honours `user_barriers_definite_control`. Mirrors bcfishpass `model/01_access/sql/barriers_subsurfaceflow.sql` exactly.
- New `subsurfaceflow` entry in `lnk_pipeline_break.R` `source_tables` map; conditional UNION ALL in `lnk_pipeline_classify_build_breaks` so the new break source emits `'blocked'` into `fresh.streams_breaks` when the config opts in.
- Inclusion is gated on `cfg$pipeline$break_order` containing `'subsurfaceflow'` at every site (prepare, break, classify). Configs control the toggle, not code.
- `inst/extdata/configs/bcfishpass/config.yaml` opts in (parity with bcfishpass). `inst/extdata/configs/default/config.yaml` does not opt in (NewGraph methodology decision pending).
- `?lnk_pipeline_break` gains a `## Break sources` table covering every valid `break_order` entry — source table, role, classify-phase label. Both bundled `config.yaml` files carry an inline comment listing the available entries with one-line semantics so future-readers see the toggle without leaving the config file.

**Parity claim retraction**. Earlier framing ("all species within 5%", "exact reproduction") held only on a small set of pre-selected WSGs. The 10-WSG rollup surfaced systematic gaps. Vignette pulled, README and DESCRIPTION reframed as experimental.

- `vignettes/habitat-bcfishpass.Rmd` removed; bundled vignette data in `inst/extdata/vignette-data/` removed.
- `README.md` rewritten as one-liner ("Experimental package — breaking all the time and loving the learning curve") plus install + license.
- `DESCRIPTION` Title and Description reframed; `bookdown`, `knitr`, `mapgl`, `rmarkdown` dropped from Suggests; `VignetteBuilder` removed.
- `data-raw/_targets.R` extended to 10 WSGs (PARS, MORR, KISP, KOTL, NATR added).
- `research/bcfishpass_comparison.md` retraction at top with the diagnosis tables and the natural-vs-anthropogenic two-tier classification reference; historical content preserved below.
- `CLAUDE.md` Status block flags remaining gaps.

**Remaining departures** (per `research/bcfishpass_comparison.md`): 7 of 210 spawning/rearing/rearing_stream rows >5%, six of seven `link < bcfishpass`. Concentrated on MORR ST (cluster connectivity), MORR SK and KISP SK (new geographies for the existing fresh#147 SK lake-proximity logic). Tracked separately; not in this release.

# link 0.18.1

Closes [#78](https://github.com/NewGraphEnvironment/link/issues/78). Adds attribution for redistributed upstream data and refreshes the package Title + Description to reflect the package's current scope.

- `LICENSE-bcfishpass` at root — verbatim copy of upstream `smnorris/bcfishpass` LICENSE governing the redistributed override CSVs
- `NOTICE.md` at root — source/license table, names redistributed files
- `inst/extdata/configs/{bcfishpass,default}/overrides/README.md` — pointer files reachable via `system.file()`
- `README.md` "Acknowledgements" section above License
- `Authors@R` — Simon Norris added as `[ctb]`
- `Title` — `Habitat and Connectivity Interpretation for Stream Networks` (was the v0.6-era `Crossing Connectivity Interpretation`)
- `Description` — refactored to mirror the README's "fresh answers what the habitat is, link answers what the features mean for the network" framing; names the three habitat axes (intrinsic potential, accessibility under connectivity, per-feature rollups)

CITATION file and mirror to NewGraphEnvironment/crate (which also ships bcfishpass fixtures via crt_ingest examples) deferred — to be filed as their own work.

# link 0.18.0

Closes [#65](https://github.com/NewGraphEnvironment/link/issues/65). Decompose the config bundle into a manifest layer and a data-ingest layer, and route registered files through [crate](https://github.com/NewGraphEnvironment/crate) for source-agnostic canonicalization.

**`lnk_config()` is now manifest-only.** It reads `config.yaml` and returns paths, file declarations, pipeline knobs, and provenance — no parsed CSVs. Cheap to call. `lnk_config_verify()` and `lnk_stamp()` no longer pay for CSV parsing they don't need.

**New: `lnk_load_overrides(cfg)`** materializes the data files declared in `cfg$files` and returns a named list of canonical-shape tibbles. Entries with `source` + `canonical_schema` declarations dispatch through `crate::crt_ingest()` (currently `bcfp/user_habitat_classification`); others fall through to local reads dispatched on path extension. New source families plug in by config edit alone — no link R code change.

**New `config.yaml` schema.** Top-level `rules:` and `dimensions:` paths replace `files.rules_yaml` / `files.dimensions_csv` (format follows from the path's extension, not the key name). The previous `files:` and `overrides:` maps merge into one flat `files:` map keyed by filename stem (e.g. `user_barriers_definite`, `pscis_modelledcrossings_streams_xref`). Each entry carries `path:` and optionally `source:` and `canonical_schema:`. Configs may declare `extends:` to inherit from another config; child entries override same-key parent entries.

**Pipeline phase signatures gain `loaded`.** Every `lnk_pipeline_*` phase that reads a data table now takes `cfg` and `loaded` together. Callers (the bundled targets pipeline, project scripts) call `lnk_load_overrides(cfg)` once and thread the result through phases. `cfg$overrides$X` and `cfg$habitat_classification` access points become `loaded$X`. See `data-raw/_targets.R` and `data-raw/compare_bcfishpass_wsg.R` for the pattern.

**Verification.** `tar_make()` on 5 WSGs × 2 configs reproduces the v0.17.0 baseline rollup bit-identically (sha256 `a82de9928809b9751213e08916c476b4ee3f99286bc9ea2dc53f9659eeb92097`). Refactor introduces no behaviour change.

**Migration**

| Old | New |
|---|---|
| `cfg$rules_yaml` | `cfg$rules` |
| `cfg$dimensions_csv` | `cfg$dimensions` |
| `cfg$parameters_fresh` (data frame) | `loaded$parameters_fresh` |
| `cfg$habitat_classification` | `loaded$user_habitat_classification` |
| `cfg$observation_exclusions` | `loaded$observation_exclusions` |
| `cfg$wsg_species` | `loaded$wsg_species_presence` |
| `cfg$overrides$X` | `loaded$X` (e.g. `loaded$user_barriers_definite`) |

**Out of scope (follow-up issues):**

- crate schemas for the other 9 bcfp-sourced files (one issue per file as canonical-shape decisions concretize). Today they fall through to plain CSV read.
- `nge` / `local` source families (when project-experimental configs need them).
- Type-aware variant matching in crate (planned crate v0.1.x roadmap).

# link 0.17.0

Ship the `Modelling spawning and rearing habitat using bcfishpass defaults` vignette ([`vignettes/habitat-bcfishpass.Rmd`](https://github.com/NewGraphEnvironment/link/blob/main/vignettes/habitat-bcfishpass.Rmd)) on top of the post-phase-3 codebase. Regenerated bundled artifacts (`inst/extdata/vignette-data/{rollup, sub_ch, sub_ch_bcfp}.rds`) reflect the corrected emit semantics and tighter parity.

**bcfishpass-bundle parity (5 WSGs × 5 species, spawn + rear):**

- 42 of 42 non-NA rows within ±5%
- 35 of 42 within ±2%
- median 1.1%; max 5.0%

Tighter than v0.13.1's 100% within ±5% / median 1.5% claim because phase 1's emit-semantics fix landed in main, and the regenerated rollup reflects it. Spawning rows that previously sat at +3-5% (BT/CH/CO/ST across multiple WSGs) are now at +0-2%.

The vignette text claim updated to match the new numbers. Cuts the v0.13.1 vignette's residual-deltas paragraph that mentioned overlay-range-containment and stream-order-bypass — those were pre-phase-3 artifacts; with rule emission corrected, residual deltas are mostly segmentation-boundary rounding plus the documented stream-order bypass.

# link 0.16.0

Phase 3 of [#69](https://github.com/NewGraphEnvironment/link/issues/69) — proof artifact + emit-semantics fix.

**Proof artifact:** new `research/rule_flexibility.md` runs BABL × CO under three configs (use case 1, use case 2, bcfishpass) by swapping only `dimensions.csv` cells, with `rules.yaml` diffs side-by-side. Reproducible via `data-raw/rule_flexibility_demo.R` + `data-raw/rule_flexibility_render.R`. Demonstrates that every methodology dial is a CSV cell, no buried emission rules. The numbers prove the matrix:

- Use case 1 (default bundle): rearing 1388.90 km, lake_rearing 54507.85 ha, wetland_rearing 5786.74 ha. Counts polygon-mainlines as linear AND rolls up polygon area.
- Use case 2: rearing 1271.02 km, same area rollups. Excludes polygon-mainlines from linear via `in_waterbody: false` + `area_only: true` on L/W; areas still bucket via the polygon rules.
- bcfishpass bundle: rearing 1271.02 km, no area rollup (no L/W polygon rules at all). Functionally identical rear predicate to use case 2 because `area_only: true` makes the L/W rules contribute to bucket flags only.

**Emit-semantics fix in `lnk_rules_build()`** (under #69 phase 1 banner — corrects a bug introduced in 0.14.0):

Previous behaviour: `rear_stream_in_waterbody: yes` emitted `in_waterbody: true` on the stream rule. fresh interprets that as "match segments inside polygons ONLY," the opposite of the column's intent ("include polygon-mainlines too"). The default bundle's permissive rear was effectively only matching in-polygon segments — broken since 0.14.0 but never visible because the bcfishpass bundle (which set `no` for all species) was the only side tested for parity.

Corrected emit:

- `yes` (or absent): omit the `in_waterbody` field. Rule matches segments inside AND outside polygons (today's permissive default — polygon-mainlines count too).
- `no`: emit `in_waterbody: false`. Rule matches outside polygons only (strict partition).

The third grammar state (`in_waterbody: true` = inside polygons only) has no biological use case for stream rules and is no longer emitted by `lnk_rules_build()`.

**bcfishpass bundle output unchanged:** the bundle ships `rear_stream_in_waterbody: no` for all species, so the fixed emit produces byte-identical rules.yaml to 0.15.0. Default bundle output changes (now actually permissive — pass-through stream rule).

Tests updated (3 cases): `yes` (or absent) omits the field; `no` emits `in_waterbody: false`; default bundle smoke tests assert the rear stream rule has no `in_waterbody` field.

# link 0.15.0

Phase 2 of [#69](https://github.com/NewGraphEnvironment/link/issues/69). Adds dimensions-driven `area_only` emission + polygon-rule mainlines edge filter. Default bundle now ships use case 1 (linear includes mainlines through L/W polygons; area rolls up via bucket flags) with the new edge filter restricting polygon-rule contributions to mainlines only (1000/1100). bcfishpass bundle output unchanged.

**New per-species columns** in `dimensions.csv`:

- `rear_lake_area_only` — yes/no — emit `area_only: true` on the L polygon rule. When `yes`, fresh derives the `lake_rearing` bucket flag from the rule but excludes it from the main `rear` predicate (linear). When `no` or absent, the rule contributes to both (today's behaviour). Both bundles ship `no` for all species — default ships use case 1; bcfishpass ships parity-with-bcfp.
- `rear_wetland_area_only` — yes/no — same shape on the W polygon rule. Both bundles ship `no` for all species.

**Polygon-rule edge filter** (`edge_types_explicit: [1000, 1100]` on L/W rules in the additive rear branch):

- Restricts the L/W polygon rule's match to mainlines (single-line main flow + secondary flow) when emitted under `rear_lake: yes` or `rear_wetland: yes` + `rear_wetland_polygon: yes`. Without the filter, polygon rules matched every segment in the polygon (shorelines 1700, banks 1800, island edges, construction lines), all crediting linear `rearing`. The bucket pred (`lake_rearing` / `wetland_rearing`) is unaffected — area still rolls up the polygon's full area as long as any tagged segment exists in it.
- The `rear_lake_only` branch (SK / KO) is intentionally **not** filtered — the L rule there IS the rear classification, must continue matching the whole lake polygon.

**Default bundle methodology shift** — use case 1: linear km includes mainlines through wetlands and lakes, with area rollups (`lake_rearing_ha`, `wetland_rearing_ha`) populating from the polygon footprint. `rear_wetland_polygon` flipped from `no` (v0.14.0) back to `yes` for rear_wetland=yes species. The 2026-04-27 cut to `no` was the right call given the v0.14.0 grammar (no edge filter; W rule would over-emit), but with the mainlines edge filter shipped here, polygon-mainlines are the right thing to count for linear AND area.

**Required:** fresh ≥ 0.24.0 ([#182](https://github.com/NewGraphEnvironment/fresh/issues/182), [fresh#184](https://github.com/NewGraphEnvironment/fresh/pull/184)) — `area_only` predicate decouples bucket-flag derivation from the main rear predicate.

**Tests** — `test-lnk_rules_build.R` 130 PASS (was 124 in 0.14.0): 6 new tests covering area_only emission per the columns + polygon-edge-types filter present on L/W rules (additive branch only) + rear_lake_only branch left untouched. Full suite 554 PASS / 0 FAIL.

**BABL parity (bcfishpass bundle):** unchanged from 0.14.0 — 8 of 10 rows within ±2%, 10 of 10 within ±5%. The new knobs are inert when set to today's defaults, so bcfp bundle output is byte-identical to v0.14.0.

**Coordinates with** [#69 phase 3](https://github.com/NewGraphEnvironment/link/issues/69) — `research/rule_flexibility.md` proof artifact runs BABL × CO under three configs (use case 1, use case 2, bcfishpass) by swapping only `dimensions.csv` cells, with `rules.yaml` diffs side-by-side.

# link 0.14.0

Dimensions-driven `in_waterbody` + bcfishpass-bundle methodology fixes that bring 5-species BABL parity to ±5% (8 of 10 rows within ±2%) on the bcfishpass bundle. The methodology dials are now visible in `dimensions.csv` cells per species — no buried emission rules.

**New per-species columns** ([#69 phase 1](https://github.com/NewGraphEnvironment/link/issues/69)):

- `spawn_stream_in_waterbody` — yes/no — emit `in_waterbody: <bool>` on the stream-spawn rule. `no` excludes polygon-mainlines from spawn classification (the partition that pairs with `waterbody_type: R/L/W` polygon rules); `yes` is permissive and matches polygon-mainlines too. Both bundles ship with `no` for all species (biology — spawning happens in stream channels).
- `rear_stream_in_waterbody` — yes/no — same shape on the stream-rear rule. bcfishpass bundle ships `no` (strict partition matches bcfishpass's per-species access SQL); default bundle ships `yes` (NewGraph permissive — counts polygon-mainlines as `rearing` for species with `rear_lake: yes` etc., orthogonal to area rollups).
- `rear_wetland_polygon` — yes/no — gate emission of the `waterbody_type: W` polygon rule. When `no`, only the 1050/1150 wetland-flow carve-out emits; when `yes` (or absent), the W polygon rule emits too (sets the `wetland_rearing` flag for area rollups). Both bundles ship `no` for all species — segments inside an FWA wetland polygon are wider than the fish-bearing channel and shouldn't count as rearing habitat.

**Methodology fixes carried in from earlier branch work** (previously held in `vignette-ship`):

- **`apply_habitat_overlay: false` flag in `pipeline:` block of bcfishpass `config.yaml`.** Comparison-scope choice, not a behavioural claim about bcfishpass. bcfishpass ships both layers: `habitat_linear_<sp>` (per-species rule output) and `streams_habitat_linear` (rule + known-habitat overlay blended). The bcfishpass bundle disables `frs_habitat_overlay()` so its output is rule-only and compares apples-to-apples against bcfishpass's own rule layer (`habitat_linear_<sp>`). Comparing the rule slices in isolation keeps rule-emission drift from hiding behind known-habitat overlay drift; overlay parity is a separate question to revisit once rule parity is locked. Default bundle keeps overlay enabled (NewGraph methodology produces the blended output by default).
- **`lnk_barrier_overrides()` habitat-confirmation SQL** updated for bcfishpass's authoritative CSV shape (post-2026-04-26: `species_code` + `spawning` + `rearing` integer columns instead of the dropped `habitat_ind` column).
- **`lnk_pipeline_prepare()`** empty-table fallback `CREATE TABLE` matches the new CSV shape.

**Required:** fresh ≥ 0.23.1 ([#180](https://github.com/NewGraphEnvironment/fresh/issues/180), [fresh#181](https://github.com/NewGraphEnvironment/fresh/pull/181), [fresh#183](https://github.com/NewGraphEnvironment/fresh/pull/183)) — adds the `in_waterbody` predicate to the rule grammar plus the validator hotfix.

**Tests** — `test-lnk_rules_build.R` 124 PASS (was 86): 6 new tests for `in_waterbody` emission across permutations + bundle-level smoke tests; 4 new tests for `rear_wetland_polygon` (yes/no/absent backward-compat). Full suite 516 PASS / 0 FAIL.

**BABL parity (bcfishpass bundle):** 8 of 10 spawning+rearing rows within ±2%; max 5.0%; max spawning drift 1.5% (was 4.8%). The remaining ±2-5% drift is a follow-up — phase 2 will add the `area_only` predicate ([fresh#182](https://github.com/NewGraphEnvironment/fresh/issues/182)) and `edge_types_explicit: [1000, 1100]` filter on polygon rules to support the use case 2 pattern (mainlines excluded from linear, area still rolls up).

**Coordinates with** [#69 phase 2](https://github.com/NewGraphEnvironment/link/issues/69) — adds `rear_lake_area_only` / `rear_wetland_area_only` columns once fresh#182 lands. Phase 3 ships the proof artifact (`research/rule_flexibility.md`) running BABL × CO under three configs (use case 1, use case 2, bcfishpass) by swapping only `dimensions.csv` cells.

# link 0.13.0

Shape fingerprint + halt auto-merge on shape drift ([#64](https://github.com/NewGraphEnvironment/link/issues/64)).

`data-raw/sync_bcfishpass_csvs.R` and the daily `sync-bcfishpass-csvs.yml` cron previously compared each bcfishpass-sourced CSV against a recorded sha256 byte checksum and auto-merged any drift. That worked for value drift (rows added/edited) but was blind to shape drift — bcfishpass's 2026-04-26 long→wide reshape (with column type change) passed straight through and broke link's pipeline downstream. This release adds a separate **shape fingerprint** alongside the byte checksum; the workflow auto-merges byte-only drift as before but halts shape drift for coordinated review.

- New `shape_checksum` field in the `provenance:` block of each bundle's `config.yaml`. Computed as sha256 of the file's first line (whitespace-normalized). Catches column rename / add / remove / reshape — the dominant failure mode. Type changes within stable columns are out of scope (rarer; can extend later if needed).
- `data-raw/sync_bcfishpass_csvs.R` computes shape fingerprint at sync time, classifies each file's drift as `byte` or `shape`, writes the overall drift kind to `/tmp/sync_drift_kind` for the workflow to consume.
- `.github/workflows/sync-bcfishpass-csvs.yml` reads the drift kind. Byte-only drift → auto-PR + auto-merge as today. Shape drift → auto-PR opens with `schema-drift` label, NOT auto-merged, workflow exits non-zero (red on Actions tab) so the change is visible. Coordinated review across link / fresh / crate is required before merging.
- `lnk_config_verify()` extended with `shape_drift` column. **Breaking** (pre-1.0): old single `drift` column renamed to `byte_drift`; existing tibble shape now `(file, byte_expected, byte_observed, byte_drift, shape_expected, shape_observed, shape_drift, missing)`.
- `lnk_stamp()` markdown rendering surfaces both byte and shape drift counts in the provenance summary.
- 15 new tests (468 total, was 453) — `.lnk_shape_fingerprint()` helper + shape-drift detection + missing-file handling + backward-compat path for bundles without `shape_checksum:` field.

Coordinates with crate's adapter pattern (link#65, crate#2) — when shape drift fires, crate's normalize handler is the right place to absorb the upstream change before link's pipeline sees it.

# link 0.12.0

Pick up `fresh 0.22.0` overlay simplification — caller-side update for the canonical-shape contract.

- `lnk_pipeline_classify()` now calls `frs_habitat_overlay()` with `species_col = "species_code"` + `habitat_types = c("spawning", "rearing")` instead of `format = "long"` + `long_value_col = "habitat_ind"`. Matches the shape bcfishpass's `user_habitat_classification.csv` adopted on 2026-04-26 (row-per-(segment × species), per-habitat indicator columns). Three-line caller-side diff; no link API change.
- `Suggests: fresh (>= 0.22.0)`. Coordinates with [fresh#177](https://github.com/NewGraphEnvironment/fresh/issues/177).
- Pipeline runs again. The vignette stays in `dev/` until link#64 (sync workflow shape fingerprint) and link#65 (`lnk_load_overrides()` via `crate::crt_ingest()`) land.

# link 0.11.2

bcfishpass vignette pulled out of pkgdown until tighter.

- `vignettes/reproducing-bcfishpass.Rmd` → `dev/habitat-bcfishpass.Rmd.draft`. Same pattern as scoring-crossings — out of build path, preserved for resumption when content lands clean.
- Content updates applied before move: title now "Modelling spawning and rearing habitat using bcfishpass defaults"; new scope paragraph describing what bcfishpass covers beyond linear classification; entrypoint replaced with explicit `lnk_pipeline_*` calls (was `tar_make()`); map section clarifies linear classification covers spawning/rearing/lake_rearing/wetland_rearing per species.
- `README.md`: "Full pipeline (reproducing bcfishpass)" → "Full pipeline (linear habitat classification)"; broken pkgdown vignette link removed.
- Open follow-ups: rollup-query retarget to `streams_habitat_linear` for apples-to-apples post-overlay comparison; range-containment relaxation in `fresh::frs_habitat_overlay`.

# link 0.11.1

Vignette cleanup.

- `vignettes/scoring-crossings.Rmd` moved to `dev/scoring-crossings.Rmd.draft` — out of build path until the scoring methodology lands.
- `vignettes/reproducing-bcfishpass.Rmd` updated for the v0.9.0 overlay: added overlay step to the pipeline DAG, new "Known-habitat overlay" subsection, clarified rollup vs. map comparison.
- `data-raw/vignette_reproducing_bcfishpass.R`: bcfishpass-side map query reads `streams_habitat_linear` (model + known) instead of `habitat_linear_ch` (model-only) for apples-to-apples comparison with link's post-overlay output.
- Regenerated bundled snapshots (`inst/extdata/vignette-data/{rollup,sub_ch,sub_ch_bcfp}.rds`) from v0.10.0 + overlay state.

# link 0.11.0

Config-bundle provenance + run stamps — closes the drift attribution loop. Pipeline outputs that shift between runs on the same DB state can now be traced back to which input changed. Closes [#40](https://github.com/NewGraphEnvironment/link/issues/40); supersedes the narrower scope of [#24](https://github.com/NewGraphEnvironment/link/issues/24).

- `inst/extdata/configs/{bcfishpass,default}/config.yaml` carry `provenance:` blocks with sha256 checksums for every tracked file. Externally sourced files (bcfishpass overrides) record `source` URL + `upstream_sha` (`ea3c5d8`, synced 2026-04-13) + `path` within source repo. Generated files (`rules.yaml`) record `generated_from` + `generated_by` + `generator_sha`. Hand-authored files record link's git sha at edit time.
- `lnk_config()` exposes parsed provenance as `cfg$provenance` (named list, one entry per tracked file). `print(cfg)` shows the count of tracked files.
- New `lnk_config_verify(cfg, strict)` recomputes sha256 for every provenanced file and returns a tibble `(file, expected, observed, drift, missing)`. Default warns on drift; `strict = TRUE` errors. `digest` added to Suggests.
- New `lnk_stamp(cfg, conn, aoi, db_snapshot)` returns an `lnk_stamp` S3 list capturing the full set of inputs at run time: cfg provenance with current observed checksums, software versions and git SHAs (link, fresh, R), DB snapshot row counts (`bcfishobs.observations`, `whse_basemapping.fwa_stream_networks_sp`) when conn is provided, AOI + start_time. `lnk_stamp_finish(stamp, result, end_time)` finalizes; `format(stamp, "markdown")` renders for report appendix or run-log dump.
- `data-raw/compare_bcfishpass_wsg.R` now emits a stamp markdown at the head of every WSG run, captured into `data-raw/logs/*.txt` via the standard stderr redirect.
- Tests: 93 new — provenance parsing, drift detection (clean / mutated / missing / strict), bundled-config drift = 0 invariants, stamp shape + markdown rendering + finalization + db-snapshot opt-out.

# link 0.10.0

Default config bundle now uses explicit FWA `edge_type` codes for spawn and rear-stream predicates, matching bcfishpass's 20-year-validated convention.

- `data-raw/build_rules.R`: switched both default rule-builder calls (`inst/extdata/parameters_habitat_rules.yaml` and `inst/extdata/configs/default/rules.yaml`) from `edge_types = "categories"` to `edge_types = "explicit"`. Predicates now emit `edge_types_explicit: [1000, 1100, 2000, 2300]` in place of `edge_types: [stream, canal]` (which expanded to `1000/1050/1100/1150` + `2000/2100/2300`).
- Drops `1050/1150` (stream-thru-wetland) and `2100` (rare double-line canal) from spawn AND rear-stream rules. The dedicated wetland-rearing rule (`edge_types_explicit: [1050, 1150]` with `thresholds: false`) is unchanged — `wetland_rearing` flag still captures stream-thru-wetland segments for species with `rear_wetland = yes`. Net `rearing` flag (= `rear_stream OR wetland_rearing OR rear_lake`) is preserved for those species; species with `rear_wetland = no` (GR, KO) lose `1050/1150` from both spawn AND rearing.
- ADMS preflight (M1, fresh 0.21.0): default-bundle spawning km drops 4-7% across all spawning species (BT 397→368, CH 296→279, CO 340→318, SK 98→94, RB 331→311). Rearing km essentially unchanged for `rear_wetland = yes` species. Full per-WSG numbers in `research/default_vs_bcfishpass.md`.
- Default and bcfishpass bundles now emit structurally aligned spawn predicates — confirms bcfishpass's edge-type convention is what link ships by default.
- `tests/testthat/test-lnk_rules_build.R`: regression tests added — default rules.yaml has no `1050/1150/2100` in spawn or rear-stream predicates; the dedicated wetland-rear rule still carries `[1050, 1150]`.

# link 0.9.0

`lnk_pipeline_classify()` now overlays known habitat from `user_habitat_classification.csv` onto `fresh.streams_habitat` after rule-based classification. Closes [#55](https://github.com/NewGraphEnvironment/link/issues/55).

- After `frs_habitat_classify()` finishes, calls `frs_habitat_overlay()` (fresh ≥ 0.21.0) when the manifest declares `habitat_classification`. Loaded long-format table is overlaid via a 3-way bridge join through `fresh.streams` (range containment on `[drm, urm]`).
- Closes the gap surfaced in research doc §5/§7: bcfishpass's published `streams_habitat_linear.spawning_sk > 0` blends model + observation-curated knowns; link's pipeline previously only emitted the model side.
- 5-WSG rerun (digest `0f00c713`) shows BABL SK spawning under bcfishpass bundle rises from 57.6 → 85.2 km (+27.6 km from overlay). ADMS SK +5.14 km, BULK SK +0.8 km. Default bundle similar magnitudes.
- Requires fresh ≥ 0.21.0 (overlay rename + bridge support; see fresh#175).

# link 0.8.0

Default NewGraph habitat-classification config bundle ships alongside the bcfishpass reproduction bundle ([#51](https://github.com/NewGraphEnvironment/link/issues/51)).

- New `inst/extdata/configs/default/` bundle — intentional methodological departures from bcfishpass: intermittent streams included in rearing, wetland rearing added for resident species, lake rearing extended to species beyond SK/KO with per-species `rear_lake_ha_min` thresholds, `river_skip_cw_min = yes`. Loadable via `link::lnk_config("default")`.
- Per-species `rear_lake_ha_min` via a new column in `configs/default/dimensions.csv`. `lnk_rules_build()` prefers that value over the shared `fresh::parameters_habitat_thresholds` default when present, keeping bcfishpass bundle at its 200 ha threshold for SK/KO while letting default express species-specific biology (CO 2 ha, BT/WCT/RB/CT/DV 10 ha, GR 40 ha, ST 60 ha, CH 100 ha, SK/KO 200 ha). Non-numeric entries in the dimensions CSV fall through to the fresh fallback rather than silently disabling it.
- Per-species `rear_wetland_ha_min` via a new column in `configs/default/dimensions.csv`. `lnk_rules_build()` now emits both `edge_types: wetland` (for rearing km) AND `waterbody_type: W` (drives `wetland_rearing_ha` rollup) rules when `rear_wetland = yes`. Thresholds: CO 0.5 ha (beaver complexes), BT/CH/CT/DV/RB/ST/WCT 1 ha.
- SK + KO spawn_connected block — added five columns to `configs/default/dimensions.csv` (`rear_stream_order_bypass`, `spawn_connected_direction`, `spawn_connected_gradient_max`, `spawn_connected_cw_min`, `spawn_connected_edge_types`) so `lnk_rules_build()` emits the `spawn_connected:` block with `direction: downstream` for lake-obligate species. `spawn_lake = no` for SK/KO to prevent lake-centerline inflation (Babine Lake alone is 177 km).
- `data-raw/compare_bcfishpass_wsg()` emits a compound rollup with 7 rows per species × WSG × config: `spawning`/`rearing` km, `lake_rearing`/`wetland_rearing` ha, plus three edge-type slice rows (`rearing_stream`, `rearing_lake_centerline`, `rearing_wetland_centerline`) for decomposing the rearing total. Reference side uses the same `habitat_linear_<sp>` + `fwa_{lakes,wetlands}_poly` methodology as link, so both sides are apples-to-apples.
- `data-raw/_targets.R` runs both bundles side-by-side across all 5 validation WSGs (ADMS, BULK, BABL, ELKR, DEAD) — 10 comparison targets, unified rollup with a `config` identity column. Rollup digest `e3eaf5f62df44d6713bfed32cd08fc5d` (357 rows) on M1 with fresh 0.17.1.
- New research doc `research/default_vs_bcfishpass.md` — methodology comparison, per-WSG per-species results, 9 observations covering the debugging journey (SK spawning over-inflation root causes, bcfishpass known-habitat overlay via `streams_habitat_known`, gradient-floor calibration, segment-averaging risk).
- Three companion maps (`data-raw/maps/sk_spawning_BABL*.R`) — mapgl overlays of SK spawning BABL comparing bundle-vs-bundle and default-vs-bcfishpass-published (model + known); per-layer toggle, popups with `id_segment` / `segmented_stream_id` / plain-language edge_type / gradient / length.
- Requires `fresh >= 0.17.1` for `waterbody_type: L/W` rear-rule honouring + `lake_ha_min` / `wetland_ha_min` thresholds.
- `tests/testthat/test-lnk_rules_build.R` — new suite with 56 tests covering lake + wetland rule emission (per-config ha_min, fresh fallback, rear_lake=no / rear_wetland=no), spawn rules (stream+canal vs explicit codes, spawn_lake, spawn_requires_connected, spawn_connected block), rear precedence (no_fw, lake_only, all_edges), river polygon + river_skip_cw_min, species skipping, rear_stream_order_bypass, non-numeric ha_min fallthrough.

# link 0.7.0

`user_barriers_definite` no longer eligible for observation-based override ([#48](https://github.com/NewGraphEnvironment/link/issues/48)).

- `.lnk_pipeline_prep_natural()` previously unioned `barriers_definite` into `natural_barriers`, which `lnk_barrier_overrides()` iterates over. Net effect: the 227 reviewer-added user-definite positions (EXCLUSION zones, MISC detections the model misses) could be re-opened by observations clearing the species threshold. Confirmed active on ELKR pre-fix — 4 override rows at Erickson Creek exclusion and Spillway MISC positions that bcfishpass keeps as permanent barriers.
- bcfishpass's `model_access_*.sql` builds the barriers CTE from gradient + falls + subsurfaceflow only and appends `barriers_user_definite` post-filter via `UNION ALL`. Observations and habitat filters never see user-definite rows, so they're never overridable. link now matches this shape: `natural_barriers` is gradient + falls only; `barriers_definite` stays consumed separately as a break source in `lnk_pipeline_break()` and as a direct `UNION ALL` entry into `fresh.streams_breaks` via `lnk_pipeline_classify()`.
- ELKR rollup shifts toward bcfishpass: BT spawning +3.4% → +2.8%, WCT spawning +4.0% → +2.6%, WCT rearing +1.6% → +0.3%. Other four WSGs unchanged (ADMS/BABL/DEAD have empty `barriers_definite`; BULK has 87 rows but no observation-threshold matches to any of them).

# link 0.6.0

Honour `user_barriers_definite_control.csv` at the observation-override step.

- `lnk_barrier_overrides()` now excludes observations upstream of control-flagged positions from counting toward the override threshold, matching bcfishpass's access SQL. Previously controlled positions (concrete dams, long impassable falls, diversions) could be re-opened by upstream historical observations ([#44](https://github.com/NewGraphEnvironment/link/issues/44)).
- Gated per-species by a new `observation_control_apply` column in `parameters_fresh.csv` — TRUE for CH/CM/CO/PK/SK/ST; FALSE for BT/WCT; NA for CT/DV/RB. Residents routinely inhabit reaches upstream of anadromous-blocking falls (post-glacial headwater connectivity, no ocean-return requirement), so their observations still override. Matches bcfishpass's per-model application.
- Habitat-confirmation override path intentionally bypasses the control table — expert-confirmed habitat is higher-trust than observations, and bcfishpass's `hab_upstr` CTE has no control join either.
- `.lnk_pipeline_prep_overrides` now passes the control table to `lnk_barrier_overrides()` when the config manifest declares `barriers_definite_control`. Manifest key is the contract; no DB probe.
- `.lnk_pipeline_prep_load_aux` now always creates a schema-valid (possibly empty) `barriers_definite_control` table when the manifest declares the key — fixes an asymmetric gating bug that would have raised "relation does not exist" on AOIs with zero control rows.
- End-to-end validation WSG: DEAD (Deadman River) added to `data-raw/_targets.R`. It has a single `barrier_ind = TRUE` control row at FALLS (356361749, 45743) with six anadromous observations upstream and zero habitat coverage — the unique combination that actively exercises the filter. All four prior WSGs (ADMS/BULK/BABL/ELKR) were rescued by either the observation threshold or habitat path, making them parity checks rather than filter tests.

# link 0.5.0

Documentation and narrative for the targets pipeline.

- New vignette: "Reproducing bcfishpass with link + fresh" — three-line entrypoint, rollup interpretation, BULK chinook habitat map (mapgl), reproducibility framing. Data-prep script at `data-raw/vignette_reproducing_bcfishpass.R` generates `inst/extdata/vignette-data/{rollup,bulk_ch}.rds` from a real run; vignette loads the `.rds` so pkgdown builds don't need fwapg access. Follows the CLAUDE.md convention for vignettes that need external resources ([#38](https://github.com/NewGraphEnvironment/link/issues/38))
- Research doc (`research/bcfishpass_comparison.md`) updated with bit-identical rollup numbers from 2026-04-22 and a new "Targets orchestration" section showing how `_targets.R` composes the per-WSG runs.
- `mapgl`, `sf` added to DESCRIPTION Suggests.
- Retired `data-raw/compare_bcfishpass.R` — `data-raw/_targets.R` + `data-raw/compare_bcfishpass_wsg.R` supersede it. Git history preserves the prior form.

# link 0.4.0

Targets-driven comparison pipeline for all four validated watershed groups.

- Add `data-raw/_targets.R` — `tar_map(wsg = c("ADMS", "BULK", "BABL", "ELKR"))` over a per-AOI target function, synchronous execution, `dplyr::bind_rows` rollup. `fresh.streams` is a shared schema so single-host parallelism would collide — runs serially today; distributed runs (M4 + M1) are a follow-up alongside a fresh upstream change for per-AOI output paths ([#38](https://github.com/NewGraphEnvironment/link/issues/38))
- Add `data-raw/compare_bcfishpass_wsg(wsg, config)` — per-AOI target function. Wraps the six `lnk_pipeline_*` phases, diffs the output against `bcfishpass.habitat_linear_*` reference on the tunnel DB, returns a ~10-row tibble (`wsg × species × habitat_type × link_km × bcfishpass_km × diff_pct`). KB-scale — safe to ship over SSH.
- Promote `.lnk_pipeline_classify_species` to an exported `lnk_pipeline_species(cfg, aoi)` — canonical public API for "species this config classifies in this AOI." Used by `lnk_pipeline_classify` and `lnk_pipeline_connect` internally and by the targets per-AOI function externally. Removes the duplicate private helper that was briefly inlined in `data-raw/`.
- End-to-end verification (`data-raw/logs/20260422_11_tar_make_final.txt`) — 4 WSGs / 34 rows produced over 8.5 minutes wall clock (serial). **Reproducibility:** consecutive `tar_make()` invocations on the same DB state produce bit-identical rollup tibbles. **Parity to bcfishpass (informational):** all 34 `diff_pct` values within 5% of reference; research-doc drift (BT rearing: -0.7 → -1.1 pp) traces to env state between 2026-04-15 and today, not to pipeline non-determinism.

# link 0.3.0

Pipeline phase helpers extract the bcfishpass comparison orchestration into composable building blocks. The 635-line `data-raw/compare_bcfishpass.R` is now 136 lines of sequenced helper calls.

- Add `lnk_pipeline_setup()` — create the per-run working schema ([#38](https://github.com/NewGraphEnvironment/link/issues/38))
- Add `lnk_pipeline_load()` — load crossings and apply modelled-fix and PSCIS overrides
- Add `lnk_pipeline_prepare()` — load falls / definite / control / habitat CSVs, detect gradient barriers, compute per-species barrier skip list, reduce to minimal set via `fresh::frs_barriers_minimal()`, load base segments
- Add `lnk_pipeline_break()` — sequential `frs_break_apply` over observations / gradient / definite / habitat / crossings in config-defined order
- Add `lnk_pipeline_classify()` — assemble access-gating breaks table and run `fresh::frs_habitat_classify()`
- Add `lnk_pipeline_connect()` — per-species rearing-spawning clustering and connected-waterbody rules
- Canonical signature `(conn, aoi, cfg, schema)` — `aoi` follows fresh convention (WSG code today; extends to ltree / sf polygons / mapsheets later), `schema` is the caller's per-run namespace (`working_<aoi>` by convention) so parallel runs do not collide
- `cfg$species` parsed from the rules YAML at `lnk_config()` load — intersects with `cfg$wsg_species` presence to pick per-AOI classify targets
- Requires fresh 0.14.0 (for `frs_barriers_minimal`)

# link 0.2.0

Config bundles for pipeline variants.

- Add `lnk_config(name_or_path)` — load a config bundle (rules YAML, dimensions CSV, parameters_fresh, overrides, pipeline knobs) as one list object. Bundles live at `inst/extdata/configs/<name>/` with a `config.yaml` manifest, or any directory containing `config.yaml` for custom variants ([#37](https://github.com/NewGraphEnvironment/link/issues/37))
- Relocate bcfishpass config files into `inst/extdata/configs/bcfishpass/` (rules.yaml, dimensions.csv, parameters_fresh.csv, overrides/). All R scripts and data-raw/ references updated.

# link 0.0.0.9000

Initial release. Crossing connectivity interpretation layer — scores,
overrides, and prioritizes crossings for fish passage using configurable
severity thresholds and multi-source data integration.
