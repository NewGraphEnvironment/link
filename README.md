# link <img src="man/figures/logo.png" align="right" height="139" alt="" />

Connect features to stream networks and interpret what they mean.

link is the interpretation layer between point features on a network
and [fresh](https://github.com/NewGraphEnvironment/fresh)'s generic
modelling engine. It loads, validates, matches, scores, and overrides
features — crossings, observations, barriers, habitat confirmations —
then produces the specs that fresh consumes.

fresh answers "what is the habitat on this network?" link answers
"what do these features mean for this network?"

## Installation

```r
pak::pak("NewGraphEnvironment/link")
```

## What it does

```
override CSVs    --\
crossing data    ----> link (load, match, score, interpret) --> break sources --> fresh
fish observations --/                                       --> barrier overrides -->
habitat confirms -/
```

1. **Load and validate** — read correction CSVs into the database with
   provenance tracking and referential integrity checks
2. **Match** — link features from different sources (PSCIS assessments,
   modelled crossings, culvert inventories) using network position with
   bidirectional deduplication
3. **Override** — apply hand-reviewed corrections accumulated across field
   seasons, flag orphans and duplicates
4. **Score** — classify features by biological impact (severity) or
   weighted multi-criteria ranking (prioritization)
5. **Interpret barriers** — process observations and habitat confirmations
   into per-species barrier skip lists using `fwa_upstream()` network
   topology
6. **Bridge to fresh** — produce break source specs and barrier override
   tables that plug directly into `frs_habitat()`

## Data sources

No database required for loading and validation. DB needed for match,
score, and barrier override functions (SQL via fwapg).

| Data | Source |
|------|--------|
| Crossings (province-wide) | `fresh::system.file("extdata", "crossings.csv")` |
| PSCIS assessments | `bcdata::bcdc_get_data("7ecfafa6-...")` |
| Override CSVs | `inst/extdata/` (synced from bcfishpass/data) |
| Habitat thresholds | `fresh::system.file("extdata", "parameters_habitat_thresholds.csv")` |
| Species presence per WSG | `fresh::system.file("extdata", "wsg_species_presence.csv")` |

## Quick start

```r
library(link)

conn <- lnk_db_conn()

# Load crossings, apply corrections
lnk_load(conn, csv = "overrides.csv", to = "working.fixes")
lnk_override(conn, "working.crossings", "working.fixes")

# Score severity
lnk_score(conn, "working.crossings", method = "severity")

# Build barrier override list from observations + habitat confirmations
lnk_barrier_overrides(conn,
  barriers = "working.natural_barriers",
  observations = "bcfishobs.observations",
  habitat = "working.user_habitat_classification",
  params = params_fresh,
  to = "working.barrier_overrides")

# Bridge to fresh
src <- lnk_source(conn, "working.crossings")
fresh::frs_habitat(conn, "MORR",
  break_sources = list(src),
  barrier_overrides = "working.barrier_overrides")

# Per-crossing upstream habitat rollup
lnk_aggregate(conn, "working.crossings", "fresh.streams_habitat")
```

## Ecosystem

| Package | Role |
|---------|------|
| [fresh](https://github.com/NewGraphEnvironment/fresh) | Stream network modelling engine — segment, classify, cluster |
| **link** | Feature interpretation — load, match, score, override (this package) |
| [flooded](https://github.com/NewGraphEnvironment/flooded) | Delineate floodplain extents from DEMs and stream networks |
| [drift](https://github.com/NewGraphEnvironment/drift) | Track land cover change within floodplains over time |

fresh models habitat on the network. link connects features to the
network and interprets them. They change for different reasons and can
each be used independently.

## License

MIT
