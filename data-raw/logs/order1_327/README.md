# The order-1 exception in `default`, scored (#327)

Built by `data-raw/habitat_variants_build.R` with `data-raw/habitat_score/variants_327.csv`
and `wsg_roles_327.csv` (`--prefix=score327_ --jobs=4`), and scored by
`data-raw/habitat_variants_score.R` with `--floor=expected`, on m1 on 2026-11-23: link 0.88.0
at `9306e581` (from a separate worktree), fresh 0.55.1 (`29e7aa13`), local fwapg,
375,962 bcfishobs records (`stamp_build.txt`, `stamp_score.txt`).

- **Arms** (each a `dims` structure variant of one species' row, on `default`):
  `bt_order1`, `ch_order1` and `st_order1` set `rear_stream_order_bypass = yes` (order-1
  lines off a parent of order 5 or more, on a known width below the rearing minimum);
  `ch_pair_both` sets CH's `rear_near_river = both` (#364's refused scope, for the side by
  side #327 asks for).
- **Groups**: BT held out in ADMS, BULK, CHWK, FINA, PCEA and SQAM, in-sample in PARS
  (its records set #284's percentiles); CH held out in ADMS, BULK, CHWK, CLWR and SQAM; ST
  in BULK, CHWK and SQAM. Their 20-group closure (`closure.txt`) was modelled under
  `default`. CO is not scored (its known rearing reaches sit in these groups), nor WCT (no
  scored group holds it).

## Result (`structure_bands_pooled.csv`, `habitat_change.csv`)

| arm | rearing km added (held out) | locations found / expected |
|---|---|---|
| BT order-1 | 21.4 (BULK 19.1, ADMS 2.3; CHWK, FINA, PCEA, SQAM 0) | 0 / 1.4 |
| BT order-1, PARS in-sample | 15.8 | 0 / 1.5 |
| CH order-1 | 11.7 (BULK 11.7, ADMS 0.02) | 0 / 0.8 |
| ST order-1 | 12.8 (BULK) | 0 / 1.1 |
| CH pair at `both` | 272.9 (BULK 145.9, SQAM 54.3, CHWK 43.1, ADMS 18.3, CLWR 11.4) | 1 / 19.1 |

No order-1 band expects 10 locations, so each is underpowered and, under the rule fixed
before scoring (decision 7), declines. The pair at `both` reproduces #364 (275.6 km, 1 of
19.5): refused. Spawning does not move. The owner declined the exception (decision 8,
2026-11-23).

## How the run went

- **The base took 691 min of modelling**, against 1.7 to 25 min a group for 18 of the 20:
  KLUM took 363 min and FRCN 200 (`build.log`). Not investigated here; the stall pattern of
  #487.
- **The first score refused every variant** (`score.log` holds the second): variant schemas
  held no `log` rows, and the validator reads a group with none as having walked no
  near-river pair, where `default` walks CH's since #364. `habitat_variants_build.R` now
  writes each variant pass's row (`log_variant_pass()`); this build predates that, so
  `backfill_log.R` wrote the same rows from `built.csv` and the variants' bundles.
