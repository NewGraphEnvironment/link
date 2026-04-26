# Findings — v0.10.0 spawn edge_types tightening

## What's actually in the categorical `stream` set

`fresh` (or whatever resolves the `edge_types` token) expands `stream` to
FWA edge_type integers `1000, 1050, 1100, 1150` and `canal` to
`2000, 2100, 2300`. Reference: bcfishpass per-species access SQL +
prior link rules audit.

Codes:

| code | meaning |
|------|---------|
| 1000 | Stream segment (single-line) |
| 1050 | Stream-through-wetland (single-line, runs through wetland zone) |
| 1100 | Stream segment (double-line river) |
| 1150 | Stream-through-wetland (double-line) |
| 1200 | Construction line |
| 1250 | Construction line (other) |
| 1350 | Construction line (subtype) |
| 1450 | Connector |
| 1500 | Lake centerline |
| 1525 | Lake centerline (subtype) |
| 1700 | Wetland centerline |
| 2000 | Canal segment |
| 2100 | Canal (rare double-line) |
| 2300 | Canal subtype |

`1050/1150` are **streams that flow through wetland zones**, not wetland
shorelines. They're flagged separately because the surrounding wetland
zone affects flow energy and substrate retention — biologically borderline
for spawning gravel.

`1500/1525/1700` are **lake/wetland centerlines** — these are NOT in the
default spawn rules today. The dimensions CSV emits a `waterbody_type = L`
rule only when `spawn_lake = yes`, which is `no` for every species. So
the user's framing ("we include lake/wetland edges in spawn") is slightly
imprecise — the actual borderline edges are the stream-thru-wetland
codes (`1050/1150`), not lake/wetland centerlines.

## What `edge_types = "explicit"` mode emits today

From `R/lnk_rules_build.R:99-104`:

```r
stream_edges <- if (edge_types == "categories") {
  list(edge_types = c("stream", "canal"))
} else {
  list(edge_types_explicit = c(1000L, 1100L, 2000L, 2300L))
}
```

Already drops `1050/1150/2100`. The bcfishpass config has used this since
day one. The default config has always used `categories`. Switching the
default config call to `explicit` is a one-line change in
`data-raw/build_rules.R`.

## Wetland rearing rule is independent

`rear_wetland = yes` species emit a separate rule using **only**
`1050/1150`:

```r
rear_rules[[length(rear_rules) + 1]] <- add_rc(list(
  edge_types_explicit = c(1050L, 1150L), thresholds = FALSE), rear_rc, rear_cdm)
```

This rule sets the `wetland_rearing` flag in `fresh.streams_habitat`. It's
unaffected by the global `edge_types` switch — the explicit
`c(1050L, 1150L)` is hardcoded for both modes.

The `rearing` flag is the OR across `rear_stream` + `rear_lake` +
`wetland_rearing`. So a `1050/1150` segment that was previously TRUE for
both `rear_stream` (via category expansion) and `wetland_rearing` (via
dedicated rule) will, after the switch, be TRUE only via
`wetland_rearing`. Net `rearing = TRUE` is preserved for any species
with `rear_wetland = yes`.

## Species-by-species impact prediction

| species | spawn 1050/1150 effect | rear 1050/1150 effect (via wetland_rearing) | net rearing flag |
|---------|------------------------|---------------------------------------------|------------------|
| BT | spawn flag drops | wetland_rearing carries it | unchanged |
| CH | spawn flag drops | wetland_rearing carries it | unchanged |
| CM | n/a (no spawn output for CM, spawn_stream=no? actually yes — recheck) | n/a | n/a |
| CO | spawn flag drops | wetland_rearing carries it | unchanged |
| GR | spawn flag drops | rear_wetland=no → no wetland_rearing | rearing drops |
| KO | spawn flag drops | rear_wetland=no | rearing drops |
| PK | n/a (rear_no_fw) | n/a | n/a |
| RB | spawn flag drops | wetland_rearing carries it | unchanged |
| SK | spawn flag drops (but spawn_connected_distance_max also gates) | rear_lake_only — no rear_stream rule | unchanged |
| ST | spawn flag drops | wetland_rearing carries it | unchanged |
| WCT | spawn flag drops | wetland_rearing carries it | unchanged |
| CT | spawn flag drops | wetland_rearing carries it | unchanged |
| DV | spawn flag drops | wetland_rearing carries it | unchanged |

CM and PK have `spawn_stream = yes` per current dimensions CSV, so spawn
predicates ARE emitted; they'll lose `1050/1150` too. PK has `rear_no_fw`,
so no rearing rules. CM has `rear_no_fw` too.

Re-check CM/PK in dimensions.csv — task_plan v1 said "NOT for CM/PK which
have `spawn_stream=no`" — that was wrong; `spawn_stream = yes` for both.

## Test coverage

`tests/testthat/test-lnk_rules_build.R:270` already covers explicit-mode
emission. We need one more test that loads the **regenerated** default
rules.yaml and asserts no spawn rule contains `1050`, `1150`, or `2100`.
That's a regression guard against a future re-introduction of the
`categories` setting.

## ADMS preflight expectations

ADMS WSG has CH, CO, BT, SK as primary spawning species. Without exact
1050/1150 km counts in ADMS, expect spawning km to drop a few percent
across all four. The previous v0.9.0 baseline was:

- BT 397.17 km, CH 295.50 km, CO 339.54 km, SK 98.42 km

Decreases of 1–10% across species are expected and acceptable. Decreases
of >25% would warrant investigation (could indicate `1050/1150` is a
larger share of ADMS than expected).

## Reproducibility implications

Stamps + lineage tracking (link#40) make the v0.9.0 → v0.10.0 rollup
delta explainable: same fwapg, same bcfishobs, but different default
rules.yaml → different predicates → different outputs. Each WSG's
rollup row should attribute the delta to "rules.yaml v2" or whatever the
stamp pins.
