## Outcome

Backlog move 8 (#476) landed as link 0.92.0, one batch of seven issues. The config column dictionaries render as `inst/extdata/configs/README.md` and `lnk_rules_build(strict =)` checks columns against them (#75). Residence comes from a `residence` column in `default` and `bcfishpass` `dimensions.csv`, with spawn-only read from `rear_no_fw`, for every persisted mapping code (#189; the exported functions are #512, move 9). The top-level sample rules are `default`'s, and fresh PR #332 adds a weekly workflow that opens a `rules-sync` PR on drift (#129). The order-1 exception was scored on `default` and declined (#327). #212, #316 and #86 were closed by the owner's decisions. Two lessons: the variants harness had been unable to score any variant on `default` since #364, because variant schemas held no `log` rows and the validator read them as walking no near-river pair (`log_variant_pass()` fixes it); and a markdown renderer checked only against its own output kept missing characters until a test read it through cmark-gfm.

## Measurement

The order-1 exception on `default`'s 20-group closure, scored with `--floor=expected` (`research/habitat_thresholds.md`, "Order-1 streams off large rivers on a measured width"): BT adds 21.4 km of held-out rearing (0 locations against 1.4 expected) and 15.8 km in-sample in PARS (0 of 1.5); CH 11.7 km (0 of 0.8); ST 12.8 km (0 of 1.1). Every band underpowered, so declined; at most 0.6 % of a species' rearing in any group. CH's near-river pair at `both` reproduced #364's refusal (272.9 km, 1 of 19.1). The base took 691 min of modelling on m1, 563 of it KLUM and FRCN, the rest of the groups under 25 min each. Residence from the bundle: ADMS (15,716 rows) and PARS (45,974) mapping codes digest identical against the hard-coded sets. The first score refused every variant; the harness fix and a backfill from `built.csv` followed. Why fwapg models no order-1 width was not found in the sources held.

## Evidence

`data-raw/logs/order1_327/*`, `data-raw/logs/residence_189/*`; fresh PR #332's run 45203080645 for the sync workflow.

## Owed

- The pre-run gate runs again before the next provincial run (`R/` and `inst/extdata/` changed).
- `config_hash` moves for `default`, `bcfishpass`, and the three bundles that extend `default`. The cost is near nil, since an `R/` change already refuses readers.
- Under Open decision 4's recommended option, the owner ticks fresh's Actions setting, the fresh PR merges, and fresh releases its refreshed sample.

Closed by: PR for branch `476-backlog-move-8-the-rules-builder-and-dim`
