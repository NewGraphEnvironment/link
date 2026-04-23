# bcfishpass config

Reproduces bcfishpass output exactly for regression. All five watershed groups (ADMS, BULK, BABL, ELKR, DEAD) are within 5% of bcfishpass when this config drives the pipeline. ADMS/BULK/BABL/ELKR are the numerical-parity set; DEAD is the end-to-end test for the `barriers_definite_control` override filter (see `research/bcfishpass_comparison.md`).

## What is in here

| File | Role |
|------|------|
| `config.yaml` | Manifest — points at everything below, plus pipeline parameters |
| `rules.yaml` | Built rules YAML (consumed by `frs_habitat_classify()`). Regenerate from `dimensions.csv` via `lnk_rules_build()` |
| `dimensions.csv` | Source of `rules.yaml` — species × habitat biology encoded for bcfishpass-match |
| `parameters_fresh.csv` | Per-species fresh overrides (spawn_gradient_min, observation_threshold, etc.) |
| `overrides/` | Synced from `smnorris/bcfishpass/data/` — expert-curated corrections + confirmed habitat + observation exclusions |

## What NOT to do here

- Do not hand-edit `rules.yaml` — edit `dimensions.csv` and run `lnk_rules_build()`
- Do not hand-edit files under `overrides/` — they are synced from bcfishpass upstream; file your correction there instead (see [smnorris/bcfishpass](https://github.com/smnorris/bcfishpass))

## Regenerating rules.yaml

```r
link::lnk_rules_build(
  csv = system.file("extdata", "configs", "bcfishpass", "dimensions.csv",
                    package = "link"),
  to = "inst/extdata/configs/bcfishpass/rules.yaml",
  edge_types = "explicit"
)
```

See `data-raw/build_rules.R` for the canonical invocation.

## See also

- `research/bcfishpass_comparison.md` — pipeline DAG and per-WSG results
- [link#37](https://github.com/NewGraphEnvironment/link/issues/37) — `lnk_config` loader that consumes `config.yaml`
