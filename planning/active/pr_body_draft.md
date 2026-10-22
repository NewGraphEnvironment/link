Closes #364. Release 0.67.0. Needs fresh 0.42.0 (NewGraphEnvironment/fresh#264): **merge and tag that first**, or this PR's `Remotes:` pin cannot install.

**`default` rears a stretch that runs through a wetland only where it would rear as a stream.** The stretch must be big enough itself, or for CH, within 1 km of a large river.

- **`rear_wetland_flow`** (dimensions.csv) shapes the FWA 1050/1150 rear rule: `stream` (inherits the species' gradient, size and near-river thresholds), `gradient` (bcfishpass's coho rule) or `free` (the old rule). `default` takes `stream` for BT, CH, CO, ST, WCT, CT, DV and RB. The `bcfishpass` bundle gives CO `gradient`.
- **The near-river pair is a threshold** (`<stage>_river_*` in `parameters_habitat_thresholds.csv`), inherited by fresh. `rear_near_river` scopes it, and `lnk_rules_build()` writes only `near_river: false` stamps, always on river-polygon rules. `default`'s CH pair is 15 m modelled width under `cw` (3 m³/s under `mad`) within 1,000 m, on its through-wetland lines only.
- **Persisted, logged, validated.** `<schema>.streams_near_river` keeps the walked distances. `log.near_river` records each group's pairs, and `lnk_habitat_validate()` re-tests against both. Schemas built before this release (`fresh_default`) are refused under `default` until re-modelled.
- **The variants harness varies rules**: a `dims` column, structure rows, near-river cells in `set`, pair anchors, rules and dimensions shas in `built.csv`, and ANALYZE before the habitat gate.

| check | result |
|---|---|
| `devtools::test()` | 3,726 expectations; 2 failures, the stale golden dams pin (8 ADMS dams; `cabd.dams` gives 7), unchanged from main |
| End to end on ADMS, test bundle with a CH pair | 5,849 near-river rows persisted, pair logged, validator 0 post_predicate |
| `default` on filled vs unfilled discharge | identical habitat digest |
| Rules diff | river-polygon stamps everywhere; 1050/1150 rule for six `default` species; CO's gradient in `bcfishpass` |
| `audit_configs.R`; provenance | exit 0; 0 drifted entries |
| Scoring on five held-out groups (291 CH locations) | door −43.1 km, 0 captured locations lost; pair on every stream rule +275.6 km at 5 % of the core rate (refused); pair on wetland lines +4.3 km |
| CO under `bcfishpass` vs reference | ADMS 352.55 → 352.33 km (ref 351.19); BULK 2,215.57 → 2,214.12 (ref 2,221.93) |
| `/code-check branch` | TO FILL: rounds and how the loop ended |

The CH scope was revised by the operator on the scoring evidence (`wetland_flow`, not `both`). Evidence: `data-raw/logs/wetland_door_364/`; write-up `research/habitat_thresholds.md`.

**Owed after merge:** re-prep cyphers for the fresh pin. Re-model every group in the next provincial run. Re-score bcfishpass parity. Two operator decisions with these numbers: the W polygon rule's `area_only`, and lake lines as "a river" (fresh#262). File the rule-table issue (draft in the archive). #346: CO's pair and CH's 0.75 m³/s floor.

- Relates to NewGraphEnvironment/sred#24

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01WJE2szSCkeV9R3qKhuSwyx
