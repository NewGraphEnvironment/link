# Task: cypher_prep.sh masks snapshot_bcfp.sh failures via | tail -5 pipeline (pipefail) (#182)

## Problem

`data-raw/cypher_prep.sh:43` uses `set -e` (NOT `set -euo pipefail`). At line 58, `bash snapshot_bcfp.sh 2>&1 | tail -5` masks snapshot failures under `tail`'s exit 0. Same bug at line 67-77 for the `lnk_persist_init` Rscript. The script proceeds past silent failures and prints `=== READY`, leaving the umbrella's downstream marker-grep as the only safety net.

Hit twice in this session (2026-05-15 Peace Tier 2 retry + post-#185 re-spin). Tour-mode (M1 driving cyphers from Europe per rtj#165 RUNBOOK.md) needs loud surface-level failures. Sibling rtj#163 already swept rtj's cypher orchestration scripts for the same bug class — this is the link-side complement.

## Phase 1 — Fix cypher_prep.sh

- [x] Replace `set -e` (line 43) with `set -euo pipefail`.
- [x] Wrap `bash snapshot_bcfp.sh 2>&1 | tail -5` with the tempfile + exit-check pattern. Preserve the tail-5-on-success for back-compat with the umbrella's marker-grep.
- [x] Wrap the `Rscript -e '...lnk_persist_init...' 2>&1 | tail -10` with the same pattern. Same bug class, same fix.
- [x] **Extended scope**: also wrapped `Rscript -e "pak::local_install ..." 2>&1 | tail -3` (third instance of the same anti-pattern, flagged by code-check round 1). Three sites total, all hardened.
- [x] `bash -n data-raw/cypher_prep.sh` syntax-clean.
- [x] `/code-check` clean on staged diff (two rounds — round 1 surfaced the third site, round 2 clean on extended fix).
- [x] Commit `cypher_prep.sh: fail loud on snapshot + persist_init + pak failures (#182)`.

## Phase 2 — Local syntax + dry verification (no cypher spin)

- [ ] `bash -n data-raw/cypher_prep.sh` clean.
- [ ] Visual diff of expected stdout: confirm the last line of cypher_prep's stdout on success still contains `snapshot_bcfp.sh: complete.` so the umbrella's `grep -q` works unchanged.

## Phase 3 — Live verification (deferred to next cypher spin)

Live cypher smoke is the gold standard but adds ~$0.50 + ~5 min overhead and a babysit window. The umbrella's marker-grep check is already proven (fired correctly twice in this session). Cypher_prep's new exit-code path is a strict superset of the old behavior — failure now ALSO surfaces via exit code; success path unchanged.

- [ ] Defer live smoke to next provincial run (the v0.39.1 patch ships before tour; live verification happens organically on the next cypher dispatch from either M4 or M1).

## Phase 4 — Release v0.39.1

- [ ] Update `DESCRIPTION`: `Version: 0.39.0 → 0.39.1`, `Date: 2026-05-15`.
- [ ] Update `NEWS.md` with v0.39.1 entry. Cite rtj#163 as the cross-repo companion fix.
- [ ] Update `CLAUDE.md` branch reference to `v0.39.1`.
- [ ] Commit `Release v0.39.1`.
- [ ] `/planning-archive` with slug `cypher-prep-pipefail`.
- [ ] `/gh-pr-push` opens PR.
- [ ] `/gh-pr-merge` after CI green.

## Validation

- [ ] `bash -n data-raw/cypher_prep.sh` clean
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
