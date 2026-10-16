# Task: Provenanced province-wide `default` run (#246)

**If done:** `fresh_default` holds a `default` build of all 217 modelable watershed groups, every row traceable to one
run, its code and its inputs, so threshold calibration can be scored wherever a species occurs (#346), and a
`bcfishpass` parity check confirms the engine at the same code. **If never:** `fresh_default` stays at 56 groups with
provenance on 5, and every calibration drops the groups it does not cover.

### Phase 1 — Bodies and room (no spend)
- [ ] Correct #246 and #346 to 241 groups under `default`, and name the 24 groups that `default` adds
- [ ] Operator grows colima: `colima stop && colima start --disk 600` (bare command handed over). `fresh-db` comes back
      healthy and `df` shows ≥ 300 G free

### Phase 2 — Re-baseline at HEAD (issue Phase 3)
- [ ] Generate the 241-group split: `study_area_buckets.R --config=default --hosts=4 --focal=<all 246> --write`.
      The disjoint-closure and downstream-first assertions pass, with host speeds from measured rates (#259)
- [ ] Setdiff: every group in `fresh_default` is in the 241 (re-run at HEAD, recorded in `findings.md`)
- [ ] State the decision set in `progress.md`:
  - config `default`, schema `fresh_default`, 241 groups, species per host;
  - flags `--refresh-primitives` and `--recompute-jobs=4`;
  - the run label
- [ ] Commit and push; `study_area_run.sh --preflight-only --config=default --schema=fresh_default` passes every gate
- [ ] One-host pilot at HEAD, dispatcher only, `--config=default` into a scratch schema, on one small group, so
      nothing between 0.47 and 0.66 breaks the paid run. The pilot also takes `--refresh-primitives`, so the vintage
      gate passes at its 7-day default
- [ ] Optional: drop the orphan `working_*` / `zz_lnk_mc_scratch_*` debris with `state_clean.sh --schemas=` scoped to
      the orphans (never the unscoped mode)

### Phase 3 — The run (issue Phase 4)
- [ ] Launch detached on the same day as the refresh:
      `study_area_run.sh --cy-workspaces=job1,job2,job3 --focal=×4 --config=default --schema=fresh_default
      --run-label="provincial 241 default (#246)"`. The repo stays frozen until the driver exits
- [ ] Wait on the driver PID and the log's final verdict, not the wrapper. Report times in Vancouver time
- [ ] Post-consolidate recompute across all 241 (in the driver)
- [ ] Record the run_uid, wall clock per host and for the recompute, the cost, and the DB growth
- [ ] Parity check at the same code, dispatcher only:
  - `--config=bcfishpass --schema=<scratch>` on the closure of ADMS, BULK, BABL and ELKR;
  - `lnk_parity_annotate()` against the local `fresh.streams_vw_bcfp`;
  - read the compare log for groups that error silently (#167), and count the UNEXPLAINED rows

### Phase 4 — Verify provenance (issue Phase 5)
- [ ] `fresh_default.log`:
  - one row per group for this run_uid, all 241;
  - non-NULL `config_hash`, `link_sha`, `fresh_sha` and `fwapg_sha`;
  - no group's newest row predates the run
- [ ] `fresh_default.log_input`:
  - per-primitive row counts and `source_at`;
  - `config_drift` FALSE;
  - `artifact_*` version ids identical across all four hosts
- [ ] `log_parameters_fresh` / `log_dimensions` populated for this run (confirm, don't assume)
- [ ] `study_area_verify.sql -v run_uid=… -v expected_n=241` passes
- [ ] Commit the run logs under one campaign prefix, `data-raw/logs/provincial_246/`

### Phase 5 — Record
- [ ] Revise `research/study_area_run.md` in place with every host's stamp, and the rates against the estimate
- [ ] CLAUDE.md status: `fresh_default` is one provenanced build, which retires the "not one build" fact
- [ ] #346 part 1 is satisfied, so note it there; the PR closes #246

## Validation

- [ ] Tests pass (no R code changes are planned; if any land, `devtools::test()`)
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
