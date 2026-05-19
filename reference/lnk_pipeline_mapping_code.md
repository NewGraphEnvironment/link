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
  species_resident = c("bt", "wct"),
  species_anadromous = c("ch", "cm", "co", "pk", "sk", "st"),
  species_spawn_only = c("cm", "pk"),
  segment_id_col = "id_segment",
  intermittent_feature_code = "GA24850150",
  resident_species,
  anadromous_species,
  spawn_only_species
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
  `streams_habitat_linear` shape.

- feature_code:

  Named character or data.frame. Either a named character vector mapping
  `segment_id` -\> `feature_code`, or a data.frame with `segment_id_col`
  and `"feature_code"` columns. Used for the `INTERMITTENT` flag.

- to:

  Character or `NULL`. Optional schema-qualified destination table. When
  supplied, the result tibble is written via
  `dbWriteTable(overwrite = TRUE)` and the tibble is also returned (so
  callers can chain into `lnk_pipeline_persist` /
  `build_species_views.R`). Default `NULL` returns-only.

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html).
  Required only when `to` is supplied; ignored otherwise.

- species_resident:

  Character. Species using the resident flavor of
  `mapping_code_barrier`. Default `c("bt", "wct")`. (Renamed from
  `resident_species` in v0.40.0; old name accepted with deprecation
  warning until v0.41.0.)

- species_anadromous:

  Character. Species using the anadromous flavor. Default
  `c("ch", "cm", "co", "pk", "sk", "st")`. (Renamed from
  `anadromous_species` in v0.40.0.)

- species_spawn_only:

  Character. Species without rearing semantics (token 1 only emits
  SPAWN, never REAR). Default `c("cm", "pk")`. Mirrors bcfp. (Renamed
  from `spawn_only_species` in v0.40.0.)

- segment_id_col:

  Character. Default `"id_segment"`.

- intermittent_feature_code:

  Character. The `feature_code` value that flags an intermittent stream.
  Default `"GA24850150"` (bcfp).

- resident_species:

  **Deprecated** alias for `species_resident`. Kept for one release
  (v0.40.0); removal in v0.41.0.

- anadromous_species:

  **Deprecated** alias for `species_anadromous`. Kept for one release
  (v0.40.0); removal in v0.41.0.

- spawn_only_species:

  **Deprecated** alias for `species_spawn_only`. Kept for one release
  (v0.40.0); removal in v0.41.0.

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
downstream is empty (i.e. accessible). Resident-flavor (BT, WCT) and
anadromous-flavor (CH/CM/CO/PK/SK/ST) differ in their CASE order:

- Resident: REMEDIATED \> DAM \> ASSESSED (anthropogenic + pscis + no
  dam) \> MODELLED (anthropogenic + no pscis + no dam) \> NONE (no
  anthropogenic).

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
