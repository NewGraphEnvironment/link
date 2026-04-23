# Findings — #46 (manifest-driven probes refactor)

## Probe locations

**`.lnk_pipeline_prep_gradient()`** (R/lnk_pipeline_prepare.R, around line 180):

```r
ctrl_exists <- DBI::dbGetQuery(conn, sprintf(
  "SELECT 1 FROM information_schema.tables
   WHERE table_schema = %s AND table_name = 'barriers_definite_control'",
  .lnk_quote_literal(schema)))
if (nrow(ctrl_exists) > 0) {
  .lnk_db_execute(conn, sprintf(
    "DELETE FROM %s.gradient_barriers_raw g
     USING %s.barriers_definite_control c ...", schema, schema))
}
```

Target:

```r
if (!is.null(cfg$overrides$barriers_definite_control)) {
  .lnk_db_execute(conn, sprintf(
    "DELETE FROM %s.gradient_barriers_raw g
     USING %s.barriers_definite_control c ...", schema, schema))
}
```

Signature change: `.lnk_pipeline_prep_gradient(conn, aoi, schema)` → `(conn, aoi, cfg, schema)`.

**`.lnk_pipeline_prep_overrides()`** (R/lnk_pipeline_prepare.R, around line 260):

```r
habitat_tbl <- paste0(schema, ".user_habitat_classification")
habitat_exists <- DBI::dbGetQuery(conn, sprintf(
  "SELECT 1 FROM information_schema.tables
   WHERE table_schema = %s AND table_name = 'user_habitat_classification'",
  .lnk_quote_literal(schema)))
habitat_arg <- if (nrow(habitat_exists) > 0) habitat_tbl else NULL
```

Target:

```r
habitat_arg <- if (!is.null(cfg$habitat_classification)) {
  paste0(schema, ".user_habitat_classification")
} else {
  NULL
}
```

No signature change — `cfg` is already passed in.

## Why manifest-driven is better

The probes work because `.lnk_pipeline_prep_load_aux()` writes the table exactly when the manifest declares it. But that chain is indirect — it relies on the load step's empty-table policy being correct. The asymmetric-gating bug fixed in #44 was rooted in this exact seam (manifest declared the key but load wrote nothing when the AOI had zero rows, causing a downstream probe to skip what the manifest intended).

Reading `cfg$overrides$barriers_definite_control` directly makes the capability activation locally readable — no DB state dependency, no empty-table edge cases.

## Expected rollup behavior

Both probes currently return the same answer the manifest would give on the `bcfishpass` config bundle:

- `working_<wsg>.barriers_definite_control` exists iff manifest has `overrides.barriers_definite_control`
- `working_<wsg>.user_habitat_classification` exists iff manifest has `habitat_classification`

So the refactor MUST produce a bit-identical rollup. Post-#48 baseline digest: `50908d234e2131fc0842dc3ab653ae78` (46 rows).

If the digest diverges, likely candidates:
- Some AOI in the manifest has the key but the load step writes an empty table (Phase 2 of #44 established this for `barriers_definite_control`; same pattern may or may not apply to `user_habitat_classification`). In that case pre-refactor the probe would see the empty table and pass; post-refactor the manifest check would pass too, and the downstream join would hit the empty table — same result.
- An unrelated WSG with the manifest-key absent but a stale table left over from a prior run. Unlikely given tar_destroy before each tar_make.
