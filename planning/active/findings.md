# Findings — Persistent province-wide habitat tables (#112)

## Issue context

### Goal

Today: per-WSG segment-level output is built in `fresh.streams` then **clobbered every run** by `compare_bcfishpass_wsg.R:62-64`'s `DROP TABLE … CASCADE`. The 232 RDS files saved per provincial run are KB-scale **summary tibbles only** — not the modelled streams. We can't query the province without re-running every WSG.

bcfp's `bcfishpass.streams` + `bcfishpass.habitat_linear_<sp>` accumulate. Link should mirror that.

### Design summary

- **Persistent tables** in `<schema>.streams` (segments + geom) + `<schema>.streams_habitat_<sp>` (one per species, wide-per-species like bcfp). Long format was rejected — wide-per-species matches bcfp, gives direct per-species queries, and disk cost is essentially the same.
- **Per-WSG staging** in `working_<wsg>` schema (where every other per-WSG input already lives). New `working_<wsg>.streams`, `working_<wsg>.streams_habitat`, `working_<wsg>.streams_breaks`. Per-WSG isolation gives multi-worker parallelism for free.
- **Parameterize via `pipeline.schema` config knob** — REQUIRED, no default fallback. Enables side-by-side bundle compare (`schema: fresh_bcfp` vs `schema: fresh_default`), within-host parallelism (`schema: fresh_w1`/`fresh_w2`), branch isolation, centralized vs distributed write target.
- **`lnk_persist_init(conn, cfg, species)`** — idempotent `CREATE TABLE IF NOT EXISTS` for the persistent tables.
- **`lnk_pipeline_persist(conn, aoi, cfg, species)`** — DELETE-WHERE-WSG + INSERT pivoting fresh's long-format `working_<wsg>.streams_habitat` into wide-per-species. ~2-5s per WSG.
- **Multi-host** — each host accumulates locally, final `pg_dump --schema=fresh --table=streams --table=streams_habitat_*` on M1+cypher → `pg_restore` on M4.

### Out of scope

- Per-host pg_dump consolidation script (separate data-raw helper)
- Multi-worker per-host orchestration (works after this lands; orchestrator script separate)
- `tables = NULL` override on pipeline functions (debug convenience; add when needed)
- bcfp parity comparison wiring (works after rename — `compare_bcfishpass_wsg` queries `working_<aoi>.streams_habitat` for its rollup)
- Geometry on `streams_habitat_<sp>` tables (geom in `fresh.streams` only; map queries JOIN once per matched segment)

## Key references

- Issue: https://github.com/NewGraphEnvironment/link/issues/112
- bcfp pattern:
  - `bcfishpass.streams` — single accumulator (segments + geom + metadata)
  - `bcfishpass.habitat_linear_<sp>` — per-species, accumulating, booleans only
- fresh's existing per-WSG isolation: `working.streams_<job_label>` — already supports multi-tenant staging via the `job_label` parameter on `frs_habitat()`. Lower-level helpers (`frs_break_apply`, `frs_habitat_classify`) take `table = …` directly so they're already parameterized — only link's hardcoded `"fresh.streams"` literal stops us.
- LRDO drilldown 2026-05-03: had to re-run LRDO just to look at why bcfp's SK barriers credit 2,164 ha less lake_rearing than link does. That should have been a `SELECT` away — directly motivates this issue.

## Decisions locked in (confirmed with user)

| | Decision |
|---|---|
| Schema | `fresh` (default) — but parameterizable via `pipeline.schema` |
| Format | Wide-per-species (one table per species, bcfp pattern) |
| Naming | `<schema>.streams` (persistent) + `working_<wsg>.streams` (staging) — no `_prep` suffix |
| IP layer | Same `<schema>.streams` — access-gated IS the intrinsic |
| `pipeline.schema` cfg knob | Required, no default fallback |
| `tables = NULL` override on pipeline functions | DROP — debug convenience, add when actually needed |
| Backwards compat | Not a goal — clean break is fine |

## Multi-worker / multi-bundle unlocks (free with `pipeline.schema`)

- **Within-host parallelism:** Worker 1 uses `schema: fresh_w1`, worker 2 `fresh_w2`. Two WSGs in parallel on M4 → 2× host throughput. Trifecta with 2 workers per host = 6 effective workers, ~5× speedup over single-host serial.
- **Side-by-side bundle compare:** `bcfishpass/config.yaml` → `schema: fresh_bcfp`; `default/config.yaml` → `schema: fresh_default`. Run both, query both for the methodology-delta comparison without clobber.
- **Branch isolation:** WIP feature uses `schema: fresh_link112_wip` while main keeps `schema: fresh` for cartography.

## Known fragility

- Cross-cfg interference within a run — pipeline phases must use same cfg. Document; don't enforce.
- Concurrent DDL race for `lnk_persist_init` — `IF NOT EXISTS` everywhere makes it safe.
- Stale prep tables across parallel workers — per-WSG schema isolation removes this concern, since each WSG's staging lives in its own `working_<wsg>` schema.
