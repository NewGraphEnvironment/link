# PR #60 — daily bcfishpass CSV sync workflow (#56)

**Outcome:** GitHub Action runs daily at 09:00 UTC (with manual
`workflow_dispatch`), diffs every bcfishpass-sourced override CSV
against the recorded provenance checksum, and opens + auto-merges a PR
when upstream has moved. Both `bcfishpass` and `default` bundles
update identically (they share files byte-for-byte). Zero review
burden — the PR exists for discoverability (history + revert), not
review.

**Implementation:** R script (`data-raw/sync_bcfishpass_csvs.R`) does
the heavy lifting via `gh api` (contents endpoint with git-blob
fallback for >1MB files), targeted YAML editing that preserves
comments. Workflow YAML (`.github/workflows/sync-bcfishpass-csvs.yml`)
orchestrates the branch + PR + auto-merge. Required a one-time repo
setting flip (`Settings → Actions → General → Allow GitHub Actions to
create and approve pull requests`) — set via `gh api -X PUT
repos/<owner>/<repo>/actions/permissions/workflow`.

**Validation:** First `workflow_dispatch` after merge produced PR #61,
auto-merged in 4 minutes, syncing 5 drifted files (provenance blocks
in both bundles updated; `lnk_config_verify()` clean post-pull).

**Caveat (documented in workflow header):** PRs created by
`GITHUB_TOKEN` don't trigger downstream workflows. Today there's no
R-CMD-check workflow so this is benign. If added later, switch to a
PAT or run checks within this workflow before merging.

**Closing commit:** `57fa8d1` (merge of PR #60). The first auto-sync
PR was #61 (merge commit `57fa8d1`'s child `f2a088a`).

**Closes:** #56
