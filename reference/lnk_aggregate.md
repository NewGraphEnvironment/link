# Habitat upstream of each crossing, per species

For each crossing, sums the habitat of each species found anywhere
upstream of it on the stream network: the crossing's own stream above it
and every tributary, in every watershed group the persist schema holds.
This is the demand side of prioritization: severity says how bad a
barrier is, upstream habitat says what fixing it would open.

## Usage

``` r
lnk_aggregate(
  conn,
  crossings,
  schema,
  to,
  config,
  species = NULL,
  col_id = "aggregated_crossings_id",
  barriers = NULL,
  barriers_col_id = "barriers_anthropogenic_id",
  verbose = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- crossings:

  Character. Schema-qualified table of crossings, with `col_id`,
  `blue_line_key` and `downstream_route_measure`. Typically a working
  schema's `crossings`.

- schema:

  Character. The persist schema holding `streams` and
  `streams_habitat_<sp>` (for example `"fresh_default"`). Every group it
  holds is read: upstream habitat crosses watershed groups, so groups
  upstream of the crossings must be persisted for their habitat to
  count.

- to:

  Character. `<schema>.<table>` to write (dropped and recreated),
  outside `schema` and different from `crossings` and `barriers`. One
  row per crossing and species.

- config:

  Character. The config whose build `schema` holds, written to the
  `config` column (for example `cfg$name`).

- species:

  Character vector of species codes, or `NULL` (default) for every
  `streams_habitat_<sp>` table in `schema`.

- col_id:

  Character. Crossing identifier column. Default
  `"aggregated_crossings_id"`.

- barriers:

  Character or `NULL`. Schema-qualified table of human-made barriers
  (for example a working schema's `barriers_anthropogenic`, from
  [`lnk_barriers_emit()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_emit.md)),
  with `barriers_col_id`, `blue_line_key`, `downstream_route_measure`.
  When given, each metric also gets a `_belowupstrbarriers_km` total:
  the habitat upstream of the crossing but below the next barriers
  upstream, as bcfishpass's `*_belowupstrbarriers_km`.

- barriers_col_id:

  Character. Identifier column of `barriers`. Default
  `"barriers_anthropogenic_id"`. Ids shared with `crossings` name the
  same feature.

- verbose:

  Logical. Report each species' summary.

## Value

`invisible(to)`. Side effect: creates `to`.

## Details

The walk is
[`fresh::frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.html),
refined by the measure-aware
`fwa_upstream(..., include_equivalents = TRUE, tolerance = 1)` that
bcfishpass's `crossings_upstream_habitat` uses, so a segment counts when
it starts at or above the crossing (within 1 m) on the crossing's own
stream, or lies on a stream that joins above it. The main stem below the
crossing never counts.

Columns of `to`: the crossing id (named as `col_id`), `config`,
`species_code`, then in km:

- `spawning_km`: segments the species spawns on;

- `rearing_km`: segments it rears on, lake connection lines left out, as
  [`lnk_rollup_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_rollup_wsg.md)'s
  `rearing_km`;

- `rearing_stream_km`, `rearing_lake_km`, `rearing_wetland_km`: that
  rearing split by the polygon each line sits in;

- `rearing_lake_connection_km`: rearing on lake connection lines (FWA
  edge 1450 in a lake), which bcfishpass counts in rearing.

Each sum is exact (`numeric`), so it does not depend on row order. A
crossing with no habitat upstream gets zeros. A crossing whose measure
is exactly the top of its stream has no segment holding it, so nothing
is found above it and it gets zeros.

The barrier totals subtract, from a crossing's total, the totals of the
barriers upstream of it that have no other barrier between it and them
(a barrier at the crossing's own id is not its own upstream barrier). Of
two barriers within 1 m on one stream, the one with the higher measure
is upstream of the other, so the habitat above the pair is subtracted
once.

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
# a working schema left by lnk_pipeline_run(cleanup_working = FALSE)
lnk_aggregate(conn,
  crossings = "working_adms.crossings",
  schema = "fresh_default",
  to = "working_adms.crossings_upstream_habitat",
  config = "default",
  barriers = "working_adms.barriers_anthropogenic")

# which barriers block the most chinook spawning below the next barrier?
DBI::dbGetQuery(conn, "
  SELECT aggregated_crossings_id, spawning_belowupstrbarriers_km
  FROM working_adms.crossings_upstream_habitat
  WHERE species_code = 'CH'
  ORDER BY 2 DESC LIMIT 5")
} # }
```
