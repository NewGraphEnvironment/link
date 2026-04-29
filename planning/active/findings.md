# Findings — link#65

## Architectural decision: Path C, single PR

The original issue body proposed a parallel `lnk_load_overrides()` alongside the existing `lnk_config()`. Inventory of the current code (2026-04-29) showed `lnk_config()` already reads every override CSV via `read.csv()` and exposes them as data frames in the returned object. Two functions reading the same files would be parallel APIs with the same job.

**Resolution:** decompose `lnk_config()` into manifest (paths, provenance, file declarations) + `lnk_load_overrides()` (data ingestion via crate dispatch). Single PR, single v0.18.0 bump, no backwards-compat shim.

**Why no shim:** link has zero external code consumers (verified via grep across local repos — fresh has one `@seealso` doc reference, rtj refs are archived planning). CLAUDE.md guidance: don't write shims when you can just change the code.

## Current consumer surface

`cfg$*` slot accesses live in 8 R files + tests:
- `lnk_pipeline_load.R` — `cfg$overrides$crossings_misc`, `modelled_fixes`, `pscis_barrier_status`
- `lnk_pipeline_prepare.R` — `cfg$overrides$barriers_definite`, `barriers_definite_control` (4 spots), `cfg$habitat_classification`
- `lnk_pipeline_break.R` — `cfg$observation_exclusions`, `cfg$wsg_species`, `cfg$pipeline$break_order`
- `lnk_pipeline_classify.R` — `cfg$habitat_classification`, `cfg$pipeline$apply_habitat_overlay`, `cfg$rules_yaml`, `cfg$parameters_fresh`
- `lnk_pipeline_connect.R` — `cfg$rules_yaml`, `cfg$parameters_fresh`, `cfg$wsg_species`
- `lnk_pipeline_species.R` — `cfg$species`, `cfg$wsg_species`, `cfg$parameters_fresh`
- `lnk_stamp.R` — `cfg$name`, `cfg$dir`, `cfg$provenance` (manifest-only — no migration needed)
- `lnk_config_verify.R` — `cfg$provenance`, `cfg$dir`, `cfg$name` (manifest-only — no migration needed)

~25 reference points to migrate to `loaded$*` for data slots; manifest accesses unchanged.

## crate API contract (v0.0.1)

```r
crt_ingest(source, file_name, path)   # returns canonical tibble
crt_files(source = NULL)              # returns registry tibble
```

Today registered: `bcfp/user_habitat_classification` only. Schema YAML at `crate/inst/extdata/schemas/bcfp/user_habitat_classification.yaml`. Variant matching is column-NAMES only (type-aware ingest is v0.1.x roadmap, separate concern).

## Why we missed the overlap

`lnk_config()` was added incrementally — first as a thin "load rules YAML + paths" helper, then grew to absorb override CSVs as pipeline phases needed them, then provenance, then dimensions, then species. By v0.16-0.17 it had become the everything-bundle. Issue #65 was scoped from a clean-slate "what should source-agnostic ingestion look like" framing without inventorying what `lnk_config()` had accumulated. Classic accumulation-of-responsibility — common when domain understanding moves faster than architectural review.

## Long-term flexibility enabled by the split

1. Lazy / per-WSG loading possible (`crossings.csv` is 533k rows; today read 2× per tar_make for 2 configs).
2. `lnk_config_verify()` + `lnk_stamp()` run without parsing data — useful for CI checks.
3. Adding a new source family (NGE, lab, local) is a crate registration + config edit, no link R code change.
4. Schema-only consumers (UIs that show "what's in this config") don't pay for CSV parses.
5. `lnk_config_diff(cfg_a, cfg_b)` becomes meaningful at the manifest level.
6. Crate's planned v0.1.x type-aware ingest naturally lives in `lnk_load_overrides()`.
