# Segment the Stream Network at Configured Break Positions

Fourth phase of the habitat classification pipeline. Builds the
remaining break-source tables (observations, habitat endpoints,
crossings) that depend on AOI- and config-specific data, then runs
[`fresh::frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.html)
sequentially over the break sources in the order defined by the config.
After each round, `id_segment` is reassigned so downstream rounds see
contiguous integer IDs.

## Usage

``` r
lnk_pipeline_break(
  conn,
  aoi,
  cfg,
  loaded,
  schema,
  observations = "bcfishobs.observations"
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- aoi:

  Character. Watershed group code (today; extends to other spatial
  filters later).

- cfg:

  An `lnk_config` object from
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md).

- loaded:

  Named list of tibbles from
  [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md).
  Carries `observation_exclusions` and `wsg_species_presence`.

- schema:

  Character. Working schema name.

- observations:

  Character. Schema-qualified observations table (default
  `"bcfishobs.observations"`).

## Value

`conn` invisibly, for pipe chaining.

## Details

The break-source order matters. bcfishpass processes: observations →
gradient_minimal → falls → barriers_definite → habitat_endpoints →
crossings. This order is encoded in the bundled bcfishpass config
(`cfg$pipeline$break_order`) and is the default when the config does not
specify one.

### Break sources

Valid entries for `cfg$pipeline$break_order`. Omit an entry to skip both
segmentation and access-gating from that source.

|  |  |  |  |
|----|----|----|----|
| name | source table | role | classify label |
| `observations` | `<schema>.observations_breaks` | fish observations from `bcfishobs.observations`, WSG- and species-filtered, exclusions applied | (informational; not a barrier) |
| `gradient_minimal` | `<schema>.gradient_barriers_minimal` | minimal-reduced gradient barriers (per-model 15/20/25/30%) | classify uses the FULL set with `gradient_<NNNN>` labels |
| `falls` | `<schema>.falls` | natural waterfalls from `whse_basemapping.fwa_obstacles_sp` (loaded by `prep_load_aux`); each fall is its own barrier (NOT minimal-reduced) | `blocked` |
| `barriers_definite` | `<schema>.barriers_definite` | `user_barriers_definite.csv` for the AOI | `blocked` |
| `subsurfaceflow` | `<schema>.barriers_subsurfaceflow` | FWA `edge_type IN (1410, 1425)` start points; honours `user_barriers_definite_control`. Opt-in (only built when listed) | `blocked` |
| `habitat_endpoints` | `<schema>.habitat_endpoints` | DRM and URM from `user_habitat_classification.csv` | (segmentation only; not a barrier) |
| `crossings` | `<schema>.crossings_breaks` | PSCIS + modelled crossings (any `barrier_status`) | classify maps `barrier_status` → `barrier`/`potential`/`passable` |

Bcfishpass-bundle config opts in to `subsurfaceflow` for parity with
bcfishpass natural access. Default-bundle leaves it off pending a
NewGraph methodology decision.

Writes to (under the caller's working schema unless noted):

- `<schema>.observations_breaks` — WSG- and species-filtered observation
  positions, data-error exclusions applied

- `<schema>.habitat_endpoints` — both DRM and URM from the habitat
  classification table (matches bcfishpass convention)

- `<schema>.crossings_breaks` — crossing positions

- Mutates `fresh.streams` in place — adds segment boundaries at each
  break source position, reassigns `id_segment`

## See also

Other pipeline:
[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md),
[`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md),
[`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md),
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md),
[`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md),
[`lnk_pipeline_species()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_species.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn   <- lnk_db_conn()
cfg    <- lnk_config("bcfishpass")
loaded <- lnk_load_overrides(cfg)
schema <- "working_bulk"

lnk_pipeline_setup(conn, schema)
lnk_pipeline_load(conn, "BULK", cfg, loaded, schema)
lnk_pipeline_prepare(conn, "BULK", cfg, loaded, schema)
lnk_pipeline_break(conn, "BULK", cfg, loaded, schema)

DBI::dbGetQuery(conn,
  "SELECT count(*) FROM fresh.streams")

DBI::dbDisconnect(conn)
} # }
```
