## Checklist read

Read the prose of the Mechanisms headings in code-check.md (guard fails toward pass, wrapper's exit, zero-length/unset), and the code-check-shell.md headings for `&` backgrounding, `local`, `set -e`/`||` contexts, `wait`, `if ! cmd; rc=$?`, arrays under `set -u`, Tailscale ssh exit codes, and `pgrep`/ps waiters. Read code-check-r.md for `on.exit`, `nzchar`, `Rscript -e`. Read the full diff of the shell and R driver edits and grepped every caller of each driver (data-raw, tests, R, .github, RUNBOOK). Nothing was executed.

## Findings

Checked and found sound (no finding):
- Every caller of `wsg_run_one.R`, `wsg_recompute_one.R`, `study_area_wsgs.R`, `barriers_views_build.R`, `host_stamp.R` and `study_area_compare.R` passes a config, including the ssh legs and the printed re-model commands.
- `study_area_run.sh` exports `LNK_RUN_UID` (line 625) and `LNK_RUN_LABEL` before every local and remote leg, and `REMOTE_LEG_VARS` carries both across ssh. The `recompute_one` pool in `recompute_parity.sh` and `recompute_sweep.sh` has no uid, and both scripts export a label. `pretest_run.sh` sets `LNK_RUN_LABEL=pretest`.
- `study_area_run.sh` exports `LNK_SCHEMA` before the barrier-view build and the recompute, so the new `LNK_SCHEMA` guards do not trip there.
- `cypher_prep.sh` takes the config guard only at `STAGE=all`, and the main cypher prep call passes `CYPHER_PREP_CONFIG`.
- No kept script, test, workflow or `pretest_inputs.csv` row references any of the nine deleted scripts.
- `lnk_pipeline_species(..., paused = TRUE)` exists.
- `VINT_OUT`/`VINT_RC` are assigned in `preflight_local`, which is called as `preflight_local || ...` with no subshell. The assignment is global and the variable is initialised, so there is no `set -u` problem. The `if A=$(...); B=$?; \ printf; [ ]` form is a valid compound condition.
- The moved `PRETEST_NOTE` block uses only `SCHEMA`, `CONFIG`, `RUN_SHA` and `RUN_UID`, all set before it. Moving it after bucket resolution is safe, and nothing spends between the two positions.
- `--tables=` validation is anchored to lower-case `schema.table`, so no quote or semicolon can reach the SQL. An empty value is refused.
- `PGPASSWORD=postgres drop_start ...` is a function-call prefix assignment. In non-POSIX bash it is visible inside the function and inherited by the backgrounded subshell, so psql gets it.
- `DROP_PIDS` is never empty, so `${!DROP_PIDS[@]}` is safe under `set -u`.

### 1. fragile: state_clean.sh:137 (step 1 kill pattern)
`ps -ef | grep -E "study_area_run|cypher_run|ssh.*cypher@|..." | ... xargs kill -9` replaced `wsgs_dispatch|wsgs_run_host` with `study_area_run`. In full mode and in `--schemas=` mode (which the header says is for "per-bundle pre-cleans before subset dispatches"), this now SIGKILLs any live `study_area_run.sh`, and any process whose command line merely contains the string, such as a `tail` of its log or another session's `--preflight-only`.

A `kill -9` on the driver skips its EXIT trap, so a driver that has spun cloud droplets leaves them running and billing, with no burn. The legacy dispatcher it replaced did not have that exposure. `--tables=` skips the kill, but the other two modes keep it.

Suggest at least refusing, as the `--tables=` branch does, when a `study_area_run.sh` is live, rather than killing it.

**Rule:** code-check.md, "A guard that fails toward pass" (a destructive default widened by a pattern swap).

### 2. fragile: study_area_run.sh:1752 (preflight-only hint)
The hint still prints `bash data-raw/study_area_run.sh --preflight-only --cy-workspaces=job1,job2,job3` with no `--config=`. Pasted as printed, it now exits 1 at the new config guard.

**Rule:** none.

### 3. fragile: study_area_run.sh preflight-only block (~1731-1741)
`--preflight-only` now runs `study_area_wsgs.R` (a database connection) and writes `$LOG_DIR/${TS}_decisions.txt`, after the script's own comment promises no writes. It also omits `${WSGS_FLAG[@]}`, so with `--wsgs=` the decision block reports a different resolution from the real run.

A resolution failure now turns a passing preflight into `FATAL ... could not be resolved`. This is only an inaccuracy of the preview, not data loss.

**Rule:** code-check.md, "A proxy is not the property" (the preview resolves a different set from the run it previews).

### 4. fragile: state_clean.sh --hosts= validation (line ~205)
The regex `^[A-Za-z0-9_.@-]+$` admits an entry starting with `-` (for example `-v` or `-Fx`), which is passed to `ssh "$h"` as an option. The input is operator-typed, so the risk is low. Rejecting a leading `-` or passing `--` would close it.

**Rule:** none.

No data-loss or security bugs found in the diff beyond the above.
