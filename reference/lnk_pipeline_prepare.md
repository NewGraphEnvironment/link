# Prepare the Network and Barrier Inputs for a Pipeline Run

Third phase of the habitat classification pipeline. Loads the evidence
and network data that downstream phases
([`break`](https://rdrr.io/r/base/Control.html), `classify`, `connect`)
consume:

## Usage

``` r
lnk_pipeline_prepare(
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

  Character. Watershed group code today; extends to ltree filters / sf
  polygons later (same AOI abstraction fresh uses).

- cfg:

  An `lnk_config` object from
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md).

- loaded:

  Named list of tibbles from
  [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md).
  Carries `user_barriers_definite`, `user_barriers_definite_control`,
  `user_habitat_classification`, and `parameters_fresh`.

- schema:

  Character. Working schema name (must already exist — call
  [`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md)
  first).

- observations:

  Character. Schema-qualified observations table used for building
  barrier overrides. Default `"bcfishobs.observations"` — matches
  bcfishpass's reference data on both M4 and M1 fwapg instances (see
  `rtj/docs/distributed-fwapg.md`).

## Value

`conn` invisibly, for pipe chaining.

## Details

- Falls (from the `fresh` package), user-identified definite barriers,
  user barriers-definite control table, and expert habitat confirmation
  CSVs from the config bundle

- Gradient barriers detected on the raw FWA network via
  [`fresh::frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.html),
  pruned against the control table, enriched with `wscode_ltree` and
  `localcode_ltree` for `fwa_upstream()` joins

- A natural-barriers table (gradient + falls) used by
  [`lnk_barrier_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_barrier_overrides.md)
  to compute the per-species skip list. User-definite barriers are
  intentionally excluded here and consumed by later phases directly —
  bcfishpass parity.

- Per-model barrier tables reduced to the minimal downstream-most set
  via
  [`fresh::frs_barriers_minimal()`](https://newgraphenvironment.github.io/fresh/reference/frs_barriers_minimal.html),
  then unioned into `gradient_barriers_minimal` for segmentation

- Base stream segments (`fresh.streams`) loaded from FWA with channel
  width, stream order parent, GENERATED gradient / measures / length
  columns, and a unique `id_segment`

Writes to (under the caller's working schema unless noted):

- `<schema>.falls`, `<schema>.barriers_definite`,
  `<schema>.barriers_definite_control`,
  `<schema>.user_habitat_classification`

- `<schema>.gradient_barriers_raw` (with ltree)

- `<schema>.natural_barriers`

- `<schema>.barrier_overrides`

- `<schema>.barriers_<model>` + `<schema>.barriers_<model>_min`
  per-model pre/post minimal reduction

- `<schema>.gradient_barriers_minimal` (union of minimal positions)

- `fresh.streams` (base segments — not namespaced by AOI; fresh owns its
  output schema)

## See also

Other pipeline:
[`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md),
[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md),
[`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md),
[`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md),
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

DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*) FROM %s.gradient_barriers_minimal", schema))

DBI::dbDisconnect(conn)
} # }
```
