## Outcome

`rearing_km` now means one thing in link's WSG rollups. `lnk_rollup_wsg()`'s default leaves FWA
lake connection lines (edge 1450 in a lake or reservoir polygon) out and reports them as a new
default `rearing_lake_connection_km`, as the compare rollups have since #317. So
`lnk_habitat_validate()`'s cost changes meaning, while its capture keeps reading the `rearing`
flag, because about half of in-lake fish records sit on a connection line. The parity scripts
apply the same predicate to `fresh.streams_vw_bcfp`. `lnk_aggregate()` and two older one-off
scripts still sum the flag.

Two things were learned on the way. First, the planned #284 re-score cannot run at any HEAD after
#307: the variant bundles `extends: default` by name, and `default`'s thresholds have moved. A
direct check replaced it. Second, the plan's reproducibility enumeration left out the #283
validator baseline, the one place a BT number moves. Code-check round 3 found it by asking for
the mechanism (closed-set prose built from what was in view) rather than more instances.

## Measurement

- **Parity cross-section** (FINA PARS PCEA LKEL, bcfishpass config): 25/25 pass before and
  after. Accessible and spawning are identical. BT rearing moves alike on both sides:
  - FINA loses 393.6 km on each side.
  - PCEA's gap goes from +1.10 % to +1.87 %, because link carries 8.2 km fewer connection
    lines there.
  - `pars_accessible.rds` rearing goes from 2575.06 / 2588.91 to 2565.31 / 2579.15 km.
- **Score schemas:** BT, CH, GR and RB rear on 0 km of connection lines in every #284–#305
  schema, and #284's `habitat_change.csv` reproduces 36 / 36 exactly.
  - SK and KO are not 0. #300's and #305's in-sample KO cost would read KOTL 259.06 km (was
    568.63) on a re-score. No verdict reads it.
- **#283 baseline:** the bcfishpass-config BT cost falls from 76,872 to 74,369 km (2,503 km of
  connection lines), against `default`'s 75,280 km.
  - "`default` has 1,592 km less BT rearing" becomes about 911 km more.
  - CH does not move.
- **Wrong turns kept:**
  - A full re-score was attempted twice: first missing bundles under `--out`, then refused by
    the bundle-drift guard.
  - A rollup over every score schema stalled for minutes. Part of that was backends left
    running by a killed R client. Part was `score284_bt_rear_0p*` MORR having no planner
    statistics (estimated 1 row), which `ANALYZE` fixed.
  - Code-check: round 1 clean; round 2, 4 doc-claim findings; round 3, 4 more, one inside
    round 2's fix. The loop ended by enumerating 58 claim lines (`review-enumeration.md`).

## Evidence

`data-raw/logs/lake_connection_319/*`; the durable write-up is `research/habitat_thresholds.md`,
"One meaning of `rearing_km` (#319)", and `research/habitat_validation.md`, "Baseline".

Closed by: PR for #319 (branch `319-rearing-km-means-two-things-lnk-rollup-w`)
