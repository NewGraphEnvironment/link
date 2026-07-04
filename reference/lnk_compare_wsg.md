# Compare one watershed group against a reference dataset

Per-WSG convenience wrapper around the existing `lnk_pipeline_*` helpers
that produces a long-format rollup tibble suitable for provincial parity
comparisons. Optionally adds a per-segment `mapping_code` lens when
`mapping_code = TRUE`.

## Usage

``` r
lnk_compare_wsg(
  conn,
  aoi,
  cfg,
  loaded,
  reference = "bcfishpass",
  mapping_code = FALSE,
  conn_ref = NULL,
  species = NULL,
  schema = paste0("working_", tolower(aoi)),
  dams = TRUE,
  cleanup_working = TRUE,
  with_mapping_code
)
```

## Arguments

- conn:

  DBI connection to the local pipeline database (typically localhost
  fwapg).

- aoi:

  Watershed group code (e.g. `"ADMS"`).

- cfg:

  An `lnk_config` object (from
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md)).

- loaded:

  Named list from
  [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md).

- reference:

  Character scalar identifying the reference dataset. Currently only
  `"bcfishpass"` is supported.

- mapping_code:

  Logical. When `TRUE`, run the additional `barriers_unify` →
  `barriers_views` → `access` → `mapping_code` phases and emit
  per-species segment-match stats. Default `FALSE`. (Renamed from
  `with_mapping_code` in v0.40.0; old name still accepted with
  deprecation warning until v0.41.0.)

- conn_ref:

  DBI connection to the reference database. Required when
  `reference = "bcfishpass"` (the bcfp tunnel at `localhost:63333`).
  Caller manages this connection.

- species:

  Character vector of species codes to restrict the rollup to (e.g.
  `c("BT","CH","CM","CO","PK","SK","ST","WCT")` for the 8 bcfp-bundle
  species). Default `NULL` uses
  [`lnk_pipeline_species()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_species.md)
  intersected with WSG presence.

- schema:

  Working schema name. Default `paste0("working_", tolower(aoi))`.

- dams:

  Logical. When `TRUE` (default), pass `conn` as `conn_tunnel` to
  [`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md)
  so the CABD dams step runs from local `cabd.dams`. Pass `FALSE` to
  skip dams entirely.

- cleanup_working:

  Logical. When `TRUE` (default), drop the `<schema>` working schema at
  the end. Pass `FALSE` for interactive debug / manual inspection.

- with_mapping_code:

  **Deprecated** alias for `mapping_code`. Kept for one release
  (v0.40.0); removal in v0.41.0. Emits a deprecation warning when
  supplied.

## Value

A list with two elements:

- `rollup`: tibble with one row per (species, habitat_type) — 8 habitat
  types: `spawning`, `rearing`, `lake_rearing`, `wetland_rearing`,
  `rearing_stream`, `rearing_lake_centerline`,
  `rearing_wetland_centerline`, `accessible` (km, link#221). Columns:
  `wsg`, `species`, `habitat_type`, `unit` (`km` \| `ha`), `link_value`,
  `ref_value`, `diff_pct`. `accessible`'s `ref_value` is `NA` until the
  tunnel-free reference path lands.

- `mapping_code`: tibble with one row per species — segment-level match
  stats vs `bcfishpass.streams_mapping_code`. Columns: `wsg`, `species`,
  `total_segs`, `match_pct`, `n_diffs`, `top_pattern`,
  `top_pattern_count`. `NULL` when `mapping_code = FALSE`.

## Details

`reference` is a string identifying the comparison source. Today only
`"bcfishpass"` is supported (queries `bcfishpass.habitat_linear_<sp>` on
`conn_ref`). The arg is future-proofed for default-bundle parity,
regression detection across link runs, or non-bcfp external data.

### Additive, not duplicative

Both `mapping_code = FALSE` and `mapping_code = TRUE` run the per-WSG
pipeline **once**. The `TRUE` path is purely additive — it adds
`lnk_barriers_unify`, `lnk_barriers_views`, `lnk_pipeline_access`, and
`lnk_pipeline_mapping_code` phases on top of the same network state,
then queries `bcfishpass.streams_mapping_code` for the segment- level
diff. The rollup tibble is unchanged between the two modes.

Side effects: writes per-WSG segment-level data to the persistent
`<persist_schema>.streams` + `streams_habitat_<sp>` tables via
[`lnk_pipeline_persist()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_persist.md).
Drops the `<schema>` working schema at end unless
`cleanup_working = FALSE`.

Rollup methodology mirrors what bcfp's `habitat_linear_<sp>` measures:
linear km from `length_metre` summed over rearing/spawning-flagged
segments, with edge-type decomposition into stream / lake-centerline /
wetland-centerline slices. Lake / wetland area in hectares uses
`DISTINCT waterbody_key` joins to `whse_basemapping.fwa_lakes_poly` /
`fwa_wetlands_poly` to avoid double-counting multi-segment lakes. See
`research/default_vs_bcfishpass.md` for the measurement-asymmetry
decision (link reports both centerline km and polygon ha; bcfp credits
only one depending on species rule).

## See also

[`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md),
[`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md),
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md),
[`lnk_pipeline_persist()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_persist.md),
[`lnk_parity_annotate()`](https://newgraphenvironment.github.io/link/reference/lnk_parity_annotate.md)

Other compare:
[`lnk_access()`](https://newgraphenvironment.github.io/link/reference/lnk_access.md),
[`lnk_compare_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_mapping_code.md),
[`lnk_compare_rollup()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_rollup.md),
[`lnk_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_mapping_code.md),
[`lnk_parity_annotate()`](https://newgraphenvironment.github.io/link/reference/lnk_parity_annotate.md),
[`lnk_rollup_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_rollup_wsg.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
conn_ref <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 63333, dbname = "bcfishpass",
  user = "newgraph", password = Sys.getenv("PG_PASS_SHARE"))
cfg <- lnk_config("bcfishpass")
loaded <- lnk_load_overrides(cfg)

# Rollup-only (~70s per WSG)
result <- lnk_compare_wsg(
  conn = conn, aoi = "ADMS",
  cfg = cfg, loaded = loaded,
  reference = "bcfishpass", conn_ref = conn_ref
)
print(result$rollup)

# Add mapping_code lens (~100s per WSG)
result_mc <- lnk_compare_wsg(
  conn = conn, aoi = "ADMS",
  cfg = cfg, loaded = loaded,
  reference = "bcfishpass", conn_ref = conn_ref,
  mapping_code = TRUE
)
print(result_mc$mapping_code)
} # }
```
