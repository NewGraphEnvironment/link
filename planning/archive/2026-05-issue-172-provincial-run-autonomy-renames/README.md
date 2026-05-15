# Provincial run autonomy + script renames (#172) — 2026-05-14

## Outcome

Shipped v0.38.0 on top of v0.37.0 (#168 decouple). Two-axis change:

1. **Autonomy CLI surface.** `wsgs_run_pipeline.sh` (was `province_run.sh`) accepts `--wsgs=A,B,C`, `--config=`, `--schema=`, `--no-cyphers`, `--force`, forwards to `wsgs_dispatch.sh` (was `trifecta_provincial.sh`). New Step 0 pre-clean fires `state_clean.sh --schemas=<schema>` when `--schema=` is set, eliminating the consolidate-stale-WSG class of failures. Phase 3 acceptance: 16/16 WSGs in `fresh_default.streams` on M4 after a single `bash data-raw/wsgs_run_pipeline.sh ...` invocation, ~20 min wall, exit 0, no operator prompts.
2. **8 mechanical renames to noun_verb.** `province_*` / `trifecta_*` / `consolidate_schema` / `archive_provincial_runs` / `balance_provincial_buckets` / `run_provincial_parity` → honest names that describe scope. Done via `git mv` so `git log --follow` preserves history. `compare_bcfishpass_wsg.R → wsg_compare.R` was already renamed in #168.

Resulting naming family:
- `wsg_*` (singular, per-WSG functions from #168): `wsg_pipeline_run.R`, `wsg_compare.R`.
- `wsgs_*` (plural, collection-level orchestrators): `wsgs_run_host.R`, `wsgs_dispatch.sh`, `wsgs_run_pipeline.sh`.
- Mixed nouns for other wrappers: `state_clean.sh`, `progress_check.sh`, `runs_archive.sh`, `buckets_balance.R`, `schema_consolidate.R`.

Side-fixes that landed because they were load-bearing for autonomy:
- Phantom-cy bug (R's `paste0("cy", integer(0))` returns `"cy"` length-1 via constant recycling).
- Empty `CY_WORKSPACES` init now explicit `CY_WS_ARR=()`.
- `SPLIT_OUT=$(Rscript ...)` wrapped with `||` block so R `stop()` errors reach the operator instead of silent abort.

`/code-check` caught 3 real bugs over the phases:
- Phase 1: silent R-error abort (no operator-visible message)
- Phase 2: empty TARGET_SCHEMA fallback (masked misconfigured `--config=`)
- Phase 1.5: empty `--schemas=` silent fall-through to destructive default

All fixed inline.

## Filed-but-not-closed follow-ups

- **Cypher integration tests** (issue #172 Phase 2 + 3 acceptance) — defer until M4+M1 baseline lands repeatably. Will file as new issue.
- **LPT-fallback empty-bucket edge case** when N_WSGs ≤ N_hosts without prior timing CSVs — pre-existing, not a #172 regression. Surfaces under `--wsgs=DEAD --config=bcfishpass --no-cyphers` (config without timing CSVs).
- **rtj `scripts/cypher/cypher_run.sh` ref** — only a docstring reference at line 8; updated post-merge as part of `/gh-pr-merge` workflow.

Closed by: PR (TBD, branch `172-provincial-run-autonomy-renames`, tag `v0.38.0`).
