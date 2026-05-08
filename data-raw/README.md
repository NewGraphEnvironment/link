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
- Python `bcdata` CLI: `pip install bcdata`.
- GDAL `ogr2ogr` with GeoJSON + parquet drivers (Homebrew GDAL has both).
- `curl`, `unzip`.
- `aws` CLI (only for `--with-bcfp-views`; anonymous read works).
- R with link package installed (for the baseline-stamp step).

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

The dispatch hierarchy: trifecta → run_provincial → compare_wsg.

| Script | Calls | Purpose |
|--------|-------|---------|
| `trifecta_provincial.sh` | `run_provincial_parity.R` (×3 hosts) | 3-host orchestrator. Splits WSGs across M4 + M1 + cypher, dispatches in parallel, consolidates RDS files back to M4. Accepts `--config=`, `--schema=`, optional `--m4-bucket=`/`--m1-bucket=`/`--cy-bucket=` LPT overrides. |
| `trifecta_15wsg.sh` | same | 15-WSG smoke variant of the above. |
| `trifecta_smoke.sh` | same | Single-WSG smoke variant. |
| `run_provincial_parity.R` | `compare_bcfishpass_wsg.R` per WSG | Single-host provincial dispatcher. Loops every WSG in `wsg_species_presence`, saves per-WSG RDS, emits per-WSG times CSV. Accepts `--wsgs=`, `--config=`, `--schema=`, `--rds-dir=`. |
| `compare_bcfishpass_wsg.R` | `lnk_pipeline_*` family | Single-WSG end-to-end runner. Sources both connections (local fwapg + bcfp tunnel), runs the 6-phase pipeline, persists, emits comparison rollup tibble (link vs bcfp). The atomic unit of work in every multi-WSG run above. |

## Pipeline support

Run-adjacent helpers (planning, consolidation across hosts).

| Script | Purpose |
|--------|---------|
| `balance_provincial_buckets.R` | Reads per-host wall times from prior provincial runs (CSV preferred, text-log fallback) and emits LPT-balanced 3-host buckets. ~27 min savings vs sequential thirds. Output ready to paste into `trifecta_provincial.sh --m4-bucket=…`. |
| `consolidate_schema.R` | pg_dump from M1 + cypher → scp to M4 → pg_restore --data-only. Used after a multi-host trifecta run to merge per-host schema writes onto the M4 reference DB. |

## Analysis (post-run)

Read persistent state, emit comparisons / methodology evidence.

| Script | Purpose |
|--------|---------|
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
| `_targets.R` | The (legacy) targets pipeline that pre-dated `trifecta_provincial.sh`. Kept for the multi-WSG comparison harness. |
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

- `provincial_parity/`, `provincial_default/`, `provincial_default_extrabreaks/` — per-WSG RDS + per-WSG times CSV from `run_provincial_parity.R`.
- `methodology_delta/` — schema-vs-schema delta RDS from `methodology_delta_query.R`.
- `dumps_<schema>/` — pg_dump custom-format files from `consolidate_schema.R`.
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
working schemas on completion; `consolidate_schema(keep_source = FALSE)`
drops source persistent schema after successful pg_restore), a
single-bundle-in-flight worker holds ~60 GB total — comfortable on the
existing 96 GB cypher tier.

Per-run footprint is recorded in `data-raw/logs/bcfp_baselines.csv`
(bcfp build + run label) — cross-reference with `du -sh` on
`/var/lib/docker/volumes/<vol>/_data` to track actual disk over time.
