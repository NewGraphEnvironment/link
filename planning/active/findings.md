# Findings — Ingest CABD dams as parallel reporting dimension (#103)

## Issue context

link does not ingest dam locations from CABD. bcfp pulls them from `cabd.dams` + applies four edit CSVs (`cabd_exclusions`, `cabd_blkey_xref`, `cabd_passability_status_updates`, `cabd_additions` filtered to `feature_type='dams'`).

**Important framing:** bcfp's per-species access models AND habitat_linear models are **dam-blind** — verified across all 5 `model_access_*.sql` and 8 `load_habitat_linear_*.sql` files: zero references to `barriers_dams`, `barriers_anthropogenic`, or `barriers_pscis`. Dams in bcfp live as a **parallel reporting dimension** (the `bcfishpass.dams` table) that downstream consumers compose with habitat output for reports, WCRP tracking, and dam-impact analyses.

This issue is **not a habitat-parity gap** — fixing it will not close any rollup deltas. It's a **reporting-data gap**: real-world habitat above Stave / Alouette / Campbell / Strathcona dams is materially blocked, but bcfp's habitat output is dam-blind and link's would be too.

## bcfp's load_dams.sql, mapped

`bcfp/model/01_access/sql/load_dams.sql` — same shape as load_falls.sql, four CABD-edit CSVs:

```sql
-- 1. Pull CABD dams, exclude false positives, snap blkey via xref
with cabd as (
  select d.cabd_id as dam_id, blk.blue_line_key, st_transform(d.geom, 3005) as geom
  from cabd.dams d
  left outer join bcfishpass.cabd_exclusions x on d.cabd_id = x.cabd_id
  left outer join bcfishpass.cabd_blkey_xref blk on d.cabd_id = blk.cabd_id
  where x.cabd_id is null
),

-- 2. Snap to nearest stream segment within 65 m
matched as ( ...lateral join on fwa_stream_networks_sp... ),

-- 3. Apply passability override + carry CABD attributes (height_m, owner, dam_use, operating_status)
cabd_pts as (
  select n.*, cabd.dam_name_en, cabd.height_m, cabd.owner, cabd.dam_use, cabd.operating_status,
         coalesce(u.passability_status_code, cabd.passability_status_code) as passability_status_code
  from matched n
  inner join cabd.dams cabd on n.dam_id = cabd.cabd_id
  left outer join bcfishpass.cabd_passability_status_updates u on n.dam_id = u.cabd_id
),

-- 4. US dam placeholders (Grand Coulee, Ross) — additions where feature_type='dams'
usa as ( ... select from bcfishpass.cabd_additions where feature_type = 'dams' ... )

insert into bcfishpass.dams (...) select * from cabd_pts union all select ... from usa;
```

## What's in `cabd_additions.csv` for dams (currently 4 rows)

All four are **US-side dam placeholders** for trans-border flows — Grand Coulee Dam x4 entries on different blkeys (different streams flowing into the Columbia → Grand Coulee impoundment), and Ross Dam x1. **No domestic-BC dam additions** in the current CSV. The CABD source itself covers all the BC dams; additions exists to handle CABD's BC-only geographic scope.

## CABD edit CSVs — current row counts

The same 4 CSVs that link#102 (closed) was going to wire for falls. They apply to dams too — they key on `cabd_id` which spans both `cabd.waterfalls` and `cabd.dams`.

| CSV | Function | Rows | Dams relevance |
|---|---|---|---|
| `cabd_exclusions.csv` | Drop specific cabd_ids | 12 | Some dams likely |
| `cabd_passability_status_updates.csv` | Override `passability_status_code` | 12 | Some dams likely |
| `cabd_blkey_xref.csv` | Override blkey snap | 1 | Tiny |
| `cabd_additions.csv` (dams rows) | Add features missing from CABD | **4** | US placeholders only |

All four are actively wired in bcfp's `01_access` pipeline. None deprecated.

## Why we didn't find this gap on the falls side

link#102 detective work showed fresh's static `falls.csv` was already extracted from CABD at the barrier-truth subset level — fresh's per-WSG barrier counts matched bcfp's `bcfishpass.falls WHERE barrier_ind=true` across all 187 BC WSGs. fresh `falls.csv` row-level identical to bcfp on CAMB.

There's no equivalent shortcut for dams. There's no `dams.csv` shipped in fresh; link doesn't see dam features at all today. Has to be wired from CABD.

## Verification expectations

For verification (Phase 6), the load-bearing test is "habitat output byte-identical to pre-fix baseline post-data-ingestion." If the rollup shifts after wiring this in, the dams data is leaking somewhere it shouldn't (into `streams_breaks`, into `barrier_overrides`, into per-species classification). The wire-up has to be carefully gated to the parallel data layer only.
