# Task: GitHub Action to sync bcfishpass overrides CSVs (#56)

link ships bcfishpass-curated CSVs under `inst/extdata/configs/{bcfishpass,
default}/overrides/`. These are human-edited upstream — field surveys,
expert reviews, GIS edits — at a cadence of 1-3 PRs per active weekday
in busy periods (April 2026 sample: 18 of 22 weekdays had CSV-touching
PRs). Today nothing pulls those changes; link gradually drifts.

With v0.11.0 provenance, drift is *visible* (`lnk_config_verify()`),
but not yet *closed*. This PR closes the loop: a scheduled GitHub
Action diffs upstream CSVs against the bundled copies, opens a PR
when anything changed, and updates the `provenance:` blocks in both
bundles' `config.yaml` so the new state is fully attributed.

## Cadence decision: nightly Mon-Sat 09:00 UTC

Upstream sample shows 18-of-22 weekdays touch CSVs. Nightly diffs
catch each upstream PR within ~24h, producing a small, traceable
sync PR. Weekly would batch 5-15 changes per PR — harder to review
and trace back to specific upstream PRs. Sundays are essentially
quiet — skip them to save 52 no-op runs/year. 09:00 UTC = 1-2am
Pacific depending on DST. Cron is best-effort; exact-time doesn't
matter.

## Goal

A workflow that, when scheduled or `workflow_dispatch`-triggered:

1. Walks `inst/extdata/configs/bcfishpass/overrides/` and pulls each
   matching file from `https://github.com/smnorris/bcfishpass/data/`
2. Compares sha256 against the recorded checksum in
   `bcfishpass/config.yaml$provenance`
3. For drifted files: writes the new content into BOTH
   `bcfishpass/overrides/` and `default/overrides/`, updates the
   `provenance:` blocks (new `synced` date, new `upstream_sha` —
   per-file via the commit that last touched it, new `checksum`)
4. If anything changed: opens a PR titled
   `csv-sync: bcfishpass <short-sha> <date>` with a summary table of
   changed files. Never pushes to main.
5. If nothing changed: exits 0 silently.

## Scope decisions

- **Both bundles sync identically.** `default/overrides/` mirrors
  `bcfishpass/overrides/` for every sourced file. Manual divergence
  in default would be flagged by `lnk_config_verify()` after sync.
- **Per-file `upstream_sha`** via `gh api repos/smnorris/bcfishpass/commits?path=data/<file>&per_page=1`.
  More accurate than a single repo HEAD sha.
- **R script does the heavy lifting**, workflow shell only orchestrates.
  Reuses `lnk_config()` + `digest::digest()` paths. Keeps logic
  testable locally (`Rscript data-raw/sync_bcfishpass_csvs.R`).
- **No CI verification of the sync PR.** Full `tar_make()` is 15+ min
  and needs DB access — out of scope. Human reviewer runs it.
- **No version bump.** This is infra, not a library API change.
  Existing v0.11.0 doesn't need to roll just because we add a workflow.

## Phases

- [ ] Phase 1 — PWF baseline (task_plan, findings, progress)
- [ ] Phase 2 — `data-raw/sync_bcfishpass_csvs.R` script: walk both bundle override dirs (which share the same files), pull each upstream CSV, sha256-diff, write changes + update both `config.yaml` provenance blocks. Idempotent. Exits 0 if no drift, 0 with `cat /tmp/sync_summary` set if drift, non-zero only on errors.
- [ ] Phase 3 — `.github/workflows/sync-bcfishpass-csvs.yml`: cron `0 9 * * 1-6`, also `workflow_dispatch`. Runs the R script; if working tree is dirty, creates a branch, commits, opens a PR via `gh pr create`. Uses `actions/checkout@v4` + `r-lib/actions/setup-r@v2` + `r-lib/actions/setup-r-dependencies@v2`. Permissions: `contents: write`, `pull-requests: write`.
- [ ] Phase 4 — Local dry-run: run the R script against current state. Expect either zero drift (if everything's current) OR an actionable diff list. Either is success — proves the script works.
- [ ] Phase 5 — Commit workflow + script. Push branch. Trigger via `workflow_dispatch` to validate end-to-end before merge. Capture the workflow run output for the PR body.
- [ ] Phase 6 — `/code-check` on staged diff
- [ ] Phase 7 — Open PR, close #56 via commit message

## Critical files

- `data-raw/sync_bcfishpass_csvs.R` — new
- `.github/workflows/sync-bcfishpass-csvs.yml` — new
- `inst/extdata/configs/{bcfishpass,default}/overrides/*.csv` — possibly updated by first run
- `inst/extdata/configs/{bcfishpass,default}/config.yaml` — possibly updated provenance blocks
- `planning/active/{task_plan,findings,progress}.md` — PWF tracking

## Acceptance

- `Rscript data-raw/sync_bcfishpass_csvs.R --dry-run` lists drift without writing
- `Rscript data-raw/sync_bcfishpass_csvs.R` writes any drifted files + updates provenance blocks
- Workflow `workflow_dispatch` from GitHub UI runs to completion
- If no drift: workflow exits clean, no PR created
- If drift: workflow opens a PR with a clear summary table
- The opened PR's CSV diff matches what the upstream PRs added/changed
- Closes #56 on PR merge

## Risks

- **Concurrent manual edit conflict**: if a human is editing an override CSV when the workflow runs, the PR diff will include both. Reviewer resolves. Acceptable — the PR is reviewed before merge.
- **Upstream rename / delete**: a tracked file disappears upstream. The script should warn but not fail; record `upstream_status: missing` in provenance and let the human decide.
- **Per-file `upstream_sha` rate limit**: 12 files × 1 commit-list call = 12 API calls per run. GitHub's unauthenticated limit is 60/h; authenticated `GITHUB_TOKEN` is 1000+/h. Use the token. Negligible.
- **Workflow runner cost**: GH Actions free tier is 2000 min/mo for private repos; this repo is public so unmetered. Runs are <1 min each.
- **Auto-syncing default bundle when defaults intentionally diverge**: today they don't. If/when default overrides diverge from bcfishpass, the script will need a per-file sync flag in `default/config.yaml`. Not an issue now; document as a future-extension.

## Not in this PR

- Full pipeline rerun on the sync PR (cost + DB access; out of scope)
- Auto-sync of non-bcfishpass-sourced files (none today)
- Per-file divergence flags for `default` bundle (no current divergence)
- A second workflow that runs `tar_make()` on the sync branch — file as follow-up if reviewers find the human-only verification too slow
