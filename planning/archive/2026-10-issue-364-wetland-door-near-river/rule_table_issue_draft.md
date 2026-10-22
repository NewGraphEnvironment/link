**Title:** Habitat rules as a table: one row per species, stage and rule

**If done:** a bundle's habitat rules are a table with one row per (species, stage, rule), each row naming its edge set, waterbody type and which thresholds it inherits or overrides, and `lnk_rules_build()` writes `rules.yaml` from it without a hand-written branch per rule shape. A new rule shape is a new row, not new builder code. **If never:** every new rule shape is a new `dimensions.csv` column plus a branch in `lnk_rules_build()`, so the builder grows one interacting `if` per decision. #364 added two of them (`rear_wetland_flow`, `rear_near_river`) and the stamps they imply.

## What we have

`dimensions.csv` holds one row per species and one column per scenario switch (`rear_wetland`, `rear_wetland_polygon`, `rear_wetland_flow`, `rear_near_river`, `rear_stream_in_waterbody`, `river_skip_cw_min`, …). `lnk_rules_build()` (`R/lnk_rules_build.R`) turns those switches into rules through branches that depend on each other. For example, the 1050/1150 rule's type, its floor and its position relative to the W polygon rule depend on `rear_wetland_ha_min`, `rear_wetland_polygon` and `rear_wetland_flow` together. Dead combinations are caught by checks written beside the branches.

## What we want

A rules table per bundle, for example `rules.csv`:

| species | stage | rule | edges | waterbody_type | inherits | gradient | size | near_river | floor_ha | area_only | connected |
|---|---|---|---|---|---|---|---|---|---|---|---|
| CH | rear | stream | 1000,1100,2000,2300 | | yes | | | inherit | | | |
| CH | rear | river | | R | yes | | 0-9999 | false | | | |
| CH | rear | wetland_flow | 1050,1150 | | yes | | | inherit | | | |
| CH | rear | wetland_polygon | 1000,1100 | W | no | | | | 1 | | spawning 10000 |

- `lnk_rules_build()` becomes a writer: one rule per row, in row order (fresh reads the first W rule as the bucket rule, so order stays meaningful and visible).
- The numbers stay in `parameters_habitat_thresholds.csv`; the table says only which rule inherits which.
- The variants harness varies a structure by editing rows, as it now varies `dims`.

## Points to settle

- Whether the table replaces `dimensions.csv` or is generated from it once and then edited.
- How the bcfishpass bundle's table is kept in step with bcfishpass's SQL.
- Whether row order or an explicit `order` column carries fresh's first-rule semantics.

Relates to #364 (Decision 8 there).
