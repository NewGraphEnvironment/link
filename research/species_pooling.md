# Species pooling: which observations count as which species

**Verified:** 2026-09-26 · **Issues:** #290 (this), #236 (access override, which should read the same table), #284 (the BT evidence it defines) · **Produced by:** `lnk_species_pooling()` over `configs/default/species_pooling.csv` and `inst/extdata/wsg_regions.csv` (`data-raw/wsg_regions.R`); counts below from local fwapg, bcfishobs 373,050 rows; the naming history and scenario sensitivity from `data-raw/species_pooling_evidence.R` → `data-raw/logs/species_pooling_290/` · **Status:** seeded with one decision (DV → BT in four drainages). **The Skeena row is in question**: see "The Skeena is a different case"

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

## How DV and BT are recorded through time

The DV share of all BT and DV records (`decade_region.csv`; releases removed; 24,337 records, 692 undated), with the record count in brackets:

| | ≤ 1960s | 1970s | 1980s | 1990s | 2000s | 2010s |
|---|---|---|---|---|---|---|
| Columbia | 89 % (36) | 87 % (474) | 67 % (177) | **1 %** (1,384) | 0 % (743) | 0 % (1,631) |
| Fraser | 93 % (46) | 86 % (310) | 89 % (478) | 37 % (1,089) | 14 % (605) | 5 % (1,081) |
| Mackenzie | 94 % (16) | 74 % (453) | 57 % (348) | 23 % (1,016) | 9 % (1,456) | 7 % (1,562) |
| **Skeena** | 100 % (24) | 100 % (346) | 100 % (141) | **91 %** (1,742) | **86 %** (450) | **98 %** (447) |
| Coast and north | 100 % (56) | 100 % (554) | 100 % (764) | 96 % (2,247) | 89 % (1,030) | 83 % (2,461) |

**In the interior the name changed.**
- Char were mostly recorded as DV until the 1980s, and the name flips to BT through the 1990s, consistent with bull trout being recognised as a separate species and recording practice catching up.
- The streams that carry a DV record show what happened after (`dv_streams_resampled.csv`; a later BT record counts first, whenever it came):

  | Region | Streams with a DV record | Later recorded as BT | Not sampled after 1995 | Sampled after 1995, DV only |
  |---|---|---|---|---|
  | Columbia | 163 | 74 % | 26 % | 0 % |
  | Fraser | 547 | 27 % | 51 % | 23 % |
  | Mackenzie | 329 | 34 % | 45 % | 21 % |
  | Skeena | 1,180 | **1 %** | 14 % | **85 %** |
  | Coast and north | 2,356 | 2 % | 35 % | 63 % |

- In the Fraser and Mackenzie about half the DV streams were fished in the inventory era and never again, so their only char evidence is an old "DV" that is almost certainly a bull trout. Where they were re-sampled, it often came back BT (74 % in the Columbia, where no DV stream was re-sampled without a BT record). Pooling is well founded there.

## The Skeena is a different case

- Skeena DV is **not** a legacy name. It is still 86 % or more of char records in every decade, the 2010s included.
- 85 % of Skeena DV streams were sampled again after 1995 and still recorded only DV. Only 1 % were ever recorded as BT.
- Whatever these fish are (true Dolly Varden, a local recording convention, or both), the naming-change argument that justifies interior pooling does not cover them. Pooling the Skeena is a judgement, and it carries the most weight: 1,929 of the 2,822 DV records in the #284 evidence are Skeena records, mostly from the 1990s on.

## Sensitivity: what pooling does to the #284 BT evidence

The scenarios (`scenarios.csv`):
- **S0:** the current tracker.
- **S1:** Skeena pooling only above Hazelton, where the Bulkley joins the Skeena. Pooled: BULK, MORR, KISP, BABL, BABR, SUST, MSKE, USKE. Kept apart: LSKE, KLUM, LKEL, ZYMO.
- **S2:** no Skeena pooling.
- **S3:** interior DV counted as BT only for records before 1995, and no Skeena pooling. The tracker has no time axis, so S3 is computed from the S0 evidence by the same rule. That reimplementation reproduces the producer exactly for S0–S2.

| | DV records pooled | Rearing n | Rearing gradient P95 | Rule gives | Rearing width P5 | Spawning n (DV staged) | Bridge loss |
|---|---|---|---|---|---|---|---|
| S0 current | 2,822 | 4,764 | 0.1348 | **0.1349** | 1.48 m | 76 | 1.7 % |
| S1 Hazelton | 1,970 | 3,988 | 0.1309 | **0.1349** | 1.47 m | 59 | 1.5 % |
| S2 no Skeena | 893 | 3,058 | 0.1204 | **0.1249** | 1.68 m | 18 | 1.0 % |
| S3 interior pre-1995 | 537 | 2,824 | 0.1203 | **0.1249** | 2.07 m | 8 | — |
| BT records only | 0 | 2,443 | 0.1253 | **0.1249** | 1.91 m | 0 | 1.2 % (from #284's `bridge_bt.csv`) |

- **`default_tuned`'s BT `rear_gradient_max` of 0.1349 depends on the Skeena DV records.** Drop them (S2, S3) and the rule gives 0.1249, the value the BT records alone give. The Hazelton cut (S1) keeps 0.1349, but only just: the rule floors the P95 to the hundredth, and S1's 0.1309 is **0.0009** above the 0.13 line where the result drops to 0.1249 (S0's 0.1348 is 0.0048 above it). A handful of records would flip it.
- Rearing width stays within 0.5 m of the current 1.5 m in S0–S2, so it stays **keep**. S3's 2.07 m is 0.57 m above the current value, past the rule's 0.5 m keep band, so on that evidence the rule would tighten rearing width to about 2.1 m. It has not been checked against the literature here.
- Without the Skeena, the staged spawning evidence nearly vanishes (18 records in S2, 8 in S3). BT's spawning thresholds already rest on the literature, and would then rest on nothing else.

**Validator scores** (`validate_scenarios.csv`, `default` on `fresh_default`, BT, buffer 0). The model is the same in every row; only the evidence changes.

| | Any stage: n | Capture on any rearing | Rear-staged: n | Capture on any rearing |
|---|---|---|---|---|
| S0 | 5,104 | 82.4 % | 1,053 | 66.5 % |
| S1 | 4,275 | 83.5 % | 628 | 66.1 % |
| S2 | 3,259 | 86.2 % | 205 | 75.6 % |

Skeena DV records sit on modelled BT rearing less often than the rest (the model is the same in all three rows). That fits them being partly true Dolly Varden, in smaller and steeper water than the interior bull trout the thresholds describe. Most of the "rear-staged" BT evidence is Skeena DV: 848 of 1,053 records, since bcfishobs gives BT no life stage.

## What this leaves open

The tracker cannot yet say "DV counts as BT for records **before 1995**" (S3), which is the mechanism the interior history supports. That would take one optional column (for example `obs_year_max`) and one filter in `lnk_species_pooling()`'s consumers. The Skeena choice is S0, S1 or S2. It decides whether `default_tuned` keeps 0.1349 or goes back to 0.1249, so it is an input to #284 step 5, not a detail of it.
