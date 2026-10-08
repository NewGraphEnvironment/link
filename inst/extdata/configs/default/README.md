# default config

NewGraph default habitat-classification config. Method distinct from bcfishpass — intended for general-purpose watershed modelling rather than provincial-standard reproduction. Per-WSG comparison against the bcfishpass variant lives in `research/default_vs_bcfishpass.md`.

Documented departures from bcfishpass:

- Intermittent streams included in the rearing set.
- Wetland reaches (edge_type 1050/1150) as rearing habitat for species flagged `rear_wetland=yes` in dimensions.csv.
- Both wetland rear rules require wetlands of at least `rear_wetland_ha_min` (1 ha; CO 0.5 ha): the 1050/1150 wetland-flow rule and the polygon rule for mainlines through wetlands (link#311). Mainlines in smaller wetlands can still rear through the stream rule, which has no waterbody test.
- Lake rearing expanded beyond SK/KO to BT/CO/ST/WCT per literature.
- `river_skip_cw_min=yes` — channel-width thresholds dropped on river-polygon segments where they're not meaningful.
- Mean-annual-discharge minima for BT, GR, KO and RB, which bcfishpass leaves unranged: this bundle's own width minima converted to discharge (link#307). They act only in a group put on `mad`.
- Not a departure: `spawn_gradient_min` stays 0, as in bcfishpass. A 0.0025 floor to exclude depositional reaches over-pruned observed spawning and was reverted (`research/default_vs_bcfishpass.md` §4); calibrating it is link#284.

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
| `parameters_habitat_thresholds.csv` | Per-species gradient / channel-width / MAD / lake-area thresholds and edge types, read by classify and connect. fresh's copy, plus mean-annual-discharge minima for BT, GR, KO and RB converted from this bundle's own channel-width minima (spawning 2 m, GR 4 m → 0.041 / 0.20 m³/s; BT, GR and RB rearing 1.5 m → 0.021, KO rearing lake-only and unranged; maxima open; link#307, producer `data-raw/query_width_mad_equivalent.R`), so in a group put on `mad` their streams are sized by discharge instead of dropping out. A line with no `mad_m3s` still fails every MAD test: this bundle sets no `discharge_fill`, and a group with no discharge coverage (BULK) keeps no stream habitat. Provenance in `config.yaml`. |
| `parameters_habitat_method.csv` | Per-watershed-group habitat size model, `cw` (channel width) or `mad` (mean annual discharge), handed to fresh by classify. All `cw`; a frozen copy of bcfishpass `parameters/example_newgraph`, not csv-synced, so moving a group to `mad` is a reviewed edit (update its `checksum` in `config.yaml`). Columns in `configs/dictionary_parameters_habitat_method.csv`. |
| `species_pooling.csv` | Which observation species count as evidence for which model species, and where: one dated, sourced row per decision, scoped to a region, sub-region (`inst/extdata/wsg_regions.csv`) or WSG. Either side can be a group from `species_groups.csv`. Read by `lnk_species_pooling()`; columns in `configs/dictionary_species_pooling.csv`. Anything unlisted is not pooled. After an edit, update its `checksum` in `config.yaml` (`lnk_config_verify()` reports the drift until you do). |
| `species_groups.csv` | Named sets of species (`SALMON`, `CHAR`) usable on either side of a pooling row. |
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
