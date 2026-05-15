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

The dispatch hierarchy: trifecta → run_provincial → compare_wsg.

| Script | Calls | Purpose |
|--------|-------|---------|
| `wsgs_dispatch.sh` | `wsgs_run_host.R` (×N hosts) | M4 + M1 + N-cypher orchestrator. Inline LPT bucket allocation (reads `_per_wsg_times.csv` from prior runs, computes balanced split using `--host-speeds=`), pre-flight version check across all hosts, parallel dispatch, RDS pull-back, post-pull `lnk_parity_annotate` against the divergence taxonomy. See "Provincial dispatch" section below for full flag reference + gotchas. |
| `trifecta_15wsg.sh` | same | 15-WSG smoke variant (legacy 3-host, hardcoded WSG list). |
| `trifecta_smoke.sh` | `wsgs_dispatch.sh` | N-host smoke shim: one small WSG per host, ~3 min wall. See `Provincial dispatch` section. |
| `wsgs_run_host.R` | `compare_bcfishpass_wsg.R` per WSG | Single-host provincial dispatcher. Loops every WSG in `wsg_species_presence`, saves per-WSG RDS, emits per-WSG times CSV. After the loop, optionally annotates the host's bucket against `research/bcfp_divergence_taxonomy.yml` (writes `<TS>_<host>_annotated.csv`). Accepts `--wsgs=`, `--config=`, `--schema=`, `--rds-dir=`, `--with-mapping-code`. |
| `compare_bcfishpass_wsg.R` | `lnk_pipeline_*` family | Single-WSG end-to-end runner. Sources both connections (local fwapg + bcfp tunnel), runs the 6-phase pipeline, persists, emits comparison rollup tibble (link vs bcfp). The atomic unit of work in every multi-WSG run above. |

## Pipeline support

Run-adjacent helpers (planning, consolidation across hosts).

| Script | Purpose |
|--------|---------|
| `buckets_balance.R` | Standalone LPT planner for the 3-host case. Reads per-host wall times from prior runs and prints buckets ready to paste into `wsgs_dispatch.sh --m4-bucket=…`. **Superseded for the N-host orchestrator** — `wsgs_dispatch.sh` now computes the LPT plan inline at dispatch time using the same algorithm. Kept here for one-off planning + cross-checks. Dedups `(wsg, host)` and across hosts before LPT so multi-run CSV accumulation doesn't double-assign WSGs. |
| `schema_consolidate.R` | pg_dump from M1 + cypher → scp to M4 → pg_restore --data-only. Bucket-aware destination cleanup (DELETEs each source host's WSG bucket from destination tables before restore — avoids duplicate-key violations on re-consolidation). `ok = TRUE` requires pg_restore rc=0 AND post-restore row count > 0; rc=0 with empty schema flags as failure. |
| `runs_archive.sh` | Moves the current top-level `_per_wsg_times.csv` + `*.rds` + `*_annotated.csv` artifacts in `provincial_<bundle>/` to `archive/<TS>/`. Operator cadence: run between provincial runs when you want the LPT planner to use the most recent run only. Skip to median-over multiple recent runs. |
| `trifecta_smoke.sh` | Thin shim over `wsgs_dispatch.sh` — one small WSG per host (m4→DEAD, m1→ELKR, cyN→ADMS/BABL/BULL). ~3 min wall. Exercises every orchestrator code path (preflight, dispatch, tunnel, RDS pull-back, annotation) before committing to a 200-WSG run. All flags pass through (e.g. `--cy-workspaces=`, `--with-mapping-code`). |

## Provincial dispatch (`wsgs_dispatch.sh`)

The flagship orchestrator. Dispatches `wsgs_run_host.R` across
M4 + M1 + N cyphers in parallel, pulls RDS files back, and emits a
province-wide annotated CSV.

### Quick start

```bash
cd ~/Projects/repo/link/data-raw

# Optional: archive prior run's CSVs first if you want LPT to plan
# against this run only (not median-of-recent-runs):
./runs_archive.sh

# Smoke-test first (~3 min, one small WSG per host) — catches preflight,
# tunnel, dispatch, and annotation surprises before the full run:
./trifecta_smoke.sh                                     # 3-host smoke
./trifecta_smoke.sh --cy-workspaces=job1,job2,job3      # 5-host smoke

# Full run:
./wsgs_dispatch.sh                                # 3-host default
./wsgs_dispatch.sh --cy-workspaces=job1,job2,job3 # 5-host

# Add per-segment mapping_code lens (+50% cost):
./wsgs_dispatch.sh --cy-workspaces=job1,job2,job3 --with-mapping-code

# Custom host-speed factors (lower = faster):
./wsgs_dispatch.sh --host-speeds=m4=1.0,m1=0.83,cy=1.83
```

**Recommended cadence:** archive → smoke → full run. The smoke catches
~99% of surprises in 3 minutes; the archive ensures LPT plans against
the freshest data.

### CLI flags

| Flag | Default | Purpose |
|------|---------|---------|
| `--config=<name>` | `bcfishpass` | Bundle (also `default`, etc.) |
| `--schema=<name>` | bundle's `cfg$pipeline$schema` | Override persist schema |
| `--rds-dir=<name>` | `provincial_<config>` | Override RDS output dir |
| `--host-speeds=<csv>` | `m4=1.0,m1=0.83,cy=1.83` | Per-host slowness vs M4. Used for LPT projection AND back-normalizing prior-run times to M4-equivalent intrinsic work. |
| `--cy-workspaces=<csv>` | `default` | Comma-list of cypher tofu workspaces |
| `--with-mapping-code` | off | Pass through to per-host runner |
| `--skip-preflight` | off | Skip version-match check (debug only) |
| `--m4-bucket=<csv>` | LPT plan | Override M4's WSG list |
| `--m1-bucket=<csv>` | LPT plan | Override M1's WSG list |
| `--cy-bucket=<csv>` | LPT plan | Single-cypher override (only with N_CY=1) |
| `--cyN-bucket=<csv>` (1-indexed) | LPT plan | Per-cypher override for N>1 cyphers |

### How bucket allocation works

The orchestrator allocates WSGs to hosts using greedy LPT (Longest
Processing Time first), computed inline at dispatch time:

1. Reads every `_per_wsg_times.csv` in `data-raw/logs/provincial_parity/`
   (or `provincial_<config>/` for non-bcfishpass bundles).
2. Back-normalizes each WSG's recorded elapsed time to M4-equivalent
   intrinsic work using the **CLI `--host-speeds`** factors (NOT
   per-host observed means — that would feedback-loop on imbalanced
   prior runs).
3. Sorts WSGs descending by M4-equivalent work.
4. For each WSG, assigns it to the host with the lowest projected
   finish time (`current_load + m4_equiv × host_factor`).
5. Missing WSGs (no timing data yet) get the median M4-equivalent.

Without prior timing CSVs in the live dir, falls back to a deterministic
`ceil(n/H)` split. Manual `--<host>-bucket=` overrides bypass LPT.

### Pre-flight version check

Before dispatch, the orchestrator queries `packageVersion("link")` +
`packageVersion("fresh")` on each host (local M4, ssh-to-M1, ssh-to-each-cypher).
Aborts if any disagree — a stale install on one host silently produces
divergent rollup numbers and pollutes the comparison.

Override with `--skip-preflight` only for development; in production
the version match is the cheapest sanity check available.

### Gotchas

- **Bash 4+ required.** Uses associative arrays and `read -a`. macOS
  ships bash 3.2; ensure `#!/usr/bin/env bash` resolves to homebrew bash
  (`/opt/homebrew/bin/bash` on Apple Silicon). The orchestrator detects
  this implicitly via the env shebang.
- **Cyphers must be spun up before dispatch.** `cypher_up.sh --workspace
  job1` per workspace listed in `--cy-workspaces=`. The pre-flight
  `tofu output -raw droplet_ip` fails fast when a workspace has no
  droplet.
- **Per-WSG timing CSVs accumulate.** The LPT block reads ALL CSVs in
  the live dir, taking the per-WSG median across samples. Archive older
  runs to `archive/YYYYMMDD_HHMM/` if you want the planner to focus on
  recent data only.
- **Host-name detection is hardcoded.** Maps `MacBook-Pro-2*` → m4,
  `Allans*|*MacBook-Pro$` → m1, `cypher*` → cy. New/renamed machines
  emit `[LPT] WARN: dropped N timing rows with unrecognized host_short`
  and silently miss those samples — update the regex in the inline R
  block when the fleet changes.
- **`--host-speeds` is the ground truth.** Re-measure with an ADMS smoke
  per host when fleet/firmware changes shift performance. Defaults
  (`m4=1.0, m1=0.83, cy=1.83`) derive from the 2026-05-11 5-host run.
- **Per-cypher speed overrides** via `--host-speeds=...,cy1=1.83,cy2=2.10`
  apply only to LPT projection (where the script knows about each
  cypher workspace), not back-normalization (where the CSV's host_short
  is always `cy`, never `cy1`).
- **Empty buckets fail loudly.** The orchestrator aborts before dispatch
  if LPT produces an empty bucket for any host. Without this guard the
  dispatched `Rscript ... --wsgs=` would silently process zero WSGs and
  exit 0.
- **Both per-host AND province-wide annotated CSVs land in
  `provincial_<config>/`.** Per-host (`<TS>_<host>_annotated.csv`) is
  each host's own bucket; orchestrator-side (`<TS>_annotated.csv`) is
  the province-wide aggregate. Intentional redundancy — single-host
  runs only produce the per-host CSV.
- **Disk: 60 GB minimum per worker** (see "Disk capacity per worker
  host" section below). The cypher disk-full incident on 2026-05-04
  motivated `cleanup_working = TRUE` defaults.

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
| `_targets.R` | The (legacy) targets pipeline that pre-dated `wsgs_dispatch.sh`. Kept for the multi-WSG comparison harness. |
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

- `provincial_parity/`, `provincial_default/`, `provincial_default_extrabreaks/` — per-WSG RDS + per-WSG times CSV from `wsgs_run_host.R`.
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
