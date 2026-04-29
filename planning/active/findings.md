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

## Proposed config.yaml schema

```yaml
name: bcfishpass
description: |
  ...

# Non-tabular pipeline inputs (kept top-level)
rules_yaml: rules.yaml
dimensions_csv: dimensions.csv

# Tabular data files. All accessed via lnk_load_overrides(cfg)$<key>.
# Entries with `source` + `canonical_schema` dispatch through crate::crt_ingest();
# others fall through to read.csv() until crate registers their schemas.
files:
  parameters_fresh:
    path: parameters_fresh.csv
  habitat_classification:                           # was cfg$habitat_classification
    source: bcfp
    path: overrides/user_habitat_classification.csv
    canonical_schema: bcfp/user_habitat_classification
  observation_exclusions:                           # was cfg$observation_exclusions
    path: overrides/observation_exclusions.csv
  wsg_species:                                      # was cfg$wsg_species
    path: overrides/wsg_species_presence.csv
  modelled_fixes:                                   # was cfg$overrides$modelled_fixes
    source: bcfp
    path: overrides/user_modelled_crossing_fixes.csv
  pscis_barrier_status:
    source: bcfp
    path: overrides/user_pscis_barrier_status.csv
  pscis_xref:
    source: bcfp
    path: overrides/pscis_modelledcrossings_streams_xref.csv
  barriers_definite:
    source: bcfp
    path: overrides/user_barriers_definite.csv
  barriers_definite_control:
    source: bcfp
    path: overrides/user_barriers_definite_control.csv
  crossings_misc:
    source: bcfp
    path: overrides/user_crossings_misc.csv

extends: null   # optional — project configs use this; bundled don't

pipeline:
  ...   # unchanged

provenance:
  ...   # unchanged — already byte/shape checksums per file
```

### Design choices

1. **Flatten `files:` and `overrides:` into one `files:` map.** Today's split (`files:` for "internal" CSVs, `overrides:` for bcfp CSVs) was a historical accident — semantically they're all tabular data the pipeline reads. After the split, `loaded$habitat_classification` and `loaded$barriers_definite` both come out of the same call: `lnk_load_overrides(cfg)`. No more `cfg$overrides$X` vs `cfg$X` distinction.
2. **Keep `rules_yaml` + `dimensions_csv` top-level.** They're not tabular data — `rules.yaml` is read by fresh as YAML; `dimensions.csv` is the input to `lnk_rules_build()`, not pipeline data. They don't belong in `lnk_load_overrides()`'s output.
3. **`source` and `canonical_schema` are optional per entry.** Files registered in crate get both. Files not yet registered (8 of the 10 bcfp CSVs today) get `source: bcfp` only — falls through to plain `read.csv()` until crate adds their schemas (one issue per file as a follow-up). Internal hand-authored files (`parameters_fresh`, `observation_exclusions`, `wsg_species`) get neither — pure local reads.
4. **`extends:` is opt-in.** Bundled configs (`bcfishpass`, `default`) don't use it. Project configs (e.g., Wedzin Kwa) declare `extends: default` and override specific entries.
5. **Friendly names, not upstream filenames.** Entry keys are `barriers_definite` (downstream-friendly), not `user_barriers_definite.csv` (upstream filename). The upstream filename lives in `path:`. crate's `file_name` arg uses upstream-style (`user_habitat_classification`) — that's a crate-registry concern, not a link-config concern.

### Migration mapping

| Today | Tomorrow |
|-------|---------|
| `cfg$rules_yaml` | `cfg$rules_yaml` (unchanged) |
| `cfg$dimensions_csv` | `cfg$dimensions_csv` (unchanged) |
| `cfg$parameters_fresh` (data frame) | `loaded$parameters_fresh` |
| `cfg$habitat_classification` | `loaded$habitat_classification` |
| `cfg$observation_exclusions` | `loaded$observation_exclusions` |
| `cfg$wsg_species` | `loaded$wsg_species` |
| `cfg$overrides$X` | `loaded$X` |
| `cfg$pipeline$*` | `cfg$pipeline$*` (unchanged) |
| `cfg$provenance` | `cfg$provenance` (unchanged) |
| `cfg$species` | `cfg$species` (parsed from rules.yaml at manifest load — unchanged) |
| `cfg$name`, `cfg$dir` | `cfg$name`, `cfg$dir` (unchanged) |
