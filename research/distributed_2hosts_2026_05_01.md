# 2-host distributed parity run — link#53 first-cut baseline

**Date**: 2026-05-01 08:12–08:18 PDT
**Versions**: link 0.21.0, fresh 0.26.0, bcfishpass 440bc1e
**Hosts**: M4 Max + M1 over Tailscale, both with local Docker fwapg :5432 + bcfp tunnel :63333
**Coordination**: ad-hoc — `Rscript run_provincial_parity.R --wsgs=<bucket>` per host, rsync per-WSG RDS files at end

## Headline

| host | bucket | wall-time | per-WSG breakdown |
|---|---|---:|---|
| M4 | BULK + HARR + DEAD | **5:03** | ~3:00 + 1:25 + 0:38 |
| M1 | ELKR + LFRA + VICT | **4:06** | ~2:30 + 1:00 + 0:36 |
| **distributed total** | (limited by slowest host) | **5:03** | |
| **single-host estimate** | sum of 6 | ~10:05 | |
| **speedup** | | **2.0×** | |

## Why this matters

Single-host provincial parity baseline (2026-04-30): **4h 55min** for 232 WSGs. Linear projection of a 2-host split with the same bucket balance: **~2h 30min provincial**. That's the SRED iteration speedup target.

## Correctness

All 6 WSGs produced numerically valid parity rollups. HARR (run on M4) is bit-identical to the single-host baseline (-0.15 / -0.69 / -1.29% on BT spawning/rearing/rearing_stream). Other 5 WSGs in expected ranges.

The minor `bcfishobs` row-count delta between M4 (372,420) and M1 (372,505 from prior bcfp tunnel) didn't materially affect parity in this sample. After #92's per-AOI species-presence + exclusions filter, the working observation set per WSG is small enough that the ~85-row delta doesn't reach our test set.

## Architecture

Each host runs `run_provincial_parity.R --wsgs=<bucket>` against its own:
- writable Docker fwapg on :5432 (mutates `fresh.streams` per WSG)
- bcfp reference DB on :63333 (read-only via SSH tunnel to db_newgraph)

Per-WSG output: `data-raw/logs/provincial_parity/<WSG>.rds`. Resume-friendly (skips existing files). Aggregation via rsync to one host + the existing analysis script.

No shared filesystem. No coordination layer. Manual partition driven by per-WSG runtimes from the prior single-host run (`workloads.csv` pattern).

## What's NOT in this first cut

- **No automatic load-balancing**. WSG buckets are picked manually from prior runtimes. With 232 WSGs and known runtimes, this is fine — provincial scheduling is well-conditioned. For ad-hoc work the manual cut is overhead-free.
- **No automatic aggregation**. End-of-run `rsync` is one command, not a pipeline step. Could automate via a "collector" host but unnecessary at 2-host scale.
- **No db_newgraph as third compute host**. The droplet hosts the bcfp reference (`db_newgraph` schema) but doesn't have a separate writable fwapg or R installed. Asking rtj if titiler/qwc/another VM can become a third compute target — see `rtj/comms/link/20260501_compute_capacity.md`. If yes, theoretical ~3× speedup → ~1h 40min provincial.

## Reproducer

```bash
# m4
mkdir -p data-raw/logs/provincial_parity
Rscript data-raw/run_provincial_parity.R --wsgs=BULK,HARR,DEAD \
  > data-raw/logs/<TS>_dist_m4.txt 2>&1 &

# m1 (over Tailscale)
ssh m1 "cd /Users/airvine/Projects/repo/link && nohup bash -c \
  '/usr/bin/time -p Rscript data-raw/run_provincial_parity.R --wsgs=ELKR,LFRA,VICT \
   > data-raw/logs/<TS>_dist_m1.txt 2>&1' > /dev/null 2>&1 < /dev/null &"

# wait for both, then rsync
rsync -av m1:.../provincial_parity/{ELKR,LFRA,VICT}.rds \
  /Users/airvine/Projects/repo/link/data-raw/logs/provincial_parity/
```

Logs:
- `data-raw/logs/20260501_0812_dist_m4.txt`
- m1: `/Users/airvine/Projects/repo/link/data-raw/logs/20260501_0812_dist_m1.txt`
