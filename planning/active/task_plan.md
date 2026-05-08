# Task: data-raw snapshot_bcfp.sh — manual snapshot of bcfp dependencies (#137)

Shell script that loads the primitives `lnk_pipeline_crossings()` (#138) needs, plus optional bcfp output views for parity verification, into the local fwapg from public sources only (no SSH tunnel).

## Phase 1: `data-raw/snapshot_bcfp.sh` shell script

- [ ] Header with prereqs (`PG*` / `~/.pgpass`, `bcdata` Python CLI, `ogr2ogr`, `curl`, `aws` CLI). `set -euxo pipefail`.
- [ ] Section 1: BCDC PSCIS via `bcdata bc2pg --refresh whse_fish.pscis_*` (4 tables).
- [ ] Section 2: CABD dams via `ogr2ogr` from CABD GeoJSON API → `cabd.dams`.
- [ ] Section 3: bchamp `modelled_stream_crossings.gpkg.zip` via `curl` + `ogr2ogr` → `fresh.modelled_stream_crossings`.
- [ ] Section 4: bchamp `observations.parquet` via `ogr2ogr ... /vsicurl/...` → `bcfishobs.observations`. Mirrors bcfp's `jobs/load_observations`.
- [ ] Section 5 (optional, gated by `--with-bcfp-views`): Simon's bcfp views from `s3://newgraph` → `fresh.crossings_bcfp` / `fresh.streams_bcfp`.
- [ ] Section 6: stamp `data-raw/logs/bcfp_baselines.csv` via `Rscript -e 'lnk_baseline_append(lnk_bucket_log(), run_label = "snapshot-<date>", notes = "...")'`.

## Phase 2: `data-raw/README.md` documentation

- [ ] Document `snapshot_bcfp.sh` purpose + when to run.
- [ ] Prereqs section (CLI tools + install hints).
- [ ] Quick-start invocation + expected runtime.
- [ ] Output schema list.
- [ ] Pointer to `lnk_pipeline_crossings()` (#138) as the consumer.

## Phase 3: NEWS + DESCRIPTION + open PR

- [ ] DESCRIPTION 0.31.0 → 0.31.1 (patch — data-raw + docs).
- [ ] NEWS.md 0.31.1 entry.
- [ ] `/code-check` clean on staged diff.
- [ ] `devtools::test()` + `lintr::lint_package()` clean.
- [ ] Commit, push, open PR closing #137 with SRED tag.
- [ ] `/gh-pr-merge` → tag v0.31.1.
- [ ] `/planning-archive`.

## Validation

- [ ] Tests pass (no R changes — should be no-op)
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
