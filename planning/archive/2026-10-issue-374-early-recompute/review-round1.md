# Code review, round 1: link#374 (early recompute), `git diff b24778b9...HEAD`

## Checklist read

- **code-check.md.index, code-check-shell.md.index, code-check-r.md.index, code-check-spatial.md.index:** each read in full.
- **code-check.md:** the prose (not the table rows) of every H3 under `## Mechanisms`. Read in full: "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output", "A guard's scope, escape hatches, and remedies", "A fix lands in one of two callers that share a harness", "Restore the bug and prove the guard fires", "A shared working tree…", "A wrapper's exit is not the work", "Zero-length, empty, and unset…", "The probe is broken before the world is", "Written data outlives the fix" (most of it). Skimmed only: "Serialization loses meaning silently" and "One fact derived twice". None of the "Rules that stand alone", Security, or Spreadsheets/PDFs sections (about 25 headings) were read in full.
- **code-check-shell.md:** read in full: "`wait` with no argument…", "A second `trap … EXIT` replaces the first", "Put cleanup on the EXIT trap, not RETURN", "`for x in $(cmd | grep … || true)`…", "Over Tailscale SSH to a Mac…", "A failed `cd`…", "Parallel writers sharing one output file…", "psql does not interpolate…", "`&` binds to the whole `&&` list…", "On this Mac `stat` and `date` are GNU…" (10 sections). The other 63 or so were not read in full.
- **code-check-r.md:** read in full: "Postgres row order is never fixed…", "`on.exit()` at a script's top level never fires", "A `data-raw/` script must load the source tree…", "`read.delim()` quotes by default…", "testthat counts an uncaught error under `error`…", "A `function(...)` mock hides arguments…", "Rscript reads a script as it runs…", "`sprintf("%g", x)`…", "An `information_schema` lookup…" (9 sections). The other 110 or so were not read in full.
- **code-check-spatial.md:** index only. No full sections were read (about 120 headings), because the diff uses no spatial tooling beyond FWA ltree SQL.

## Probes run (temp dirs only, no database)

- `recompute_landed` and `recompute_ready` from a copy of `study_area_recompute.sh`, with stubbed `.hosts_query`, under macOS `/usr/bin/awk` and bash 5.3. Landing, SKIP, in_flight and dependency blocking all behaved as documented.
- Bash 5.3 `wait -n -p who <listed pid>` ignores an unlisted background job (the scheduler), so `legs_wait` is not disturbed by the new subshell.
- `set -euo pipefail` plus `n=$(awk … missing-file 2>/dev/null | wc -l | tr -d ' ')`: the shell exits 2, which confirms finding 2.

## Findings

- **[fragile] data-raw/recompute_audit.R:71-73, 83, 93: the audit compares two different clocks for remote dependencies.**
  - A remote dependency's landing is `state_utc`, taken from the driver host's `date -u` (`.legs_now`) and truncated to the second.
  - The recompute's start is `log_recompute.date_start = now()`, taken from the database server's clock, which runs in docker inside the colima VM.
  - The only guaranteed margin between them is the job's prologue (about 1.6 s per #260), plus 0 to `RC_POLL` seconds.
  - If the VM clock runs behind the Mac by more than that, which colima does after a host sleep, a correct early start is reported `EARLY`. The run then exits 1 and tells the operator to re-model those groups.
  - If the VM clock runs ahead, a genuinely early start inside the skew window passes, which is the direction the audit exists to catch.
  - Dispatcher dependencies are fine, because both of their times come from the database clock.
  - Fix: compare like with like. The scheduler's own launch epoch in `launched.tsv` is on the same clock as `state_utc`, so use it. Alternatively, record the remote landing time from the database.

- **[fragile] data-raw/study_area_finish.sh:701 (and 704): an unguarded substitution under `set -euo pipefail` can kill the driver before the fallback pool runs.**
  - The line is `n_early=$(awk … "$RC_DIR/launched.tsv" 2>/dev/null | wc -l | tr -d ' ')`.
  - If `launched.tsv` does not exist, awk exits 2, pipefail fails the substitution, and errexit (active, because `run_finish` is called bare) ends the driver inside `run_finish_recompute_early`.
  - The file is missing exactly when the scheduler died at its first step (`mkdir -p` or `: >> launched.tsv` failed, its `return 1`). That is the dead-scheduler case the fallback ("a dead scheduler costs time, never a group") was written for, and in it no group is recomputed at all.
  - Line 704's `find "$RC_DIR" … | cut | .hosts_csv` has the same shape if `RC_DIR` is gone.
  - Lines 694 and 699 (`first=`, `cp`) are already guarded. These two need `|| n_early=0` and `|| done_rc=""`.
  - Verified in a temp shell: exit 2, and nothing after the substitution runs.

- **[fragile] data-raw/study_area_finish.sh:703-711: the fallback can start a second, concurrent recompute of a group the dead scheduler already started.**
  - `left = ALL_WSGS − (groups with a .rc file)`. A group the scheduler launched whose job is still running has no `.rc` yet, so it lands in `left` and `run_recompute_pool` starts it again.
  - The two jobs on one group collide on the `zz_lnk_*_<wsg>` scratch tables and both run the one-way habitat gate.
  - Every one of the scheduler's own return paths waits for its jobs first, so this needs the scheduler subshell itself to die abnormally: a `set -u` error in a helper, a signal to it alone, or OOM.
  - Fix: subtract `launched.tsv` as well, or wait on or kill those pids, before relaunching.

- **[fragile] data-raw/recompute_audit.R:59-62, and its exit status as read at study_area_finish.sh:668-676: the audit can misreport a crash and cannot see failed jobs.**
  - **A crash reads as a verdict.** Any uncaught R error outside the `tryCatch`-wrapped reads (a failed `write.table` to `out_p`, for one) makes Rscript exit 1. The driver maps 1 to "a group started before a group it reads had landed" and prints the re-model remedy, instead of "audit could not run", which is reserved for any other status.
  - **Failed jobs are not audited.** It audits only closed `log_recompute` rows (`date_end IS NOT NULL`). In `wsg_recompute_one.R` the gate commits before the mapping-code rebuild and `.rc_finish`, so a recompute that started early and then failed may already have cleared flags for good, and it is left out of the one check that says the early starts were right.
  - Fix: wrap the body so an unexpected error exits 2, and audit open rows too (use `date_start` regardless of `date_end`).

- **[fragile] data-raw/recompute_deps.R:143-146 and data-raw/study_area_run.sh:1876-1880: an empty dependency map passes the gate, and the scheduler then fails open.**
  - If the FWA query returns no rows, the script writes a header-only file and exits 0. The driver accepts it, because it checks only the exit code and the header, and prints "0 pairs".
  - A zero-row result could come from an empty or wrong `fwa_stream_networks_sp`, or from NULL code columns as in docker fwapg's `fwa_watershed_groups_poly`.
  - The scheduler then treats every landed group as ready at once: the fail-open state the design forbids.
  - Fix: refuse zero pairs, or better, assert that the map has rows for the run's groups that have downstream neighbours.

- **[fragile] R/lnk_persist_init.R:340-346 (`.lnk_view_replace`): the md5 key in the view's comment can go stale.**
  - The key lives in the view's COMMENT, and Postgres keeps a view's comment across `CREATE OR REPLACE VIEW` (same OID, same `pg_description` row).
  - Any writer that replaces `streams_habitat_long_vw` without refreshing the comment leaves the new key on a different definition. Examples: an older link checkout run against the same schema (the frozen-worktree practice in CLAUDE.md), `exp_gradient_extra_breaks.R`'s species subset under old code, or a hand edit.
  - Every later init then sees a matching key and skips the replace for good, so the long view silently serves the wrong species union.
  - Fix: compare a digest of `pg_get_viewdef()` (normalised) instead of a self-written comment, or have the replace path also drop or rewrite the comment unconditionally when it issues DDL.

No issues found in `recompute_landed` or `recompute_ready` (they fail closed on a bad header, another run_uid, an unreadable file or a database that does not answer; `PIPESTATUS` indexes are right). None in the scheduler's stop and orphan handling, `legs_wait`'s interaction with the new background job, the persist and views prep ordering, or the measurement scripts. Two notes on the latter:
- In `recompute_schedule_sim.R`, `land <- c(ld, cl$land)` and `match(size, bucket_n)` would misbehave for a group on two hosts or for two hosts with equal bucket sizes. The replayed 2026-10-23 run has 241 rows for 241 groups (component atoms), so the committed numbers are unaffected.
- `digest_test.R`'s `line_ok` passes vacuously if the `all` variant has no rows for the group. It does not assert `n_all > 0`.

/Users/airvine/Projects/repo/link/planning/active/review-round1.md
