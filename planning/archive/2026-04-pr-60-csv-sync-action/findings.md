# Findings — #56 CSV sync workflow

## Upstream churn (sample, last 60 PRs to bcfishpass)

| date range | CSV-touching PRs/day |
|---|---|
| 2026-04-20 to 2026-04-24 (5 weekdays) | 1, 1, 3, 1, 5 |
| 2026-03-30 to 2026-04-08 (8 weekdays) | 1, 2, 1, 0, 0, 0, 0, 2, 2 |
| 2026-03-13 to 2026-03-27 | 4, then 2-week gap |

Active periods average 1-3 CSV-touching PRs/weekday. Sundays have
near-zero activity. `user_habitat_classification.csv` is the
dominant target — touched in nearly every CSV PR.

Picking nightly Mon-Sat over weekly: each sync PR maps to ~1 upstream
PR (much easier to review/trace) at the cost of more total PRs (~250
vs ~52/year). Cron is free; review burden is *lower per PR* with
nightly even though there are more.

## Files to track

`inst/extdata/configs/bcfishpass/overrides/` currently has 16 files;
12 of them have provenance entries. The 4 not yet provenanced are
likely either link-internal (cabd_*, dfo_*, wcrp_*) or legacy
(`user_modelled_crossing_fixes_20240825.csv`).

For this PR, sync only files that have a `provenance:` entry with
`source: https://github.com/smnorris/bcfishpass`. That's the
authoritative scope contract — if it's provenanced as bcfishpass-
sourced, sync it. Anything else is left alone.

bcfishpass-sourced provenanced files (per
`bcfishpass/config.yaml$provenance`):

- overrides/user_habitat_classification.csv
- overrides/user_modelled_crossing_fixes.csv
- overrides/user_pscis_barrier_status.csv
- overrides/pscis_modelledcrossings_streams_xref.csv
- overrides/user_barriers_definite.csv
- overrides/user_barriers_definite_control.csv
- overrides/user_crossings_misc.csv

Plus:

- overrides/user_habitat_classification.csv
- (in `default/config.yaml` — same set)

7 files × 2 bundles. But since `default` overrides are byte-identical
to `bcfishpass` overrides today (verified via `diff -r`), the script
only needs to fetch each file once and write to both paths.

## Upstream URL pattern

Raw content: `https://raw.githubusercontent.com/smnorris/bcfishpass/<sha>/data/<file>`

Latest: `https://raw.githubusercontent.com/smnorris/bcfishpass/main/data/<file>`

For per-file commit lookup:
`gh api repos/smnorris/bcfishpass/commits?path=data/<file>&per_page=1`
returns the most recent commit touching that path. The `sha` field
goes into `provenance.<file>.upstream_sha` (use short 7-char sha to
match existing format).

## YAML editing approach

Both bundles' `config.yaml` files have a `provenance:` block. We
need to update three keys per drifted file: `synced` (today's date),
`upstream_sha` (latest commit short sha), `checksum` (new sha256).

Round-tripping YAML in R via the `yaml` package will reformat the
file (loses comments, may reorder keys). To preserve the existing
hand-formatted structure, use targeted text editing:

```r
# Replace: `    upstream_sha: ea3c5d8`
# With:    `    upstream_sha: <new_sha>`
```

This is what the script does — pure regex replacement on three
specific lines per drifted file. Comments + ordering preserved.

## R-vs-bash for the sync script

R wins because:

- We already use `digest::digest()` for the same sha256 computation in `lnk_config_verify()` — single source of truth
- `lnk_config()` parses the manifest cleanly; we get the file list and current checksums for free
- yaml package reads the manifest; can iterate provenance entries declaratively
- `httr` or just `download.file()` does the fetch
- jsonlite parses `gh api` JSON output

bash + jq + sha256sum + curl + yq would also work, but in this repo
where R is the lingua franca, R is more maintainable. R script tested
locally, then GH Actions just `Rscript`s it.

## Workflow shape

```yaml
name: sync-bcfishpass-csvs
on:
  schedule:
    - cron: '0 9 * * 1-6'  # 09:00 UTC Mon-Sat
  workflow_dispatch:

jobs:
  sync:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
      - uses: r-lib/actions/setup-r@v2
      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          packages: |
            digest
            yaml
            jsonlite
      - name: Run sync
        run: Rscript data-raw/sync_bcfishpass_csvs.R
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      - name: Open PR if changes
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          if [[ -z "$(git status --porcelain)" ]]; then
            echo "No drift — exiting clean"
            exit 0
          fi
          BRANCH="csv-sync/$(date -u +%Y%m%d)"
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git checkout -b "$BRANCH"
          git add inst/extdata/configs/
          git commit -m "csv-sync: pull bcfishpass overrides $(date -u +%Y-%m-%d)"
          git push -u origin "$BRANCH"
          gh pr create --base main --head "$BRANCH" \
            --title "csv-sync: pull bcfishpass overrides $(date -u +%Y-%m-%d)" \
            --body-file /tmp/sync_summary.md
```

The R script writes `/tmp/sync_summary.md` (a markdown table of
changed files + their old/new sha) for the PR body.

## Failure modes

- **Upstream unreachable / `gh api` 404**: workflow fails loudly. Visible in Actions tab; no false-positive PR.
- **Upstream renamed/removed a file**: R script skips it with a warning, doesn't crash. Provenance entry is left alone — flagged by `lnk_config_verify()` later.
- **`GITHUB_TOKEN` rate limit**: 1000 calls/h authenticated. We make ~14 calls/run (7 files × 2 calls each: raw fetch + commit list). Far under limit.
- **Concurrent manual PR conflict**: workflow's PR will conflict with main; human resolves on review. Acceptable.
- **GitHub API change**: `commits?path=` endpoint is stable; no concern.

## Local testing

```r
# In link/ root
Rscript data-raw/sync_bcfishpass_csvs.R --dry-run  # report drift, no writes
Rscript data-raw/sync_bcfishpass_csvs.R            # write changes
git diff inst/extdata/configs/                       # inspect
git checkout -- inst/extdata/configs/                # revert if testing
```

Dry-run mode is for CI of the script itself + ad-hoc developer use.
