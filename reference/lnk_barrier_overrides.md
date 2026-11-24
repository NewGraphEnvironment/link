# Build barrier override list from evidence sources

Processes fish observations, habitat confirmations, and control tables
to determine which gradient/falls barriers should be skipped during
access classification. Uses `fwa_upstream()` SQL in fwapg to check
whether evidence exists upstream of each barrier.

## Usage

``` r
lnk_barrier_overrides(
  conn,
  barriers,
  observations = NULL,
  habitat = NULL,
  exclusions = NULL,
  control = NULL,
  params,
  cols_index = c("blue_line_key", "wscode_ltree", "localcode_ltree"),
  to,
  evidence = NULL,
  verbose = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- barriers:

  Character. Schema-qualified table of barriers with columns:
  `blue_line_key`, `downstream_route_measure`, `wscode_ltree`,
  `localcode_ltree`, `label`. Typically `fresh.streams_breaks`.

- observations:

  Character or `NULL`. Schema-qualified table of fish observations with
  columns: `species_code`, `blue_line_key`, `downstream_route_measure`,
  `wscode`, `localcode`, `observation_date`. Typically
  `bcfishobs.observations`.

- habitat:

  Character or `NULL`. Schema-qualified table of confirmed habitat in
  canonical shape (post-2026-04-26 bcfishpass): one row per (segment x
  species) with columns `species_code`, `blue_line_key`,
  `downstream_route_measure`, `upstream_route_measure`, plus
  per-habitat-type indicator columns `spawning` and `rearing` (integer 1
  / NULL or text `'t'`/`'true'`). Any confirmed habitat (spawning or
  rearing flagged) upstream of a barrier removes it (threshold = 1).

- exclusions:

  Character or `NULL`. Schema-qualified table of observation exclusions
  with column `observation_key`. Flagged observations are removed before
  counting.

- control:

  Character or `NULL`. Schema-qualified table of barrier controls with
  columns: `blue_line_key`, `downstream_route_measure`, `barrier_ind`.
  Barriers in this table with `barrier_ind = TRUE` cannot be overridden
  **by observations** — but only for species where
  `params$observation_control_apply` is TRUE. Resident species routinely
  inhabit reaches upstream of anadromous-blocking falls (post-glacial
  connectivity, no ocean-return requirement), so their observations
  still count unless this flag says otherwise. Habitat confirmations
  (`habitat` argument) are higher-trust than observations — they bypass
  the control table entirely, for all species.

- params:

  Data frame of lift rules, one row per rule. Must have columns:
  `species_code`, `observation_threshold`, `observation_date_min`,
  `observation_buffer_m`, `observation_species`. Optional column
  `observation_control_apply` (logical) — when TRUE, the `control` table
  blocks overrides for this rule; when FALSE/NA/missing, the rule
  ignores control. Bcfishpass defaults: TRUE for CH/CM/CO/PK/SK/ST,
  FALSE for BT/WCT. See `configs/bcfishpass/parameters_fresh.csv`.
  Optional column `rule` names each rule (link#236): a species may have
  several, and a barrier is lifted where any one of them is met (the
  records of two rules never add together). Without it every row is rule
  `own`, so a `parameters_fresh.csv`-shaped table lifts as it always
  has. Habitat lifts run once per species, on its `own` row's species
  list.

- cols_index:

  Character vector. Column names to index on the barriers table for
  `fwa_upstream()` performance. Indexes are created `IF NOT EXISTS`.
  Default `c("blue_line_key", "wscode_ltree", "localcode_ltree")` — only
  columns that exist in the table are indexed.

- to:

  Character. Schema-qualified output table name.

- evidence:

  Character or `NULL`. Schema-qualified table to (re)create holding what
  each lift rests on (link#434): one row per lifted barrier, species and
  evidence record. An observation lift lists every record that met the
  rule (`observation_key`, the code it is filed under, its date and
  group); a habitat lift lists each confirming habitat row. Every row
  carries the rule as applied (`observation_threshold`,
  `observation_date_min`, `observation_species`, `observation_buffer_m`)
  and its name in `lift_rule` (`habitat` for a habitat lift), so a
  record counted under two rules has a row for each. `NULL` (default)
  writes none.

- verbose:

  Logical. Report counts.

## Value

Invisible data frame with override counts per species.

## Details

This is the interpretation layer — link decides which barriers to skip
based on domain-specific evidence and thresholds. fresh receives the
output as a simple skip list via `barrier_overrides`.

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()

params <- read.csv(system.file("extdata", "configs", "bcfishpass",
  "parameters_fresh.csv", package = "link"))

lnk_barrier_overrides(conn,
  barriers = "fresh.streams_breaks",
  observations = "bcfishobs.observations",
  habitat = "working.user_habitat_classification",
  params = params,
  to = "working.barrier_overrides"
)

# Pass to fresh
fresh::frs_habitat(conn, wsg = "ADMS",
  barrier_overrides = "working.barrier_overrides",
  ...)
} # }
```
