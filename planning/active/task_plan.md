# Task: `lnk_compare_wsg` + provincial parity annotated CSV (single-source-of-truth taxonomy) (#162)

Today the "why does this WSG-species-metric diverge from bcfp?" knowledge is spread across three places: `research/provincial_parity_2026_05_01.md` (Class A/B/C/D narrative), `research/bcfp_compare_mapping_code.md` (per-segment Phase A), and ~12 PR/issue threads. Every provincial run rediscovers known answers because there's no joinable artifact.

This branch lifts two scattered scripts into one package-level function (`lnk_compare_wsg`), establishes `research/bcfp_divergence_taxonomy.yml` as the single source of truth for known patterns, and adds a post-run annotator that emits one CSV with every row tagged against the taxonomy. Acceptance bar: **zero rows with `|diff_pct| ≥ 2%` AND `class == UNEXPLAINED`** after a full provincial run.

Full algorithm + critical-files table in `/Users/airvine/.claude/plans/snuggly-fluttering-hopper.md`.

Bundles three cleanups while in the area: `balance_provincial_buckets.R` dedup bug, `consolidate_schema.R` `ok=FALSE` false-positive + bucket-aware destination cleanup, stale `_per_wsg_times.csv` discovery.

## Phase 1: scaffold + `lnk_compare_wsg` (rollup-only path)

- [x] Write `R/lnk_compare_wsg.R` — exported function. Body composes existing pipeline phases. `with_mapping_code = FALSE` only in this phase. `reference` arg validated against `c("bcfishpass")`.
- [x] `devtools::document()`.
- [x] Mocked tests: SQL composition under `local_mocked_bindings`, arg validation, reference dispatch error on unknown values.
- [x] `lintr::lint` clean (indent warnings match existing codebase style; not regressions).

## Phase 2: `lnk_compare_wsg` mapping_code branch

- [x] Extend `lnk_compare_wsg.R` with `with_mapping_code = TRUE` path. Composes the additional phases (barriers_unify → views → access → mapping_code → diff vs `bcfishpass.streams_mapping_code`).
- [x] Per-species segment-level diff stats: total_segs, match_pct, n_diffs, top_pattern, top_pattern_count. Tibble shape matches the `mapping_code` slot in the return value documented above.
- [x] Tests cover the additional path (mocked SQL).

## Phase 3: data-raw refactor

- [x] `data-raw/compare_bcfishpass_wsg.R` — collapse to thin wrapper around `lnk_compare_wsg(reference = "bcfishpass")`. Keep RDS persistence + bcfp baseline stamping + per-WSG timing CSV (those stay in data-raw).
- [x] `data-raw/compare_bcfp_mapping_code.R` — DELETE (logic now in `lnk_compare_wsg`).
- [x] Smoke: re-run ADMS via the refactored wrapper, confirm bit-identical rollup tibble + mapping_code stats vs pre-refactor.

## Phase 4: taxonomy YAML + annotator

- [x] Write `research/bcfp_divergence_taxonomy.yml` with initial ~20 entries covering Class A (SETN), Class B (HORS et al), Class C (SK new-geographies — LRDO/BULK/NASR/etc.), Class D survivor (BBAR CH/CO), MEASUREMENT_ASYMMETRY (lake/wetland centerline-vs-polygon), TOKEN2_RESIDUAL.
- [x] Write `R/lnk_parity_annotate.R` — reads taxonomy, joins per-WSG rollup + mapping_code stats, emits annotated tibble + optional CSV.
- [x] Mocked tests: wildcard handling, pattern matching (`link_gt_bcfp`, `link_lt_bcfp`, `bcfp_only`, `link_only`), first-match-wins semantics, UNEXPLAINED fallback at `|diff_pct| >= 2%`.

## Phase 5: orchestrator + dispatch

- [ ] `data-raw/run_provincial_parity.R` — `--with-mapping-code` flag passthrough. Post-run call to `lnk_parity_annotate()` writes `<TS>_annotated.csv` to `data-raw/logs/provincial_parity/`.
- [ ] `data-raw/trifecta_provincial.sh` — `--with-mapping-code` flag + multi-workspace dispatch (3 cyphers via `--workspace job1,job2,job3` + M4 + M1). Each cypher workspace dispatched via `cypher_run.sh --workspace jobN`. RDS files auto-pulled back to M4 at completion (existing rsync pattern).
- [ ] Pre-flight checks (per `research/provincial_run_runbook.md`): all 5 hosts return matching link+fresh versions before dispatch.

## Phase 6: cleanups bundled

- [ ] `data-raw/balance_provincial_buckets.R` — add `aggregate(time_s ~ wsg + host, FUN = median)` after CSV load to dedup `(wsg, host)` pairs from multi-run CSV picks; then `aggregate(m4_equiv ~ wsg, FUN = median)` before LPT to dedup across hosts. Test by re-running yesterday's CSVs (which contain dupes) and confirming bucket counts sum to canonical.
- [ ] `data-raw/consolidate_schema.R` — change `ok` flag derivation: `ok = TRUE` only when pg_restore exit code 0 AND post-restore row count > 0 for the target schema. Add bucket-aware destination cleanup: before pg_restore, `DELETE FROM <dest_schema>.<tbl> WHERE watershed_group_code IN (<source host's bucket>)` per table that has `watershed_group_code` column.
- [ ] Stale `_per_wsg_times.csv` convention: extend `balance_provincial_buckets.R` to read only `data-raw/logs/provincial_parity/*_per_wsg_times.csv` (top level) — older CSVs move to `archive/YYYYMMDD_HHMM/` subdirs.

## Phase 7: full provincial run + acceptance

- [ ] Spin 3 cyphers via `cypher_up.sh --workspace job1`, `--workspace job2`, `--workspace job3`. Verify rtj#129 fix holds.
- [ ] Pre-flight all 5 hosts (versions match, snapshot_bcfp.sh runs cleanly on cyphers).
- [ ] Dispatch `./trifecta_provincial.sh --with-mapping-code` with LPT-balanced buckets across 5 hosts. Predicted wall: ~50-60 min with the mapping_code +50% cost.
- [ ] After completion: aggregate annotated CSV. Verify acceptance: **zero rows with `|diff_pct| >= 2%` AND `class == UNEXPLAINED`**.
- [ ] If UNEXPLAINED rows surface ≥2% — investigate, add taxonomy entries, re-annotate (don't rerun the pipeline).
- [ ] Consolidate `fresh` schema from m1 + 3 cyphers → M4 via fixed `consolidate_schema.R`.
- [ ] Burn down all 3 cyphers via `cypher_down.sh --workspace jobN` per workspace.

## Phase 8: research doc + release

- [ ] Update `research/provincial_run_runbook.md` — annotated CSV is the primary deliverable; existing rollup/mapping_code outputs documented as diagnostic detail. 5-host dispatch pattern via Tofu workspaces.
- [ ] Append addendum to `research/provincial_parity_2026_05_11.md` with the post-#162 run results (or new dated doc if magnitudes shift).
- [ ] `DESCRIPTION` 0.35.0 → 0.36.0; `NEWS.md` entry covering `lnk_compare_wsg`, `lnk_parity_annotate`, `bcfp_divergence_taxonomy.yml`, the three bundled cleanups.
- [ ] `devtools::check()`: 0 errors.
- [ ] `/planning-archive` + `/gh-pr-push`.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
