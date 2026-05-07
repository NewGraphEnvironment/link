# Build per-segment access codes + downstream-feature arrays

Composes
[`fresh::frs_network_features()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_features.html)
calls across species (and optionally observations) to produce a
`streams_access` wide table that mirrors `bcfishpass.streams_access`'s
shape — one row per segment, with per-species `barriers_<sp>_dnstr`
arrays and per- species integer `access_<sp>` codes derived via CASE on
(wsg-presence × dnstr-empty × observed-upstream).

## Usage

``` r
lnk_pipeline_access(
  conn,
  segments,
  aoi,
  to = NULL,
  barriers_per_sp = list(),
  observations = NULL,
  wsg_presence = list(),
  presence = NULL,
  barrier_sources = list(),
  crossings_table = NULL,
  segment_id_col = "id_segment"
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object pointing at fwapg.

- segments:

  Character. Schema-qualified segments table.

- aoi:

  Character. Watershed group code (e.g. `"ADMS"`). Filter applied to
  segments via `watershed_group_code = aoi`.

- to:

  Character or `NULL`. Optional schema-qualified output table. When
  supplied, the wide `streams_access` shape is written via
  `dbWriteTable(overwrite = TRUE)`; in either case the tibble is
  returned invisibly. Default `NULL` returns-only.

- barriers_per_sp:

  Named list. Each name is a species code (e.g. `"bt"`); each value is a
  schema-qualified barriers table for that species (e.g.
  `"working_adms.barriers_bt"`). Each barriers table must have a
  `<sp>_id` column (e.g. `barriers_bt_id`) plus the standard
  `(blue_line_key, downstream_route_measure, wscode_ltree, localcode_ltree)`
  keys.

- observations:

  Character or `NULL`. Optional schema-qualified observations table with
  `(observation_key, species_code, ...)` + the standard FWA keys. When
  provided, drives the access code distinction between `1` (modelled)
  and `2` (observed). Default `NULL` collapses
  observation-distinguishing logic — every accessible segment gets
  `access_<sp> = 1`.

- wsg_presence:

  Named logical. One per species (matching `barriers_per_sp` keys),
  `TRUE` when the species is present in `aoi`. Sets `access_<sp> = -9`
  for species marked `FALSE`. Default empty list assumes all species
  present (no -9 codes emitted).

- barrier_sources:

  Named list. Each name is an arbitrary source tag (e.g.
  `"anthropogenic"`, `"pscis"`, `"dams"`, `"remediations"`); each value
  is a schema-qualified barriers table for that source. Output gains one
  `has_barriers_<source>_dnstr` boolean column per source. Unlike
  `barriers_per_sp`, sources here don't drive the species access integer
  code – they're the bcfp-shape dnstr indicators consumed by
  [`lnk_pipeline_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_mapping_code.md).
  Optional; default empty.

  When both `"anthropogenic"` and `"dams"` are present, the output gains
  a `dam_dnstr_ind` boolean column: TRUE iff the next- downstream
  anthropogenic barrier is also a dam (sequence-aware, mirrors bcfp's
  `array[barriers_anthropogenic_dnstr[1]] && barriers_dams_dnstr` SQL).
  Required for resident-flavor `mapping_code_bt` / `mapping_code_wct`
  parity with bcfp.

  When `"remediations"` is present AND `crossings_table` is set, the
  output gains a `remediated_dnstr_ind` boolean column.

- crossings_table:

  Character or `NULL`. Schema-qualified crossings table with
  `aggregated_crossings_id` and `pscis_status` columns (e.g.
  `"bcfishpass.crossings"`). Used only to compute `remediated_dnstr_ind`
  (TRUE iff the next-downstream remediation is a crossing whose
  `pscis_status IN ('REMEDIATED', 'PASSABLE')`).

  bcfp's own `streams_access.remediated_dnstr_ind` is currently buggy
  (see smnorris/bcfishpass#690): the JOIN clause
  `pscis_status = 'REMEDIATED' AND pscis_status = 'PASSABLE'` is
  contradictory and always FALSE – verified against 4.2M rows. link
  computes the bcfp-intended `IN` semantics, so link's mapping_code may
  emit `REMEDIATED` tokens on segments where bcfp's current output emits
  `DAM` / `MODELLED` / `ASSESSED`. PR filed against the
  `NewGraphEnvironment/bcfishpass` fork; once it lands + propagates
  upstream the outputs converge. Default `NULL` skips the
  `remediated_dnstr_ind` column.

- segment_id_col:

  Character. Default `"id_segment"`.

## Value

`conn` invisibly, for piping.

## Details

This phase runs after
[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md)
returns and before
[`lnk_pipeline_persist()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_persist.md)
cleanup_working drops the working schema — it needs the per-species
`barriers_<sp>` tables that prepare/break built. Output goes to
`<schema>.streams_access` (working schema, picked up by persist on the
next commit).

Access integer codes per species (mirroring bcfp): -9 = species not
present in WSG (per `wsg_presence`) 0 = barriers downstream (blocked) 1
= no barriers downstream + species not observed upstream (modelled
accessible) 2 = no barriers downstream + species observed upstream

## See also

Other pipeline:
[`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md),
[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md),
[`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md),
[`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md),
[`lnk_pipeline_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_mapping_code.md),
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md),
[`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md),
[`lnk_pipeline_species()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_species.md),
[`lnk_presence()`](https://newgraphenvironment.github.io/link/reference/lnk_presence.md)
