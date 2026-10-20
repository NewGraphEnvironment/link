# Settle persisted habitat flags on link's access

Sets `accessible`, `spawning`, `rearing`, `lake_rearing` and
`wetland_rearing` FALSE in `<table_habitat>_<sp>` wherever
`<table_access>.access_<sp>` is 0, for one watershed group, so the
habitat flags agree with the access a consumer reads.

## Usage

``` r
lnk_habitat_gate(
  conn,
  aoi,
  table_habitat,
  table_access,
  table_streams,
  species,
  overlay = NULL,
  table_access_prior = NULL
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- aoi:

  Character. Watershed group code (e.g. `"DUNC"`).

- table_habitat:

  Character. Schema-qualified prefix of the per-species habitat tables:
  `<table_habitat>_<sp>` (e.g. `"fresh_default.streams_habitat"`).

- table_access:

  Character. Schema-qualified `streams_access` table.

- table_streams:

  Character. Schema-qualified `streams` table (measures and
  `length_metre`).

- species:

  Character vector of species codes to settle.

- overlay:

  A data frame in `user_habitat_classification`'s shape (`species_code`,
  `blue_line_key`, `downstream_route_measure`, `upstream_route_measure`,
  `spawning`, `rearing`), or `NULL` for none.

- table_access_prior:

  Character or `NULL`. Schema-qualified table of `id_segment`,
  `watershed_group_code` and `access_<sp>` as they were before the
  recompute that precedes this call. `NULL` leaves `n_lifted_settled`
  NA.

## Value

A data frame, one row per species and flag: `species`, `flag`,
`n_segments` and `km` set from TRUE to FALSE, and `n_lifted_settled`
(per species, repeated on its rows).

## Details

The two columns are built at different times from different barrier sets
(link#349). fresh's `accessible`, which gates spawning and rearing
inside `frs_habitat_classify()`, is computed once per group from that
group's own breaks: metre-rounded positions, within the group only,
lifted by the group's own overrides. `access_<sp>` is link's, built from
every group's persisted barriers and overrides and re-settled after a
multi-host run
([`lnk_access()`](https://newgraphenvironment.github.io/link/reference/lnk_access.md)
with `merge = TRUE`). `access_<sp>` is the authoritative one, and this
step makes the habitat flags follow it.

Rows that `user_habitat_classification` marks as known habitat keep
their `spawning` / `rearing` (bcfishpass forces known habitat whatever
the model says, and so does
[`fresh::frs_habitat_overlay()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_overlay.html));
their `accessible` is still set FALSE. Pass the loaded table as
`overlay` when the bundle applies the overlay. The match is the
overlay's own: same `blue_line_key`, the segment's measure range inside
the overlay row's.

The settle is one-way. A segment it blanks gets its habitat back only
from a re-model of the group: when a later recompute lifts a segment
(`access_<sp>` 0 to 1 or 2) whose `accessible` is FALSE, its habitat is
missing until then. Pass the access values from before the recompute as
`table_access_prior` and those segments are counted in
`n_lifted_settled`.

## See also

[`lnk_access()`](https://newgraphenvironment.github.io/link/reference/lnk_access.md),
[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md)

Other pipeline:
[`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md),
[`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md),
[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md),
[`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md),
[`lnk_pipeline_crossings()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_crossings.md),
[`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md),
[`lnk_pipeline_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_mapping_code.md),
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md),
[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md),
[`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md),
[`lnk_pipeline_species()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_species.md),
[`lnk_presence()`](https://newgraphenvironment.github.io/link/reference/lnk_presence.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
cfg <- lnk_config("default")
loaded <- lnk_load_overrides(cfg)

# After a recompute of DUNC's access in fresh_default:
lnk_habitat_gate(conn, aoi = "DUNC",
  table_habitat = "fresh_default.streams_habitat",
  table_access  = "fresh_default.streams_access",
  table_streams = "fresh_default.streams",
  species = lnk_pipeline_species(cfg, loaded, "DUNC"),
  overlay = loaded$user_habitat_classification)
} # }
```
