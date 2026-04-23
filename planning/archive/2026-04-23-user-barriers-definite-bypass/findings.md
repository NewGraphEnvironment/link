# Findings — #48 (user_barriers_definite bypass)

## Pre-fix defect on ELKR (2026-04-23, via post-#47 tar_make state)

Query: `SELECT * FROM working_<wsg>.barrier_overrides bo INNER JOIN working_<wsg>.barriers_definite bd ON bd.blue_line_key = bo.blue_line_key AND abs(bd.downstream_route_measure - bo.downstream_route_measure) < 1` across 5 WSGs:

- ADMS: 0 rows in barriers_definite → no matches possible
- BULK: 87 rows in barriers_definite, 0 matches in barrier_overrides
- BABL: 0 rows in barriers_definite → no matches possible
- ELKR: 7 rows in barriers_definite, **4 matches** in barrier_overrides
- DEAD: 0 rows in barriers_definite → no matches possible

ELKR matches:

| Species | Position | Type | Name |
|---------|----------|------|------|
| BT | (356549622, 42) | EXCLUSION | Erickson Creek exclusion (mining impacts per CSV note) |
| WCT | (356549622, 42) | EXCLUSION | Erickson Creek exclusion |
| WCT | (356553439, 574) | MISC | Spillway |
| WCT | (356560765, 2935) | MISC | Spillway |

These are user-definite positions that link's pipeline treats as overridable. Post-fix they should stay as permanent blockers (matching bcfishpass). Current ELKR rollup: BT spawn +3.4% / rear -0.7%; WCT spawn +4.0% / rear +1.6%. Fixing this should bring spawning numbers down toward 0.

## Architecture comparison

**bcfishpass** — `model_access_*.sql`:

```sql
barriers CTE = gradient + falls + subsurfaceflow    -- NO user_definite
... (observation filter, habitat filter, control filter all operate on barriers CTE)
barriers_filtered as (... where n_obs < threshold and h.species_codes is null)
INSERT INTO barriers_<model>
  SELECT * FROM barriers_filtered
  UNION ALL
  SELECT * FROM bcfishpass.barriers_user_definite WHERE wsg = :wsg   -- appended post-filter
```

**link today** — `.lnk_pipeline_prep_natural()`:

```r
CREATE TABLE natural_barriers FROM gradient_barriers_raw     -- base
INSERT INTO natural_barriers SELECT FROM falls               -- + falls
INSERT INTO natural_barriers SELECT FROM barriers_definite   -- + user-definite (WRONG — subjects to override)
```

Then `.lnk_pipeline_prep_overrides()` passes `natural_barriers` to `lnk_barrier_overrides()`, which emits per-species override rows for any barrier meeting threshold — including user-definite.

## Shape A (chosen)

1. Drop the `INSERT INTO natural_barriers SELECT FROM barriers_definite` block in `.lnk_pipeline_prep_natural()`.
2. In `.lnk_pipeline_prep_minimal()`, after `frs_barriers_minimal()` emits each per-model reduced table, append `barriers_definite` rows (already WSG-filtered at load time) via `INSERT ... SELECT ... ON CONFLICT DO NOTHING`. Also append to the union that produces `gradient_barriers_minimal` so segmentation breaks include user-definite.

## natural_barriers callers

Grep confirms `natural_barriers` only referenced in:

- `.lnk_pipeline_prep_natural()` (builds)
- `.lnk_pipeline_prep_overrides()` (passes to `lnk_barrier_overrides()`)
- `.lnk_pipeline_prep_minimal()` (reads into `frs_barriers_minimal()`)

Shape A is safe — no external consumers.
