# link <img src="man/figures/logo.png" align="right" height="139" alt="link hex sticker" />

> Develop, test and communicate intrinsic habitat and connectivity models for the BC Freshwater Atlas stream network

link is a tool for building models of where each fish species could spawn and rear on a stream network, and which of that habitat fish can reach. Current models rate habitat from stream gradient, channel width and discharge, resolve access past natural barriers such as falls and steep gradients, and record the road and rail crossings and dams that sit below. Its value is flexibility: every rule and threshold is a row in a config, so a model can be changed, run beside another, checked against fish observations and traced back to the rules that produced it.

> Experimental: APIs and outputs change without notice.

<img src="man/figures/readme-pars.png" alt="Map of the Parsnip River watershed group with stream reaches coloured by Arctic grayling spawning, rearing and access, and by the barrier type below each reach" width="100%" />

*Arctic grayling habitat in the Parsnip River watershed group. Purple reaches drain to Williston Reservoir behind the W.A.C. Bennett Dam. Orange and red reaches sit above a road or rail crossing that is a barrier. Grey reaches lie above a natural barrier to grayling.*

## Installation

```r
pak::pak("NewGraphEnvironment/link")
```

link runs against a PostgreSQL database holding the BC Freshwater Atlas through [fwapg](https://github.com/smnorris/fwapg), set up as for [fresh](https://github.com/NewGraphEnvironment/fresh).

## Example

A model is a config, and its rules are tables you can read and edit:

```r
library(link)

cfg    <- lnk_config("default")
loaded <- lnk_load_overrides(cfg)

th <- loaded$parameters_habitat_thresholds
th[th$species_code %in% c("BT", "GR"),
   c("species_code", "spawn_gradient_max", "spawn_channel_width_min",
     "rear_gradient_max", "rear_channel_width_min")]
#>   species_code spawn_gradient_max spawn_channel_width_min rear_gradient_max rear_channel_width_min
#> 1           BT             0.0549                       2            0.1049                    1.5
#> 2           GR             0.0249                       4            0.0349                    1.5
```

Run it for a watershed group, then sum the habitat each species can reach:

```r
conn <- lnk_db_conn()
cfg$pipeline$schema <- "fresh_default"
lnk_pipeline_run(conn, aoi = "PARS", cfg = cfg, loaded = loaded,
                 mapping_code = TRUE)

lnk_rollup_wsg(conn, aoi = "PARS", species = c("BT", "GR"),
               schema = "fresh_default")
#>    wsg species accessible_km spawning_km rearing_km rearing_lake_connection_km
#> 1 PARS      BT       6883.03     1685.38    2635.01                          0
#> 2 PARS      GR       4442.31      983.86    1366.32                          0
```

Change a threshold, run again, and compare. Each run records its inputs, its parameters and the source versions its data was loaded from, in log tables beside its results.

## Learn more

- [Bull trout and Arctic grayling in the Parsnip River](https://newgraphenvironment.github.io/link/articles/pars-habitat-connectivity.html): a full run for one watershed group, with maps for both species.
- [Function reference](https://newgraphenvironment.github.io/link/reference/)

## Ecosystem

| Package | Role |
|---|---|
| **link** | Intrinsic habitat models: develop, test and communicate (this package) |
| [fresh](https://github.com/NewGraphEnvironment/fresh) | Stream network modelling engine: segment, classify, cluster, aggregate |
| [wet](https://github.com/NewGraphEnvironment/wet) | Stream flow and water temperature for BC's Freshwater Atlas |
| [gq](https://github.com/NewGraphEnvironment/gq) | Shared map symbology |

## Data and methods it builds on

link's access model follows the method of [bcfishpass](https://github.com/smnorris/bcfishpass), built by Simon Norris and maintained with contributions from many groups. link also reads bcfishpass's community-maintained corrections to crossings, barriers and habitat, synced weekly into the `default` and `bcfishpass` configs so they stay in one place. A `bcfishpass` config applies bcfishpass's own rules, so results can be checked against the method they come from. Fish observations come from [bcfishobs](https://github.com/smnorris/bcfishobs), and the stream network from [fwapg](https://github.com/smnorris/fwapg) and the [BC Freshwater Atlas](https://www2.gov.bc.ca/gov/content/data/geographic-data-services/topographic-data/freshwater).

## Citation

```r
citation("link")
```

## License

MIT (see [`LICENSE`](LICENSE)). Redistributed bcfishpass data carries its own license: see [`NOTICE.md`](NOTICE.md) and [`LICENSE-bcfishpass`](LICENSE-bcfishpass).
