# Task: Provincial run autonomy + script renames (#172)

After #168 shipped (v0.37.0, PG-state resume), this PR adds the CLI surface for autonomous M4+M1 runs and renames 8 operational scripts to noun_verb convention. Cypher integration deferred to a follow-up.

## Phase 1 — CLI surface on `trifecta_provincial.sh`

Patch the original filename first so the smoke (Phase 3) validates on the known-good name. Rename in Phase 4.

- [ ] Add `--wsgs=A,B,C` arg parse. In SPLIT_R block (~line 135), intersect `all_wsgs` with the `--wsgs` list when provided; error loud on unknown WSGs.
- [ ] Add `--no-cyphers` arg parse. When set: force `N_CY=0`, skip cypher wrap generation (lines 449-471), skip cypher subprocess launch (lines 523-536), skip cypher RDS pullback, skip cypher R log pullback.
- [ ] Add `--force` arg parse and forward to `Rscript run_provincial_parity.R ... --force`.
- [ ] Fix phantom-cy bug for `n_cy = 0`: `paste0("cy", integer(0))` returns `"cy"` (length-1 due to constant recycling); use explicit `if (n_cy == 0L) character(0)` branch.
- [ ] Harden empty `CY_WORKSPACES` / `N_CY` init for the cy-less path.
- [ ] Update usage block.
- [ ] `bash -n data-raw/trifecta_provincial.sh` syntax-clean.
- [ ] `/code-check` clean on staged diff.
- [ ] Commit "trifecta_provincial.sh: --wsgs filter, --no-cyphers mode, --force passthrough"

## Phase 2 — CLI surface on `province_run.sh`

- [ ] Add `--wsgs=`, `--config=`, `--schema=`, `--no-cyphers`, `--force` to arg parser.
- [ ] Defaults: `--config=bcfishpass`, `--schema=""` (use bundle default), `--wsgs=""` (full bundle).
- [ ] Forward new flags to `trifecta_provincial.sh` invocation.
- [ ] When `--no-cyphers`: skip Step 3 (cypher spin), Step 4 (cypher prep), Step 5 cypher iterations (M4+M1 archive only), Step 9 cypher consolidate sources (M1 only), Step 10 cypher burn (trap-EXIT no-op).
- [ ] Step 8 ANN_CSV path: derive from `CONFIG_NAME` so non-bcfishpass bundles get `provincial_<config>/` not hardcoded `provincial_parity/`.
- [ ] Auto-skip-smoke when `--no-cyphers` OR `--wsgs` is set. Place notice AFTER the `exec > >(tee -a "$LOG")` redirect so it lands in the log.
- [ ] Update usage block.
- [ ] `bash -n data-raw/province_run.sh` syntax-clean.
- [ ] `/code-check` clean.
- [ ] Commit "province_run.sh: --wsgs / --config / --schema / --no-cyphers / --force passthrough"

## Phase 3 — Integration test (M4+M1, 16-WSG default-bundle, pre-rename)

- [ ] Pre-flight: M4 has bcfp tunnel up, M1 ssh reachable, `fresh.modelled_stream_crossings` present on both hosts.
- [ ] Wipe state via `bash data-raw/province_clean.sh --skip-cy`.
- [ ] Run autonomous:
  ```bash
  bash data-raw/province_run.sh \
    --wsgs=CARP,CRKD,FINA,FINL,FIRE,FOXR,INGR,LOMI,MESI,NATR,OSPK,PARA,PARS,PCEA,TOOD,UOMI \
    --config=default --schema=fresh_default --no-cyphers --with-mapping-code
  ```
- [ ] Acceptance: exit code 0, ~30–40 min wall, no operator prompts mid-run.
- [ ] Verify `SELECT count(DISTINCT watershed_group_code) FROM fresh_default.streams` = 16 on M4.
- [ ] Verify `fresh_default.streams_habitat_*` populated for each species in the bundle.
- [ ] Verify annotated CSV written with all 16 WSGs.
- [ ] Document outcome in `progress.md` with wall time + per-host breakdown.

## Phase 4 — Rename 8 scripts + update all live references

- [ ] `git mv data-raw/province_run.sh data-raw/wsgs_run_pipeline.sh`
- [ ] `git mv data-raw/province_clean.sh data-raw/state_clean.sh`
- [ ] `git mv data-raw/province_progress.sh data-raw/progress_check.sh`
- [ ] `git mv data-raw/trifecta_provincial.sh data-raw/wsgs_dispatch.sh`
- [ ] `git mv data-raw/run_provincial_parity.R data-raw/wsgs_run_host.R`
- [ ] `git mv data-raw/consolidate_schema.R data-raw/schema_consolidate.R`
- [ ] `git mv data-raw/archive_provincial_runs.sh data-raw/runs_archive.sh`
- [ ] `git mv data-raw/balance_provincial_buckets.R data-raw/buckets_balance.R`
- [ ] Update internal references in each renamed file (self-name in usage block, `source()` calls between them, log filenames).
- [ ] Update `data-raw/README.md` (~27 refs).
- [ ] Update `research/provincial_run_runbook.md` (~12 refs).
- [ ] Update `research/post_compact_provincial_handoff.md` (~8 refs).
- [ ] Update `CLAUDE.md` (2 refs).
- [ ] **Do NOT update** `planning/archive/**`, `NEWS.md` historical entries.
- [ ] `bash -n` clean on all 4 renamed shell scripts.
- [ ] `/code-check` clean.
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
