# Task: Provincial run autonomy + script renames (#172)

After #168 shipped (v0.37.0, PG-state resume), this PR adds the CLI surface for autonomous M4+M1 runs and renames 8 operational scripts to noun_verb convention. Cypher integration deferred to a follow-up.

## Phase 1 — CLI surface on `trifecta_provincial.sh`

Patch the original filename first so the smoke (Phase 3) validates on the known-good name. Rename in Phase 4.

- [x] Add `--wsgs=A,B,C` arg parse. SPLIT_R block intersects `all_wsgs` with the `--wsgs` list; errors loud on unknown WSGs via `stop(call. = FALSE)`. Verified end-to-end with `--wsgs=BOGUS,ADMS`.
- [x] Add `--no-cyphers` arg parse. Wipes `CY_WORKSPACES=""` → empty `CY_WS_ARR` → `N_CY=0`; all `for ((i=0; i<N_CY; i++))` loops downstream (wrap, launch, RDS/R-log pullback) become no-ops naturally.
- [x] Add `--force` arg parse; appended to `EXTRA_ARGS` so it forwards to every per-host `Rscript run_provincial_parity.R` invocation.
- [x] Fix phantom-cy bug for `n_cy = 0`: three-branch `cy_host_keys` (`character(0)` / `"cy"` / `paste0(...)`) avoids the constant-recycling trap.
- [x] Harden empty-CY_WORKSPACES init: explicit `CY_WS_ARR=()` when `CY_WORKSPACES=""` (was `read -r -a` which yields single-element-empty-string).
- [x] Surface R-side error messages: wrap `SPLIT_OUT=$(Rscript ...)` with explicit `||` block (round-1 code-check fix; without it, R `stop()` calls aborted bash with no operator-visible message).
- [x] Update usage block.
- [x] `bash -n data-raw/trifecta_provincial.sh` syntax-clean.
- [x] Verified SPLIT_R logic via isolated R run: `--wsgs=DEAD,ADMS --no-cyphers` correctly produces `all_wsgs=ADMS,DEAD`, `n_cy=0`, `host_keys=m4,m1`, `cy_host_keys` length 0.
- [x] `/code-check` round 1 caught silent-abort bug, fixed; round 2 clean.
- [ ] Commit "trifecta_provincial.sh: --wsgs filter, --no-cyphers mode, --force passthrough"

## Phase 2 — CLI surface on `province_run.sh`

- [x] Add `--wsgs=`, `--config=`, `--schema=`, `--no-cyphers`, `--force` to arg parser. Defaults: `bcfishpass`, empty schema, no filter, cyphers on, no force.
- [x] Build `DISPATCH_FLAGS` for passthrough; forwarded to `trifecta_provincial.sh` invocation in Step 7.
- [x] Gate Step 3 (cypher spin) + Step 4 (cypher prep) behind `if NO_CYPHERS=0`. Step 5 only iterates cypher archive when `NO_CYPHERS=0` (M4+M1 always archive). `CYPHERS_UP=1` only sets inside the cypher branch, so trap-EXIT burn correctly no-ops under `--no-cyphers`.
- [x] Step 7 omits `--cy-workspaces=...` when `--no-cyphers` or `--wsgs` is set (trifecta_provincial.sh derives the M4+M1-only plan from DISPATCH_FLAGS).
- [x] Step 8 ANN_CSV path config-aware: `provincial_parity/` (bcfishpass back-compat) vs `provincial_<config>/`.
- [x] Step 9 consolidate: split into multi-host (M1+cy1+cy2+cy3) vs M1-only branches. Target schema resolved via `--schema` first, else `lnk_config(CONFIG_NAME)$pipeline$schema` lookup with explicit error/empty/NULL guards (round-1 code-check fix; round 1 had silent fallback masking misconfigured `--config=`).
- [x] Auto-skip-smoke when `--no-cyphers` OR `--wsgs` is set. Notice placed AFTER `exec > >(tee -a "$LOG")` redirect so it lands in the log.
- [x] Update usage block.
- [x] `bash -n data-raw/province_run.sh` syntax-clean.
- [x] Empirically verified TARGET_SCHEMA lookup: bcfishpass → "fresh", default → "fresh" (operator must `--schema=fresh_default` for default-bundle isolation), BOGUS → errors loud.
- [x] `/code-check` round 1: 1 real bug (TARGET_SCHEMA fallback) fixed. Round 2 clean.
- [ ] Commit "province_run.sh: --wsgs / --config / --schema / --no-cyphers / --force passthrough"

## Phase 3 — Integration test (M4+M1, 16-WSG default-bundle, pre-rename)

- [x] Pre-flight: M4 has bcfp tunnel up, M1 ssh reachable, `fresh.modelled_stream_crossings` present on both hosts. Verified at session start.
- [x] First attempt (no pre-clean) surfaced a consolidate edge case: M1's `fresh_default` had leftover WSGs from yesterday's province-wide run; `pg_dump --schema=fresh_default` pulled rows for WSGs outside the current bucket, colliding with M4's destination data on pg_restore. Six duplicate-key errors; 12 of 16 WSGs landed.
- [x] Root-cause fix: added `state_clean.sh --schemas=<csv>` scoped mode + `province_run.sh` Step 0 pre-clean. When `--schema=` is set, umbrella drops the target schema on all hosts BEFORE Step 1.
- [x] Run autonomous (relaunch with pre-clean):
  ```bash
  bash data-raw/province_run.sh \
    --wsgs=CARP,CRKD,FINA,FINL,FIRE,FOXR,INGR,LOMI,MESI,NATR,OSPK,PARA,PARS,PCEA,TOOD,UOMI \
    --config=default --schema=fresh_default --no-cyphers --with-mapping-code --force
  ```
- [x] Acceptance: exit code 0, 20m wall (under 30-40 min budget), no operator prompts mid-run.
- [x] Verified: `fresh_default.streams` = **16/16 WSGs** on M4, 468,631 rows. CARP,CRKD,FINA,FINL,FIRE,FOXR,INGR,LOMI,MESI,NATR,OSPK,PARA,PARS,PCEA,TOOD,UOMI all present.
- [x] Per-species habitat tables: bt, gr, ko, rb + barriers (correct for the geographic test set — northern WSGs without CH/CO/SK/ST presence).
- [x] Annotated CSV: `data-raw/logs/provincial_default/202605141658_annotated.csv` — 343 rows (263 NOT_APPLICABLE + 66 UNEXPLAINED + 14 WITHIN_TOLERANCE). 66 UNEXPLAINED at ≥2% surfaced as WARNING (methodology divergence, expected for `default` vs bcfishpass).
- [x] Consolidate (M1 → M4) succeeded — no duplicate-key conflicts now that pre-clean handles stale state.

## Phase 4 — Rename 8 scripts + update all live references

- [x] `git mv` all 8 renames (preserves `git log --follow`).
- [x] `sed -i ''` across live tree applies all 8 old→new substitutions atomically. Order chosen to avoid prefix collisions; verified no new name contains any old name as substring (sed map is idempotent).
- [x] Internal references updated in renamed files: usage blocks, `Rscript wsgs_run_host.R` invocations, log-filename literals (`${TS}_wsgs_dispatch_*`), cross-script `bash` calls.
- [x] Updated `data-raw/README.md`, `data-raw/trifecta_smoke.sh`, `data-raw/query_schema_delta.R`, `wsg_compare.R`, `wsg_pipeline_run.R`.
- [x] Updated `research/*.md` (runbook, handoff, parity docs).
- [x] Updated `CLAUDE.md`, `R/utils.R` (one-line docstring ref).
- [x] **NOT updated** (sealed): `NEWS.md` historical entries (reverted after sed swept them), `planning/archive/**`.
- [x] `bash -n` clean on all renamed shell scripts (wsgs_run_pipeline.sh, state_clean.sh, progress_check.sh, wsgs_dispatch.sh, runs_archive.sh) + trifecta_smoke.sh sibling.
- [x] `/code-check` round 1 clean (all 7 concerns verified: bash syntax, cross-refs, log literals, Rscript invocations, tree-wide grep empty, idempotency, R/utils.R docstring).
- [ ] Commit "Rename 8 operational scripts to noun_verb convention"

## Phase 5 — Smoke after rename

- [ ] 1-WSG smoke via the renamed umbrella:
  ```bash
  bash data-raw/wsgs_run_pipeline.sh --wsgs=DEAD --config=bcfishpass --no-cyphers
  ```
- [ ] Acceptance: exit code 0, DEAD lands in M4 `fresh.streams`.
- [ ] `devtools::test()` passes.
- [ ] `devtools::check()` — same warning baseline as v0.37.0 (no new warnings).

## Phase 6 — Cross-repo rtj update

- [ ] In `~/Projects/repo/rtj`, update `scripts/cypher/cypher_run.sh` reference from `run_provincial_parity.R` → `wsgs_run_host.R`.
- [ ] `bash -n scripts/cypher/cypher_run.sh` clean.
- [ ] Commit "scripts/cypher/cypher_run.sh: update for link wsgs_run_host.R rename" on rtj/main.
- [ ] Push to origin/main.
- [ ] Order: rtj commit lands **after** link's rename PR merges so cypher_run.sh never references a missing file on link/main.

## Phase 7 — Release v0.38.0

- [ ] Update `DESCRIPTION` Version 0.37.0 → 0.38.0.
- [ ] Update `NEWS.md` with v0.38.0 entry covering CLI surface + 8 renames.
- [ ] Update `CLAUDE.md` if any rename touches its references.
- [ ] Commit "Release v0.38.0".
- [ ] `/planning-archive` with slug `provincial-run-autonomy-renames`.
- [ ] `/gh-pr-push` opens PR with SRED tag in body.
- [ ] After merge: `/gh-pr-merge` handles tag + post-merge CI watch + rtj coordination.

## Validation

- [ ] Tests pass (`devtools::test()`)
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
