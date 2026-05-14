# Findings — Provincial run + ops tooling hardening (2026-05-13)

## Gotcha #1: M1 SSH key for db_newgraph is passphrase-protected

**Symptom**: Non-interactive ssh from M1 to db_newgraph fails with `Permission denied (publickey)`.

**Root cause**: M1's `~/.ssh/db_newgraph` private key has a passphrase. Interactive shells unlock it via macOS Keychain; non-interactive doesn't have Keychain access. Prior provincial runs worked only because operator had manually opened the tunnel from an interactive shell beforehand.

**Workaround landed**: `trifecta_provincial.sh` patched to ssh M1 with `-R 63333:127.0.0.1:63333` — M1 reverse-forwards through M4's bcfp tunnel instead of opening its own. M1 doesn't need its own db_newgraph identity working.

**Permanent fix**: would require either removing passphrase from M1's key, or storing M1's key in ssh-agent that survives across non-interactive contexts. Reverse-forward is the cleaner architecture anyway.

## Gotcha #2: M1 tailnet path degraded — slow scp transfers

**Symptom**: `scp` from M1 to M4 ran at ~1.7 MB/s today (was much faster in prior weeks). M1's 3.1 GB pg_dump took ~30 min to half-transfer, then stalled.

**Diagnosis**: tailscale ping shows 13ms direct (not DERP-relayed). Throughput-only issue, not latency. Possibly: WireGuard MTU, ISP path change, M1 network config.

**Workaround for today**: re-dumped cyphers fresh (cy→M4 via public IP scp is FAST), kept M1's dump on M1 for in-place restore. Filed potential follow-up as scp-vs-S3 optimization.

**Not filed as issue**: too host-specific to be a recurring gotcha. Mention in `post_compact_provincial_handoff.md` as known operational caveat.

## Gotcha #3: LPT fallback ignored host_speeds

**Symptom**: `[LPT] no timing CSVs found; using deterministic split` produced equal-sized buckets (44 each) for 217 WSGs across 5 hosts, ignoring the host_speeds parameter entirely.

**Root cause**: `trifecta_provincial.sh` SPLIT_R block's fallback was naive `ceiling(n/H)` — no host_speeds-weighted distribution.

**Fixed**: Patched fallback to use host_speeds-weighted alphabetical split. Documented in `research/post_compact_provincial_handoff.md`.

## Gotcha #4: HOST_SPEEDS semantics inverted in defaults

**Symptom**: After patching defaults to `cy=0.7` (interpreting "0.7× M4 speed = slower"), LPT assigned cypher MORE WSGs not fewer.

**Root cause**: `host_factor` in the LPT formula `candidate = load + m4_equiv * host_factor` is a **time multiplier** (larger = slower), not a speed multiplier. I read it backwards. Original default `cy=1.83` was directionally correct (cypher slower); just had wrong magnitude.

**Fix landed**: Updated defaults to time-multiplier semantics:
- `m4=1.0` (baseline 101s/WSG)
- `m1=0.79` (M1 actually FASTER — 80s/WSG, fresh#199 over-tuning means M4 is slower than M1 in practice)
- `cy=1.23` (cypher 124s/WSG, slower than M4)

Added detailed comment to the script. Calibrated from today's empirical timing CSV.

## Gotcha #5: Cypher snapshots ship with stale `fresh.*` data

**Symptom**: After clean dispatch, each cypher's `fresh.streams` had 107/103/75 distinct WSGs instead of the bucket size (47/48/47). Consolidate would have pulled in 60+ stale WSGs per cypher.

**Root cause**: Cypher snapshot images were built from a cypher that had completed partial pipeline runs. The pipeline-output tables (`fresh.streams`, `fresh.streams_habitat_*`, `fresh.barriers`) were captured WITH data in the snapshot.

`lnk_persist_init(force_recreate=TRUE)` only drops tables when DDL drift is detected (the GENERATED column check). For tables with correct DDL, it leaves data alone.

**Filed**:
- **rtj#145** — Rebuild cypher snapshot with fwa dump tables ONLY (no bcfishobs / cabd / whse_fish / fresh.* baked in)
- **link#169** — Simplify `lnk_persist_init` after rtj#145 lands (drop DDL-drift detection complexity)

**Workaround for today**: full DROP SCHEMA fresh CASCADE before re-running.

## Gotcha #6: Stale `working_<wsg>` schemas accumulate

**Symptom**: Found 10-15 leftover `working_<wsg>` schemas on each host (M4 + M1 + cyphers) — orphans from prior killed/errored runs.

**Root cause**: `cleanup_working = TRUE` in `compare_bcfishpass_wsg` only drops working schemas on SUCCESSFUL pipeline completion. Failures leave them behind. M4 + M1 accumulated weeks of these.

**Workaround**: SQL `\gexec` pattern to drop all `working_*` and stale `fresh_*` schemas in one pass per host.

**Follow-up**: Add this to `province_clean.sh` (planned, Phase 2).

## Gotcha #7: tail -50 buffers consolidate output

**Symptom**: Running `Rscript consolidate_schema.R 2>&1 | tail -50` with a long-running process means NO output is visible until completion. The tail waits for EOF.

**Workaround**: For long-running R processes, use `tee` + a log file, or remove the pipe entirely.

**Mental note**: don't pipe long-running stdout to tail unless you also want to wait for the whole thing.

## Gotcha #8: M4 PG over-tuning

**Symptom**: M4 Max consistently slower per-WSG (101s median) than M1 MBP (80s median).

**Root cause**: fresh's `docker-compose.yml` base defaults tuned for 128GB hosts: `shared_buffers=32GB, work_mem=2GB, max_parallel_workers=14, effective_cache_size=96GB`. M1 uses smaller override; less worker coordination overhead, better OS page cache locality.

**Filed**: fresh#199 reopened with M4-specific calibration plan.

## Gotcha #11: Filter-by-CSV is wrong; filter by "what's a valid RDS on M4"

**Symptom**: After dispatch #3, when consolidating cyphers, I DELETEd non-bucket WSGs from cy[job2]/cy[job3] using the dispatch #3 per_wsg_times.csv as ground truth. This dropped ~30 WSGs of VALID link pipeline data (BULL, JENR, etc.) that came from dispatch #2's background run.

**Root cause confusion**: per_wsg_times.csv only contains entries for WSGs run in THIS dispatch invocation. Cached RDS files from PRIOR dispatches don't appear in the CSV. But their data persists in fresh.streams from the original run.

**Correct filter logic**: A WSG's data on a host should be kept if the corresponding RDS on M4 is **valid (rollup, not error stub)** — regardless of which dispatch produced it. Use:

```bash
for w in $(ls fresh.streams DISTINCT wsg); do
  if [ "$(Rscript -e 'rdsHasError($w.rds)')" = "true" ]; then
    delete_from_fresh($w)
  fi
done
```

In practice: just track each RDS's status (error vs rollup) on M4 and only keep WSGs with valid rollups in the consolidated schema.

**Impact**: Lost ~12 WSGs of valid data tonight. Recovered by re-running locally on M4.

## Gotcha #12: `run_provincial_parity.R` caches RDS — needs archive between dispatches

**Symptom**: Dispatch #3 produced rollup-OK RDS files for WSGs that NEVER ran in dispatch #3 (per the CSV). The RDS files were from dispatch #2 (cached).

**Root cause**: `run_provincial_parity.R` skips WSGs whose RDS exists (`if (file.exists(out_rds)) next`). When dispatch #2 ran in the background on cyphers (per gotcha #10), it wrote RDS files. Dispatch #3 then skipped those WSGs. The orchestrator's RDS-pull-back step grabbed all RDS files indiscriminately.

**Fix**: 
1. `archive_provincial_runs.sh` MUST run on every host before every dispatch (covered today).
2. Wrapper should explicitly verify host's `provincial_parity/` is empty post-archive before dispatching.
3. Better: name RDS files per-dispatch (`<TS>_<WSG>.rds`) so they can't collide.

## Wrapper test strategy (TODO before next provincial)

To prevent the infinite-loop failure pattern of today:

**`data-raw/province_run.sh --smoke-only` flag**: exits after smoke + consolidate + burn. Tests the full wrapper machinery in ~15 min wall, ~$0.10 cypher cost.

**`data-raw/province_run_test.sh`**: harness script that runs --smoke-only and asserts:
- exit code 0
- ≥ 5 distinct WSGs in M4 fresh.streams
- 0 cypher droplets remaining (via doctl)
- 0 lingering R processes on any host (M1 + 3 cyphers)
- No errors in dispatch log

**Cadence**: run before any change to `province_run.sh`, `trifecta_provincial.sh`, `cypher_prep.sh`, or `consolidate_schema.R`. Catch regressions early instead of after a 75-min full run.

## Gotcha #10: `pkill -9 -f Rscript` misses the R subprocess

**Symptom**: Dispatch #2 (cy=0.7 inverted speeds) was "killed" via `kill -9` on M4 trifecta + `ssh cypher 'pkill -9 -f Rscript'`. But cypher fresh.streams showed both dispatch #2 AND dispatch #3 WSGs after both runs "completed."

**Root cause**: `Rscript` is a shell wrapper that exec's `R --no-echo`. `pkill -f Rscript` matches the SHELL wrapper, but once it exits, the actual R process running on the cypher is `R --no-echo --no-restore -e '...'` — different command line. Killing the parent didn't propagate to the child (orphaned R inherited init as parent, kept running).

**Fix landed**: Verified by ps grep on remote: actual process is `R --no-echo`, not `Rscript`. Kill must target `R --no-echo` OR use a broader pattern OR send signal to all R-family processes.

Proposed kill command for the wrapper:
```bash
ssh cypher@$IP 'pkill -9 -f "R --no-echo" 2>/dev/null; pkill -9 -f "Rscript" 2>/dev/null; pkill -9 -f "run_provincial" 2>/dev/null'
```

Triple-redundant. Also need to verify with `ps -ef | grep R` post-kill, not assume.

**Impact today**: Forced fix-on-restore consolidate path (DELETE WHERE wsg NOT IN bucket per cypher) instead of straight pg_restore. ~1 hour of operator debugging.

## Gotcha #9: Cross-host timezone glob hell

**Symptom**: Probe scripts using `20260513_*_per_wsg_times.csv` matched M4/M1 files but missed cypher files (named `20260514_*`).

**Root cause**: `run_provincial_parity.R` writes CSV filename via `format(Sys.time(), "%Y%m%d_%H%M")` — uses host's local TZ. Cyphers run UTC; M4/M1 run PDT. After 17:00 PDT the dates diverge.

**Fix**: NEVER glob by date across hosts. Use `find ... -newer <ref>` with an mtime reference, or just `ls -t | head -1` (newest file regardless of name). Same lesson for any cross-host file enumeration.

## Empirical timing baseline (2026-05-13, bcfp model 122)

**First-attempt partial-CSV calibration (noisy, 5-WSG M1 samples):**
- M4 Max: 101 s/WSG
- M1 MBP: 80 s/WSG ← turned out to be a noisy small-sample artifact
- 8vCPU/32GB cypher: 124 s/WSG

**Mid-run reality (clean re-dispatch, ~25 WSGs per host into the run):**
- M4 Max: ~105 s/WSG
- M1 MBP: ~105 s/WSG ← NOT faster than M4 in reality
- 8vCPU/32GB cypher: ~127-140 s/WSG

Corrected host_speeds for next run: `m4=1.0, m1=1.0, cy=1.30`. The "M1 is 0.79× faster" calibration was based on 5-6 WSG samples from a killed mid-run dispatch — sampling bias toward small WSGs that completed first.

**Lesson**: don't trust calibration from <30 WSG samples. Wait for a complete run's full timing CSV before re-tuning host_speeds.

## Operational discipline lessons

1. **Verify dispatch ACTUALLY launched** before walking away — system-reminders can interrupt and a Bash that printed "PID: X" might not have actually fired.
2. **Don't bundle destructive operations into approval-stacked tool calls** — single-action calls keep user control granular.
3. **Always check fresh schema row counts after consolidate** — silent contamination would show up here.
4. **Trust empirical data over docs** — today's prior 2026-05-12 doc claimed 1.83× cypher speed, today's data showed the opposite.
