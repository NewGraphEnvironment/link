# Compare one watershed group's persisted mapping_code tokens against a reference

Segment-level QA counterpart to
[`lnk_compare_rollup()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_rollup.md).
Reads the per-segment `mapping_code_<sp>` tokens that
[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md)
(with `mapping_code = TRUE`) persisted to
`<persist_schema>.streams_mapping_code`, diffs them against a
reference's tokens for the same segments, and returns a per-species
match tibble.

## Usage

``` r
lnk_compare_mapping_code(
  conn,
  aoi,
  cfg,
  reference = "bcfishpass",
  conn_ref = NULL,
  species = NULL,
  ref_table = "fresh.streams_vw_bcfp"
)
```

## Arguments

- conn:

  DBI connection to the local pipeline database (where
  `<persist_schema>` and `fresh.streams_vw_bcfp` live).

- aoi:

  Watershed group code (e.g. `"PARS"`).

- cfg:

  An `lnk_config` object (resolves `cfg$pipeline$schema`).

- reference:

  Character scalar identifying the reference. Only `"bcfishpass"` is
  supported.

- conn_ref:

  Optional DBI connection to the bcfp tunnel (`localhost:63333`).
  Default `NULL` → tunnel-free local-snapshot compare.

- species:

  Optional character vector of species codes to restrict to. Default
  `NULL` discovers the set from the mapping_code columns.

- ref_table:

  Reference table name for the tunnel-free path. Default
  `"fresh.streams_vw_bcfp"` (where `snapshot_bcfp.sh` loads bcfp's
  output).

## Value

A tibble, one row per species: `wsg`, `species`, `total_segs`,
`match_pct`, `n_diffs`, `top_pattern` (most common `link | bcfp` token
mismatch), `top_pattern_count`.

## Details

Reads only — no writes, no working schema.

### Tunnel-free by default

The reference is the **local** snapshot `fresh.streams_vw_bcfp` (loaded
by `data-raw/snapshot_bcfp.sh --with-bcfp-views` from bcfp's published
S3 output — no SSH, no `:63333`). With `conn_ref = NULL` (default) the
compare is a single local join on `conn`: no second connection, no
`PG_PASS_SHARE`, no tunnel. Pass `conn_ref` (a DBI connection to the
live bcfp tunnel) to diff against `bcfishpass.streams_mapping_code`
instead — the legacy path, kept for back-compat.

### Join

link's `streams_mapping_code.id_segment` is a local surrogate, distinct
from bcfp's `segmented_stream_id`, so the join is on FWA segment-start
position: `blue_line_key` + `downstream_route_measure` (rounded to 3
decimals — robust to ULP drift on the PostGIS-computed doubles,
deterministic across runs that share the same fwapg segmentation).
link's position columns come from `<persist_schema>.streams`, joined on
the full PK `(id_segment, watershed_group_code)` — `id_segment` alone is
not unique across WSGs. The snapshot view carries the position columns
inline.

### Species resolution

`species = NULL` (default) compares every species present as a
`mapping_code_<sp>` column on BOTH sides (link's persisted table and the
reference), with rows for the WSG. Pass `species` to restrict;
caller-passed species absent on either side drop out (no error).

## See also

[`lnk_compare_rollup()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_rollup.md),
[`lnk_compare_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_wsg.md),
[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md)

Other compare:
[`lnk_access()`](https://newgraphenvironment.github.io/link/reference/lnk_access.md),
[`lnk_compare_rollup()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_rollup.md),
[`lnk_compare_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_wsg.md),
[`lnk_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_mapping_code.md),
[`lnk_parity_annotate()`](https://newgraphenvironment.github.io/link/reference/lnk_parity_annotate.md),
[`lnk_rollup_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_rollup_wsg.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
cfg <- lnk_config("bcfishpass")

# Tunnel-free: diff persisted tokens vs the local fresh.streams_vw_bcfp snapshot.
lnk_compare_mapping_code(conn, aoi = "PARS", cfg = cfg)

# Legacy tunnel path (requires the bcfp tunnel up):
conn_ref <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 63333, dbname = "bcfishpass",
  user = "newgraph", password = Sys.getenv("PG_PASS_SHARE"))
lnk_compare_mapping_code(conn, "PARS", cfg, conn_ref = conn_ref)
} # }
```
