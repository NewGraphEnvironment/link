# Task: Provenanced province-wide `default` run (#246)

**If done:** `fresh_default` holds a `default` build of all 241 `default`-modelable watershed groups, every row traceable to one
run, its code and its inputs, so threshold calibration can be scored wherever a species occurs (#346), and a
`bcfishpass` parity check confirms the engine at the same code. **If never:** `fresh_default` stays at 56 groups with
provenance on 5, and every calibration drops the groups it does not cover.

### Phase 1 — Bodies and room (no spend)
- [x] Correct #246 and #346 to 241 groups under `default`, and name the 24 groups that `default` adds
- [x] Operator grows colima: `colima stop && colima start --disk 600` (bare command handed over). `fresh-db` comes back
      healthy and `df` shows ≥ 300 G free

### Phase 2 — Re-baseline at HEAD (issue Phase 3)
- [x] Generate the 241-group split: `study_area_buckets.R --config=default --hosts=4 --focal=<all 246> --write`.
      The disjoint-closure and downstream-first assertions pass, with host speeds from measured rates (#259)
- [x] Setdiff: every group in `fresh_default` is in the 241 (re-run at HEAD, recorded in `findings.md`)
- [x] State the decision set in `progress.md`:
  - config `default`, schema `fresh_default`, 241 groups, species per host;
  - flags `--refresh-primitives` and `--recompute-jobs=4`;
  - the run label
- [x] Fix what review 1 (`review-1.md`) confirmed before any spend (one commit):
  - the driver resolves buckets with the run's config and the source tree (B1);
  - cloud-host prep initialises the run's config and schema (G1);
  - ssh keepalives on the per-bucket session (G3);
  - a bash ≥ 4 guard (A2);
  - the generator emits its own config in the launch command (G4);
  - `parity_crosssection.R` takes `LNK_SCHEMA`, writes an annotated CSV and fails on a group it has no rows for (B3)
- [x] Re-pack at equal host speeds (`--host-speeds=1,1,1,1`): the 34-group run measured cloud hosts at or above m1's
      rate, not 0.45 (A1)
- [x] Commit and push; `study_area_run.sh --preflight-only --cy-workspaces=job1,job2,job3 --config=default
      --schema=fresh_default` passes every gate, run with `/opt/homebrew/bin/bash` (A-3)
- [x] Record the `fresh.streams_vw_bcfp` row count (4,272,365 / 188 groups, recorded 2026-10-16) before the refresh, and again after (A4)
- [x] Pilot at HEAD on m1 + job1 into a scratch schema: m1 `--focal=KAKC`, job1 `--focal=TSEA` (`default`-only groups,
      so it exercises the B1 fix, cloud-host prep at 0.66 and 11-species consolidate). It takes `--refresh-primitives`,
      so the vintage gate passes, and it checks free disk on the cloud host (A5)
- [ ] Optional: drop the orphan `working_*` / `zz_lnk_mc_scratch_*` debris with `state_clean.sh --schemas=` scoped to
      the orphans (never the unscoped mode). Skipped: the resize left 307 G free, so it was not needed

### Phase 3 — The run (issue Phase 4)
- [x] Launch detached on the same day as the refresh:
      `/opt/homebrew/bin/bash data-raw/study_area_run.sh --cy-workspaces=job1,job2,job3 --focal=×4 --config=default
      --schema=fresh_default --refresh-primitives --run-label=provincial-241-default-246` under `caffeinate`, output under
      `data-raw/logs/`. The repo stays untouched until the driver exits (A3)
- [x] Wait on the driver PID and the log's final verdict, not the wrapper. Report times in Vancouver time
- [x] Post-consolidate recompute across all 241 (in the driver): 241/241, 154 min at `-j4`
- [x] Record the run_uid, wall clock per host and for the recompute, the cost, and the DB growth
- [x] Parity check at the same code, dispatcher only, after the main run (never overlapping it, O3):
  - `--config=bcfishpass --schema=<scratch>` on the closure of ADMS, BULK, BABL and ELKR;
  - `LNK_SCHEMA=<scratch> LNK_PARITY_OUT=… parity_crosssection.R` against `fresh.streams_vw_bcfp`, annotated;
  - count UNEXPLAINED rows, and read the compare log for groups that error silently (#167)
- [x] Recover what the run lost (added mid-run; findings "The run"):
  - the 18 finished groups the driver counted as missing, consolidated by hand from the paused cloud hosts (#347);
  - KITR and UPET fixed (`a17e9177`, tests and a restore-the-bug proof) and re-run on m1 under the same run_uid;
  - the driver resumed, so its recompute covers all 241 (#348 would have skipped it)

### Phase 4 — Verify provenance (issue Phase 5)
- [x] `fresh_default.log`:
  - one row per group for this run_uid, all 241;
  - non-NULL `config_hash`, `link_sha`, `fresh_sha` and `fwapg_sha`;
  - no group's newest row predates the run
- [x] `fresh_default.log_input`:
  - per-primitive row counts and `source_at`;
  - `config_drift` FALSE;
  - loader version ids for bcfishobs and crossings identical across hosts, and `row_count` per table compared
    across hosts (FWA rows are probes and `api` sources are NULL by design; the record states this, A-4)
- [x] `log_parameters_fresh` / `log_dimensions` populated for this run (confirm, don't assume)
- [x] `study_area_verify.sql -v schema=fresh_default -v run_uid=… -v expected_n=241` passes; the checks it does not make
      (config hash and drift, `log_input`, parameter logs, newest row) get their own SQL (A-1, A-2)
- [x] Commit the run logs under one campaign prefix, `data-raw/logs/provincial_246/`

### Phase 5 — Record
- [x] Revise `research/study_area_run.md` in place with every host's stamp, and the rates against the estimate
- [x] CLAUDE.md status: `fresh_default` is one provenanced build, which retires the "not one build" fact
- [x] #346 part 1 is satisfied, so note it there; the PR closes #246
- [x] #276: the post-#265 finding and a pre-spend `source_artifact` gate added to its body

## Validation

- [x] Tests: R code did land (`a17e9177`, `91a968ab`), so `devtools::test()` ran: 2,989 pass. 5 problems, none in a changed
      file: 3 need the closed `:63333` tunnel (`test-lnk_db_conn.R:10`, `test-lnk_wsg_resolve.R:143`, `:154`), 2 are the golden
      ADMS dams test that CLAUDE.md already says to re-pin (8 → 7 dams). The two fixes each have a restore-the-bug proof
- [x] `/code-check branch`: rounds 1–4 before the run; 5–7 over the run's fixes and prose. Round 6 found a defect inside
      the UPET fix (fixed `91a968ab`), so round 7 ended the loop by enumeration (26 code places, 61 prose claims; one
      wrong claim fixed). Two latent defects outside the diff drafted as an issue
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion
