# Provincial run runbook

Pre-flight checklist, execution recipe, and post-run cleanup for the 3-host distributed provincial parity run (`data-raw/trifecta_provincial.sh`). Use this every time before kicking off a provincial run — the catches surface input drift, timing collisions with bcfp rebuilds, and broken-cleanup-state from prior runs.

Companion docs:
- `research/provincial_parity_2026_05_11.md` — latest run results + divergence taxonomy
- `research/bcfishpass_methodology.md` — bcfp methodology canonical reference
- `research/bcfp_compare_mapping_code.md` — per-segment mapping_code parity (#152/#154/#158 closure)
- CLAUDE.md `## bcfishpass tunnel rebuild cadence` — timing semantics

## TL;DR sequence

```
[pre-flight] → [snapshot bcfp inputs] → [install fresh+link latest] → [dispatch trifecta] → [verify outputs] → [burn down cypher]
```

Every step has explicit checks below. If any check fails, **don't proceed — diagnose first**.

## 1. Pre-flight checks (must all pass)

### 1.1 — bcfp tunnel rebuild cadence

The bcfp tunnel (`bcfishpass` schema on `localhost:63333` via `db_newgraph`) **rebuilds weekly on Tuesdays around 19:00-23:00 PDT** via `smnorris/db_newgraph`'s scheduled GHA workflow.

**Risk:** if your input snapshot is taken AFTER rebuild starts but BEFORE it finishes (or vice versa), inputs are mismatched against the bcfp parity reference.

**Check:**

```sql
-- localhost:63333 / dbname=bcfishpass / user=newgraph
SELECT model_run_id, date_completed, model_version
FROM bcfishpass.log
ORDER BY model_run_id DESC LIMIT 5;
```

Decision table:

| Condition | Action |
|---|---|
| Now < Tue 19:00 PDT AND last build > 1 day old | **Safe.** Run. Both snapshot + tunnel are in the same cycle. |
| Tue 19:00 PDT ≤ Now ≤ Wed 02:00 PDT (rebuild window) | **WAIT.** Rebuild in flight or just finished — tables may be inconsistent. Defer 12+ hours. |
| Now > Wed 02:00 PDT AND last build = today | **Safe.** Fresh cycle just landed. Run. |

### 1.2 — fresh + link versions on all 3 hosts

```bash
for HOST in M4 m1 cypher; do
  case $HOST in
    M4)  CMD='Rscript -e "cat(as.character(packageVersion(\"fresh\")), as.character(packageVersion(\"link\")))"' ;;
    m1)  CMD="ssh m1 'Rscript -e \"cat(as.character(packageVersion(\\\"fresh\\\")), as.character(packageVersion(\\\"link\\\")))\"'" ;;
    cypher) CMD="ssh cypher 'Rscript -e \"cat(as.character(packageVersion(\\\"fresh\\\")), as.character(packageVersion(\\\"link\\\")))\"'" ;;
  esac
  echo -n "$HOST: " && eval "$CMD" && echo
done
```

Latest versions today: `fresh@0.31.0`, `link@0.35.0+`. All 3 hosts must match before dispatch. See §3.2 for install recipe.

### 1.3 — working schema cleanup on all hosts

```bash
# M4
psql "postgresql://postgres:postgres@localhost:5432/fwapg" -c "
SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE 'working_%';"
# m1 / cypher
ssh m1 "docker exec fresh-db psql -U postgres fwapg -c \"
SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE 'working_%';\""
ssh cypher "docker exec fresh-db psql -U postgres fwapg -c \"
SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE 'working_%';\""
```

**Expect empty.** If schemas linger, prior run had an error-path leak (see link#159). Drop them:

```bash
# M4 example
psql "postgresql://postgres:postgres@localhost:5432/fwapg" -c "DROP SCHEMA IF EXISTS working_<wsg> CASCADE;"
```

### 1.4 — disk free on cypher (if reusing droplet)

Cypher droplet has 100 GB. A fresh provincial run with no cleanup leaks consumes ~10-15 GB. **If `df -h` on cypher shows >70% used, destroy and re-spin before running** (`cypher_down.sh && cypher_up.sh`).

```bash
ssh cypher 'df -h | grep -E "^/dev/|Filesystem"'
```

### 1.5 — RDS file count on M4

Trifecta is resume-safe (skips WSGs with existing RDS). Decide whether you want to resume or start fresh.

```bash
ls data-raw/logs/provincial_parity/*.rds 2>/dev/null | wc -l
```

To start fresh:

```bash
rm -f data-raw/logs/provincial_parity/{ADMS,BULK,...}.rds
# OR for full reset:
mv data-raw/logs/provincial_parity data-raw/logs/provincial_parity_$(date +%Y%m%d_%H%M)
mkdir data-raw/logs/provincial_parity
```

## 2. Snapshot bcfp inputs (on each host that needs it)

`data-raw/snapshot_bcfp.sh` loads from public sources into local Postgres:
- `whse_fish.pscis_assessment_svw` via Python `bcdata bc2pg`
- `cabd.dams` via ogr2ogr (GeoJSON API)
- `fresh.modelled_stream_crossings` via curl + gpkg
- `bcfishobs.observations` via parquet

Idempotent — run on each host that doesn't have current state. **Must run AFTER a bcfp-tunnel rebuild** to refresh tables to current cycle.

### M4 snapshot (canonical reference)

```bash
~/.config/snapshot-bcfp.env  # PG* env vars
bash ~/Projects/repo/link/data-raw/snapshot_bcfp.sh 2>&1 | tee ~/.local/state/snapshot-bcfp/$(date +%Y%m%d%H%M).log
```

### m1 + cypher

Requires the same `~/.config/snapshot-bcfp.env` on each host. M1 has the canonical setup. Cypher's `cypher-20260508-warm` snapshot has the GDAL/conda/bcdata stack baked in (rtj#66), but the env file may or may not be in the snapshot:

```bash
ssh cypher 'cat ~/.config/snapshot-bcfp.env 2>/dev/null || echo MISSING'
# If MISSING, write inline (cypher's Docker fresh-db on localhost:5432):
ssh cypher 'mkdir -p ~/.config && cat > ~/.config/snapshot-bcfp.env <<EOF
export PGHOST=localhost
export PGPORT=5432
export PGUSER=postgres
export PGPASSWORD=postgres
export PGDATABASE=fwapg
export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/fwapg
EOF'
ssh cypher 'bash ~/Projects/repo/link/data-raw/snapshot_bcfp.sh' 2>&1 | tail -5
```

### Verify snapshot landed (per-host)

```sql
SELECT 'cabd.dams' t, count(*) FROM cabd.dams
UNION ALL SELECT 'pscis_svw', count(*) FROM whse_fish.pscis_assessment_svw
UNION ALL SELECT 'modelled', count(*) FROM fresh.modelled_stream_crossings;
```

Expected magnitudes (as of 2026-05-11): cabd.dams 2,594 / pscis_svw 19,903 / modelled 532,166.

### Baselines ledger

`snapshot_bcfp.sh` stamps `data-raw/logs/bcfp_baselines.csv` with the bcfp build identifier (`model_version` from `bcfishpass.log`) and an absolute timestamp. **Confirm the run_label / model_version row is fresh** before kicking the trifecta. Cross-run drift in bcfp `model_version` between hosts means snapshot timing wasn't aligned.

## 3. Install fresh + link to latest on all hosts

### 3.1 — pull main

```bash
cd ~/Projects/repo/fresh && git checkout main && git pull --ff-only
cd ~/Projects/repo/link && git checkout main && git pull --ff-only

ssh m1 'cd ~/Projects/repo/fresh && git pull --ff-only && cd ~/Projects/repo/link && git checkout data-raw/logs/bcfp_baselines.csv && git pull --ff-only'
ssh cypher 'cd ~/Projects/repo/fresh && git pull --ff-only && cd ~/Projects/repo/link && git checkout data-raw/logs/bcfp_baselines.csv && git pull --ff-only'
```

### 3.2 — install

M4 + M1 (pak handles sf):

```bash
Rscript -e 'pak::local_install("~/Projects/repo/fresh", upgrade = FALSE, ask = FALSE)'
Rscript -e 'pak::local_install("~/Projects/repo/link",  upgrade = FALSE, ask = FALSE)'
ssh m1 'Rscript -e "pak::local_install(\"~/Projects/repo/fresh\", upgrade = FALSE, ask = FALSE)"'
ssh m1 'Rscript -e "pak::local_install(\"~/Projects/repo/link\",  upgrade = FALSE, ask = FALSE)"'
```

Cypher (pak conflicts with conda-managed sf; use R CMD INSTALL to skip dependency reinstall):

```bash
ssh cypher 'R CMD INSTALL --no-test-load ~/Projects/repo/fresh && R CMD INSTALL --no-test-load ~/Projects/repo/link'
```

### 3.3 — verify

```bash
for HOST in '' m1 cypher; do
  CMD='Rscript -e "cat(\"fresh\", as.character(packageVersion(\"fresh\")), \" link\", as.character(packageVersion(\"link\")), \"\n\")"'
  if [ -z "$HOST" ]; then eval "$CMD"; else ssh $HOST "$CMD"; fi
done
```

All 3 must report identical fresh + link versions.

## 4. Pre-dispatch cleanup

```bash
# Compute LPT-balanced buckets using prior per-WSG times (or median fallback)
Rscript data-raw/balance_provincial_buckets.R
# Copy the --m4-bucket / --m1-bucket / --cy-bucket lines to clipboard.
```

```bash
# Clear persistent schema if you want a strictly clean fresh.streams + fresh.barriers.
# Skip if resuming or wanting to preserve prior run for diff.
psql "postgresql://postgres:postgres@localhost:5432/fwapg" -c "TRUNCATE fresh.streams CASCADE;"
ssh m1     'docker exec fresh-db psql -U postgres fwapg -c "TRUNCATE fresh.streams CASCADE;"'
ssh cypher 'docker exec fresh-db psql -U postgres fwapg -c "TRUNCATE fresh.streams CASCADE;"'
```

```bash
# Clear stale fresh.streams.gradient GENERATED column if present (pre-#152 snapshot artifact)
ssh cypher 'docker exec fresh-db psql -U postgres fwapg -c "DROP TABLE IF EXISTS fresh.streams CASCADE;"'
```

## 5. Dispatch trifecta

```bash
cd ~/Projects/repo/link/data-raw && time ./trifecta_provincial.sh \
  --m4-bucket="WSG1,WSG2,..." \
  --m1-bucket="..." \
  --cy-bucket="..."
```

Wall: ~2 hours with 3 hosts at LPT-balanced ~155 min projection. Orchestrator log + per-host logs in `data-raw/logs/<TS>_trifecta_provincial_*.txt`. RDS files auto-rsync'd back from m1 + cypher to M4 at completion.

## 6. Post-run verification

```bash
# Count
ls data-raw/logs/provincial_parity/*.rds | wc -l
# Should equal expected canonical count (217 for bcfishpass bundle after link#157).

# Aggregate summary script (`/tmp/summary.R` pattern from research/provincial_parity_2026_05_11.md)
Rscript /tmp/summary.R

# Check error-status RDS files
Rscript -e '
files <- list.files("data-raw/logs/provincial_parity", pattern = "^[A-Z]{4}\\.rds$", full.names = TRUE)
for (f in files) { r <- readRDS(f); if (is.list(r) && !is.null(r$error)) cat(basename(f), ": ", r$error, "\n") }
'
```

## 7. Cypher burn-down (mandatory)

```bash
~/Projects/repo/rtj/scripts/cypher/cypher_down.sh
```

**Always run**, regardless of outcome. The reserved IP (24.144.70.121) persists for the next spin. Cypher droplet costs ~$0.50/hr while up.

## 8. Document run in research/

If headline numbers shifted meaningfully from `research/provincial_parity_<latest>.md`, append a dated addendum or create a new dated file. Required sections:

- Run metadata (timestamp, hardware, link/fresh versions, bcfp `model_version` reference)
- Per-host wall times
- Headline parity per species
- Anomalies (new divergence patterns)
- Cypher state (destroyed at end)

## Known operational issues (open)

- **link#159** — error-path cleanup leaks working schemas. Wrap per-WSG body in `tryCatch({...}, finally = drop_working_schema)`.
- **link#157** — fixed: 15 known-empty WSGs now filtered pre-dispatch (~12 min saved per run).
- **link#158** — fixed: `crossing_fixes.structure = ''` no longer drops modelled crossings (token2-NONE→MODELLED pattern closed at segment level).

## Known measurement asymmetries (intentional, won't close without methodology decisions)

- **Lake/wetland rearing centerline-vs-polygon double-count** — link credits both `*_ha` polygon area and `*_centerline_km` linear length; bcfp credits only one. Produces `-100%` sentinel rows in rollups. See `research/default_vs_bcfishpass.md`.
- **`rear_stream_order_bypass = no`** — fresh has no clean implementation of bcfp's inline `(stream_order_parent >= 5 AND stream_order = 1)` cw-bypass. Costs 5-9% under-credit on HORS/CLRH/COLR/KHOR rearing_stream. fresh#158 deferred.
- **SK new-geographies** — fresh#190 (multi-lake topology, parked) + fresh#191 (lake-adjacency knob, filed). Causes 10-85% divergence on LRDO / BULK / NASR / NASC / TOBA / NEVI / CHWK / QUES / KUMR / THOM. Each WSG needs individual stale-bcfp-vs-methodology classification.

## Quick-reference table — what each script does

| Script | Purpose | Wall |
|---|---|---|
| `snapshot_bcfp.sh` | Load BCDC PSCIS + CABD + bchamp + bcfishobs into local fwapg from public sources | 10-15 min |
| `cypher_up.sh` | Spin DO droplet from `cypher-<date>-warm` snapshot | 3 min |
| `cypher_restore-fwapg.sh` | **Only if snapshot lacks fwapg.** Restores from S3 dump | 30 min |
| `trifecta_provincial.sh` | Dispatch 3-host distributed provincial run with LPT buckets | ~2 hr |
| `compare_bcfishpass_wsg()` | Per-WSG rollup parity (linear sums vs bcfp.habitat_linear_*) | 30-300s per WSG |
| `compare_bcfp_mapping_code.R` | Per-segment mapping_code parity (token-level vs bcfp.streams_mapping_code) | 30-300s per WSG |
| `balance_provincial_buckets.R` | Compute LPT-balanced WSG buckets from per-WSG times | 10s |
| `cypher_down.sh` | Destroy DO droplet (reserved IP persists) | 30s |
