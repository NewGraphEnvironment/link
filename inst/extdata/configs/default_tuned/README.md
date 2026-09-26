# default_tuned config

The `default` bundle with calibrated species habitat thresholds. It is a **thin** bundle: `config.yaml` declares `extends: default` and overrides only two things.

| File / key | Role |
|------|------|
| `config.yaml` | Manifest. `extends: default`; persist schema `fresh_default_tuned`; declares its own `parameters_habitat_thresholds` |
| `parameters_habitat_thresholds.csv` | Per-species spawn/rear gradient max, channel-width min/max, MAD, lake-area floor and edge types, read by `lnk_pipeline_classify()` and `lnk_pipeline_connect()` |

Everything else — `rules.yaml`, `dimensions.csv`, `parameters_fresh.csv`, `overrides/`, `break_order`, cluster settings — is inherited from `configs/default/` and resolves to that directory. `lnk_config("default_tuned")$chain` lists both.

## Status

The thresholds CSV starts as a byte-identical copy of `default`'s, so today this bundle classifies exactly as `default` does, into its own schema. Calibrated CH and BT gradient and channel-width values from the observation work in link#284 land here, each with its evidence recorded in `research/habitat_thresholds.md`.

## When you change a value

1. Edit `parameters_habitat_thresholds.csv` and update its `checksum` in `config.yaml`'s `provenance:` block (`lnk_config_verify(lnk_config("default_tuned"))` reports the drift until you do).
2. If you changed `rear_lake_ha_min`, this bundle needs its own `rules.yaml` (that value is baked into the rules by `lnk_rules_build()`); add a `rules:` key and build it with `thresholds =` pointing here.
3. Runs record the values themselves in `<schema>.log_parameters_habitat_thresholds`, keyed on `config_hash`.

Do not tune the `bcfishpass` bundle's copy: it is the parity reference.
