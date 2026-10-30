# Code-check round 2 — link#274 (HEAD df08c728, base 9ae7be27)

## Checklist read

- **code-check.md**: the prose of all 14 H3s under `## Mechanisms`, table rows skipped (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice). Not read: the 18 standalone, Security and Spreadsheets/PDFs headings.
- **code-check-r.md**: read in full: `system2(stdout = TRUE)` warns on a non-zero exit…; `read.delim()` quotes by default…; `data.frame()` recycles a scalar against a zero-length column; `strsplit()` drops a trailing empty field…; Postgres row order is never fixed unless the query fixes it…; `$` on a list partial-matches…; `match()` treats NA as a matchable VALUE…; A `data-raw/` script must load the source tree…; `on.exit()` at a script's top level never fires. About 140 headings not read.
- **code-check-shell.md**: read in full: `wait` with no argument waits for every background job in the shell; A `local` statement cannot read a variable it is assigning in the same statement; Over Tailscale SSH to a Mac, `ssh` exits 0…; A failed `cd` lets every later command run…; macOS `/usr/bin/awk` aborts when a regex meets a byte slice…; psql does not interpolate `:'var'`…; A second `trap … EXIT` replaces the first. About 95 headings not read.
- **code-check-spatial.md**: none applicable (no spatial code in the diff); all headings not read.

## What was checked

- **Round-1 fix 1** (`facts` with 0-row `last`): ran the exact construction with a 0-row `last`. It builds a 0-row frame, and `readers_classify()` returns `no_log` for the reader. With an NA `link_sha`, `pc[last$link_sha]` gives NA, so the reader is refused with `sha_unresolvable`. Inside the fix: clean.
- **Round-1 fix 2** (`dispatcher_fresh_dirty`): `lnk_stamp()` returns `software$fresh$dirty`, from `.lnk_pkg_git_state()`: TRUE, FALSE or NA. `identical(…, FALSE)` refuses on NA as well as TRUE, so it fails toward refusal. Inside the fix: clean.
- **An empty CLI argument (`COV_MISSING` empty, the usual case) reaches Rscript:** `commandArgs()` keeps `""`, so `length(args) == 8` holds.
- **`wait "$RC_DEPS_PID"` in at-end mode after `legs_wait`'s `wait -n -p who <pids>`:** measured on bash 5.3.9. An unlisted job that finished earlier keeps its status for a later `wait <pid>` (it returned 7 as set).
- **Early mode:** the scheduler's final set, the fallback pool, `fanout_judge.R` and `recompute_audit.R` all accept outside readers. The audit skips a dependency outside `run_wsgs.tsv` and checks a reader's run dependencies against its final launch. `recompute_order` keeps groups with no prior time.
- **`lnk_wsg_downstream_check()`** issues no DDL, so the dry run beside the early scheduler takes no locks. It is the same call as `wsg_recompute_one.R`'s, with `on_fail = "warn"`.
- **`run_coverage`** partitions `RUN_WSGS` exactly into `COV_RECOMPUTE` and `COV_MISSING`, so a reader cannot pass while it reads an unfinished run group.
- **The verifier changes:** 6h and 6i run against the live run (`verify_negative_run2.out`).
- **The three changed test files pass** in a worktree (57 / 277 / 62, 0 fail, 0 error).

## Clean
No issues found.
