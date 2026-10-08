# Findings — Default lake and wetland rearing: connected to spawning, centrelines kept, km and ha broken out (#310)

## Issue context

**If done:** in `default`, a species' lake and wetland rearing counts only water it can reach from its own spawning, within a distance the bundle states. CO rears in lakes and wetlands of any size. Rollups report rearing km separately for streams, lake centrelines and wetland centrelines, with lake and wetland hectares beside them. They say plainly that a lake's km and its hectares describe the same water. **If never:**
- `default`'s lake departure lives in a bucket column that ignores spawning.
- Lake centrelines count nowhere.
- CO's lake and wetland use is cut by size floors nobody decided on.
- Hectares and km sit in one table with nothing saying they overlap.

## Decisions

Operator, 2026-10-06 on #307's PR; revised 2026-10-07.

1. **Lake and wetland use requires connected same-species spawning** within a distance stated in the rules. This covers BT, RB, GR, ST and CO (lakes and wetlands alike) — "reasonable number stated in rules".
2. **CO rears in lakes and wetlands, with no minimum size.**
   - This corrects this issue's first draft, which read the operator's *"No. Ditch minimum"* as dropping CO lakes. It meant ditching the minimum.
   - The minimum stays configurable: `rear_lake_ha_min` / `rear_wetland_ha_min` are left blank for CO, not removed.
3. **Centrelines are kept in `rearing` km by default** for every species in `default`. `rear_lake_area_only` / `rear_wetland_area_only` remain the per-species switch to discard them.
4. **Rollups break out km and hectares** (columns below).
   - A lake's or wetland's km and its hectares describe the same water and are never added together.
   - Lines are assigned to lake or wetland by the polygon they sit in (`waterbody_key`), not by edge type.
5. **Reservoirs count as lakes**, in fresh's bucket and in link's rollup. This matches fresh's `.frs_waterbody_tables("L")` and bcfishpass SK lake rearing.
6. **SK and KO keep their current lake settings.** Their spawning is anchored to `rearing` lake lines, so discarding those centrelines would remove all their spawning.
7. **Wetland km are filtered by `wetland_ha_min`.** *Superseded 2026-10-07 by #311:* fresh v0.38.0 applies a W rule's floor to `rearing` (fresh#237), and #311 puts the floor on the 1050/1150 wetland-flow rule too, so a declared floor bounds both wetland rear rules (mainlines in smaller wetlands can still rear through the stream rule). Blanking CO's `rear_wetland_ha_min` (decision 2) therefore also lifts its floor on wetland km. This decision first read "not filtered … fresh's main rear predicate ignores it".

## Problem (measured on persisted `fresh_default`, 52 WSGs, link@`5807d35`)

- **The L rear rule admits almost nothing.** `lnk_rules_build()` writes it with `edge_types_explicit: [1000, 1100]` (`R/lnk_rules_build.R:371-373`).
  - Lines inside lakes are FWA construction lines: 1200 (main flow), 1450 (connection) and 1475 (lake arm).
  - Of 16,652 BT `lake_rearing` rows, 1 is `rearing` (edge 1000), and 7,223 km are construction lines.
- **The buckets ignore connectivity.** fresh clears only `rearing` in its cluster pass, so `lake_rearing` / `wetland_rearing` stay TRUE on polygons with no BT spawning connected. That is 16,651 lake rows and 2,133 wetland rows. `lnk_compare_wsg()` sums polygon hectares from the bucket alone (`R/lnk_compare_wsg.R:278-305`).
- **The buckets were sized by the line through the polygon.** Fixed in fresh v0.37.0 (fresh#240): buckets are now area-only.

## Proposal

### fresh (released before this lands)

- **fresh#240, released in v0.37.0.** It adds `requires_connected: spawning` + `connected_distance_max` on the first rear L / W rule. A polygon keeps its bucket only if same-species spawning lies on it, or downstream or upstream of it within the distance.
  - Anywhere else, those keys fail the rules load.
  - Pinning ≥ v0.37.0 moves `default`'s buckets by itself. BT on NATR goes from 309.9 to 521.4 lake km and from 683.9 to 1,287.3 wetland km (fresh `data-raw/logs/bucket_connected_240/`, which also has the 0.5 to 10 km connection ladder).
  - **Done in #311:** link pins fresh v0.39.0. The bucket movement was re-measured on one segmentation and matches exactly (`data-raw/logs/wetland_floor_311/`). This issue starts from that baseline.
- **To file: the lake bucket includes reservoirs** (`fwa_manmade_waterbodies_poly`). That is decision 5.
- **To file: `.frs_run_connectivity()` falls back to 200 ha** as the lake minimum for SK/KO spawning when the L rule has no `lake_ha_min`. With no minimum set, that is a silent floor.

### link

- **`dimensions.csv` (`configs/default/`):**
  - CO: blank `rear_lake_ha_min` and `rear_wetland_ha_min`; keep `rear_lake = yes`.
  - New `rear_lake_connected_distance_max` and `rear_wetland_connected_distance_max` (m), documented in `dictionary_dimensions.csv`.
  - Values per species are set in `research/`, with literature on adfluvial lake use (BT, RB, GR, ST) and CO off-channel and overwintering use. bcfishpass's only precedent is SK's 3 km between lake and spawning.
- **`lnk_rules_build()`:**
  - **Keep centrelines in the lake rule.** When the lake rule is not `area_only`, admit the edge types of lines inside lake polygons (1200, 1450, 1475 from the measurement above). Confirm the full set, including 1300 and 1400, against `fwa_edge_type_codes` before emitting. Add `thresholds: false` so no channel-width test applies to lake lines, many of which have no width. Wetland flow lines (1050/1150) already reach `rearing` through the existing carve-out rule.
  - **Fix `add_rc()`.** Today it stamps `rear_requires_connected` / `rear_connected_distance_max` on every rear rule, which fresh v0.37.0 rejects. Stamp only the first L and first W rule, from the new per-type columns, and retire or redefine the old columns and their dictionary rows. Since #311 a floored species has **two** W rear rules: the polygon rule (1000/1100), then the floored 1050/1150 rule. The polygon rule comes first, so it is the one to stamp; the second W rule must not carry `requires_connected`, or fresh refuses the rules.
  - **Refuse `area_only` on the lake rule of a species whose spawning requires connected lake rearing** (SK, KO). That turns decision 6 into a build-time error.
- **Rollup** (`lnk_compare_wsg()` / `lnk_rollup_wsg()`):

  | column | counts |
  |---|---|
  | `rearing_km` | total, unchanged (parity and existing rollups) |
  | `rearing_stream_km` | `rearing` lines outside any lake, reservoir or wetland polygon (river-polygon lines stay here) |
  | `rearing_lake_km` | `rearing` centrelines in lake or reservoir polygons |
  | `rearing_wetland_km` | `rearing` centrelines in wetland polygons |
  | `lake_rearing_ha` | lake + reservoir bucket polygons |
  | `wetland_rearing_ha` | wetland bucket polygons |

  - Test the invariant: stream + lake + wetland km = `rearing_km`.
  - State in the rollup docs and output that the lake/wetland km and ha pairs overlap.

### Known divergence (documented, not fixed here)

A lake's km and its hectares are decided by different checks:
- **Hectares:** is there spawning within the stated distance, above or below the lake?
- **Centreline km:** the lake lines go through the rearing cluster pass like any stream. That means spawning anywhere upstream, or spawning downstream within 10 km with no step over 5 % on the way.

Example: spawning 4 km below a lake, past a small falls. With a 5 km distance the hectares count, while the centreline km are dropped at the falls. The breakdown makes this visible. If it is common, tying the two together is its own issue.

### Validation

Regenerate `rules.yaml` and update provenance. Re-run one WSG with all the lake species (NATR) and one with CO (ADMS), and diff:
- `rearing` km rises by the lake centreline km of the lake species;
- CO gains lakes and wetlands below the old 2 ha / 0.5 ha floors;
- lake and wetland hectares drop where polygons are disconnected;
- stream + lake + wetland km equal the total;
- SK and KO spawning is unchanged.

### Docs

- the `default` README's departures list;
- RUNBOOK §7;
- `research/habitat_thresholds.md`'s #307 section, which still presents the bucket shrink under `mad` as expected behaviour (it was the size-test artifact fresh#240 removed);
- the dictionary rows for the new and retired columns.

## Not in scope

- The `bcfishpass` bundle (a parity instrument). `default_tuned` inherits from `default`.
- Changing SK or KO lake handling.
- Making the centreline km follow the hectare connection test (see "Known divergence").
- ~~Applying `wetland_ha_min` to wetland km (fresh#237).~~ Done by fresh v0.38.0 and #311.

Relates to #307, #311, fresh#240, fresh#237, #20.




## Plan-mode measurements (2026-10-07)

Edge types inside waterbody polygons, NATR + ADMS + PARS + BULK
(`fwa_stream_networks_sp` × `fwa_waterbodies` on `waterbody_key`), segments / km:

| type | edge | n | km |
|---|---|---|---|
| L | 1200 | 8,365 | 1,242 |
| L | 1300 | 34 | 4 |
| L | 1400 | 21 | 7 |
| L | 1450 | 2,369 | 725 |
| L | 1475 | 18 | 11 |
| W | 1000 | 5,107 | 704 |
| W | 1050 | 10,482 | 1,848 |
| W | 1100 | 182 | 35 |
| W | 1150 | 24 | 4 |
| W | 1200 | 2,891 | 464 |
| W | 1400 | 175 | 61 |
| W | 1410 | 95 | 5 |
| X | 1200 / 1400 / 1450 | 24 | 4 |

- Lake polygons hold **no** 1000/1100 lines, which is why the L rear rule admits ~nothing.
- 464 km of 1200 (+ 61 km 1400) inside wetlands is admitted by no rear rule. Operator: left as scoped; follow-up drafted.
- `bcfishpass/rules.yaml`: only SK's lake-only L rule, zero W rules.
- `default/parameters_habitat_thresholds.csv` `rear_lake_ha_min`: NA for CO (only KO, SK = 200), so blanking dims removes CO's floor.
- fresh `.frs_waterbody_tables("L")` (`R/utils.R:179`) includes `fwa_manmade_waterbodies_poly`.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| Zotero MCP: "Missing required environment variables ZOTERO_LIBRARY_ID and ZOTERO_API_KEY" | Read `~/Zotero/zotero.sqlite?immutable=1` + `pdftotext` on storage PDFs |

## Plan review triage (2026-10-07)

Full review in `review-plan.md`. Verified before acting: B1 (fresh lake bucket = `fwa_lakes_poly` only, `git show v0.39.0:R/frs_habitat_predicates.R`), B2 (CT/DV absent from `default/rules.yaml`), G1 (`cluster_rearing` FALSE for RB, CT, DV, CM, PK in `default/parameters_fresh.csv`).

Province-wide edge types inside lake (L) / reservoir (X) polygons, km: L 1200 54,402 · 1450 44,528 · 1400 6,225 · 1475 2,127 · 1300 478 · 1000/1250 ~0; X 1200 64 · 1400 126 · 1450 30 · 1250 13 · 1350 11 · 1300 1. Lake rule set widened to add 1250 / 1350.

## `fwa_waterbodies` misses polygon lines (2026-10-07)

Province-wide, lines whose `waterbody_key` is in a polygon table but has no `fwa_waterbodies` row: lakes 83,922 segments / 5,649 km, wetlands 125,384 / 17,757 km, reservoirs 1,443 / 101 km (fwapg builds `fwa_waterbodies` only from lines with a non-NULL localcode and a non-999 wscode). fresh's rules read the polygon tables, so the rollup's class does too. `fwa_lakes_poly`, `fwa_manmade_waterbodies_poly` and `fwa_wetlands_poly` share no `waterbody_key`; each is indexed on it.

## Adams Lake and 1450 connection lines (2026-10-07)

ADMS CH / CO lake km: Adams Lake (13,229 ha) holds 211.6 km of rearing lines, 62.8 km of 1200 main flow and 148.8 km of 1450 connection lines. NATR BT lake km: 275.0 km of 1450, 227.6 km of 1200. The issue names 1450; whether connection lines belong in lake km is left for review.
