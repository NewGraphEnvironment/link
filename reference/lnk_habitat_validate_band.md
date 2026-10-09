# Score the habitat one threshold step adds or removes

Compares two persisted runs that share segmentation and differ in one
habitat threshold, and asks whether the segments the step moves (the
**band**) are used by fish about as often as habitat both runs agree on
(the **core**). It reports observations per km in each and their ratio,
which is the evidence for taking or refusing the step.

## Usage

``` r
lnk_habitat_validate_band(
  conn,
  aoi,
  species,
  flag = c("spawning", "rearing"),
  schema,
  schema_ref,
  observations,
  stage = c("any", "spawn", "rear"),
  schema_core = c(schema, schema_ref)
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`lnk_db_conn()`](https://newgraphenvironment.github.io/link/reference/lnk_db_conn.md)).

- aoi:

  Character vector of watershed group codes, persisted in every schema.

- species:

  Character vector of model species codes. Each must name
  `<schema>.streams_habitat_<sp>` in every schema.

- flag:

  `"spawning"` or `"rearing"` (fresh's `rearing` flag, which the rearing
  thresholds govern on stream lines).

- schema:

  Persist schema with the step taken.

- schema_ref:

  Persist schema the step is taken from.

- observations:

  The `observations` data frame from
  [`lnk_habitat_validate()`](https://newgraphenvironment.github.io/link/reference/lnk_habitat_validate.md).
  Uses `species_code`, `watershed_group_code`, `id_segment`, `is_spawn`
  and `is_rear`.

- stage:

  Which locations count: `"any"` (all), `"spawn"` (spawn-staged) or
  `"rear"` (rear-staged).

- schema_core:

  Character vector of persist schemas whose shared `flag` segments form
  the core. Default `c(schema, schema_ref)`.

## Value

A data frame, one row per `watershed_group_code` x `species_code` x
`direction` (`added`, `removed`), with `flag`, `stage`, `band_km`,
`n_band` (locations on band segments), `core_km`, `n_core`,
`density_band` and `density_core` (locations per km; `NA` when the km is
0) and `density_ratio` (`density_band / density_core`; `NA` when either
is `NA` or the core density is 0). Counts are returned beside the
densities so rows can be pooled across WSGs by summing.

## Details

For each watershed group and species:

- **Band, `added`:** segments `flag` in `schema` and not in
  `schema_ref`.

- **Band, `removed`:** segments `flag` in `schema_ref` and not in
  `schema`.

- **Core:** segments `flag` in every schema of `schema_core`. Pass all
  the schemas of a threshold ladder so the core is the habitat no step
  in it moves.

Observation locations are counted on the segment the validator attached
them to, so `observations` must come from
[`lnk_habitat_validate()`](https://newgraphenvironment.github.io/link/reference/lnk_habitat_validate.md)
on one of these schemas.

## Why segmentation must match

Segments are compared on the full key
`(id_segment, watershed_group_code)`, which names the same stretch of
stream in two schemas only when both were broken identically. Two full
pipeline runs are not guaranteed to be, so prepare the network once and
re-classify it per threshold. The function compares an `id_segment` x
`length_metre` digest of `streams` per WSG across every schema it reads
and stops when any differ. It also stops when a schema holds no
`streams_habitat_<sp>` rows for a WSG, which would otherwise read as a
WSG with no habitat.

## See also

[`lnk_habitat_validate()`](https://newgraphenvironment.github.io/link/reference/lnk_habitat_validate.md)

Other compare:
[`lnk_access()`](https://newgraphenvironment.github.io/link/reference/lnk_access.md),
[`lnk_compare_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_mapping_code.md),
[`lnk_compare_rollup()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_rollup.md),
[`lnk_compare_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_wsg.md),
[`lnk_habitat_validate()`](https://newgraphenvironment.github.io/link/reference/lnk_habitat_validate.md),
[`lnk_log_read()`](https://newgraphenvironment.github.io/link/reference/lnk_log_read.md),
[`lnk_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_mapping_code.md),
[`lnk_parity_annotate()`](https://newgraphenvironment.github.io/link/reference/lnk_parity_annotate.md),
[`lnk_rollup_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_rollup_wsg.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config("default")
loaded <- lnk_load_overrides(cfg)

# Observations as the validator attaches them to segments
v <- lnk_habitat_validate(conn, aoi = "BULL", cfg = cfg, loaded = loaded,
                          species = "BT", schema = "score284_default")

# Is the rearing that BT rear_gradient_max 0.1249 -> 0.1349 adds used as
# often per km as the rearing every step agrees on?
lnk_habitat_validate_band(
  conn, aoi = "BULL", species = "BT", flag = "rearing",
  schema = "score284_bt_rear_0p1349",
  schema_ref = "score284_bt_rear_0p1249",
  observations = v$observations, stage = "any",
  schema_core = c("score284_default", "score284_bt_rear_0p1249",
                  "score284_bt_rear_0p1349"))
} # }
```
