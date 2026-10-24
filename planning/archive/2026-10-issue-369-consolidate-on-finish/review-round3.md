# Code-check round 3: branch 369 (`git diff 102762da...HEAD`)

## Checklist read

- `index_code-check.md`, `index_code-check-shell.md`, `index_code-check-r.md`,
  `index_code-check-spatial.md`: in full.
- `code-check.md`: every H3 under `## Mechanisms` in full (14, table rows skipped).
  "Rules that stand alone", Security, Spreadsheets: index only (21 headings not read in full).
- `code-check-shell.md`: read in full: "`wait` with no argument…", "`if ! cmd; then rc=$?`…",
  "A second `trap … EXIT`…", "A `local` statement…", "Parallel writers sharing one output
  file…", "`grep -c` prints…", "Put cleanup on the EXIT trap…", "A failed `cd`…", "`exit`
  inside a loop condition…", "`&` binds to the whole `&&` list…" (10). The other ~70: index only.
- `code-check-r.md`: read in full: "An `information_schema` lookup by the literal table
  name…", "Rscript reads a script as it runs…", "`system2(stdout = TRUE)` warns…", "A
  `data-raw/` script must load the source tree…" (4). The other ~150: index only.
- `code-check-spatial.md`: index only. Nothing in this diff is spatial.

Probes run (no database, no repo writes), in
`/private/tmp/claude-501/-Users-airvine-Projects-repo-link/b98a6efd-d5c8-44bf-bef3-9937b0e4ac75/scratchpad/r3/`:
- `waitn.sh` (bash 5.3.9). A leg that ended while the main shell made 0, 200 or 3000
  forks, a process substitution and a foreground subshell is still returned at once
  by `wait -n -p who A B` (rc 3, `who`=A). So a cypher whose leg ends during another
  host's consolidate is not lost behind the dispatcher's still-running pid.
- `t.R`. `.lnk_read_git_head()` with a relative `gitdir:` pointer: NULL when cwd is
  not the worktree root, the SHA when it is (see the finding).

## Mechanism

**The shared assumption.** Each step read shared state at a point that the old fixed
sequence made safe, and nothing checked it. The sequence was: every leg ends → account
every host → back up → consolidate every host in one call → burn. The state read was the
dispatcher's database (its log rows, persist tables and catalog locks), the per-host maps
and flags, the state and kept records, and `wait`'s answer. Each read silently required
that a known set of writers had already finished and that no other writer was active.
#369 breaks the sequence in three ways:
- Account, consolidate and burn now run per host in the middle of the legs.
- Init and backup now run before the legs.
- The legs are waited on as a set in the order they end, not one by one.

So every read now happens at a different time relative to the other actors, and the
precondition it depended on is false. Fixes 1, 2, 3 and 5 are this:
1. `wait -n` over a set can report no job.
2. "Leg done" was set before the step that defers the host.
3. The destination's table set now reflects earlier builds, not this run's first group.
5. The dispatcher's log now holds rows the cyphers copied in.

Fix 4 is the same assumption about a different resource. The stamp assumed one checkout,
with HEAD and refs side by side. The run-from-a-worktree rule (keeping edits away from a
running driver) breaks that.

**Every place the mechanism reaches in this diff:**

| # | Read / step, and what moved | Status |
|---|---|---|
| 1 | `legs_wait`: one `wait pid` per leg in a fixed order became `wait -n -p` over the set. `who` is unset on a no-job return; a pid that was already returned is returned again (5.3); an ended job is reaped during a long consolidate. | Handled. Fix 1 plus removal from the pending list. The probe above shows a job reaped mid-consolidate is still returned. No signal other than EXIT is trapped, so the >128 path cannot arise. |
| 2 | `CY_LEG_DONE` is read by a burn in the middle of the run, which now runs before later legs end. | Handled. Fix 2: set in `host_finish_leg`, after deferral. |
| 3 | `consolidate_missing_persist`: the destination's tables used to have been created by the dispatcher's groups; now consolidate can run before the first group does. | Handled. The driver initialises the persist before dispatch, and the core-only refusal is fix 3. |
| 4 | `host_account dispatcher` reads dispatcher log rows; it now runs after the cyphers' copies. | Handled. Fix 5. It keys on `CY_CONS_STATE` being non-empty, so a copy that failed after the log tables landed (tables copy in alphabetical order, `log*` before `streams*`) and a no-outcome copy are both excluded. Overlap groups (in `expected`) stay credited. For a failed overlap copy, `CONS_EXCLUDED` and `CONS_FAILED` still make the run incomplete and keep those groups out of the recompute. |
| 5 | Consolidate's copy check used to count whole tables; the dispatcher now writes the same tables during the copy. | Handled. Bucket-only `count_sql`, and the bucket is disjoint from the dispatcher's (overlaps deferred, row 7). |
| 6 | No-op DDL (`ADD COLUMN IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`) in the dispatcher's per-group `lnk_persist_init` and in consolidate's step 0 `.lnk_log_create_tables` now runs beside the other side's COPY or DELETE. | Handled. Columns and indexes are read from the catalog first. What is left (`CREATE TABLE/SCHEMA IF NOT EXISTS`, and `CREATE OR REPLACE VIEW streams_habitat_long_vw`, which takes ACCESS EXCLUSIVE on the view only and ACCESS SHARE on the tables) does not conflict with ROW EXCLUSIVE. Log tables keyed by config (`log_parameters_*`) have no `watershed_group_code`, so consolidate never copies them, and there is no cross-session key collision. |
| 7 | A group in both buckets used to be copied only after every write to it; it can now be copied while the dispatcher is writing it. | Handled. Rule 3 deferral. Cypher-to-cypher overlaps: `consolidate_newer_on_dest` picks the build that started later whatever the copy order, so the shipped data does not depend on order (only which host is refused and kept does). |
| 8 | Dispatcher model-time reads of other groups' persisted barriers (cross-WSG views, downstream walk) can now land between a consolidate's DELETE and COPY. | Handled by the post-consolidate recompute, not by code in this diff. Model-time habitat sees only the AOI's breaks; `LNK_HABITAT_GATE=0`; the recompute rewrites access and mapping code and gates. RUNBOOK §8d says so. It relies on the recompute covering every run group (#274 must not narrow that). |
| 9 | The backup used to be taken inside the consolidate, after the dispatcher wrote; it is now taken before any write, in the background beside prep. | Handled. The driver waits on `BACKUP_PID` and reads the rc file before dispatch, and fails closed if the file is missing. The refresh runs earlier (line 1241). The cyphers' prep does not touch the dispatcher DB. The bare `wait` on prep that would have waited on the backup is gone. |
| 10 | `CONSOLIDATING` changed from a 0/1 flag over every source to the name of the host. | Handled. The init value `0` is never a workspace name. The trap reads the copying host as unsettled and the rest by `CY_RUN_RC` (unset until reaped, so the read is conservative). |
| 11 | The consolidate state record used to be written once for every source and is now rewritten per host, so a host not yet reached has no rows. | Handled. Writing `in_flight` before the copy fails closed. A bare `--recompute-only` after a kill finds the unreached host's groups missing through the log and coverage, not through the record. Both headers are read. |
| 12 | `CONS_FAILED` / `CONS_EXCLUDED` used to be reset by the single call; they are now accumulated per host. | Handled (`only` argument; `.legs_no_outcome` and `state_unwritten` add to them). |
| 13 | `run_wsgs_write` and the kept-hosts report now run mid-run with only some hosts accounted or ended. | Handled. A missing SKIP reads `unknown` until accounted. The kept file only grows, since an ended kept host is never burned later; the trap and the final burn write the full set. |
| 14 | Consolidate's R program and `schema_consolidate.R` are now loaded at each host's leg end, through the run, rather than once at the end. | Same exposure as before, spread over more of the run. Covered by the existing "run from a worktree / touch nothing" rule. The dirty predicate excludes `data-raw/logs`, where the new per-host logs land. |
| 15 | The stamp reads HEAD and refs, and the run now goes from a worktree. | Handled for absolute `gitdir:` pointers (fix 4, which also reads `packed-refs`). Not handled for relative pointers (finding below). |
| 16 | The dispatcher's statements under the 30 min bound now run beside a bulk COPY and DELETE of a whole cypher bucket into the same tables: I/O contention, dead tuples, stale planner statistics until autovacuum. | Unhandled and unmeasured. No lock wait is left, so this is a load and plan risk, not a correctness defect: a slow plan now fails the group instead of finishing. Run A's `phases.tsv` and `TIMEOUT` lines are where it would show. Not a finding. |

## Findings

- **[severity: fragile]** `R/lnk_stamp.R:510-514`: `.lnk_read_git_head()` reads `gitdir:`
  from a worktree's `.git` file. When the path is relative it is used as is, so it
  resolves against R's working directory, not the `.git` file's directory. Relative
  pointers come from `git worktree add --relative-paths` / `worktree.useRelativePaths`
  (git ≥ 2.48; this machine has 2.50.1) and from submodules. Probed: a relative pointer
  returns the SHA only when cwd is the worktree root, and NULL from anywhere else. The
  driver happens to run R from `REPO_ROOT`, and `.lnk_pkg_git_lookup()` tries
  `pkg_dir/.git` first, so link's own SHA survives. `.lnk_checkout_sha()` for
  fwapg/bcfishobs reads `~/Projects/repo/<repo>/.git` from link's cwd, so a relative
  worktree there would log `fwapg_sha` / `bcfishobs_sha` NULL. This is the class fix 4
  closed for absolute pointers, and it predates this diff. It is not reachable today: the
  live worktree's pointer is absolute and `useRelativePaths` is unset. The one-line
  remedy is to resolve a relative `gitdir` against `dirname(git_path)`.

Nothing else. Every place the mechanism reaches is handled, except row 16 (unmeasured,
not a defect) and the finding above.
