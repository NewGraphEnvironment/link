# `data-raw/` — pipeline drivers, analysis scripts, generated artifacts

Scripts that drive the link pipeline, generate package data, and produce
research artifacts. Anything that's NOT exported R code from `R/`.

Naming convention for new files: **verb-prefix the action, suffix the
target.** Pick the verb prefix from the categories below; suffix the
target (e.g. `_provincial`, `_wsg`, `_schema`, `_breaks`) so the purpose
reads left-to-right.

## Bootstrap

One-time setup so `lnk_pipeline_crossings()` (link#138) and parity comparisons can run against a local fwapg without a tunnel.

| Script | Purpose |
|--------|---------|
| `snapshot_bcfp.sh` | Loads bcfp dependencies into the local Postgres from public sources only. PSCIS via Python `bcdata bc2pg`, CABD dams via CABD GeoJSON API, modelled crossings + observations from bchamp objectstore. Optional `--with-bcfp-views` also pulls Simon's bcfp output views from `s3://newgraph` for parity comparison. Stamps `data-raw/logs/bcfp_baselines.csv` with the upstream build identifier (link#117 ledger). |

### Prereqs

- Local Postgres with PostGIS. `PGUSER`/`PGPASSWORD`/`PGHOST`/`PGPORT`/`PGDATABASE` env vars or `~/.pgpass` (or a single `DATABASE_URL`).
- Python `bcdata` CLI: `uv tool install bcdata==0.16.0.post1`.
- GDAL `ogr2ogr` with GeoJSON + Parquet drivers.
- `curl`, `unzip`.
- `aws` CLI (only for `--with-bcfp-views`; anonymous read works).
- R with link package installed (for the baseline-stamp step).

#### Install paths by host

| Host | GDAL | bcdata | Canonical installer |
|------|------|--------|---------------------|
| M4 / m1 (macOS) | Homebrew (`brew install gdal`) | `uv tool install bcdata==0.16.0.post1` | `kdot install_geo.sh` |
| cypher (Ubuntu) | conda-forge via micromamba | `uv tool install bcdata==0.16.0.post1` | rtj cloud-init |

#### Verify your setup

```bash
bcdata --version
ogr2ogr --formats | grep -i parquet
psql --version
curl --version
aws --version          # only needed for --with-bcfp-views
```

The script checks these at startup and exits with a clear error if anything is missing.

### Quick start

```bash
cd ~/Projects/repo/link

# Primitives only (~5 min):
bash data-raw/snapshot_bcfp.sh

# Plus parity-comparison views (~7 min):
bash data-raw/snapshot_bcfp.sh --with-bcfp-views
```

### What lands in your local DB

- `whse_fish.pscis_assessment_svw`, `pscis_design_proposal_svw`, `pscis_habitat_confirmation_svw`, `pscis_remediation_svw` (BCDC PSCIS)
- `cabd.dams` (CABD public API)
- `fresh.modelled_stream_crossings` (bchamp gpkg)
- `bcfishobs.observations` (bchamp parquet — same artifact bcfp's `jobs/load_observations` consumes)
- `data-raw/logs/bcfp_baselines.csv` — appended row stamping which upstream build the snapshot reflects.

With `--with-bcfp-views`:

- `fresh.crossings_bcfp`, `fresh.streams_bcfp` (bcfp output, dumped weekly Sun by Simon's `dump_weekly`; aligned with the most recent Tue rebuild SHA between Wed and the next Tue).

After running this script, `lnk_pipeline_crossings()` (link#138) and `lnk_pipeline_access(barrier_sources = list(...))` work end-to-end against locally-loaded primitives.

## Pipeline drivers (top-down)

`study_area_run.sh` is the one runner. The older `wsgs_*` / `trifecta_*` dispatch path was retired in 0.89.0 (it kept per-WSG RDS caches and a fallback split that no longer applied).

| Script | Calls | Purpose |
|--------|-------|---------|
| `study_area_run.sh` | `study_area_wsgs.R`, `wsg_run_one.R`, `schema_consolidate.R`, `study_area_compare.R` | **Lean tunnel-free, M1-as-dispatcher** study-area parity runner (link#175). No M4, no `:63333`. Drainage-closed DS-first buckets (one study area per host), per-WSG soft-fail, consolidate cyphers→M1, burn, tunnel-free `lnk_compare_mapping_code` → CSV. Full procedure + gotchas: `research/study_area_run.md`. |
| `compare_bcfishpass_wsg.R` | `lnk_pipeline_*` family | Single-WSG end-to-end runner. Sources both connections (local fwapg + bcfp tunnel), runs the 6-phase pipeline, persists, emits comparison rollup tibble (link vs bcfp). The atomic unit of work in every multi-WSG run above. |

## Pipeline support

Run-adjacent helpers (planning, consolidation across hosts).

| Script | Purpose |
|--------|---------|
| `schema_consolidate.R` | Per-table, bucket-filtered `COPY` from each source host over ssh into the dispatcher. Deletes each source's bucket from the destination's persist tables before copying; the three log tables it copies (`log`, `log_input`, `log_recompute`) are history, so on the destination their rows are replaced by primary key and never deleted by group, and a source is refused if a group that has a destination log row has an older or no log row on the source (#354). `ok = TRUE` requires every table's COPY to succeed and the row count to rise. |

## Analysis (post-run)

Read persistent state, emit comparisons / methodology evidence.

| Script | Purpose |
|--------|---------|
| `streams_parent_build.R` | Builds `<schema>.streams_parent` (each full segment's minimal parent, `lnk_streams_parent()`) for every group two persist schemas both hold, after judging the pair once (`streams_parent.R`, over `pretest.R`): closed clean builds, one code, config, fresh and token set per schema, `cut-min` against `cut-full-*`, the same species, and no modelling-path change between the two `link_sha`s (#444). `--verify` names groups a re-model has left stale. Args: `--schema=`, `--schema-minimal=`, `--out=` (no default), `[--wsgs=]`, `[--verify]`. |
| `query_mad_width_equivalent.R` | The modelled channel width at which streams in a persist schema reach a mean annual discharge: the reverse of `query_width_mad_equivalent.R` (#364; 3 m³/s → 15 m). Writes `mad_width_*` to `--out` (default `data-raw/logs/wetland_door_364/`). |
| `query_schema_delta.R` | Compares per-species spawn / rear km between two persistent fresh schemas. Province-wide totals + per-WSG breakdowns + shift breadth. Replaces inline `Rscript -e '…'` SQL — schema-vs-schema deltas are versioned now. Args: `<baseline_schema> <experiment_schema> [species_csv]`. |
| `compare_adms.R` | One-shot ADMS-only comparison (legacy single-WSG diagnostic). Superseded by `compare_bcfishpass_wsg.R` for parametric reuse. |

## Data preparation / artifacts

Generate package-shipped data, hex sticker, vignette inputs.

| Script | Purpose |
|--------|---------|
| `build_rules.R` | Regenerates `inst/extdata/configs/<bundle>/rules.yaml` from each bundle's `dimensions.csv` via `lnk_rules_build()`. Run after editing dimensions. |
| `sync_bcfishpass_csvs.R` | Pulls latest upstream `bcfishpass/data/` CSVs into `inst/extdata/configs/bcfishpass/overrides/`. Daily CI workflow runs this. |
| `regen_provenance.R` | Recomputes `provenance:` checksums in each bundle's `config.yaml` after data file edits. Audited by `audit_configs.R`. |
| `audit_configs.R` | Drift audit across rules / dimensions / parameters / overrides / provenance for every config bundle. Run before any provincial trifecta to catch staleness. |
| `testdata.R` | Generates test fixtures committed to `inst/testdata/`. |
| `make_hexsticker.R` | Renders the package hex sticker. One-shot. |

## Targets / experiments / regression tests

Research scratchpad and one-off verification scripts.

| Script | Purpose |
|--------|---------|
| `_targets.R` | The (legacy) targets pipeline that pre-dated the study-area runner. Kept for the multi-WSG comparison harness. |
| `exp_gradient_extra_breaks.R` | Experimental script that prototyped the orphan-class break source via in-line `frs_break_apply` before it was absorbed into `lnk_pipeline_prep_minimal()` (link v0.28.0). Kept as the smoke-test reference. |
| `rule_flexibility_demo.R` / `rule_flexibility_render.R` | Demonstration of rules.yaml format flexibility, rendered as RMarkdown. |
| `regress_dams_isolation.R` | One-off regression test for the dams-isolation work (link #109). |
| `test_sequential_breaking.R` | Break-order experiment script (research). |

## Naming conventions for new scripts

Each new script picks a verb prefix from this list — makes purpose
discoverable without opening the file:

| Prefix | When to use |
|--------|-------------|
| `run_` | Drives a multi-step pipeline run (replaces an inline R block in a runbook). |
| `compare_` | Compares two outputs / sources side-by-side. |
| `query_` | Issues SQL against persistent state, no pipeline mutation. |
| `balance_` / `consolidate_` | Operational helpers around runs (planning, multi-host merging). |
| `build_` / `make_` / `sync_` / `regen_` | Generates / refreshes a committed artifact (rules, hex, vignette data, provenance). |
| `audit_` | Recurring drift / consistency check. |
| `exp_` | Experimental research script. Often superseded by package code; keep as a reference. |
| `regress_` / `test_` | Regression-test driver for a specific issue or feature. |

## Output directories

Run artifacts land in subdirectories of `data-raw/logs/` keyed by topic:

- `provincial_parity/`, `provincial_default/`, `provincial_default_extrabreaks/` — per-WSG RDS + per-WSG times CSV from the retired `wsgs_run_host.R` (old runs only).
- `methodology_delta/` — schema-vs-schema delta RDS from `methodology_delta_query.R`.
- `dumps_<schema>/` — pg_dump custom-format files from `schema_consolidate.R`.
- `<TS>_*.txt` — orchestrator + per-host run logs.

Reusable helper scripts read from these directories without hardcoded
filenames where possible (newest-by-mtime wins).

## Disk capacity per worker host

Trifecta workers (M1, cypher) hold short-lived per-WSG scratch + a
single bundle's persistent schema. Rough footprints on a 232-WSG run:

| Working state | Disk on a worker |
|---------------|------------------|
| `working_<wsg>` × 60 (per-WSG scratch) | ~10–15 GB |
| Single bundle persistent schema (no extras) | ~25 GB |
| Single bundle persistent schema (extras — 2.8× row count) | ~30 GB |
| fwapg base data (whse_basemapping, bcfishobs, etc.) | ~30–40 GB |
| **Recommended free disk per worker (single bundle in flight)** | **60 GB minimum** |

The 2026-05-04 cypher disk-full incident filled a 96 GB droplet with
3 accumulated bundles + 60 working schemas at once. After the v0.29.0
hygiene fixes (`compare_bcfishpass_wsg(cleanup_working = TRUE)` drops
working schemas on completion; `schema_consolidate(keep_source = FALSE)`
drops source persistent schema after successful pg_restore), a
single-bundle-in-flight worker holds ~60 GB total — comfortable on the
existing 96 GB cypher tier.

Per-run footprint is recorded in `data-raw/logs/bcfp_baselines.csv`
(bcfp build + run label) — cross-reference with `du -sh` on
`/var/lib/docker/volumes/<vol>/_data` to track actual disk over time.
