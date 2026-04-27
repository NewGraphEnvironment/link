# Task: Shape fingerprint + halt auto-merge on shape drift (link#64)

`data-raw/sync_bcfishpass_csvs.R` and the daily `sync-bcfishpass-csvs.yml`
GHA cron compare each bcfishpass-sourced CSV against a recorded sha256
**byte** checksum. When upstream changes the file BYTES, an auto-PR
opens and auto-merges. This works for value drift (rows added/edited)
but is **blind to shape drift** — yesterday's `user_habitat_classification.csv`
long→wide reshape (with column type change) passed straight through and
broke link's pipeline downstream (fixed today via fresh#177 + link 0.12.0).

This PR adds a **shape fingerprint** alongside the byte checksum, branches
the sync logic, and surfaces shape drift as a halt-on-merge signal so
downstream consumers don't get silently broken again.

## Goal

```
Drift type            Action
─────────────────────  ─────────────────────────────────────────────
Byte drift, shape ✓    Auto-PR + auto-merge as today
Shape drift            Auto-PR opens, labelled `schema-drift`,
                       NOT auto-merged, GHA exits non-zero
```

Scope:

1. New `shape_checksum` field in the `provenance:` block of each
   bundle's `config.yaml`, computed from each CSV's header line
   (sha256 of the first line, normalized). Catches column rename /
   add / remove / reshape — the dominant failure mode. Type changes
   within stable columns are out of scope (rarer; can extend later).
2. `data-raw/sync_bcfishpass_csvs.R` computes and compares shape
   checksums. On shape drift, sets a flag the workflow reads.
3. `.github/workflows/sync-bcfishpass-csvs.yml` branches: byte-only
   drift → auto-PR + auto-merge as today; shape drift → auto-PR with
   `schema-drift` label, NO auto-merge, workflow exits non-zero
   (red X on Actions tab).
4. `lnk_config_verify()` extended to surface shape drift alongside
   byte drift; new column in the returned tibble.

## Phases

- [ ] Phase 1 — PWF baseline (this file + findings + progress)
- [ ] Phase 2 — Compute shape checksums for all 12 currently-tracked files in both bundles. Add `shape_checksum: sha256:<hex>` field to each entry in `inst/extdata/configs/{bcfishpass,default}/config.yaml`'s `provenance:` block.
- [ ] Phase 3 — Update `data-raw/sync_bcfishpass_csvs.R`: compute shape checksum from each fetched file's header line; compare against recorded; tag drifts as `byte_only` or `shape`. Write `/tmp/sync_summary.md` with per-file drift type. Write `/tmp/sync_drift_kind` (single-line file containing `byte` or `shape` or `none`) for the workflow to read.
- [ ] Phase 4 — Update `.github/workflows/sync-bcfishpass-csvs.yml`: read `/tmp/sync_drift_kind`; on `shape`, label PR `schema-drift`, skip auto-merge, exit non-zero; on `byte`, behave as today; on `none`, exit clean. Test the label step is idempotent (re-runs don't error).
- [ ] Phase 5 — Extend `R/lnk_config_verify.R`: compute shape checksum at runtime (read first line, sha256), compare to provenance's `shape_checksum`, add `shape_drift` column to the returned tibble. Update existing tests + add new test covering shape drift detection.
- [ ] Phase 6 — Tests: extend `test-lnk_config_verify.R` for shape drift. Add a tiny sync-script integration test that simulates the 2026-04-26 reshape (column rename) on a temp dir and confirms shape-drift detection.
- [ ] Phase 7 — `/code-check` on staged diff
- [ ] Phase 8 — Full devtools::test() suite
- [ ] Phase 9 — NEWS entry; version bump 0.12.0 → 0.13.0 (minor — adds provenance field + verify column; pre-1.0 still)
- [ ] Phase 10 — PR (closes #64)

## Critical files

- `data-raw/sync_bcfishpass_csvs.R` — extend with shape fingerprint
- `.github/workflows/sync-bcfishpass-csvs.yml` — branch on drift kind
- `inst/extdata/configs/bcfishpass/config.yaml` — `shape_checksum` field per file
- `inst/extdata/configs/default/config.yaml` — same
- `R/lnk_config_verify.R` — extend with shape checking
- `tests/testthat/test-lnk_config_verify.R` — extend
- `NEWS.md`, `DESCRIPTION` — release artifacts

## Acceptance

- Both bundles' config.yaml `provenance:` blocks have `shape_checksum: sha256:<hex>` for every smnorris-sourced file
- `lnk_config_verify(cfg)` returns a tibble with a `shape_drift` column alongside `drift` (byte) and `missing`
- Local dry-run of `sync_bcfishpass_csvs.R` against current state reports clean (no drift)
- Simulated header rename (e.g., adding a column to a fixture's first line) flips `shape_drift` to TRUE and `/tmp/sync_drift_kind` to `shape`
- Workflow YAML branches correctly on the drift kind file
- All existing tests pass; new tests cover shape detection

## Risks

- **Header-only fingerprint misses type changes within stable columns**: documented limitation. The 2026-04-26 break was both header AND type change, so header-only catches it. A type fingerprint can be added later if a type-only break surfaces. YAGNI for now.
- **First-line whitespace / line-ending differences**: normalize before hashing — strip trailing whitespace, force `\n` line ending. Avoid false drifts from CRLF vs LF or trailing spaces.
- **Workflow drift-flag file mechanism**: relies on `/tmp/sync_drift_kind` being readable by the next step. GHA runners have a shared `/tmp` per job, so this works — verified pattern in the existing workflow file (`/tmp/sync_summary.md`).
- **Concurrent sync runs**: not a real concern since only one workflow run executes at a time per branch (GHA default for `schedule:` and `workflow_dispatch:`).

## Not in this PR

- Type-fingerprint extension (column-level type signature) — file as follow-up issue if a type-only break surfaces
- crate's `lnk_load_overrides()` integration (link#65) — separate PR after crate v0.0.1 ships
- Vignette-tighten resumption — separate PR after this lands (vignette stays in dev/ for now)
