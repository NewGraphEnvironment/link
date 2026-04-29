# default config

NewGraph default habitat-classification config. Method distinct from bcfishpass — intended for general-purpose watershed modelling rather than provincial-standard reproduction. Per-WSG comparison against the bcfishpass variant lives in `research/default_vs_bcfishpass.md`.

Documented departures from bcfishpass:

- Intermittent streams included in the rearing set.
- Wetland reaches (edge_type 1050/1150) as rearing habitat for species flagged `rear_wetland=yes` in dimensions.csv.
- Lake rearing expanded beyond SK/KO to BT/CO/ST/WCT per literature.
- `river_skip_cw_min=yes` — channel-width thresholds dropped on river-polygon segments where they're not meaningful.
- `spawn_gradient_min = 0.0025` to exclude depositional reaches from spawning.

Not in this config:

- Temperature / thermal refugia / GSDD — needs Poisson SSN + Hillcrest CW regression + water-temp-bc composed end-to-end. Separate follow-up.
- Channel-class-based segmentation — separate research question ([link#52](https://github.com/NewGraphEnvironment/link/issues/52)).

## What is in here

| File | Role |
|------|------|
| `config.yaml` | Manifest — points at everything below, plus pipeline parameters |
| `rules.yaml` | Built rules YAML (consumed by `frs_habitat_classify()`). Regenerate from `dimensions.csv` via `lnk_rules_build()` |
| `dimensions.csv` | Source of `rules.yaml` — species × habitat biology encoded for NewGraph defaults. Source of truth is `inst/extdata/parameters_habitat_dimensions.csv` (copied in here on bundle assembly) |
| `parameters_fresh.csv` | Per-species fresh overrides (spawn_gradient_min, observation_threshold, etc.) |
| `overrides/` | Shared jurisdiction data — same barrier corrections, PSCIS status overrides, observation exclusions, habitat confirmations as the bcfishpass variant. These are BC-specific facts, not method choices. Redistributed under `LICENSE-bcfishpass` at the repo root. |

The bundle is consumed via `lnk_config("default")` + `lnk_load_overrides(cfg)`. Project-experimental configs can declare `extends: default` to inherit this bundle and override specific entries (e.g. point a project's `user_barriers_definite` at a project-local CSV).

## What NOT to do here

- Do not hand-edit `rules.yaml` — edit `dimensions.csv` and run `lnk_rules_build()`.
- Do not hand-edit files under `overrides/` — shared with bcfishpass variant; file corrections in the upstream source.

## Regenerating rules.yaml

```r
link::lnk_rules_build(
  csv = system.file("extdata", "configs", "default", "dimensions.csv",
                    package = "link"),
  to = "inst/extdata/configs/default/rules.yaml",
  edge_types = "explicit"
)
```

See `data-raw/build_rules.R` for the canonical invocation (both variants regenerate there).

## See also

- `research/default_vs_bcfishpass.md` — per-WSG comparison + biological rationale
- `research/bcfishpass_comparison.md` — bcfishpass variant DAG + results
