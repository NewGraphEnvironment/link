# Findings

## Confirmed: what matches bcfishpass

### Base segments
`localcode_ltree IS NOT NULL`, `edge_type != 6010`, `wscode_ltree <@ '999' IS FALSE`. 10,458 segments on ADMS — exact match.

### Gradient barrier detection
50,063 barriers across 8 classes, matching to 3/50,063. Island grouping, vertex extraction, 100m lookahead — identical algorithm.

### Non-minimal barrier removal
`fwa_upstream` self-join deletes barriers with another barrier downstream. ADMS: 27,443 → 677. Without this: +149% segments.

### Sequential breaking
Observations → gradient barriers → habitat endpoints → crossings. GENERATED columns recompute. 1m guard. Matches bcfishpass `break_streams()`.

### Access model
bcfishpass uses ONLY natural barriers for access (`barriers_bt_dnstr`, `barriers_ch_cm_co_pk_sk_dnstr`, etc.). Anthropogenic barriers (crossings) are recorded but do NOT block access. Our `label_block = "blocked"` is correct. Tested `label_block = c("blocked", "barrier", "potential")` — caused -52% across all species.

### Channel width
Synced from tunnel (75,736 field measurements). Tightened results ~0.5%.

### Observation filtering
Species filtered by `wsg_species_presence.csv`. CT remaps (CCT, ACT, CT/RB). 179 vs 178 unique positions on ADMS.

### Habitat endpoints
Both `downstream_route_measure` and `upstream_route_measure` as break positions. 143 vs 145 on ADMS.

### SK rearing
Exact match on all WSGs (0.0%).

## Confirmed: what doesn't match

### ST spawning -22% (BABL)
Thresholds match exactly. Access matches. Rules match. Cause unknown. Needs segment-level comparison against tunnel.

### ST rearing -25% (BABL)
Stream order exception tested (+3 points, -28% → -25%). Not the main cause. Three-phase rearing and waterbody filter differences hypothesized but NOT verified. Needs segment-level comparison.

### SK spawning -14% to -40% (BULK, BABL)
fresh#147 algorithm. Two-phase downstream trace + upstream lake proximity. Works on ADMS (+2.6%) but diverges on larger WSGs with complex lake geometry. Reopened fresh#147.

### BT rearing +5.4% to +7.1% (BULK, ELKR)
Slightly over. Stream order exception added more segments (+7.1% on ELKR). May be from segment boundary differences or classification predicates we're applying that bcfishpass doesn't.

### WCT -3.4% spawning, -4.2% rearing (ELKR)
Stream order exception closed 1 point on rearing. Same unknown cause as ST but less severe.

## Tested and eliminated as ST/WCT cause

| Hypothesis | Test | Result |
|-----------|------|--------|
| Per-model non-minimal removal | Built bt/salmon/st/wct barrier tables, removed non-minimal within each | No change on ST/WCT |
| Crossings blocking access | `label_block = c("blocked", "barrier", "potential")` | -52% all species, wrong |
| Stream order rearing bypass | Post-classification UPDATE for stream_order=1, parent>=5 | +3 points ST rearing, not main cause |
| Gradient/channel_width thresholds | Compared params_obj vs tunnel parameters_habitat_thresholds | Exact match |
| Access gating mechanism | Compared access counts | Close (12,728 vs 11,673 ST accessible on BABL) |

## Bugs found

### bcfishpass access_st checks SK instead of ST
`load_streams_access.sql` line 120: `'SK' = any(obsrvtn_species_codes_upstr)` should be `'ST'`. Copy-paste from SK block. Filed NewGraphEnvironment/bcfishpass#9, referenced in link#33. Does not affect access blocking, only the access code label (1 vs 2).

## Unverified hypotheses

### Rearing waterbody filter OR vs AND
bcfishpass rearing: `wb.waterbody_type = 'R' OR (wb.waterbody_type IS NULL OR edge_type IN (...))` — permissive, includes NULL waterbody.
bcfishpass spawning: `wb.waterbody_type = 'R' OR (wb.waterbody_type IS NULL AND edge_type IN (...))` — restrictive.
Not verified whether our rules produce the same SQL. Could add rearing segments on non-standard edge types.

### Three-phase rearing
bcfishpass rearing runs 3 phases for BT/CH/CO/ST/WCT:
1. On spawning streams (spawning AND rearing thresholds, no connectivity)
2. Downstream of spawning (cluster + fwa_upstream trace)
3. Upstream of spawning (cluster + fwa_downstream trace, 10km, 5% gradient bridge)

Our frs_cluster does a single pass removing disconnected rearing. Not verified whether the three-phase approach classifies more rearing.

### Stream order exception across species
Applied to BT, CH, CO, ST, WCT in bcfishpass. Tested as post-classification UPDATE. Adds segments but not enough to explain gaps. CM, PK, SK do not have the exception. CM/PK have spawning only (no rearing model).

## Results summary (with stream order exception)

| Species | Metric | ADMS | BULK | BABL | ELKR |
|---------|--------|------|------|------|------|
| BT | spawn | +1.8% | +3.3% | +4.1% | +3.4% |
| BT | rear | +2.6% | +5.4% | +2.8% | +7.1% |
| CH | spawn | +0.5% | +2.4% | +3.8% | — |
| CH | rear | +2.1% | +4.8% | +6.1% | — |
| CO | spawn | +1.6% | +3.4% | +4.8% | — |
| CO | rear | -1.0% | +0.0% | +0.0% | — |
| PK | spawn | — | +2.7% | — | — |
| SK | spawn | +2.6% | -39.9% | -13.6% | — |
| SK | rear | +0.0% | +0.0% | +0.0% | — |
| ST | spawn | — | — | -22.0% | — |
| ST | rear | — | — | -25.4% | — |
| WCT | spawn | — | — | — | -3.4% |
| WCT | rear | — | — | — | -4.2% |
