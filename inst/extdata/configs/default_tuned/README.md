# default_tuned config

The `default` bundle with calibrated species habitat thresholds. It is a **thin** bundle: `config.yaml` declares `extends: default` and overrides only two things.

| File / key | Role |
|------|------|
| `config.yaml` | Manifest. `extends: default`; persist schema `fresh_default_tuned`; declares its own `parameters_habitat_thresholds` |
| `parameters_habitat_method.csv` (inherited) | Per-watershed-group `cw`/`mad` model, from `default` |
| `parameters_habitat_thresholds.csv` | Per-species spawn/rear gradient max, channel-width min/max, MAD, lake-area floor and edge types, read by `lnk_pipeline_classify()` and `lnk_pipeline_connect()` |

Everything else — `rules.yaml`, `dimensions.csv`, `parameters_fresh.csv`, `overrides/`, `break_order`, cluster settings — is inherited from `configs/default/` and resolves to that directory. `lnk_config("default_tuned")$chain` lists both.

## Status

**Gradient (link#284).** BT `rear_gradient_max` 0.1049 → 0.1349, from BT and DV records pooled (BT records alone give 0.1249; both are in the research doc). The other CH and BT gradient maxima and channel-width minima were examined and kept, as were `spawn_gradient_min` and `cluster_bridge_gradient` in the inherited `parameters_fresh.csv`. Channel-width maxima, lake area and edge types were out of scope and are unchanged. The evidence for each value, changed or kept, is in [`research/habitat_thresholds.md`](../../../../research/habitat_thresholds.md). The BT value was **scored** against fish observations on eight watershed groups held out from its calibration (link#284 step 5) and held: the steps to 0.1349 add rearing that BT use at 0.60–0.71 of the core rate (0.75–0.89 at the same elevation), and the step past it does not. The kept CH values could not be scored with the data available; the other kept BT values were not tested.

**MAD ranges (link#302).** `default` converts its channel-width minima to mean annual discharge for BT, GR, KO and RB (link#307: 0.041 m³/s spawning, GR 0.20, and 0.021 for BT, GR and RB rearing; KO rears in lakes only). This bundle carries ranges calibrated on fish observations instead: BT spawning and rearing 0.078 m³/s, GR spawning 0.96 and rearing 0.97, KO spawning 0.57, RB spawning 0.011 and rearing 0.019, every maximum open (9999). **They move no output while every group is on `cw`**, which is every group today. The values were calibrated on fish observations in 46 groups. The BT, GR and RB values were then scored on held-out groups by a rule fixed before the run, and they are what that rule walked to. KO's is the unscored candidate: there is no held-out group for it. At these values a `mad` group keeps less stream rearing than `cw` does on the held-out groups: about a third less for BT and three-quarters less for GR (−32 % and −76 %, with main-stem discharge filled, link#305). Stream size and sampling effort are not yet separated in that score. The research doc gives the numbers; read it before moving a group to `mad`.

## When you change a value

1. Edit `parameters_habitat_thresholds.csv` and update its `checksum` in `config.yaml`'s `provenance:` block (`lnk_config_verify(lnk_config("default_tuned"))` reports the drift until you do).
2. If you changed `rear_lake_ha_min`, or added or dropped a species, this bundle needs its own `rules.yaml` (the inherited one was built from `default`'s thresholds, and `lnk_rules_build()` bakes those in); add a `rules:` key and build it with `thresholds =` pointing here. `data-raw/audit_configs.R` §2 rebuilds every bundle's rules from its own thresholds and flags the mismatch if you forget.
3. Runs record the values themselves in `<schema>.log_parameters_habitat_thresholds`, keyed on `config_hash`.

Do not tune the `bcfishpass` bundle's copy: it is the parity reference.
