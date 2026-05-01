# Findings — link#88

## Diagnosis (2026-04-30)

### Single-stream trace: HARR blkey 356286055

- link `fresh.streams_habitat`: 21 segments, all `rearing=FALSE` for BT, all `accessible=FALSE` for BT
- bcfp `streams_access`: `access_bt = 1` on every segment, `barriers_bt_dnstr = {}` (zero natural BT barriers)
- bcfp `barriers_anthropogenic_dnstr`: 2 entries (DAM at 356282804 DRM 739, ROAD/DEMOGRAPHIC at 356282804 DRM 658) — both flagged in `barriers_remediations` (REMEDIATED)
- Two **subsurfaceflow** points downstream on 356282804 (DRMs 265, 279) in `barriers_subsurfaceflow`
- 55 anadromous obs (CH/CM/CO) upstream of (356282804, 265) — clears bcfp's threshold (1 for BT, 5 for anadromous)
- bcfp lifts both subsurfaceflow points → `barriers_bt` and `barriers_ch_cm_co_pk_sk` empty in this drainage → BT/CH/CO credit upstream

### Why link doesn't lift

`lnk_pipeline_prepare()` build order (current):

1. `prep_load_aux` → falls, definite, control, habitat
2. `prep_gradient` → gradient_barriers_raw (pruned, ltree-enriched)
3. **`prep_natural` → `<schema>.natural_barriers` = gradient + falls** ← subsurfaceflow NOT here
4. `prep_overrides` → calls `lnk_barrier_overrides(barriers = natural_barriers)` → per-species skip list
5. **`prep_subsurfaceflow`** (opt-in) → `<schema>.barriers_subsurfaceflow` ← runs AFTER overrides

`lnk_pipeline_classify_build_breaks()` then UNIONs `barriers_subsurfaceflow` directly into `fresh.streams_breaks` with label `blocked`. Since the override skip list never saw it, `frs_habitat_classify(barrier_overrides = ...)` cannot lift it. All species get blocked at the subsurfaceflow position.

### bcfishpass natural barrier construction (per-species)

`model/01_access/sql/model_access_bt.sql` — `barriers_bt`:

- gradient_25 + gradient_30 + falls + **subsurfaceflow** + user_definite
- LIFT: any obs upstream (BT/CH/CM/CO/PK/SK/ST), or any habitat upstream
- user_definite always retained

`model/01_access/sql/model_access_ch_cm_co_pk_sk.sql` — `barriers_ch_cm_co_pk_sk`:

- gradient_15/20/25/30 + falls + **subsurfaceflow** + user_definite
- LIFT: ≥5 anadromous obs upstream (post-1990), or any habitat upstream
- `user_barriers_definite_control.barrier_ind = TRUE` blocks the obs lift; habitat lift unaffected
- user_definite always retained

bcfp's `barriers_anthropogenic` (PSCIS, dams, road crossings) is **NOT** in the per-species barrier set. It's tracked separately for downstream-of-crossing accountability. Anthropogenic barriers don't gate species access in bcfp's habitat sums.

### Design diagnosis

`.lnk_pipeline_prep_subsurfaceflow` was added in PR #82 as its own helper. Treated subsurfaceflow as a parallel concept needing a parallel pipeline phase. But subsurfaceflow is just **a third row in the same union** that `prep_natural` already builds for gradient + falls. The wiring miss: subsurfaceflow's positions never reached `natural_barriers`, so the per-species lift skipped it entirely.

`prep_natural` is the right home — bcfp's source of truth confirms gradient + falls + subsurfaceflow is *the* natural-barrier union per species.

### Where it surfaces (15-WSG rollup, parity)

| WSG  | sp | metric          | link | bcfp | diff_pct |
|------|----|-----------------|------|------|---------:|
| HARR | CH | rearing_stream  | 118  | 139  | -14.8 |
| HARR | CO | rearing_stream  | 134  | 155  | -13.3 |
| HARR | ST | rearing_stream  | 157  | 177  | -11.6 |
| HARR | BT | rearing_stream  | 292  | 326  | -10.4 |
| HORS | BT | rearing_stream  | 366  | 396  |  -7.7 |
| LFRA | BT | rearing_stream  | 1020 | 1103 |  -7.5 |
| LFRA | BT | rearing         | 1670 | 1800 |  -7.2 |
| HORS | CH | rearing_stream  | 167  | 179  |  -6.8 |

LILL/VICT unaffected — sparse subsurfaceflow + sparse fish observations above what does exist.

## What is NOT involved

- #83 (anthropogenic dam design): the dam at DRM 739 and road at DRM 658 carry `barrier`/`potential` labels in `fresh.streams_breaks`. Default `label_block = "blocked"` means they don't gate. Not the cause.
- `barriers_definite`: intentionally separate per bcfp — never lifted via obs/hab. Link mirrors that.
- `barriers_remediations`: bcfp tracks for downstream reporting only; doesn't gate access.

## Versions at diagnosis

- link 0.19.0 (commit e4e7a6e)
- fresh 0.25.0
- bcfishpass 440bc1e (2026-04-28)
- fwapg local Docker (port 5432)
