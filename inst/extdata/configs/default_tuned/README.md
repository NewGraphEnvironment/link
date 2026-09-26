# default_tuned config

The `default` bundle with calibrated species habitat thresholds. It is a **thin** bundle: `config.yaml` declares `extends: default` and overrides only two things.

| File / key | Role |
|------|------|
| `config.yaml` | Manifest. `extends: default`; persist schema `fresh_default_tuned`; declares its own `parameters_habitat_thresholds` |
| `parameters_habitat_thresholds.csv` | Per-species spawn/rear gradient max, channel-width min/max, MAD, lake-area floor and edge types, read by `lnk_pipeline_classify()` and `lnk_pipeline_connect()` |

Everything else — `rules.yaml`, `dimensions.csv`, `parameters_fresh.csv`, `overrides/`, `break_order`, cluster settings — is inherited from `configs/default/` and resolves to that directory. `lnk_config("default_tuned")$chain` lists both.

## Status

One cell differs from `default` (link#284): BT `rear_gradient_max` 0.1049 → 0.1349, from BT and DV records pooled (BT records alone give 0.1249; both are in the research doc). The other CH and BT gradient maxima and channel-width minima were examined and kept, as were `spawn_gradient_min` and `cluster_bridge_gradient` in the inherited `parameters_fresh.csv`. Channel-width maxima, MAD, lake area and edge types were out of scope and are unchanged. The evidence for each value, changed or kept, is in [`research/habitat_thresholds.md`](../../../../research/habitat_thresholds.md). The values are **candidates, unscored**: they have not yet been run against the observation validation (link#283).

## When you change a value

1. Edit `parameters_habitat_thresholds.csv` and update its `checksum` in `config.yaml`'s `provenance:` block (`lnk_config_verify(lnk_config("default_tuned"))` reports the drift until you do).
2. If you changed `rear_lake_ha_min`, or added or dropped a species, this bundle needs its own `rules.yaml` (the inherited one was built from `default`'s thresholds, and `lnk_rules_build()` bakes those in); add a `rules:` key and build it with `thresholds =` pointing here. `data-raw/audit_configs.R` §2 rebuilds every bundle's rules from its own thresholds and flags the mismatch if you forget.
3. Runs record the values themselves in `<schema>.log_parameters_habitat_thresholds`, keyed on `config_hash`.

Do not tune the `bcfishpass` bundle's copy: it is the parity reference.
