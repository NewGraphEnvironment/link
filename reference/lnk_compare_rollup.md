# Compare one watershed group's persisted state against a reference

Comparison-only counterpart to
[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md).
Reads the persisted `<persist_schema>.streams` + `streams_habitat_<sp>`
tables that
[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md)
wrote, queries the reference dataset, and returns a long-format diff
tibble.

## Usage

``` r
lnk_compare_rollup(
  conn,
  aoi,
  cfg,
  reference = "bcfishpass",
  conn_ref = NULL,
  species = NULL
)
```

## Arguments

- conn:

  DBI connection to the local pipeline database (where
  `<persist_schema>` lives).

- aoi:

  Watershed group code (e.g. `"ADMS"`).

- cfg:

  An `lnk_config` object (used only to resolve `cfg$pipeline$schema` for
  the persisted table names).

- reference:

  Character scalar identifying the reference dataset. Currently only
  `"bcfishpass"` is supported.

- conn_ref:

  DBI connection to the reference database. Required when
  `reference = "bcfishpass"` (bcfp tunnel at `localhost:63333`).

- species:

  Optional character vector of species codes (e.g. `c("BT","CO")`) to
  restrict the rollup to. Default `NULL` discovers the set from PG.

## Value

A tibble with one row per (species, habitat_type) — 8 habitat types per
species (the 7 habitat km/ha types plus `accessible` km, link#221).
Columns: `wsg`, `species`, `habitat_type`, `unit` (`km` \| `ha`),
`link_value`, `ref_value`, `diff_pct`. `accessible`'s `ref_value` is
sourced tunnel-free from `fresh.streams_vw_bcfp` for the salmon group
(CH/CM/CO/PK/SK); other species carry `NA` until their reference path
lands (link#221 Phase 3).

## Details

Reads only — no writes to PG, no working schema. Caller persists the
return value (e.g. `saveRDS`) if a side-artifact is wanted; that's a
separate decision from whether the model itself ran.

`reference` is a string identifying the comparison source. Today only
`"bcfishpass"` is supported (queries `bcfishpass.habitat_linear_<sp>` on
`conn_ref`). The arg is future-proofed for default-bundle parity,
regression detection across link runs, or non-bcfp external data — new
references plug in without renaming the public arg.

### Species resolution

If `species = NULL` (default), the active species set is discovered from
PG: any `<persist_schema>.streams_habitat_<sp>` table with rows for the
requested WSG. This means the rollup is grounded in actual persisted
state — no need for `cfg$species` or `wsg_species_presence` lookups
here.

If `species` is passed explicitly, it's intersected with the
PG-discovered set (caller-passed species absent from PG simply drop out
— no error).

## See also

[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md),
[`lnk_compare_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_wsg.md),
[`lnk_parity_annotate()`](https://newgraphenvironment.github.io/link/reference/lnk_parity_annotate.md)

Other compare:
[`lnk_access()`](https://newgraphenvironment.github.io/link/reference/lnk_access.md),
[`lnk_compare_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_mapping_code.md),
[`lnk_compare_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_wsg.md),
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

# Compare-only against existing PG state (~2s).
rollup <- lnk_compare_rollup(
  conn = conn, aoi = "ADMS", cfg = cfg,
  reference = "bcfishpass", conn_ref = conn_ref
)
print(rollup)
} # }
```
