# Task: Clean provincial run + operational tooling hardening (post-v0.36.0)

Session started 2026-05-13. Today's full provincial run (link 0.36.0, bcfp model 122) surfaced multiple latent gotchas in the distributed dispatch infrastructure. Fixes are landing as hot patches to `trifecta_provincial.sh` + filed follow-up issues; this PWF tracks the work so future sessions can pick up the trail.

## Phase 1: Run today's clean provincial dispatch
- [x] Verify pre-flight (tunnels, snapshots, ssh, doctl)
- [x] Snapshot M4 + M1 (matching bcfp 122)
- [x] Spin 3 cyphers + prep
- [x] First smoke (caught M1 tunnel issue)
- [x] Hot-patch trifecta to inline-tunnel M1+M4 and reverse-forward M1
- [x] Smoke clean
- [x] First full dispatch (217 WSGs, 75 min) — found `cy=0.7` host_speeds inverted semantics
- [x] First consolidate stalled on M1 tailnet (1.7 MB/s) — abandoned
- [x] Discovered cypher snapshots ship with stale `fresh.*` data (107 WSGs in dump vs 47 in bucket)
- [x] Wipe all 5 hosts cleanly (DROP fresh CASCADE + drop stale `working_*` / `fresh_*` schemas)
- [x] Reload `fresh.modelled_stream_crossings` on all 5 hosts via `snapshot_bcfp.sh --force`
- [x] Correct `HOST_SPEEDS` semantics in `trifecta_provincial.sh` (time-multiplier, larger=slower)
- [x] Clean dispatch with corrected host_speeds (3 attempts; final at 22:48 PDT, 1h15m wall, 214/217 OK)
- [x] Pull dumps to M4 (4 dumps in 7 min total — parallel pg_dump + parallel scp)
- [x] Consolidate fresh schema (filter-then-restore for cy[job2]/cy[job3] due to dispatch-#2 contamination)
- [x] Verify per-WSG counts: 207 → recovered 12 via M4-only rerun → **217 distinct WSGs**
- [x] M4-only rerun of 12 errored/missing WSGs (22 min wall, all OK)
- [x] BURN cyphers (24s wall, 0 tofu resources, 0 droplets verified)

## Phase 2: Wrapper script + cleanup script

- [x] Draft `data-raw/province_run.sh` (top-level 10-step wrapper with trap-EXIT burn)
- [x] Draft `data-raw/province_clean.sh` (idempotent multi-host cleanup; finish in <5 min)
- [x] Draft `data-raw/province_progress.sh` (mtime-based progress probe; TZ-glob-safe)
- [ ] Add `--smoke-only` flag to wrapper (next session)
- [ ] Write `province_run_test.sh` harness for wrapper regression (next session)
- [ ] Test wrapper end-to-end via smoke-only (next session)
- [ ] Add `--clean` flag to wrapper that invokes province_clean.sh before dispatch (next session)

## Phase 3: Follow-up issues filed (await fix)

- [x] **link#167** — bcfp tunnel drops cause silent per-WSG errors (autossh proposed)
- [x] **link#168** — Decouple bcfp compare from link pipeline (pair with #167)
- [x] **link#169** — Simplify `lnk_persist_init` after rtj#145 lands
- [x] **link#170** — S3-based consolidate (route pg_dumps through s3://newgraph/)
- [x] **rtj#145** — Rebuild cypher snapshot with fwa dump tables ONLY
- [x] **fresh#199** (reopened) — M4 PG over-tuning evidence + fix-up plan

## Phase 4: Documentation + commit

- [ ] Update `research/post_compact_provincial_handoff.md` with all new gotchas
- [ ] Update `project_link_state.md` memory with today's lessons
- [ ] Commit all patches in one feature branch + PR
- [ ] Archive this PWF on completion

## Validation

- [ ] Acceptance bar: clean 217-WSG run with consolidated fresh schema containing exactly today's data, no stale rows
- [ ] M4 fresh.streams distinct WSGs == 217
- [ ] No `working_*` schemas left after dispatch on any host
- [ ] Cyphers burned to 0 droplets verified via doctl
- [ ] Wrapper script + cleanup script tested on next run
