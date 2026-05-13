# Provincial run runbook

End-to-end checklist for a 5-host distributed provincial parity run. The
golden-path sequence is **archive → smoke → full → verify → burn**. Skipping any
step risks wasted compute or wasted DO spend; the orchestrator's tests (#162
Phase 7 hardening) make each step's failure mode loud.

Companion docs:

- `data-raw/README.md` — `Provincial dispatch` section: full CLI flag reference
- `research/provincial_parity_2026_05_12.md` — most recent run results
- `research/bcfp_divergence_taxonomy.yml` — known divergence patterns
- `research/bcfp_divergence_investigation.md` — diagnostic recipes
- CLAUDE.md `## bcfishpass tunnel rebuild cadence` — timing semantics

## TL;DR sequence

```bash
cd ~/Projects/repo/link/data-raw

./archive_provincial_runs.sh                            # 1. clean LPT input
# (spin cyphers per §1)
./trifecta_smoke.sh --cy-workspaces=job1,job2,job3      # 2. smoke (~3 min)
# (if smoke errors loud, fix and re-run; DO NOT skip to full)
./trifecta_provincial.sh --with-mapping-code --cy-workspaces=job1,job2,job3   # 3. full (~80 min)
# (inspect annotated CSV)
# (consolidate fresh schema via consolidate_schema.R)
~/Projects/repo/rtj/scripts/cypher/cypher_down.sh --workspace job1   # 4. burn (mandatory)
~/Projects/repo/rtj/scripts/cypher/cypher_down.sh --workspace job2
~/Projects/repo/rtj/scripts/cypher/cypher_down.sh --workspace job3
```

Each step has explicit checks below. **Don't proceed when a step fails.**

## 1. Spin up + snapshot inputs

### 1.1 bcfp tunnel cadence

The tunnel-side `bcfishpass.*` schema rebuilds Tuesdays around 19:00-23:00 PDT.
Check current build:

```sql
-- localhost:63333 / dbname=bcfishpass / user=newgraph
SELECT model_run_id, date_completed, model_version
FROM bcfishpass.log ORDER BY model_run_id DESC LIMIT 1;
```

| Now | Action |
|---|---|
| Outside Tue 19:00 → Wed 02:00 PDT window | Safe. Run. |
| Inside the window | WAIT 12 h. Tunnel may be mid-rebuild. |

Record the SHA — `data-raw/logs/bcfp_baselines.csv` will auto-stamp it at run start.

### 1.2 Spin cyphers (N workspaces)

```bash
cd ~/Projects/repo/rtj/scripts/cypher
./cypher_up.sh --workspace job1 &
./cypher_up.sh --workspace job2 &
./cypher_up.sh --workspace job3 &
wait
```

~3 min wall (parallel). Each spawns a 32 GB / 8 vcpu droplet from `cypher-<date>-warm`
snapshot. The snapshot has fwapg + bcfishobs + GDAL/bcdata tooling; primitives still need a refresh per §1.3.

### 1.3 Refresh snapshot_bcfp on all hosts

```bash
# M4 (local) — only if its PSCIS/CABD/observations are >7 days old
PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg \
  bash ~/Projects/repo/link/data-raw/snapshot_bcfp.sh

# M1
ssh m1 'cd ~/Projects/repo/link/data-raw && \
  export PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg && \
  bash snapshot_bcfp.sh'

# Each cypher — same env vars
for IP in $(for w in job1 job2 job3; do
              cd ~/Projects/repo/rtj/env/do/dev/cypher && TF_WORKSPACE=$w tofu output -raw droplet_ip
            done); do
  ssh "cypher@$IP" 'cd ~/Projects/repo/link/data-raw && \
    export PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg && \
    bash snapshot_bcfp.sh' &
done
wait
```

Verify row-counts match across hosts AND bcfp tunnel:

```bash
# All 5 hosts + bcfp tunnel should return matching row counts on
# whse_fish.pscis_assessment_svw, cabd.dams, fresh.modelled_stream_crossings,
# bcfishobs.observations. Drift on bcfishobs is the most common — re-run
# snapshot_bcfp.sh on the lagging host.
```

### 1.4 Pull + install link on all hosts (BEFORE any dispatch)

```bash
cd ~/Projects/repo/link && git pull --ff-only
Rscript -e 'pak::local_install(upgrade = FALSE, ask = FALSE)'

for H in m1 cypher@$JOB1_IP cypher@$JOB2_IP cypher@$JOB3_IP; do
  ssh $H 'cd ~/Projects/repo/link && git stash --include-untracked >/dev/null 2>&1 || true; \
          git fetch origin && git reset --hard origin/main && \
          Rscript -e "pak::local_install(upgrade = FALSE, ask = FALSE)"' &
done
wait
```

**Critical**: never `pak::local_install` on a host whose R session is already
mid-run. Library-in-memory != library-on-disk; an in-flight R session keeps the
version it loaded at startup. Install BEFORE any dispatch, full stop.

### 1.5 First-time DDL fix on cypher snapshot

Snapshot-baked cyphers carry a stale `fresh.streams` DDL (`gradient` as
`GENERATED ALWAYS`). `lnk_persist_init` detects this and errors loud. Recreate
with the correct DDL **once per cypher spin**:

```bash
for IP in $JOB1_IP $JOB2_IP $JOB3_IP; do
  ssh "cypher@$IP" 'Rscript -e "
    library(link)
    conn <- DBI::dbConnect(RPostgres::Postgres(),
      host=\"localhost\", port=5432, dbname=\"fwapg\",
      user=\"postgres\", password=\"postgres\")
    cfg <- lnk_config(\"bcfishpass\")
    loaded <- lnk_load_overrides(cfg)
    species <- unique(loaded\$parameters_fresh\$species_code)
    lnk_persist_init(conn, cfg, species, force_recreate = TRUE)
  "' &
done
wait
```

After this, `lnk_persist_init` future calls (during dispatch) are silent no-ops.

## 2. Archive prior run + smoke

### 2.1 Archive ALL hosts' RDS

```bash
cd ~/Projects/repo/link/data-raw
./archive_provincial_runs.sh
ssh m1 'cd ~/Projects/repo/link/data-raw && ./archive_provincial_runs.sh'
for IP in $JOB1_IP $JOB2_IP $JOB3_IP; do
  ssh "cypher@$IP" 'cd ~/Projects/repo/link/data-raw && ./archive_provincial_runs.sh' &
done
wait
```

Skipping a host means its leftover RDS files SCP back to M4 at run-end and
pollute the aggregate annotation (caught on 2026-05-12).

### 2.2 Smoke (1 WSG per host, ~3 min)

```bash
cd ~/Projects/repo/link/data-raw
./trifecta_smoke.sh --cy-workspaces=job1,job2,job3 --with-mapping-code
```

**Exits non-zero** if any host produced an error stub. Inspect:

```
data-raw/logs/<TS>_trifecta_provincial_*.txt       # orchestrator + per-host
data-raw/logs/<TS>_trifecta_provincial_cypher_*_R.txt   # cypher R output (auto-pulled)
```

Common smoke failures + fixes:

| Error | Cause | Fix |
|---|---|---|
| `DDL drift in fresh.streams` | §1.5 not done | Run §1.5 |
| `packageVersion mismatch` | preflight version drift | §1.4 install |
| `cannot connect to localhost:63333` | bcfp tunnel down on M4 | check SSH forwarding |
| `bcfishobs row count differs` | §1.3 not done on this host | re-run snapshot_bcfp.sh |

**Don't dispatch the full run until smoke exits 0.** Saves ~90 min of wasted
compute per failure mode.

## 3. Full dispatch

```bash
cd ~/Projects/repo/link/data-raw
./trifecta_provincial.sh \
  --with-mapping-code \
  --cy-workspaces=job1,job2,job3 \
  > /tmp/full_run.log 2>&1 &
disown
```

Inline LPT computes balanced buckets from prior `_per_wsg_times.csv`. Override
manually via `--host-speeds=` or `--<host>-bucket=` per `data-raw/README.md`.
Wall: ~80-95 min for 217 WSGs across 5 hosts.

## 4. Post-run verification

The orchestrator's final headline tells the truth:

```
[trifecta-provincial] local RDS: 217/217 pulled — 217 OK, 0 errors
```

If `errors > 0`, inspect the listed cypher-side R log paths. Don't proceed to
consolidation until the error stubs are recovered (re-dispatch the failed WSGs
on a host whose stack is healthy).

Annotated CSV path printed at end. Read class breakdown:

```r
ann <- read.csv("data-raw/logs/provincial_parity/<TS>_annotated.csv")
table(ann$class, useNA = "ifany")
unexp <- ann[ann$class == "UNEXPLAINED" & abs(ann$diff_pct) >= 2, ]
nrow(unexp)
```

**Acceptance bar**: `nrow(unexp) == 0`. Surviving UNEXPLAINED rows go through
the investigation toolkit (`research/bcfp_divergence_investigation.md`); add
taxonomy entries + re-annotate without rerunning the pipeline.

## 5. Consolidate fresh schema (m1 + cyphers → M4)

```bash
cd ~/Projects/repo/link/data-raw
Rscript -e '
source("consolidate_schema.R")
result <- consolidate_schema(
  schema = "fresh",
  sources = list(
    list(host = "m1",                  via = "docker", bucket = strsplit("WSG1,WSG2,...", ",")[[1]]),
    list(host = "cypher@<JOB1_IP>",    via = "docker", bucket = strsplit("...", ",")[[1]]),
    list(host = "cypher@<JOB2_IP>",    via = "docker", bucket = strsplit("...", ",")[[1]]),
    list(host = "cypher@<JOB3_IP>",    via = "docker", bucket = strsplit("...", ",")[[1]])
  ),
  backup = TRUE)'
```

Bucket strings come from the orchestrator log (per-host bucket lines under
`[trifecta-provincial] dispatch start`). `consolidate_schema` (Phase 6) does
bucket-aware DELETE + pg_restore + pre/post row-count assertion.

## 6. Burn cyphers — MANDATORY

```bash
for w in job1 job2 job3; do
  ~/Projects/repo/rtj/scripts/cypher/cypher_down.sh --workspace $w &
done
wait

# Verify destruction (cross-check via tofu state + doctl)
for w in job1 job2 job3; do
  N=$(cd ~/Projects/repo/rtj/env/do/dev/cypher && TF_WORKSPACE=$w tofu state list | wc -l)
  echo "cy[$w]: $N tofu resources (expect 0)"
done
doctl compute droplet list --no-header | grep -i cypher || echo "no cypher droplets (clean)"
```

Cypher droplets cost ~$0.06/hr each (3 × $0.06 = $0.18/hr). Burn at end of
EVERY session, regardless of outcome. The 2026-05-12 → 13 incident left them
running ~10 h unattended because the burn was coupled to a script that
silently died on an unrelated grep bug — see `planning/active/findings.md`
for the operational lessons.

## 7. Document run

If headline numbers shifted meaningfully from the previous dated parity doc,
append an addendum or create a new `research/provincial_parity_YYYY_MM_DD.md`.
Required sections:

- Run metadata (timestamp, hardware, link/fresh versions, bcfp `model_version`)
- Per-host wall times (from `_per_wsg_times.csv`)
- Headline class breakdown (annotated CSV summary)
- UNEXPLAINED rows + taxonomy follow-ups
- Cypher state (destroyed at end)

## Known operational issues (open)

- **link#163** — Adaptive `host_speeds` learning from observed wall times (LPT
  refinement; currently static CLI defaults)
- **fresh#158** — `stream_order_parent` rear bypass deferred (Class B taxonomy)
- **fresh#190, #191** — SK new-geographies (Class C taxonomy)

## Known measurement asymmetries (intentional)

- **Lake/wetland rearing centerline-vs-polygon double-count**. `research/default_vs_bcfishpass.md`
- **`rear_stream_order_bypass = no`** — costs 5-9% under-credit on HORS-class
  rearing_stream. Tagged Class B in taxonomy.
- **SK new-geographies** — 10-85% divergence on LRDO/BULK/NASR/NASC/TOBA/etc.
  Tagged Class C in taxonomy.

## Quick-reference table

| Script | Purpose | Wall |
|---|---|---|
| `snapshot_bcfp.sh` | Load PSCIS + CABD + bchamp + bcfishobs into local fwapg | ~5-15 min |
| `cypher_up.sh --workspace <ws>` | Spin DO droplet from `cypher-<date>-warm` snapshot | ~3 min |
| `archive_provincial_runs.sh` | Move prior-run RDS + CSVs to archive/ | <1s |
| `trifecta_smoke.sh` | 1-WSG-per-host smoke; fails loud on any error stub | ~3 min |
| `trifecta_provincial.sh` | N-cypher full dispatch with inline LPT + annotation | ~80 min (5-host) |
| `consolidate_schema.R` | pg_dump from m1+cyphers → pg_restore on M4 | ~5 min |
| `cypher_down.sh --workspace <ws>` | Destroy DO droplet (idempotent) | ~30s |
