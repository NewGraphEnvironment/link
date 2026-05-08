# Task: csv-sync cadence shift + weekly snapshot scheduler templates (#148)

After `db_newgraph#7` shifted the upstream CSV dump to Wed 3 AM PDT, link's downstream csv-sync still fires at Wed 6 AM PDT — a 3-hour gap that makes the bundle stale-by-design for anyone running parity work Wednesday morning. Plus, every snapshot consumer (M4, M1, cypher) currently runs `data-raw/snapshot_bcfp.sh` manually. Without per-host scheduling, weekly tunnel-parity work doesn't survive a vacation week.

This issue does three things:

1. Shift link's csv-sync workflow to Wed 4 AM PDT (1 h after the upstream dump in `db_newgraph#7`).
2. Add an `lnk_baseline_skip_p()` exported function so `snapshot_bcfp.sh` can short-circuit when this host already has a ledger row for the current upstream SHA (avoids redundant snapshots when launchd fires twice per cycle, e.g. after a wake-from-sleep).
3. Ship `data-raw/scheduler/` with launchd plist + cron line + README so each host's install is one copy + `launchctl load` (or `crontab -e`).

## Phase 1 — csv-sync cron shift

**File:** `.github/workflows/sync-bcfishpass-csvs.yml`

- [x] Cron `'0 13 * * WED'` → `'0 11 * * WED'` (Wed 6 AM PDT → Wed 4 AM PDT).
- [x] Header comment update: chain timing reflects upstream dump Wed 3 AM PDT (10:00 UTC) → csv-sync Wed 4 AM PDT (11:00 UTC) → host snapshot Wed 5 AM PDT (12:00 UTC).
- [x] No change to PR-merge logic, drift handling, or `gh pr merge --merge --delete-branch` semantics.

## Phase 2 — `lnk_baseline_skip_p()` (exported)

- [x] `R/lnk_baseline_skip_p.R` with roxygen + runnable `@examples`.
- [x] Mocked tests: latest-row-matches → TRUE; latest-row-mismatches → FALSE; no-host-rows → FALSE; file-missing → FALSE; per-host scoping (M4 stamped, M1 NOT skip); arg-shape validation. 12 expectations across 6 tests, all passing.

## Phase 3 — `snapshot_bcfp.sh` updates

- [x] Self-anchor cwd at repo root (`cd "$(dirname "$0")/.."`) so the cron-default `$HOME` cwd doesn't break the relative ledger path. Found in code-check round 1.
- [x] Skip-if-stamped guard runs FIRST — before env-file source + DB-credential resolution. A host with a stale env file can skip cleanly when this week's ledger already matches. Reordered in code-check round 2.
- [x] Source `~/.config/snapshot-bcfp.env` if present.
- [x] Drop `x` from `set -euxo pipefail` → `set -euo pipefail` to keep credentials out of `~/.local/state/snapshot-bcfp/*.log`. Found in code-check round 2.
- [x] No change to existing `--with-bcfp-views` flag, ledger stamping at end of script.

## Phase 4 — `data-raw/scheduler/` templates

- [x] `com.newgraph.snapshot-bcfp.plist` — macOS launchd template (Weekday=3 = Wed; Hour=5; local time).
- [x] `snapshot-bcfp.cron` — Linux crontab one-liner (`0 12 * * WED` UTC = Wed 5 AM PDT).
- [x] `README.md` — per-host install/uninstall + env file format docs.

## Phase 5 — Validation

- [x] `devtools::test()` 921 PASS / 0 FAIL.
- [x] `lintr::lint_package()` clean on touched files.
- [x] `devtools::check()` — 3 pre-existing WARNINGs unchanged, 0 new from this work.
- [ ] **Manual smoke on M4** (this host): deferred; requires `~/.config/snapshot-bcfp.env` setup + `launchctl load`. Will verify on first scheduled cycle Wed 14 May 2026.
- [x] `/code-check`: round 1 caught cron-cwd bug; round 2 caught xtrace credential leak + skip-guard ordering; round 3 Clean.

## Phase 6 — Release + PR

- [x] DESCRIPTION 0.32.1 → 0.33.0.
- [x] NEWS.md 0.33.0 section.
- [ ] Atomic commit (code + PWF tick).
- [ ] Push, open PR closing #148 with SRED tag.
- [ ] `/gh-pr-merge` → tag v0.33.0.
- [ ] `/planning-archive`.

## Validation

- [x] Tests pass
- [x] `/code-check` clean (3 rounds: round 1 + round 2 surfaced 3 real issues, all fixed; round 3 Clean)
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
