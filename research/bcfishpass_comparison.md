# bcfishpass v0.5.0 Comparison

fresh 0.13.2 + link 0.1.0 vs bcfishpass v0.5.0 on ADMS watershed group.

## Results (2026-04-13)

| Species | Spawning | Rearing |
|---------|----------|---------|
| BT | +1.2% | +1.9% |
| CH | +0.5% | +2.0% |
| CO | +1.6% | -1.1% |
| SK | +2.6% | +0.0% |

All within 5%. Segments: 14,707 vs 15,764. Total stream km: identical. Channel width table synced from tunnel (75,736 field measurements).

## DAG

```
                  ┌─────────────────────────────────┐
                  │         Config CSVs              │
                  │  (link/inst/extdata/bcfishpass/)  │
                  └──────┬──────┬──────┬─────────────┘
                         │      │      │
    ┌────────────────────┘      │      └────────────────────┐
    ▼                           ▼                           ▼
┌────────────┐          ┌──────────────┐          ┌──────────────────┐
│ crossings  │          │   overrides  │          │ habitat confirms │
│ fresh CSV  │          │ crossing_fixes│         │ user_habitat_    │
│ 533k rows  │          │ pscis_status │          │ classification   │
└─────┬──────┘          └──────┬───────┘          └────────┬─────────┘
      │                        │                           │
      ▼                        ▼                           │
┌──────────────────────────────────┐                       │
│  lnk_load + lnk_override        │                       │
│  Load, validate, apply fixes     │                       │
│  → working.crossings (corrected) │                       │
└──────────────┬───────────────────┘                       │
               │                                           │
               │    ┌──────────────────────────────────┐   │
               │    │  frs_break_find                   │   │
               │    │  Detect gradient barriers on      │   │
               │    │  raw FWA (not broken streams)     │   │
               │    │  → 27,443 barriers (4 classes)    │   │
               │    └──────────┬───────────────────────┘   │
               │               │                           │
               │               ▼                           │
               │    ┌──────────────────────────────────┐   │
               │    │  lnk_barrier_overrides            │   │
               │    │  Full barrier set + observations  │◄──┘
               │    │  + habitat confirms → skip list   │
               │    │  fwa_upstream() per species       │
               │    │  → working.barrier_overrides      │
               │    └──────────┬───────────────────────┘
               │               │
               │               ▼
               │    ┌──────────────────────────────────┐
               │    │  Remove non-minimal barriers      │
               │    │  fwa_upstream() self-join          │
               │    │  27,443 → 677 (most-downstream)   │
               │    └──────────┬───────────────────────┘
               │               │
               ▼               ▼
┌──────────────────────────────────────────────────────────┐
│  Load base segments                                       │
│  Raw FWA + bcfishpass filters + channel_width join         │
│  frs_col_generate (GENERATED gradient/measures/length)    │
│  → 10,458 base segments                                   │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│  Sequential breaking (frs_break_apply × 4)                │
│                                                           │
│  1. Observations         (+165)   ← bcfishobs, filtered  │
│  2. Gradient barriers    (+386)   ← minimal set           │
│  3. Habitat endpoints    (+116)   ← both DRM and URM     │
│  4. Crossings            (+3,582) ← corrected crossings  │
│                                                           │
│  Each round: break in-place → reassign id_segment         │
│  GENERATED columns recompute from new geometry            │
│  1m guard skips near-duplicate positions                   │
│  → 14,707 segments                                        │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│  Build breaks table for access gating                     │
│  FULL gradient barriers (all 27k, not minimal)            │
│  + falls (blocked) + crossings (barrier/potential/etc)    │
│  → fresh.streams_breaks                                   │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│  frs_habitat_classify                                     │
│  Rules YAML + thresholds CSV + params_fresh CSV           │
│  Access gating (full barriers) + barrier_overrides        │
│  Per-species: gradient, channel_width, edge_type,         │
│  waterbody_type → spawning/rearing boolean                │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│  frs_cluster + connected spawning                         │
│  CH/CO: remove disconnected rearing                       │
│  SK: downstream trace (3km) + upstream lake proximity     │
│  → final habitat classification                           │
└──────────────────────────────────────────────────────────┘
```

## Config CSVs — full inventory

All CSVs from `bcfishpass/data/` are now in `link/inst/extdata/bcfishpass/`. Each has a specific role in the pipeline.

### Currently wired into compare_bcfishpass.R

| CSV | Pipeline step | What it does |
|-----|--------------|-------------|
| `user_modelled_crossing_fixes.csv` (21k rows) | Step 3: Override crossings | Imagery/field corrections to modelled crossing barrier status. `structure = 'NONE'/'OBS'` → PASSABLE. |
| `user_pscis_barrier_status.csv` (1.3k rows) | Step 3: Override crossings | Expert barrier status overrides for PSCIS crossings before official submission. |
| `user_habitat_classification.csv` (15k rows) | Step 5: Barrier overrides + Step 6: Habitat endpoints | Confirmed habitat ranges per species. Overrides barriers below confirmed habitat. Both DRM and URM become break positions. |
| `wsg_species_presence.csv` (246 WSGs) | Step 6: Observation filter | Which species are modelled per WSG. Filters bcfishobs observations before breaking. Also in fresh. |
| `observation_exclusions.csv` (1.2k rows) | **Not yet wired** | Flags data errors and release excludes. bcfishpass filters these from observations before breaking. 1 record in ADMS. |

### Not yet wired — crossing/dam sources

| CSV | Pipeline step in bcfishpass | What it does | Impact |
|-----|---------------------------|-------------|--------|
| `pscis_modelledcrossings_streams_xref.csv` (3.6k rows) | PSCIS loading (`04_pscis.sql`) | Manual GPS corrections — matches PSCIS crossings to correct FWA stream when automated matching fails. | Affects which stream a crossing is placed on. Could shift crossing break positions. |
| `user_crossings_misc.csv` (27 rows) | Crossing loading (`load_crossings.sql`) | Adds misc crossings not in PSCIS or modelled inventory (flood control, unassessed culverts, weirs). | 27 extra crossing break positions province-wide. |
| `user_barriers_definite.csv` (228 rows) | Barrier loading (`barriers_user_definite.sql`) | User-identified definite barriers (not falls). Added to per-model barrier tables unconditionally — not filtered by observations. | Always blocks access. Used in sequential breaking. |
| `user_barriers_definite_control.csv` (238 rows) | Model access filtering (`model_access_bt.sql` etc.) | Controls which natural barriers (gradient, falls, subsurface) cannot be overridden by observations. `barrier_ind = TRUE` means "this barrier is real, don't skip it even with fish upstream." | Prevents false overrides. We don't have this control table in `lnk_barrier_overrides`. |

### Not yet wired — CABD (dams and waterfalls)

| CSV | Pipeline step in bcfishpass | What it does | Impact |
|-----|---------------------------|-------------|--------|
| `cabd_blkey_xref.csv` (2 rows) | Dam/falls loading (`load_dams.sql`, `load_falls.sql`) | Corrects CABD feature locations when snapped to wrong flow line. | Moves dam/falls break positions to correct stream. |
| `cabd_exclusions.csv` (13 rows) | Dam/falls loading | Excludes specific CABD records from barrier identification (e.g., removed dams, misclassified features). | Prevents false barriers. |
| `cabd_passability_status_updates.csv` (11 rows) | Dam/falls loading | Overrides CABD passability codes (e.g., dam marked barrier in CABD but actually passable). | Changes barrier status of dams/falls. |
| `cabd_additions.csv` (5 rows) | Manual pre-load | Falls or dams required for bcfishpass but not yet in CABD. Manually added to external tables before pipeline runs. | Adds barriers not in any standard inventory. |

### Not yet wired — habitat/reporting

| CSV | Pipeline step in bcfishpass | What it does | Impact |
|-----|---------------------------|-------------|--------|
| `dfo_known_sockeye_lakes.csv` (302 rows) | Habitat modelling | DFO Conservation Units — identifies waterbodies supporting sockeye. Used in WCRP upstream habitat quantification. | SK lake identification. May affect SK rearing classification. |
| `wcrp_watersheds.csv` (33 rows) | WCRP reporting | Target species per WCRP watershed for upstream habitat rollup. | Reporting only — not core classification. |

## Pipeline detail

### 1. Detect gradient barriers on raw FWA

`frs_break_find` reads `fwa_stream_networks_sp` directly. Vertex-to-vertex gradient with 100m upstream lookahead. 4 classes for bcfishpass config (15/20/25/30%). Island grouping collapses adjacent vertices to one barrier at downstream-most position.

Both systems: 27,443 barriers (matching to 3/50,063 across all 8 classes).

### 2. Build barrier overrides

`lnk_barrier_overrides` uses the FULL barrier set (all 27k). Counts target-species observations upstream via `fwa_upstream()`. Barriers with enough observations added to skip list. Habitat confirmations (`user_habitat_classification.upstream_route_measure`) also override barriers below confirmed habitat.

Per-species thresholds from `parameters_fresh_bcfishpass.csv`:
- BT: >= 1 obs (BT + all salmon/steelhead), any date
- CH/CM/CO/PK/SK: >= 5 obs (salmon only), post-1990

**Missing:** `user_barriers_definite_control.csv` — prevents overriding barriers that are known to be real despite upstream fish observations. Not yet wired into `lnk_barrier_overrides`.

### 3. Remove non-minimal barriers

`fwa_upstream()` self-join on barrier table. Delete any barrier with another barrier downstream. 27,443 → 677.

### 4. Load base segments

Raw FWA with filters:
- `localcode_ltree IS NOT NULL`
- `edge_type != 6010`
- `wscode_ltree <@ '999' IS FALSE`

`frs_col_join` adds `channel_width`. `frs_col_generate` makes gradient/measures/length GENERATED.

10,458 segments (identical).

### 5. Sequential breaking

`frs_break_apply` in-place, one source at a time. GENERATED columns recompute. 1m guard. `id_segment` reassigned between rounds.

| Step | Source | New segments |
|------|--------|-------------|
| 1 | Observations (species-filtered) | +165 |
| 2 | Gradient barriers (minimal) | +386 |
| 3 | Habitat endpoints (DRM + URM) | +116 |
| 4 | Crossings (corrected) | +3,582 |
| **Total** | | **14,707** |

**Missing from breaking order:** bcfishpass also breaks at `user_barriers_definite` positions (228 province-wide, added to per-model tables unconditionally). These are separate from gradient barriers — they're user-identified barriers that always block.

### 6. Access gating

Full gradient barriers (all 27k) + falls + crossings in breaks table. Barrier overrides selectively open access per species.

### 7. Classification + connectivity

`frs_habitat_classify` with rules YAML. `frs_cluster` removes disconnected rearing (CH, CO). SK spawning: downstream trace (3km) + upstream lake proximity (200ha).

## Break sources

No snapping during breaking. All positions pre-computed.

| Source | Origin |
|--------|--------|
| Gradient barriers | Computed from FWA vertex geometry |
| Observations | bcfishobs, species-filtered via `wsg_species_presence.csv` |
| Crossings | `crossings.csv` in fresh (pre-computed) |
| Habitat endpoints | `user_habitat_classification.csv` — both DRM and URM |
| Falls | `falls.csv` in fresh (fwapg `fwa_localize`) |
| User definite barriers | `user_barriers_definite.csv` — **not yet wired** |
| Misc crossings | `user_crossings_misc.csv` — **not yet wired** |

### Observation filtering

Raw bcfishobs identical (592 records, ADMS). Filtered by `wsg_species_presence`. 179 vs 178 unique break positions. `observation_exclusions` not yet applied (1 SK data_error in ADMS — no impact on break positions since co-located with valid BT observation).

### Habitat endpoints

Both DRM and URM per record. 143 vs 145 endpoints.

## Remaining +1-2% bias

| Gap | Status | Expected impact |
|-----|--------|----------------|
| `observation_exclusions.csv` | Not wired | Negligible in ADMS (1 record, co-located) |
| `user_barriers_definite.csv` | Not wired as break source | Adds ~228 barriers province-wide, always block |
| `user_barriers_definite_control.csv` | Not wired into `lnk_barrier_overrides` | Prevents false overrides on known-real barriers |
| `user_crossings_misc.csv` | Not wired | 27 extra crossings province-wide |
| `pscis_modelledcrossings_streams_xref.csv` | Not wired | GPS corrections — shifts crossing positions |
| CABD CSVs (4 files) | Not wired | Dam/falls corrections, exclusions, additions |
| `dfo_known_sockeye_lakes.csv` | Not wired | May affect SK lake identification |
| Segment boundary differences | Structural | Single minimal set vs per-model sequential |
| 179 vs 178 obs positions | Unresolved | Rounding/remap edge case |
| 143 vs 145 habitat endpoints | Unresolved | Rounding on FWA segment boundaries |

## Updates needed

### fresh

| Change | Why |
|--------|-----|
| `frs_break_minimal(conn, table)` | Remove non-minimal barriers. Currently raw SQL. |
| `id_segment` as GENERATED column | Eliminates `reassign_id` hack between break rounds. |
| Export connectivity runner | `lnk_habitat` needs to call `frs_cluster` + connected spawning after `frs_habitat_classify`. |
| `frs_break_find` dual output | Keep full barriers for access gating while using minimal for segmentation. |

### link

| Change | Why |
|--------|-----|
| `lnk_habitat(conn, wsg, config)` | Top-level orchestrator wrapping the full DAG. |
| Wire `observation_exclusions.csv` | Filter observations before breaking. |
| Wire `user_barriers_definite.csv` | Add as break source (always blocks). |
| Wire `user_barriers_definite_control.csv` | Add `control` param to `lnk_barrier_overrides`. |
| Wire `user_crossings_misc.csv` | Add to crossings loading. |
| Wire `pscis_modelledcrossings_streams_xref.csv` | GPS corrections for `lnk_match`. |
| Wire CABD CSVs | Dam/falls corrections, exclusions, passability overrides. |
| Config system | Named bundles per config (`"bcfishpass"`, `"default"`). |
| `lnk_stamp()` | Record config + versions in output. |
| GitHub Action: sync bcfishpass CSVs | Scheduled PR when upstream `data/*.csv` changes. |

## Versions

- fresh: 0.13.2
- bcfishpass: v0.5.0 (CSVs synced 2026-04-13 from smnorris/bcfishpass main @ e485fe4)
- link: 0.1.0
- fwapg: Docker local (FWA 20240830, channel_width synced from tunnel 2026-04-13)
- PostgreSQL: local 17.5 (aarch64), tunnel 16.2 (x86_64)
- PostGIS: local 3.5.2, tunnel 3.4.2
