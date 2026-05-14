# Progress

## Session 2026-05-13 → 2026-05-14 (post-compact through clean 217-WSG deliverable)

### Final state (2026-05-14 06:35 PDT)

- **M4 `fresh.streams` = 217 distinct WSGs** (full BC stream network model)
- All `fresh.streams_habitat_<sp>` populated (5,062,358 rows each)
- `fresh.barriers` populated
- Annotated parity CSV: `data-raw/logs/provincial_parity/20260514_0622_*_annotated.csv` (4,739 rows)
- Cyphers decommissioned ✓ (0 tofu resources, 0 droplets)

### What happened (chronological)

1. **Dispatch #1** (22:48 PDT smoke + 18:39 PDT first full) — 217/217 RDS pulled, but consolidate stalled on M1 tailnet (~1.7 MB/s). Discovered stale cypher snapshot data → contamination risk.
2. **Wipe + re-dispatch #2** with `cy=0.7` (INVERTED host_speeds semantics) — caught early but kill didn't propagate to cypher R subprocesses (gotcha #10). Ran to completion in background.
3. **Re-dispatch #3** with `cy=1.23` (corrected) — completed 1h15m wall, 214 OK + 3 errors, 90 UNEXPLAINED at |diff_pct|>=2%.
4. **Consolidate** — discovered each cypher dump had 107/103/75 distinct WSGs (vs expected 47/48/47) due to dispatch #2 running concurrently in background (gotcha #10). pg_restore failed on duplicate keys for cy[job2]/cy[job3].
5. **Filter + restore** — DELETEd non-dispatch-#3 WSGs from cyphers, re-dumped, restored. M4 fresh.streams = 207 distinct WSGs. Realized this also deleted ~10 WSGs of valid dispatch-#2 data on cyphers (gotcha #11).
6. **M4-only rerun** of 12 missing/errored WSGs — 22 min wall, all 12 succeeded. M4 fresh.streams = 217 ✓.
7. **Cyphers decommissioned** in 24s parallel.

### What's in working tree (uncommitted)

- `data-raw/trifecta_provincial.sh` — patched: M1 reverse-forward tunnel, M4 inline tunnel, LPT fallback uses host_speeds-weighted split, HOST_SPEEDS=m4=1.0,m1=0.79,cy=1.23 (time-multiplier semantics)
- `data-raw/province_run.sh` — NEW: top-level 10-step wrapper with trap-EXIT burn
- `data-raw/province_clean.sh` — NEW: idempotent multi-host cleanup (kills, wipes fresh.*, drops working_*, reloads snapshot)
- `data-raw/province_progress.sh` — NEW: mtime-based progress probe across 5 hosts (no TZ glob hell)
- `planning/active/task_plan.md` — phases tracked
- `planning/active/findings.md` — 12 gotchas + wrapper test strategy
- `planning/active/progress.md` — this file
- `research/post_compact_provincial_handoff.md` — updated with tunnel architecture + LPT split gotcha sections

### Issues filed

- **link#167** — bcfp tunnel drops cause silent per-WSG errors (autossh proposed)
- **link#168** — Decouple bcfp compare from link pipeline run (high-leverage)
- **link#169** — Simplify `lnk_persist_init` after rtj#145 lands
- **link#170** — S3-based consolidate (route pg_dumps through s3://newgraph/)
- **rtj#145** — Rebuild cypher snapshot with fwa dump tables ONLY
- **fresh#199** (reopened) — M4 PG over-tuning evidence + fix-up plan

### Lessons captured in findings.md (12 gotchas)

1. M1 SSH key passphrase-protected (non-interactive ssh fails)
2. M1 tailnet path degraded (~1.7 MB/s)
3. LPT fallback ignored host_speeds (equal-split with no timing data)
4. HOST_SPEEDS semantics inverted (time-multiplier, larger=slower)
5. Cypher snapshots ship with stale `fresh.*` data
6. Stale `working_<wsg>` schemas accumulate
7. `tail -50` buffers consolidate output (no real-time visibility)
8. M4 PG over-tuning (32GB shared_buffers, 14 workers = slower than M1)
9. Cross-host timezone glob hell (cyphers UTC, M4/M1 PDT)
10. `pkill -9 -f Rscript` misses `R --no-echo` subprocess
11. Filter-by-CSV is wrong; filter by RDS-validity-on-M4
12. `run_provincial_parity.R` caches RDS — needs archive between dispatches

### Wrapper test strategy

Documented in findings.md: `--smoke-only` flag for province_run.sh + `province_run_test.sh` harness. Validates wrapper end-to-end in ~15 min wall, ~$0.10 cypher cost.

### Next session

1. Commit feature branch (this session's hot patches + new scripts)
2. `.claude/settings.json` narrow wrapper-only allowlist (deferred — not needed until autonomous wrapper run)
3. Implement `--smoke-only` flag in province_run.sh
4. Run `province_run.sh --smoke-only` to validate the wrapper machinery
5. Strategy: M4-only as the simple baseline next provincial run; add hosts incrementally only after smoke validates each addition
6. Refactor (link#168 decouple, rtj#145 snapshot rebuild) on a separate branch
