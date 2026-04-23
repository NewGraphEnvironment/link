# bcfishpass Comparison

fresh 0.14.0 + link 0.4.0 vs bcfishpass (reference `habitat_linear_*` tables on tunnel, bcfishpass ea3c5d8, fwapg 20240830).

## Correctness bar

**Bit-identical output from the same inputs.** Three consecutive `tar_make()` runs on 2026-04-22 produced the exact same 34-row rollup tibble (`data-raw/logs/20260422_{10,11,12}_*.txt`). Parity to bcfishpass (the `diff_pct` column in the rollup) is an informational diagnostic, not the pass/fail standard.

## Results (2026-04-22, rollup from `tar_make()`)

All species within 5% of bcfishpass reference. Pipeline runs serially in ~8.5 min wall clock.

### ADMS

| Species | Spawning | Rearing |
|---------|----------|---------|
| BT | +1.8% | -1.1% |
| CH | +0.5% | +2.3% |
| CO | +1.6% | -0.1% |
| SK | +3.7% | +0.0% |

### BULK

| Species | Spawning | Rearing |
|---------|----------|---------|
| BT | +3.1% | -2.2% |
| CH | +1.9% | +2.6% |
| CO | +3.1% | +0.4% |
| PK | +2.3% | N/A |
| SK | -0.7% | +0.0% |
| ST | +1.9% | -0.1% |

### BABL

| Species | Spawning | Rearing |
|---------|----------|---------|
| BT | +4.1% | -1.9% |
| CH | +3.8% | +2.1% |
| CO | +4.8% | +0.8% |
| SK | -2.8% | +0.0% |
| ST | +3.8% | -1.3% |

### ELKR

| Species | Spawning | Rearing |
|---------|----------|---------|
| BT | +2.8% | -1.2% |
| WCT | +2.6% | +0.3% |

Updated 2026-04-23 (#48) — #48 removed `barriers_definite` from `natural_barriers`, which stopped observation-based override of user-definite positions (Erickson Creek exclusion + 2 Spillway MISC entries). Those four positions now correctly block upstream habitat, bringing link toward bcfishpass. Pre-#48 numbers: BT +3.4% / -0.7%, WCT +4.0% / +1.6%.

### DEAD

Added 2026-04-23 (#44) as the end-to-end test for `barriers_definite_control`. DEAD has a single `barrier_ind = TRUE` control row at FALLS (356361749, 45743) with six anadromous observations upstream in the CH/CM/CO/PK/SK pool and zero habitat-classification coverage — the unique combination that actively exercises the filter. Pre-fix link would have overridden the fall (six observations exceed the threshold of five; habitat-path coverage absent); post-fix link correctly blocks the override for anadromous species and matches bcfishpass, which keeps the fall in `barriers_ch_cm_co_pk_sk` post-override. BT is allowed to override the fall because `observation_control_apply = FALSE` for BT — mirrors bcfishpass's `model_access_bt.sql` which has no control join.

| Species | Spawning | Rearing |
|---------|----------|---------|
| BT | +2.1% | -0.2% |
| CH | +1.4% | +1.4% |
| CO | +1.3% | -0.3% |
| PK | +1.1% | N/A |
| ST | +1.3% | +0.0% |

## DAG

```mermaid
flowchart TD
    CSVs["Config CSVs<br/>crossings · falls · overrides · habitat confirms<br/>rules YAML · dimensions · wsg_species_presence"]

    CSVs --> Load["lnk_load + lnk_override<br/>Load crossings<br/>Apply modelled fixes + PSCIS overrides"]
    CSVs --> Find["frs_break_find<br/>Gradient barriers on raw FWA<br/>4 classes (15/20/25/30 percent)"]
    CSVs --> BarOver["lnk_barrier_overrides<br/>Observations + habitat confirms<br/>skip list per species"]

    Find --> Minimal["Non-minimal removal<br/>fwa_upstream self-join<br/>27,443 → 677 barriers (ADMS)"]

    Load --> Base["Load base segments<br/>Raw FWA + filters + channel_width<br/>stream_order_parent + frs_col_generate"]
    Minimal --> Base

    Base --> Break["Sequential breaking (frs_break_apply × 4)<br/>Observations → Gradient minimal → Habitat endpoints → Crossings"]

    Break --> Breaks["Build breaks table<br/>FULL gradient + falls + crossings<br/>WSG-filtered for access gating"]

    Breaks --> Classify["frs_habitat_classify<br/>Rules YAML + thresholds<br/>Access gating + barrier overrides<br/>Per-species: gradient · channel_width · edge_type · waterbody"]
    BarOver --> Classify

    Classify --> Cluster["frs_cluster (three-phase)<br/>Phase 1: on-spawning always valid<br/>Phase 2: upstream boolean (below spawning)<br/>Phase 3: FWA_Downstream mainstem (above spawning)"]

    Cluster --> Conn["frs_connected_waterbody (SK)<br/>Subtractive: remove spawning not near rearing lake<br/>Additive: spawn_connected in downstream trace"]

    classDef fresh fill:#e1f5ff,stroke:#0066cc,color:#003366
    classDef link fill:#fff3e1,stroke:#cc6600,color:#663300
    classDef op fill:#f0f0f0,stroke:#666,color:#333
    class Find,Classify,Cluster,Conn fresh
    class Load,BarOver link
    class CSVs,Minimal,Base,Break,Breaks op
```

Blue = `fresh` functions. Orange = `lnk_` functions. Grey = composite operations (multiple function calls bundled into one step).

## Targets orchestration

`data-raw/_targets.R` runs the pipeline DAG above once per watershed group and rolls the results up:

```mermaid
flowchart LR
    cfg["lnk_config('bcfishpass')<br/>(loaded once)"]

    cfg --> ADMS["compare_bcfishpass_wsg<br/>ADMS"]
    cfg --> BULK["compare_bcfishpass_wsg<br/>BULK"]
    cfg --> BABL["compare_bcfishpass_wsg<br/>BABL"]
    cfg --> ELKR["compare_bcfishpass_wsg<br/>ELKR"]
    cfg --> DEAD["compare_bcfishpass_wsg<br/>DEAD"]

    ADMS --> rollup["rollup<br/>46 rows · wsg × species × habitat_type × km × diff_pct"]
    BULK --> rollup
    BABL --> rollup
    ELKR --> rollup
    DEAD --> rollup

    classDef root fill:#eef,stroke:#336;
    classDef wsg  fill:#efe,stroke:#363;
    classDef sink fill:#fee,stroke:#633;
    class cfg root
    class ADMS,BULK,BABL,ELKR,DEAD wsg
    class rollup sink
```

Runs serially (`fresh.streams` is a shared output schema; parallel workers would race). Distributed M4+M1 execution via `crew.cluster` is deferred until fresh supports a per-AOI output path — see `planning/active/findings.md` and `rtj/docs/distributed-fwapg.md`.

## Pipeline operations

Composite steps in the DAG that aren't a single function call:

- **Non-minimal removal** — `fwa_upstream()` self-join that deletes gradient barriers which have another gradient barrier downstream. 27,443 → 677 on ADMS. Leaves only the furthest-downstream barrier per reach so the sequential breaking pass isn't redundant.
- **Load base segments** — raw FWA filtered to the AOI (`localcode_ltree IS NOT NULL`, `edge_type != 6010`, no coastlines), with `channel_width` joined from `fwa_stream_networks_channel_width` and `stream_order_parent` from `fwa_stream_networks_order_parent`. `frs_col_generate` adds GENERATED columns for gradient, measures, length.
- **Sequential breaking** — `frs_break_apply` called 4 times in order: observations → minimal gradient barriers → habitat endpoints (DRM + URM) → crossings. Each round reassigns `id_segment`, recomputes GENERATED columns; 1m guard prevents duplicate breaks.
- **Build breaks table** — reassembly of gradient barriers (FULL, not minimal) + falls + crossings, filtered to WSG. Used for access gating during classification.

## Key fixes during comparison

| Fix | Impact | Type |
|-----|--------|------|
| ST observation_species: "ST" → "CH;CM;CO;PK;SK;ST" | -22% → +3.8% | CSV cell |
| WCT observation_threshold: NA → 1 | -4.2% → +3.0% | CSV cell |
| BT cluster_rearing: FALSE → TRUE | +7% → +1.3% | CSV cell |
| SK outlet ordering: DRM → wscode | -22.6% → -0.7% | fresh code (0.13.5) |
| SK spawn_connected additive step | -9.6% → -0.7% | fresh code (0.13.6) |
| Three-phase cluster | CH +6% → +2.6% | fresh code (0.13.8) |
| Index input tables | 228s → 6.6s classification | fresh code (0.13.4) |
| Wire `barriers_definite_control` into override step, per-species, observation-path only | DEAD CH/CO/PK/ST +1.1 to +1.4% (moot on ADMS/BULK/BABL/ELKR) | link code (0.6.0) |
| Drop `barriers_definite` from `natural_barriers` (not eligible for observation override) | ELKR BT spawn +3.4% → +2.8%, WCT spawn +4.0% → +2.6%, WCT rear +1.6% → +0.3% | link code (0.7.0) |

### barriers_definite_control wiring (#44)

bcfishpass pairs `user_barriers_definite.csv` with a control table that flags positions as non-overridable (`barrier_ind = TRUE`) — known fish-blocking dams, long impassable falls, diversions. Historical observations upstream should not re-open these barriers. link's override step was not honouring this table. Three fixes land together in 0.6.0:

1. **Observation-path filter.** `lnk_barrier_overrides()` excludes observations from counting toward the override threshold when the barrier position has a matching TRUE control row. Uses `NOT EXISTS` rather than a LEFT JOIN so the outer `HAVING count(...) >= threshold` aggregation is not row-multiplied.
2. **Per-species application.** New column `observation_control_apply` in `parameters_fresh.csv` (TRUE for CH/CM/CO/PK/SK/ST; FALSE for BT/WCT) gates the filter. Residents inhabit reaches upstream of anadromous-blocking falls routinely (post-glacial headwater connectivity), so their observations still override. Matches bcfishpass's per-model SQL — `model_access_bt.sql` has no control join; `model_access_ch_cm_co_pk_sk.sql` and `model_access_st.sql` do.
3. **Habitat path untouched.** Expert-confirmed habitat is higher-trust than observations; it bypasses the control table, consistent with bcfishpass's `hab_upstr` CTE which has no control join.

End-to-end validation on DEAD (added specifically for this reason — see section above). Numerical impact on the four original WSGs is zero because every TRUE control row is already rescued by the observation threshold or the habitat path; the filter is correctly wired but inactive on those WSGs.

### user_barriers_definite bypass (#48)

Same-family fix as #44, different mechanism. bcfishpass's `model_access_*.sql` builds its barriers CTE from gradient + falls + subsurfaceflow only; `barriers_user_definite` is appended post-filter via `UNION ALL`, so upstream observations and habitat confirmations never re-open user-definite positions. link's `.lnk_pipeline_prep_natural()` was unioning `barriers_definite` into `natural_barriers`, which `lnk_barrier_overrides()` iterates over — the 227 reviewer-added user-definite rows (EXCLUSION zones, MISC-type barriers) became eligible for observation override.

Active defect on ELKR pre-fix: 4 rows in `working_elkr.barrier_overrides` matched `working_elkr.barriers_definite` positions — Erickson Creek exclusion (mining impacts) and two Spillway MISC entries. Post-fix: 0 matches on all 5 WSGs, and ELKR rollup shifts toward bcfishpass on BT/WCT spawning and rearing (see per-WSG table above). Other four WSGs unchanged: ADMS/BABL/DEAD have empty `barriers_definite`; BULK has 87 rows but none have observation counts clearing threshold.

Fix is a single edit to `.lnk_pipeline_prep_natural()` — drop the `INSERT INTO natural_barriers SELECT ... FROM barriers_definite` block. `barriers_definite` stays consumed separately: `lnk_pipeline_break()` applies it as a sequential break source (segmentation boundary); `lnk_pipeline_classify()` UNION ALLs it directly into `fresh.streams_breaks` (access-gating barrier set). Both surfaces are unchanged.

## Remaining gaps

### BT rearing -2.2% (BULK)

bcfishpass applies `stream_order = 1 AND stream_order_parent >= 5` as a rearing cw bypass in all three rearing phases. We don't replicate this because the bypass interacts with clustering — applying it pre-cluster inflates rearing, applying it post-cluster adds segments without connectivity constraints. The 68 km gap is the bypass segments we don't capture.

`frs_order_child` (fresh#158) will address this with a biologically-tuned approach: direct children only (`stream_order = stream_order_max`), distance cap from tributary mouth.

### Spawning +1-4% consistent positive bias

All species show +1-4% spawning excess. From segment boundary differences — our single-pass non-minimal barrier removal creates slightly different segment boundaries than bcfishpass per-model sequential breaking. Different boundaries → different per-segment gradients → different threshold pass/fail at edges.

## Break sources

All positions pre-computed. No snapping during breaking.

| Source | Origin |
|--------|--------|
| Gradient barriers | Computed from FWA vertex geometry |
| Observations | bcfishobs (species-filtered via wsg_species_presence.csv) |
| Crossings | crossings.csv in fresh (pre-computed) |
| Habitat endpoints | user_habitat_classification.csv (both DRM and URM) |
| Falls | falls.csv in fresh |

## Versions

- fresh: 0.13.8
- link: main (7f5d880)
- bcfishpass: ea3c5d8 (post-v0.7.13), tunnel model run v0.7.12
- fwapg: Docker (FWA 20240830, channel_width synced from tunnel 2026-04-13)
