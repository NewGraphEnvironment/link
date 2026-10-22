# #364: through-wetland lines rear through the stream door; the near-river pair is a threshold

Closes #364; link 0.67.0, on fresh 0.42.0 (NewGraphEnvironment/fresh#264, issues fresh#262 and fresh#263).

**Outcome.** `default` rears FWA 1050 / 1150 lines only where they would rear as a stream (`rear_wetland_flow = stream` for BT, CH, CO, ST, WCT, CT, DV, RB). CH's near-river pair (a river of at least 15 m modelled width, or 3 m³/s under `mad`, within 1 km) applies to those lines only (`rear_near_river = wetland_flow`). The operator decided the scope on Phase 4's evidence. The pair is a threshold fresh inherits: `lnk_rules_build()` writes no numbers, only `near_river: false` stamps, always on river-polygon rules. The `bcfishpass` bundle gives CO bcfishpass's gradient-only rule. The pair is persisted (`<schema>.streams_near_river`), logged (`log.near_river`) and validated. The variants harness varies rules as well as thresholds.

## Measurement

Five held-out groups (ADMS, BULK, CHWK, CLWR, SQAM; 291 CH locations), `--floor=expected`:

| CH rearing | added km (found / expected) | removed km | capture |
|---|---|---|---|
| stream door, no pair | 3.3 (0 / 0.2) | 43.1 | 260 of 291, unchanged |
| pair on every stream rule | 275.6 (1 / 19.5): refused | 31.2 | 261 |
| pair on wetland lines only | 4.3 (0 / 0.3) | 31.2 | 260 |

On `cw` the door keeps 83 to 95 % of through-wetland CH rearing in four groups, because CH's size test is a 1.5 m width. The issue's province-wide 10,197 → 2,338 km used #346's 0.75 m³/s floor. 3 m³/s converts to 15 m. CO under `bcfishpass`: ADMS rearing 352.55 → 352.33 km against bcfishpass's 351.19.

The first scoring build's variants ran 20 to 40 times slower than the pre-flight. The habitat gate's count was planned on statistics from before the variant's rows were inserted. Fixed in the harness with an ANALYZE.

**Review.** `/code-check branch`, three rounds with 6, 2 and 2 findings. Rounds 2 and 3 found defects inside the earlier fixes, all one mechanism: a set taken from a stand-in instead of its source. It ended on the 13-row enumeration in `findings.md`.

## Evidence

`data-raw/logs/wetland_door_364/` (README with every table; `score/` the scoring build); `data-raw/habitat_score/variants_364.csv`, `wsg_roles_364.csv`. Write-up: `research/habitat_thresholds.md`, "Through-wetland lines and the near-river test (#364)".

## Owed

- Merge fresh PR #264 and tag v0.42.0; until then link's `Remotes:` pin cannot install and CI fails.
- Re-prep cyphers for the fresh pin before the next dispatch.
- The next provincial `default` run re-models every group (the validator refuses `fresh_default` until then).
- Re-score the bcfishpass parity record at the next release (CO moves on the gradient fix).
- Operator decisions with Phase 4's numbers: the W polygon rule's `area_only`; lake flow lines as "a river" (fresh#262).
- File the rule-table issue after body review (`rule_table_issue_draft.md` here).
- #346: CO's pair, and CH's `rear_mad_min` 0.75 in `default_tuned`; scoring #346's rule, a strict floor plus the river exception, as a whole config.
