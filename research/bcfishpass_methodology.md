# bcfishpass methodology — canonical reference

Living doc capturing bcfishpass's per-species classification logic, link's matching dimensions, and methodology choices we've made (or deferred). Cross-links: `research/bcfishpass_comparison.md` (rollup history + bug fixes), `research/dimensions_audit.md` (per-column audit), open issues, and merged PRs.

## Per-species rear-rule waterbody filter (verified 2026-04-30)

Read directly from `bcfishpass/model/02_habitat_linear/sql/load_habitat_linear_<sp>.sql`, "REARING ON SPAWNING STREAMS" INSERT.

| species | rear-rule waterbody filter | edge types | wetland-flow (1050/1150) | dimensions mapping |
|---|---|---|---|---|
| BT | **none** (no waterbody filter, no edge filter) | all | yes | `rear_all_edges = yes` |
| CH | strict: `wb='R' OR (wb IS NULL AND edge IN list)` | 1000/1100/2000/2300 | no | `rear_stream_in_waterbody = no` |
| CM | no freshwater rearing | — | — | `rear_no_fw = yes` |
| CO | permissive: `wb='R' OR wb IS NULL OR edge IN list` | 1000/1100/2000/2300/**1050/1150** | yes | `rear_stream_in_waterbody = yes`, `rear_wetland = yes` |
| PK | no freshwater rearing | — | — | `rear_no_fw = yes` |
| SK | lake only | — | — | `rear_lake_only = yes` |
| ST | permissive: `wb='R' OR wb IS NULL OR edge IN list` | 1000/1100/2000/2300 | no | `rear_stream_in_waterbody = yes` |
| WCT | strict: `wb='R' OR (wb IS NULL AND edge IN list)` | 1000/1100/2000/2300 | no | `rear_stream_in_waterbody = no` |

bcfp's spawn rule is **strict** (`wb='R' OR (wb IS NULL AND edge IN list)`) for every species — `spawn_stream_in_waterbody = no` everywhere matches.

## FWA edge type composition in fresh.streams

Empirically observed on a MORR pipeline run (2026-04-30, post-fix):

| edge_type | category | description | segments | km | notes |
|---|---|---|---|---|---|
| 1000 | stream | Single line blueline, main flow | 12,501 | 4,760 | bulk of network — real streams |
| 1200 | construction | Construction line, main flow | 1,261 | 234 | topological / centerline scaffolding |
| 1050 | stream | Single line blueline, main flow through wetland | 867 | 119 | stream flowing through wetland |
| 1450 | connector | Construction line, connection | 668 | 190 | synthetic links |
| 1250 | construction | Construction line, double line river, main flow | 498 | 148 | river polygon centerline |
| 1100 | stream | Single line blueline, secondary flow | 43 | 9 | secondary streams |
| 1410 | connector | Construction line, network connector | 41 | 10 | already a barrier in bcfp (subsurface-style) |
| 1350 | construction | Construction line, double line river, secondary flow | 14 | 3 | river polygon secondary |
| 1150 | stream | Single line blueline, secondary flow through wetland | 7 | 1 | secondary through wetland |
| 1300 | construction | Construction line, secondary flow | 5 | 0.5 | rare |
| 1400 | connector | Construction line, other flow/inferred connection | 5 | 1 | rare |
| 2000 | canal | Single line, Canal | 2 | 0.4 | irrigation |

`frs_network_segment` filters at the network-build phase. Edge types **NOT** in fresh.streams (excluded upstream): lake shorelines (1500, 1525), wetland shorelines (1700), river polygon banks (1800–1875), island shorelines (1600+), watershed boundaries (5000+), coastlines (100, 150), and others. `rear_all_edges = yes` for BT therefore pulls in only what's in fresh.streams — the dubious geometry (boundaries, island perimeter, bare shorelines) was already screened out.

## Methodology choices we've made (or deferred)

### 1. Subsurface flow (edge_type 1425) — opt-in barrier, NOT default-excluded

**Status**: subsurface is NOT auto-excluded as a barrier in defaults. The default-bundle config doesn't list `subsurfaceflow` in `pipeline.break_order` — the bundle gets stream connectivity through subsurface stretches. The bcfishpass-bundle DOES opt in to subsurfaceflow as a barrier (parity).

**Why deferred**: subsurface flow flagging in FWA is unreliable in similar shape to "intermittent" stream flagging — both depend on FWA-internal classifications that vary in quality across regions. Treating subsurface as automatic barrier loses real habitat in regions where the classification is over-aggressive. Treating it as automatic flow-through over-credits where subsurface stretches actually do block fry passage.

**What we want**: deliberate per-config choice (already wired — `pipeline.break_order` controls it) plus eventual research into:
- where in BC the subsurface flagging is reliable
- which species / life stages care
- alternative evidence (mapped channel sites, observed dry-season presence, etc.)

Tracked separately. Not in any open issue today.

### 2. Wetland shoreline (1700) — NOT in linear rollups, area metric covers it

**Status**: edge type 1700 (wetland shoreline) is NOT in fresh.streams (filtered upstream by `frs_network_segment`). Even if it were, we would NOT include it in the linear (km) rearing rollup because:

- We already credit wetland flow-through (edge types 1050, 1150) as linear rearing where the species rule includes them (`rear_wetland = yes` for CO, default-bundle ST/WCT).
- Wetland habitat is also captured by the **area** metric (`wetland_rearing_ha` rollup column from `fwa_wetlands_poly` join).
- Linear-km AND area-ha for the same wetland is double-counting.

**What's tempting but out of scope**: shoreline-edge-as-its-own-metric (e.g. "perimeter km of wetland edge accessible to fry"). Could be a separate dimension and rollup column. Not now.

### 3. BT `rear_all_edges = yes` — kept because frs_network_segment already screens

bcfp BT has no edge_type filter at all. We match in dimensions. Concern was that it would pull in dubious geometry (boundaries, island perimeter, bare shorelines). The MORR composition above shows those edge types are not in fresh.streams to begin with. The remaining `construction` and `connector` edges that DO make it in (1200, 1250, 1300, 1350, 1400, 1450) are real flow representations (river-polygon centerlines, network connectors) that BT plausibly uses.

Default-bundle keeps this for now. Revisit if a future analysis surfaces over-credit on construction-line segments.

### 4. `rear_stream_order_bypass = no` everywhere — deferred until system supports it

bcfp's per-species rear rules include an inline order-bypass: `(cw >= rear_cw_min OR (stream_order_parent >= 5 AND stream_order = 1))` — first-order tributaries of order-5+ mainstems bypass channel-width minimum. Currently link's dimensions has `rear_stream_order_bypass = no` for all species (matches bcfp via inline parity workaround in older compare scripts that no longer exists). Switching to `yes` would emit a `channel_width_min_bypass` rule predicate but we haven't validated the predicate evaluation produces the same result as bcfp's inline logic.

Deferred until we can verify the predicate behaviour in a focused test. Open issue in the audit doc; track separately.

## Recently-fixed parity gaps

- **fresh#186** (closed in v0.25.0) — `frs_cluster` phase-1 + confluence-boost interaction. Removed link's over-credit on tributary clusters above gradient barriers.
- **fresh#187** (closed in v0.25.0) — `.frs_trace_downstream` averaged-FWA gradient hid localized lake-outlet barriers. KISP SK spawning collapsed from +42.3% to 0.0% exact match.
- **dimensions.csv ST + CO `rear_stream_in_waterbody`** (this commit) — flipped `no → yes` to match bcfp's permissive stream-in-waterbody handling. Closed ~50 km of MORR ST under-credit, brought CO to exact parity. Single largest single-edit improvement in the parity slice.

## Remaining >5% departures (post-fix, 10-WSG run)

Out of 210 spawning/rearing/rearing_stream rows × 2 configs:

| wsg | species | metric | link | bcfp | diff_pct | status |
|---|---|---|---|---|---|---|
| BULK | SK | spawning | 27.1 | 24.4 | +11.0 | **parked** — see "Known parked departures" below |

**One row.** Down from 7 outliers >5% before this work cycle.

## Known parked departures

### BULK SK spawning multi-lake topology — fresh#190

Single-stream over-credit on `blue_line_key 360846413` (link 6.38 km vs bcfp 3.70 km, 2.68 km extra). Stream has TWO qualifying SK rearing lakes (Elwin 287.9 ha at DRM 9,718–12,896 + Day Lake 316.8 ha at DRM 15,924+) on the same drainage. bcfp's upstream-spawning logic (`load_habitat_linear_sk.sql` lines 137–253) and fresh's `.frs_connected_waterbody` Phase 2 (`R/frs_habitat.R:1494–1540`) are structurally identical (same DBSCAN cluster + 2m lake-polygon proximity check), but produce different segment sets on this specific topology.

Three hypotheses (not pinned down):
1. Spawn-eligible input set differs at the cluster-input step
2. DBSCAN cluster spans both lakes and the union geometry touches one qualifying polygon, dragging in segments bcfp would have isolated to a separate non-touching cluster
3. Polygon-edge precision in the 2m `ST_DWithin` check

**Why parked**: 2.68 km absolute on one stream out of 27.06 km of BULK SK spawning. SK spawning is exact or near-exact on every other tested WSG (KISP 0.0%, MORR +1.8%, ADMS +1.1%, BABL -3.8%). Topology is unusual — most drainages don't have two ≥200 ha rearing lakes 6 km apart on the same blue_line_key.

**When to revisit**: if running the rollup on more WSGs surfaces similar +10% SK spawning bumps with multi-lake topologies, mechanism is general enough to pursue. Otherwise stays parked. See fresh#190 for full diagnostic detail.

Map artifact: `data-raw/maps/BULK_SK_spawning_compare.html` (gitignored locally; reproducible via `data-raw/maps/sk_spawning_BULK.R`).

## Reading order for new contributors

1. This doc — methodology stance + edge type catalog
2. `research/bcfishpass_comparison.md` — rollup history + per-WSG diff_pct over time
3. `research/dimensions_audit.md` — per-column audit
4. `inst/extdata/configs/bcfishpass/dimensions.csv` and `default/dimensions.csv` — per-species methodology dials
5. `inst/extdata/configs/<bundle>/rules.yaml` — emitted SQL predicates (regenerated by `data-raw/build_rules.R`)

## Conventions

- Every methodology decision goes in **dimensions.csv** (or its sibling thresholds CSV) — never in code. `lnk_rules_build` emits `rules.yaml`.
- bcfishpass parity tweaks: edit the bcfishpass-bundle dimensions.csv only. Default-bundle is for NewGraph methodology and may diverge.
- Anything we discover about bcfp's per-species behaviour goes in the table at the top of this doc. Read it before assuming uniform behaviour across species.
- When dimensions.csv changes, `data-raw/build_rules.R` must be re-run; the rules.yaml diff goes in the same commit so reviewers see both.
