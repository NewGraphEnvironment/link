# Findings: _targets.R pipeline (#38)

## Why targets (and not a monolithic lnk_habitat)

Earlier session considered a big `lnk_habitat(conn, aoi, config)` wrapper that orchestrates the whole pipeline. Rejected:

- Hides the DAG that rtj is trying to parallelize
- Duplicates what `tar_make()` already provides (caching, skipping, parallelism)
- Turns pipeline variants into if/else branches inside one function rather than separate target graphs
- Every DAG node collapsed to one black-box call — inspection, debugging, partial reruns all harder

Targets solves these natively. `_targets.R` IS the pipeline definition. Each target is a named node. `tar_make()` runs, `tar_visnetwork()` / `tar_mermaid()` visualize, `tar_skip` inherits cache invalidation, parallelism via crew controllers.

link still owns interpretation helpers (the `R/lnk_habitat_*.R` phase functions). Those are called BY targets, not instead of it.

## Architectural constraints from rtj

From `rtj/docs/distributed-fwapg.md` (cross-referenced; byte-identical fwapg restored on M1 as of 2026-04-22):

1. **localhost DB per worker** — every worker creates its own `lnk_db_conn()` to localhost. No remote DB chatter over tailnet (latency blows up on hundreds of `dbGetQuery` calls).
2. **Small returns from `map()` targets** — KB-scale data frames only. No geometry, no raster, no wkb shipped over SSH. Our `compare_bcfishpass_wsg()` returns ~10 rows per WSG.
3. **M1 is optional** — `crew_controller_group` handles graceful degradation. Target graph has no M1 awareness.
4. **WSG is the parallelization unit** — ~220 WSGs province-wide, naturally independent. We start with 4 (ADMS, BULK, BABL, ELKR).
5. **Schema namespacing** — `working_<wsg>` per rtj contract. Prevents parallel workers on the same host from colliding on `working.*`.

## Design decisions

### Per-phase helpers, not one wrapper
Six `lnk_pipeline_*.R` functions, one per DAG phase. Each is a clear unit; each can be targeted independently. Phase names read as verbs: setup → load → prepare → break → classify → connect.

### `aoi` not `wsg` for the partition param
`wsg` hardcodes the bcfishpass WSG partition scheme. Fresh already uses `aoi` as the generic spatial filter (accepts WSG code, ltree, sf polygon). Link helpers inherit this convention. Today `aoi = "BULK"` works the same as the old `wsg = "BULK"`; tomorrow it extends to mapsheets, HUC basins, custom polygons.

### Prefix is `lnk_pipeline_*`
Not `lnk_habitat_*` — only one of six phases (classify) is actually about habitat. The others are setup, loading, network prep, segmenting, connectivity. `lnk_pipeline_*` reads as "these are pipeline building blocks."

### Static branching (`tar_map`) vs dynamic (`pattern = map(wsg)`)
Use `tar_map`. Static branching produces named targets (`comparison_BULK`, `comparison_ADMS`) — debuggable, inspectable, diffable. Dynamic branching hides per-element names behind indices — harder to trace.

### Targets in `Suggests`, not `Imports`
Pipeline-dev dependency, not user-facing. Users who want to run the comparison can `install.packages(c("targets", "crew"))` on demand. `link` itself stays minimal.

### Regenerate the research doc DAG
`tar_mermaid()` output replaces the hand-written Mermaid in `research/bcfishpass_comparison.md`. Single source of truth. Keep the glossary and `classDef` color-coding — those are human decoration, not pipeline structure.

### `compare_bcfishpass_wsg()` return shape
```r
tibble::tibble(
  wsg = "BULK",
  species = "BT",
  habitat_type = c("spawning", "rearing"),
  link_km = c(34.2, 71.8),
  bcfishpass_km = c(33.1, 73.4),
  diff_pct = c(+3.3, -2.2)
)
```
Pulls from fresh's `streams_habitat` table joined against `bcfishpass.streams_habitat_linear_*` reference tables. Both live on the worker's localhost DB (byte-identical dumps on M4 and M1 per rtj).

## PR 2 design constraint: `fresh.streams` is not per-AOI

`lnk_pipeline_prepare` writes base segments to `fresh.streams`, matching the legacy compare script. Fresh's downstream functions (`frs_break_apply`, `frs_habitat_classify`, `frs_cluster`) assume that table path. Every pipeline run does `DROP TABLE IF EXISTS fresh.streams CASCADE` before rebuilding, so two parallel AOI runs on the same host would overwrite each other's segments and race the `streams_habitat` output.

This is tolerable for single-host single-run today — it breaks the parallel `tar_map(wsg = ...)` + `crew_controller_local(workers = 2)` design. Three ways to handle in PR 2:

1. `crew_controller_local(workers = 1)` — serialize runs on each host. Simplest, defeats half the parallelism gain.
2. Per-AOI fresh table names — patch fresh to accept a `streams_table` parameter across break/classify/cluster, or write into `<schema>.streams` and follow all downstream fresh calls with that. Substantial fresh work.
3. Separate database per worker — overkill.

Leaning toward option 1 for the initial PR 2, with option 2 as a fresh follow-up. Document explicitly.

## Other accepted fragilities (from code-check on `prepare`)

- `id_segment` assignment in `prep_network` uses `row_number() OVER (ORDER BY blue_line_key, downstream_route_measure)`. Ties produce arbitrary ordering across runs. Faithful to compare script; ties are rare on FWA in practice.
- `natural_barriers` re-joins gradient barriers to FWA instead of using the already-enriched ltree columns from `gradient_barriers_raw`. Silent drop if an enrichment UPDATE left NULL ltree. Faithful to compare script; hasn't hit in 4 WSGs of real data.
- Per-model gradient class sets (bt, ch_cm_co_pk_sk, st, wct) are hardcoded in `prep_minimal`. TODO in-code to move into `cfg$pipeline$gradient_models` so variants can swap them.

## Unknowns to resolve during implementation

- How cleanly does `frs_habitat_classify()` accept a `working_<wsg>` schema? Does it assume `working.*`? If so, we need a `working_schema` arg in fresh. If `lnk_habitat_classify` writes to a schema name that fresh doesn't know about, classification may fail.
- Per-WSG schema cleanup contract — `on.exit(DROP SCHEMA working_<wsg> CASCADE)` inside `compare_bcfishpass_wsg()`, or let the next run drop + recreate?
- Does `frs_break_apply()` need to know the schema for the streams table, or does the input table name carry it?

Document findings as discovered.

## Cross-refs

- rtj/docs/distributed-fwapg.md — architectural source of truth
- fresh 0.14.0 — `frs_barriers_minimal()` is prerequisite for `lnk_habitat_build_network`
- link 0.2.0 — `lnk_config()` feeds all phases

## Versions

- fresh: 0.14.0
- link: main (0.2.0 → 0.3.0)
- bcfishpass: ea3c5d8
- fwapg: Docker (FWA 20240830)
