# link 0.2.0

Config bundles for pipeline variants.

- Add `lnk_config(name_or_path)` — load a config bundle (rules YAML, dimensions CSV, parameters_fresh, overrides, pipeline knobs) as one list object. Bundles live at `inst/extdata/configs/<name>/` with a `config.yaml` manifest, or any directory containing `config.yaml` for custom variants ([#37](https://github.com/NewGraphEnvironment/link/issues/37))
- Relocate bcfishpass config files into `inst/extdata/configs/bcfishpass/` (rules.yaml, dimensions.csv, parameters_fresh.csv, overrides/). All R scripts and data-raw/ references updated.

# link 0.0.0.9000

Initial release. Crossing connectivity interpretation layer — scores,
overrides, and prioritizes crossings for fish passage using configurable
severity thresholds and multi-source data integration.
