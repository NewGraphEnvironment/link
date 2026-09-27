# Species pooling: which observations count as which species

**Verified:** 2026-09-26 · **Issues:** #290 (this), #236 (access override, which should read the same table), #284 (the BT evidence it defines) · **Produced by:** `lnk_species_pooling()` over `configs/default/species_pooling.csv` and `inst/extdata/wsg_regions.csv` (`data-raw/wsg_regions.R`); counts below from local fwapg, bcfishobs 373,050 rows · **Status:** seeded with one decision (DV → BT in four drainages)

## What it is

An observation record is evidence for a model species. Which records count is a biological
position, and it varies by place: a Dolly Varden record in the Skeena is usually a bull
trout recorded under the other name, while one on the outer coast is usually a Dolly
Varden. So the rule is data, one dated and sourced row per decision, and the state of
knowledge accrues as rows.

- **`species_pooling.csv`** (bundle root; `default` declares it, `default_tuned` inherits
  it): `species_code` (the target) and `species_obs` (the evidence), each a species or a
  group from `species_groups.csv`; `scope_level` (`region`, `subregion`, `wsg`) and
  `scope`; `pool` (`yes` / `no`); and the record of why (`confidence`, `rationale`,
  `source`, `verified`, `issue`). Columns: `configs/dictionary_species_pooling.csv`.
- **`species_groups.csv`**: named sets (`SALMON` = CH, CM, CO, PK, SK; `CHAR` = BT, DV).
  A group may not share a code with a species, and groups do not nest. Only
  `lnk_species_pooling()` reads it. `lnk_presence()`'s presence groups are a separate,
  pipeline-facing concept and still live in code.
- **`inst/extdata/wsg_regions.csv`** (package-level, since it is geography): each WSG's
  region and sub-region. It is also hashed into the `config_hash` of any bundle declaring
  a tracker, because a region reassignment changes what pools.

**Resolution**, per WSG, target and evidence species: the most specific scope wins (wsg >
subregion > region); at equal scope the row naming fewer groups wins; rows still tied
must agree on `pool`, or the call errors. Two identical rows are accepted. A row whose
target is a group and a row whose evidence is a group tie at the same rank, so they must
agree. Anything unlisted is **not pooled**, a species always counts as itself, and the
target must be present in the WSG (`wsg_species_presence`).

The known species are the `wsg_species_presence` columns. bcfishobs codes that are not
columns there (`SA` salmon general, `C`, the mixed `BT/DV`) cannot be pooled, and a group
named like one of them would not be caught by the collision check.

## Regions

The region is the first segment of each group's **outlet** `wscode_ltree` (fresh
`inst/extdata/wsg_outlet.csv`, fresh ≥ v0.33.0; built with 0.34.0 installed), not of
its shallowest code, because a group can touch two drainages. LFRA's outlet is `100`, so
it is Fraser, although its Boundary Bay streams are coded `900`. The thresholds query's
segment-level `region` column calls those `900`: a small, known inconsistency. A
sub-region is the longest whole-segment wscode prefix listed in
`data-raw/wsg_regions_defs.csv`. There is one sub-region column, so nested sub-regions
are not expressible. Coastal and cross-border region names are drafts, marked in that
file.

## State of knowledge, 2026-09-26

| Region | WSGs | BT present | DV present | DV → BT pooled |
|---|---|---|---|---|
| Fraser | 68 | 52 | 54 | 52 |
| Mackenzie | 65 | 49 | 39 | 49 |
| Columbia (incl. Kootenay, 7) | 17 | 16 | 15 | 16 |
| Skeena | 12 | 12 | 12 | 12 |
| Stikine | 16 | 8 | 13 | — |
| Central Mainland Coast | 15 | 3 | 15 | — |
| East Vancouver Island | 9 | 2 | 9 | — |
| Yukon | 8 | 1 | 3 | — |
| Nass | 7 | 7 | 7 | — |
| South Mainland Coast | 7 | 4 | 7 | — |
| West Vancouver Island | 7 | 1 | 7 | — |
| Outer North Coast Islands | 6 | 0 | 4 | — |
| Taku | 4 | 1 | 4 | — |
| Haida Gwaii | 2 | 0 | 2 | — |
| Alsek, Skagit, Unuk | 1 each | 0, 1, 1 | 1 each | — |

DV pools into BT in **129 WSGs**. It is not pooled in the **29 BT-present WSGs** of the
unlisted regions: BARR, BRKS, COWN, HOMA, INKR, ISKR, JERV, KINR, KITR, KLAR, KLIN, LBIR,
LDEN, LISR, LNAR, MSTR, NASR, PARK, SKGT, SPAT, SQAM, SWIR, TAHR, TAYR, TUYR, UBIR, UDEN,
UNAR and UNUR. Before #290 every one of those pooled, because the rule was "wherever BT is
present". The #284 evidence (55 WSGs) and the #283 baseline (55 + 59) sit entirely in
pooled regions, so neither moved.

**The seed is an operator call** (2026-09-26): inland, DV records are bull trout recorded
under the other name. McPhail and Carveth (1993) support treating inland char records as
unreliable to species: juveniles "can not be reliably identified except biochemically",
and the two hybridize where they co-occur (#236 has the passage). Confidence is `medium`
on every row.

**Where the next rows are likely to go.** Mixed records in bcfishobs (`BT/DV`, `DV/BT`,
`DVxBT`) mark the contact zones:
- Skeena 48 (KLUM 26, SUST 15, MORR 4);
- Mackenzie 25 (FIRE 19, UOMI 5);
- Fraser 20 (LFRA 18);
- the Skagit (SKGT 6), and 3 each in KITR, HOMA and LBIR, which are unlisted regions.

The lower Fraser tributaries (LFRA, CHWK) are coastal-influenced, and are the first
candidates for a `wsg` row, either way. The unlisted coastal and northern BT-present WSGs
(Nass and Stikine above all) are where a `pool = yes` row would need evidence rather than
an assumption.
