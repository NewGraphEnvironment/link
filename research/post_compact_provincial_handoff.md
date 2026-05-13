# Post-compact provincial run handoff

Read this first if you're a fresh Claude session and the user asks you to run the full provincial parity model. Written 2026-05-13 after shipping v0.36.0 (link#162) and validating methodology on 5 WSGs. Survives compaction so you have everything you need to fire the run autonomously through the happy path.

## What v0.36.0 is

- `lnk_compare_wsg()` + `lnk_parity_annotate()` — exported library functions
- `research/bcfp_divergence_taxonomy.yml` — 11 verified-mechanism entries
- 5-host N-cypher orchestrator (`data-raw/trifecta_provincial.sh`)
- Phase 7 hardening: DDL drift detection, smoke fail-fast, log visibility, truth-in-headline
- 5-WSG audit (ADMS/SETN/HORS/BULK/THOM) hit 0 UNEXPLAINED at |diff_pct|>=2%

Full state in `~/.claude/projects/-Users-airvine-Projects-repo-link/memory/project_link_state.md` (also auto-loaded).

## Pre-flight requirements (verify BEFORE doing anything)

```bash
# 1. PG_PASS_SHARE env var set (needed for bcfp tunnel)
echo $PG_PASS_SHARE   # should be non-empty

# 2. bcfp tunnel alive on M4
pg_isready -h localhost -p 63333
# If down: ssh -fN -L 63333:127.0.0.1:5432 db_newgraph

# 3. local fwapg up on M4
pg_isready -h localhost -p 5432

# 4. SSH connectivity to M1
ssh -o ConnectTimeout=3 m1 'hostname'

# 5. doctl + tofu work for cypher infra
doctl compute droplet list --no-header | head -3
cd ~/Projects/repo/rtj/env/do/dev/cypher && tofu workspace list

# 6. branch is main + tag v0.36.0 present
cd ~/Projects/repo/link && git status && git tag -l v0.36.0

# 7. bcfp tunnel rebuild cadence (Tuesday 19-23 PDT)
# Skip if in the window; safe otherwise
psql -h localhost -p 63333 -U newgraph -d bcfishpass -c "
SELECT model_run_id, date_completed, model_version FROM bcfishpass.log ORDER BY model_run_id DESC LIMIT 1"
```

If ANY of these fail, surface to user and pause. Don't try to fix infrastructure unprompted.

## The 10-step sequence (happy path)

```bash
# === Step 1: cross-host alignment audit (catch drift before spend) ===
# Verify all hosts will compare apples-to-apples vs bcfp tunnel.
# Row counts should match across M4 + M1 + bcfp tunnel:
#   PSCIS: 19,903   CABD: 2,594   modelled: 532,166   bcfishobs: 372,627
# (numbers from 2026-05-13; will drift over time as bcfp rebuilds)
PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres -d fwapg -At -c \
  "SELECT count(*) FROM bcfishobs.observations"   # M4
ssh m1 'docker exec fresh-db psql -U postgres -d fwapg -At -c "SELECT count(*) FROM bcfishobs.observations"'  # M1
psql -h localhost -p 63333 -U newgraph -d bcfishpass -At -c "SELECT count(*) FROM bcfishobs.observations"  # bcfp tunnel
# If M4 or M1 drifts vs bcfp tunnel: run snapshot_bcfp.sh --force on the lagging host.

# === Step 2: refresh M4 + M1 snapshots if needed ===
PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg \
  bash ~/Projects/repo/link/data-raw/snapshot_bcfp.sh --force
ssh m1 'export PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg && \
        cd ~/Projects/repo/link/data-raw && bash snapshot_bcfp.sh --force'

# === Step 3: spin 3 cyphers in parallel (~3 min wall, ~$0.02 each) ===
cd ~/Projects/repo/rtj/scripts/cypher
for WS in job1 job2 job3; do
  ./cypher_up.sh --workspace "$WS" > "/tmp/up_$WS.log" 2>&1 &
done
wait
# Capture IPs for later steps:
for WS in job1 job2 job3; do
  IP=$(cd ~/Projects/repo/rtj/env/do/dev/cypher && TF_WORKSPACE="$WS" tofu output -raw droplet_ip)
  echo "$WS=$IP"
done

# === Step 4: per-cypher prep (git+install+snapshot+DDL fix), parallel ~1 min ===
for IP in <cy1_ip> <cy2_ip> <cy3_ip>; do
  ( scp -q ~/Projects/repo/link/data-raw/cypher_prep.sh "cypher@$IP:/tmp/cypher_prep.sh" && \
    ssh "cypher@$IP" "bash /tmp/cypher_prep.sh" ) > "/tmp/prep_${IP}.log" 2>&1 &
done
wait
# Each cypher should log: "lnk_persist_init detected GENERATED columns; DROPping per force_recreate=TRUE"
# If any cypher's prep fails, surface to user and STOP.

# === Step 5: archive prior RDS on ALL hosts (cross-host smoke gotcha from 2026-05-12) ===
cd ~/Projects/repo/link/data-raw && bash archive_provincial_runs.sh
ssh m1 'cd ~/Projects/repo/link/data-raw && ./archive_provincial_runs.sh'
for IP in <cy1_ip> <cy2_ip> <cy3_ip>; do
  ssh "cypher@$IP" 'cd ~/Projects/repo/link/data-raw && ./archive_provincial_runs.sh' &
done
wait

# === Step 6: SMOKE (1 small WSG per host, ~3 min, fail-fast) ===
cd ~/Projects/repo/link/data-raw
bash trifecta_smoke.sh --cy-workspaces=job1,job2,job3 --with-mapping-code > /tmp/smoke.log 2>&1
SMOKE_RC=$?
if [ $SMOKE_RC -ne 0 ]; then
  # Smoke caught an error stub. STOP.
  grep -E "smoke.*FAILED|smoke.*ERROR" /tmp/smoke.log
  # Inspect:
  #   data-raw/logs/<TS>_trifecta_provincial_cypher_<ws>_R.txt
  # DO NOT proceed to step 7 until smoke is clean.
fi

# === Step 7: FULL PROVINCIAL DISPATCH (~80-95 min wall) ===
cd ~/Projects/repo/link/data-raw
nohup bash trifecta_provincial.sh \
  --cy-workspaces=job1,job2,job3 \
  --with-mapping-code > /tmp/full_run.log 2>&1 &
# Check completion via process list + log tail
ps -ef | grep trifecta_provincial.sh | grep -v grep | wc -l   # 0 when done
tail -10 /tmp/full_run.log
# Expected final headline: "local RDS: 217/217 pulled — 217 OK, 0 errors"

# === Step 8: check acceptance bar ===
ANN_CSV=$(ls -1t data-raw/logs/provincial_parity/*_annotated.csv | head -1)
Rscript -e "
ann <- read.csv('$ANN_CSV', stringsAsFactors=FALSE)
unexp <- ann[ann\$class == 'UNEXPLAINED' & abs(ann\$diff_pct) >= 2, ]
cat('UNEXPLAINED at |diff_pct|>=2%:', nrow(unexp), '\n')
if (nrow(unexp) > 0) print(head(unexp[, c('wsg','species','habitat_type','link_value','ref_value','diff_pct')], 20))
"
# If 0: success.
# If >0: surface to user. Per WSG, the diagnostic recipes in
#        research/bcfp_divergence_investigation.md verify mechanism
#        before extending taxonomy. DO NOT extend taxonomy without
#        running diagnostics.

# === Step 9: consolidate fresh schema (m1 + 3 cyphers -> M4) ===
# Extract per-host buckets from orchestrator log:
ORCH_LOG=$(ls -1t data-raw/logs/*_trifecta_provincial_orchestrator.txt | head -1)
M1_BUCKET=$(grep '^  m1     bucket:' "$ORCH_LOG" | sed 's/.*bucket: //')
CY1_BUCKET=$(grep '^  cypher\[job1\] bucket:' "$ORCH_LOG" | sed 's/.*bucket: //')
CY2_BUCKET=$(grep '^  cypher\[job2\] bucket:' "$ORCH_LOG" | sed 's/.*bucket: //')
CY3_BUCKET=$(grep '^  cypher\[job3\] bucket:' "$ORCH_LOG" | sed 's/.*bucket: //')

# Then invoke consolidate_schema.R (DBI calls, needs PG_PASS_SHARE):
cd ~/Projects/repo/link/data-raw
M1_BUCKET="$M1_BUCKET" CY1_BUCKET="$CY1_BUCKET" CY2_BUCKET="$CY2_BUCKET" CY3_BUCKET="$CY3_BUCKET" \
CY1_IP=<cy1_ip> CY2_IP=<cy2_ip> CY3_IP=<cy3_ip> \
Rscript -e '
suppressPackageStartupMessages({library(link)})
source("consolidate_schema.R")
result <- consolidate_schema(
  schema = "fresh",
  sources = list(
    list(host = "m1",                                  via = "docker", bucket = strsplit(Sys.getenv("M1_BUCKET"),  ",")[[1]]),
    list(host = paste0("cypher@", Sys.getenv("CY1_IP")), via = "docker", bucket = strsplit(Sys.getenv("CY1_BUCKET"), ",")[[1]]),
    list(host = paste0("cypher@", Sys.getenv("CY2_IP")), via = "docker", bucket = strsplit(Sys.getenv("CY2_BUCKET"), ",")[[1]]),
    list(host = paste0("cypher@", Sys.getenv("CY3_IP")), via = "docker", bucket = strsplit(Sys.getenv("CY3_BUCKET"), ",")[[1]])
  ),
  backup = TRUE)
saveRDS(result, "/tmp/consolidate_result.rds")
'
# Verify all four sources reported ok=TRUE.

# === Step 10: BURN CYPHERS — MANDATORY, run regardless of outcome ===
cd ~/Projects/repo/rtj/scripts/cypher
for WS in job1 job2 job3; do
  ./cypher_down.sh --workspace "$WS" > "/tmp/burn_$WS.log" 2>&1 &
done
wait

# Verify destruction via TWO methods:
for WS in job1 job2 job3; do
  N=$(cd ~/Projects/repo/rtj/env/do/dev/cypher && TF_WORKSPACE="$WS" tofu state list 2>/dev/null | wc -l | tr -d ' ')
  echo "cy[$WS]: $N tofu resources (expect 0)"
done
doctl compute droplet list --no-header | grep -i cypher || echo "(no cypher droplets — clean)"
```

## MANDATORY: burn cyphers at end

The 2026-05-12 → 13 cost incident left 3 cyphers running ~10 hours unattended because `phase7_post_run.sh` died silently on a grep bug. ~$1.80 wasted, but the principle: **the operator's last step is to verify destruction**. If you exit your session without confirming 0 tofu resources × 3 workspaces AND no cypher droplets in `doctl`, that's a failure.

Use `trap EXIT` defense if you write a wrapper. Without a wrapper, you do this manually as Step 10 above.

## When to pause and ask the user

| Situation | Why |
|---|---|
| Pre-flight check fails | Don't try to fix infrastructure (DO creds, SSH keys, tunnel) unprompted |
| Smoke fails on a novel error | Decision: fix-forward or abort? |
| New UNEXPLAINED rows in WSGs not in current taxonomy | Decision: investigate + extend taxonomy, or file follow-up? |
| Consolidate `ok=FALSE` for any source | Decision: re-run that consolidation, or accept partial? |
| Anything that requires destructive action beyond planned burn | Always confirm first |

## Key WSGs to know

- **Baseline (clean)**: ADMS — historical BT spawning_km ~362, rearing_km ~671
- **Class A (SETN stale)**: SETN — bcfp barriers_subsurfaceflow stale on 14+ rows
- **Class B (HORS bypass)**: HORS, CLRH, COLR, KHOR — fresh#158 rear_stream_order_parent bypass deferred
- **Class C (SK new-geographies)**: BULK, CHWK, KUMR, LRDO, NASR, NEVI, QUES, TOBA, THOM, etc. — fresh#190/#191 deferred
- **Class D (small Tuesday residuals)**: BBAR, THOM (CH/CO/ST), MFRA CH, REVL WCT — suspected bcfp tunnel staleness
- **MEASUREMENT_ASYMMETRY**: any WSG with `lake_rearing` or `wetland_rearing` showing `link=0, bcfp>0` — intentional (link credits centerline km, bcfp credits polygon ha)

## Where everything lives

| What | Where |
|---|---|
| Per-WSG library API | `R/lnk_compare_wsg.R` |
| Annotator | `R/lnk_parity_annotate.R` |
| Taxonomy YAML | `research/bcfp_divergence_taxonomy.yml` |
| Diagnostic recipes per Class | `research/bcfp_divergence_investigation.md` |
| Operational runbook | `research/provincial_run_runbook.md` |
| Latest live run record | `research/provincial_parity_2026_05_12.md` |
| Orchestrator | `data-raw/trifecta_provincial.sh` |
| Smoke shim | `data-raw/trifecta_smoke.sh` |
| Per-cypher prep | `data-raw/cypher_prep.sh` (defaults to `main` branch) |
| Snapshot loader | `data-raw/snapshot_bcfp.sh` (with `--force` flag) |
| Archive helper | `data-raw/archive_provincial_runs.sh` |
| Consolidation | `data-raw/consolidate_schema.R` (R, not shell — pre/post row delta verification) |
| Cypher infra | `~/Projects/repo/rtj/scripts/cypher/cypher_{up,down,run}.sh --workspace <name>` |
| Findings from Phase 7 | `planning/archive/2026-05-link162-lnk-compare-wsg-annotated-csv/findings.md` |
| Memory state | `~/.claude/projects/-Users-airvine-Projects-repo-link/memory/project_link_state.md` |

## Open follow-ups (not blocking a province run)

- **link#163** — adaptive `host_speeds` learning (LPT recalibrates from observed wall times)
- **link#166** — data-raw script rename to noun-first convention
- **soul#46** — document noun-first naming convention org-wide

## Done

When the province run finishes with 0 UNEXPLAINED at |diff_pct|>=2% AND cyphers are burned AND `fresh` schema is consolidated to M4, you're done. Report findings to user with:

- Wall time
- 217/N OK count
- Class breakdown from annotated CSV
- Cypher destruction confirmation
- Any new UNEXPLAINED rows that need taxonomy follow-up
