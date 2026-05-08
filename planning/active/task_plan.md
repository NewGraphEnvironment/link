# Task: csv-sync cadence shift + weekly snapshot scheduler templates (#148)

After `db_newgraph#7` shifted the upstream CSV dump to Wed 3 AM PDT, link's downstream csv-sync still fires at Wed 6 AM PDT — a 3-hour gap that makes the bundle stale-by-design for anyone running parity work Wednesday morning. Plus, every snapshot consumer (M4, M1, cypher) currently runs `data-raw/snapshot_bcfp.sh` manually. Without per-host scheduling, weekly tunnel-parity work doesn't survive a vacation week.

This issue does three things:

1. Shift link's csv-sync workflow to Wed 4 AM PDT (1 h after the upstream dump in `db_newgraph#7`).
2. Add an `lnk_baseline_skip_p()` exported function so `snapshot_bcfp.sh` can short-circuit when this host already has a ledger row for the current upstream SHA (avoids redundant snapshots when launchd fires twice per cycle, e.g. after a wake-from-sleep).
3. Ship `data-raw/scheduler/` with launchd plist + cron line + README so each host's install is one copy + `launchctl load` (or `crontab -e`).

## Phase 1 — csv-sync cron shift

**File:** `.github/workflows/sync-bcfishpass-csvs.yml`

- [ ] Cron `'0 13 * * WED'` → `'0 11 * * WED'` (Wed 6 AM PDT → Wed 4 AM PDT).
- [ ] Header comment update: chain timing reflects upstream dump Wed 3 AM PDT (10:00 UTC) → csv-sync Wed 4 AM PDT (11:00 UTC) → host snapshot Wed 5 AM PDT (12:00 UTC).
- [ ] No change to PR-merge logic, drift handling, or `gh pr merge --merge --delete-branch` semantics.

## Phase 2 — `lnk_baseline_skip_p()` (exported)

New `R/lnk_baseline_skip_p.R`. Reuses `lnk_baseline_read()` + `lnk_bucket_log()`.

**Signature:**
```r
lnk_baseline_skip_p(
  log,
  host = Sys.info()[["nodename"]],
  path = "data-raw/logs/bcfp_baselines.csv"
)
```

**Behaviour:**
- Read ledger at `path` via `lnk_baseline_read()`. Filter rows where `host == <this host>`.
- If no rows for this host → return `FALSE` (snapshot should run).
- Take latest row by `run_started_pdt`. If `bcfp_model_version` equals `log$model_version`, return `TRUE` (skip).
- Else `FALSE`.
- Per-host scoping is the load-bearing piece — M4 having stamped this week's SHA must NOT prevent M1 from running (each host populates its own local fwapg).

**Tasks:**

- [ ] `R/lnk_baseline_skip_p.R` with roxygen + runnable `@examples` using bundled fixture.
- [ ] Mocked tests: latest-row-matches → TRUE; latest-row-mismatches → FALSE; no-host-rows → FALSE; file-missing → FALSE.

## Phase 3 — `snapshot_bcfp.sh` updates

**File:** `data-raw/snapshot_bcfp.sh`

- [ ] **Optional env file source** at script top: `[ -f ~/.config/snapshot-bcfp.env ] && source ~/.config/snapshot-bcfp.env`. Provides `DATABASE_URL` or `PG*` vars per host without baking secrets into the tracked plist/cron template.
- [ ] **Skip-if-stamped guard**, after env resolution but before any data loads:
  ```bash
  SKIP=$(Rscript -e "cat(link::lnk_baseline_skip_p(link::lnk_bucket_log()))")
  if [ "$SKIP" = "TRUE" ]; then
    echo "snapshot_bcfp: ledger row for $(hostname) already at this upstream SHA; skipping."
    exit 0
  fi
  ```
- [ ] No change to existing `--with-bcfp-views` flag, ledger stamping at end of script, or other behaviour.

## Phase 4 — `data-raw/scheduler/` templates

New directory.

- [ ] `com.newgraph.snapshot-bcfp.plist` — macOS launchd template. `StartCalendarInterval` = Wed 5:00 AM **local time** (launchd's calendar interval is local). `WorkingDirectory` placeholder for the repo path. `StandardOutPath` / `StandardErrorPath` → `~/.local/state/snapshot-bcfp/<date>.log`.
- [ ] `snapshot-bcfp.cron` — Linux crontab one-liner: `0 12 * * WED bash <repo-path>/data-raw/snapshot_bcfp.sh >> ~/.local/state/snapshot-bcfp/$(date +\%Y-\%m-\%d).log 2>&1`. (`0 12 UTC` = Wed 5 AM PDT.)
- [ ] `README.md` — per-host install:
  - macOS: copy plist → `~/Library/LaunchAgents/`, edit `WorkingDirectory`, `launchctl load <path>`, smoke-test with `launchctl start com.newgraph.snapshot-bcfp`.
  - Linux: `crontab -e`, paste the cron line, edit the repo path.
  - Both: create `~/.config/snapshot-bcfp.env` with `DATABASE_URL=...` (or `PG*` vars) — single example block.
  - Uninstall: `launchctl unload ...` / `crontab -e` removal.

## Phase 5 — Validation

- [ ] `devtools::test()` clean (covers new `lnk_baseline_skip_p` tests).
- [ ] `lintr::lint_package()` clean on touched files (don't re-flag pre-existing).
- [ ] `devtools::check()` — confirm 3 pre-existing WARNINGs unchanged, no new ones from this work.
- [ ] **Manual smoke on M4** (this host): copy plist, edit `WorkingDirectory`, `launchctl load`, `launchctl start com.newgraph.snapshot-bcfp`. Verify: log written to `~/.local/state/snapshot-bcfp/<date>.log`, ledger gains a fresh row, second invocation hits the skip path and exits early with the warning.
- [ ] `/code-check` round 1 on staged diff (skill spec rounds 2+3 conditional on findings).

## Phase 6 — Release + PR

- [ ] DESCRIPTION 0.32.1 → 0.33.0 (minor — new `lnk_baseline_skip_p` export).
- [ ] NEWS.md 0.33.0 section.
- [ ] Atomic commit (code + PWF tick).
- [ ] Push, open PR closing #148 with SRED tag.
- [ ] `/gh-pr-merge` → tag v0.33.0.
- [ ] `/planning-archive`.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
