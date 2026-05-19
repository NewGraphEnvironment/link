# Findings — cypher_prep.sh masks snapshot_bcfp.sh failures via | tail -5 pipeline (pipefail) (#182)

## Issue context

`data-raw/cypher_prep.sh` (cypher-side prep script invoked from `wsgs_run_pipeline.sh` Step 4) pipes `snapshot_bcfp.sh` and `lnk_persist_init` Rscript through `| tail -N`. Under `set -e` (no `pipefail`), pipeline exit comes from `tail` (always 0). If the upstream command fails, the script continues to its `=== READY` marker. The umbrella catches it via `grep -q "snapshot_bcfp.sh: complete"` but the failure is opaque on the cypher itself.

## Codebase confirmation (2026-05-15)

- `data-raw/cypher_prep.sh:43` — `set -e` (no `pipefail`).
- `data-raw/cypher_prep.sh:58` — `bash snapshot_bcfp.sh 2>&1 | tail -5` — bug site #1.
- `data-raw/cypher_prep.sh:67-77` — `Rscript -e '...' 2>&1 | tail -10` — bug site #2 (same class).
- `data-raw/snapshot_bcfp.sh:277` — success marker `snapshot_bcfp.sh: complete.`
- `data-raw/wsgs_run_pipeline.sh:264` — `grep -q "snapshot_bcfp.sh: complete"` downstream check.

## Cross-repo context

rtj#163 (commit `a0aef66`, 2026-05-18) swept rtj's `scripts/cypher/{up,down,run,snapshot}.sh` for the same bug class. Motivation was identical: `cypher_up.sh`'s `tofu apply ... | tee -a $LOG` masked DO 422 errors during M1 trip-prep. This issue is the link-side complement — rtj#163 covered the cypher orchestration scripts (which run on M1/M4), this fix covers the cypher prep script (which runs on the cypher itself).

rtj#165 RUNBOOK.md (commit `bfc95d9`, 2026-05-18) documents tour-mode operations: M1 as primary driver, Blink/tmux/iPhone workflow. Loud failure signals are critical when scrolling logs on a phone.

## Bug-class precedent in CLAUDE.md

CLAUDE.md "Shell Scripts → pipefail with ssh+tee" section:

> `set -eu` does NOT propagate exit codes through pipelines. `ssh ... | tee log` returns tee's exit (always 0 for healthy tee), masking ssh failure. Use `set -euo pipefail` for any script that pipes a meaningful command into tee/cat/grep/etc.

`cypher_prep.sh` is the canonical example.

## Fix pattern selected

Option B from issue body (robust variant):
- Capture full output to tempfile.
- On failure: dump full log to stderr + `exit 1`.
- On success: `tail -5 "$TMP_LOG"` to stdout — preserves the umbrella's marker-grep back-compat.

Alternative (option A using `PIPESTATUS[0]`) is shorter but loses the full log on failure. Tour-mode operator needs the full log to diagnose without ssh'ing into a half-broken cypher; option B wins.

## In-session evidence

- 2026-05-15 00:38 PDT (Peace Tier 2 retry) — bcdata openmaps WFS timeout, cypher_prep printed `=== READY`, umbrella correctly aborted at Step 4 grep.
- 2026-05-15 06:08 PDT (post-#185 re-spin) — same transient, same failure mode. Repeat hits in a single session establish this is operational reality, not a one-time fluke.

## Out of scope (filed as follow-ups)

- Bounded retry on snapshot transients (3 attempts, 30s backoff) — issue body documents shape.
- Umbrella ssh exit-code capture (`wsgs_run_pipeline.sh:259-269`) — currently only checks the grep marker.
- Pipefail audit across other `data-raw/*.sh` scripts (mirror of rtj#163's sweep for the link repo).
