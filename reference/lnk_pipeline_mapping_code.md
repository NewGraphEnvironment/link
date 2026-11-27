# Build per-segment per-species mapping_code strings (bcfp parity)

Mirrors `bcfishpass.streams_mapping_code` – a per-segment per-species
semicolon-token compound describing the segment's habitat label, the
most-relevant downstream barrier source, and an intermittent flag if
applicable. Pure derivation over the bcfp-shape inputs (no SQL).

## Usage

``` r
lnk_pipeline_mapping_code(
  access,
  habitat,
  feature_code,
  to = NULL,
  conn = NULL,
  presence = NULL,
  species_resident = NULL,
  species_anadromous = NULL,
  species_spawn_only = NULL,
  segment_id_col = "id_segment",
  intermittent_feature_code = "GA24850150",
  cfg = NULL,
  rules_mapping_code = NULL
)
```

## Arguments

- access:

  A tibble or data.frame keyed by `segment_id_col` with
  `has_barriers_<sp>_dnstr` boolean per species, plus the bcfp-shape
  sources `has_barriers_anthropogenic_dnstr`,
  `has_barriers_pscis_dnstr`, `has_barriers_dams_dnstr`, and (optional)
  `has_remediated_dnstr`. Typically the output of
  [`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md)
  called with `barrier_sources` populated.

- habitat:

  A tibble keyed by `segment_id_col` with `spawning_<sp>` and
  `rearing_<sp>` numeric columns per species. Mirrors bcfp's
  `streams_habitat_linear` shape. A species with no `spawning_<sp>` or
  `rearing_<sp>` column reads 0 there, as bcfishpass pre-allocates every
  species' columns (link#153); a segment with no habitat row at all
  still reads `NA`.

- feature_code:

  Named character or data.frame. Either a named character vector mapping
  `segment_id` -\> `feature_code`, or a data.frame with `segment_id_col`
  and `"feature_code"` columns. Used for the `INTERMITTENT` flag.

- to:

  Character or `NULL`. Optional schema-qualified destination table. When
  supplied, the result tibble is written via
  `dbWriteTable(overwrite = TRUE)` and the tibble is also returned (so
  callers can chain into `lnk_persist_write` / `build_species_views.R`).
  Default `NULL` returns-only.

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html).
  Required only when `to` is supplied; ignored otherwise.

- presence:

  `NULL` (the default), an `lnk_presence` object, or a named logical
  vector keyed by lower-case species code (link#351). A species it marks
  absent, or does not name, emits `""` in its token column; with `NULL`
  every species is coded.

- species_resident:

  Character or `NULL`. Species using the resident flavor of
  `mapping_code_barrier`. `NULL` (the default) takes the bundle's
  resident species from `cfg` (its `dimensions.csv` `residence` column,
  link#512), or `c("bt", "wct")` with no `cfg`. With `cfg`, the sets
  cover every species the bundle models (`cfg$species`); a persisted
  build codes only the group's active ones.

- species_anadromous:

  Character or `NULL`. Species using the anadromous flavor: from `cfg`
  as above, or `c("ch", "cm", "co", "pk", "sk", "st")` with no `cfg`. A
  species in both sets is refused.

- species_spawn_only:

  Character or `NULL`. Species without rearing semantics (token 1 only
  emits SPAWN, never REAR): from `cfg` (`rear_no_fw = yes`), or
  `c("cm", "pk")` with no `cfg`. Mirrors bcfp.

- segment_id_col:

  Character. Default `"id_segment"`.

- intermittent_feature_code:

  Character. The `feature_code` value that flags an intermittent stream.
  Default `"GA24850150"` (bcfp).

- cfg:

  An
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md)
  object, or `NULL`. Supplies the residence sets not passed and the
  mapping-code rules (`parameters_mapping_code_rules` under `files:`).

- rules_mapping_code:

  A data frame of mapping-code rules (`residence`, `precedence`,
  `token`, `when`), or `NULL` to read them from `cfg`, else the package
  copy.

## Value

A tibble keyed by `segment_id_col` with one `mapping_code_<sp>`
character column per species in
`union(species_resident, species_anadromous)`.

## Details

Vocabulary (per species):


    {ACCESS|SPAWN|REAR|""} ; {NONE|DAM|MODELLED|ASSESSED|REMEDIATED} [;INTERMITTENT]

Token 1 (habitat) per bcfp:

- `ACCESS`: species' barriers all upstream (i.e. accessible to species)
  AND segment has no spawning AND no rearing eligibility for the species

- `SPAWN`: spawning eligibility \> 0 (always wins over REAR)

- `REAR`: rearing eligibility \> 0 AND no spawning

- `""` (empty): species has at least one downstream barrier blocking it
  (so habitat label is suppressed – inaccessible).

- For species without rearing semantics (CM, PK), the rearing conditions
  drop out – only `ACCESS` (no spawn, no barriers) and `SPAWN` (spawning
  \> 0) emit.

Token 2 (barrier source) only emits when the species' barriers
downstream is empty (i.e. accessible). It comes from the bundle's
`parameters_mapping_code_rules.csv` (link#197): per residence, rows in
`precedence` order, first matching `when` wins, so a bundle adds or
reorders a token with no code change. A bundle that declares no file, or
a call with no `cfg`, reads the package copy, bcfishpass's order.
Resident and anadromous species differ there in their CASE order:

- Resident: REMEDIATED \> DAM (the next barrier down is a dam) \>
  ASSESSED (anthropogenic + pscis + no dam) \> MODELLED (anthropogenic +
  no pscis + no dam) \> NONE.

- Anadromous: REMEDIATED \> DAM (any dam) \> ASSESSED (any pscis) \>
  MODELLED (any anthropogenic) \> NONE.

Token 3 emits `INTERMITTENT` when the segment's `feature_code` matches
the bcfp intermittent code (default `"GA24850150"`) AND the species'
barriers downstream is empty.

Empty / NULL tokens are dropped via `paste(..., collapse = ";")`-style
composition so an inaccessible segment yields `""` (empty string) and an
accessible no-habitat-no-intermittent segment yields `"ACCESS;NONE"`.

## See also

Other pipeline:
[`lnk_habitat_gate()`](https://newgraphenvironment.github.io/link/reference/lnk_habitat_gate.md),
[`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md),
[`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md),
[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md),
[`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md),
[`lnk_pipeline_crossings()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_crossings.md),
[`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md),
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md),
[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md),
[`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md),
[`lnk_pipeline_species()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_species.md),
[`lnk_presence()`](https://newgraphenvironment.github.io/link/reference/lnk_presence.md)
