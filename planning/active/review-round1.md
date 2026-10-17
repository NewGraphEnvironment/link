# Code-check round 1 — branch 347-study-area-run-sh-counts-finished-groups

Reviewer: subagent, 2026-10-17. Scope: `git diff <merge-base>...HEAD` plus the context code named in
the brief. `tests/testthat/test-study_area_hosts.R` run with `NOT_CRAN=true`: 66 pass, 0 fail,
0 error, 0 skip.

Checked and found sound: every exit path after the spin (pre-dispatch aborts burn everything; from
dispatch on, `CY_HOLD=1` keeps every cypher on abort, consolidate failure and coverage FATAL; a failed
burn is kept and retried by the trap); `burn_cyphers` runs under `||` from `on_exit` and from the
explicit call, so `set -e` cannot abort it; `host_release` runs at top level with `set -e` live, but the
only thing that could fail there leaves `CY_HOLD=1`, which is the safe side; the `wait ... || {
CY_RUN_RC=$?; }` capture is right; the sentinel awk refuses truncated, empty, doubled or non-code
output; the psql script goes over stdin, so SCHEMA / RUN_UID / WSG lists never pass through a remote
shell; `schema_consolidate`'s source DELETE is per bucket, covers only `copied_tables`, and runs only
after a COPY that raised the row count; `persist_init` sizes tables to `cfg$species` on both sides, so
source-only tables do not arise in a normal run; the final `[ ] && [ ] && HOSTS_KEPT=1` list does not
trip errexit.

## Findings

- **[severity: bug]** data-raw/study_area_hosts.sh:162-163 (`host_account`), :206-209 (`host_release`),
  :311 (`hosts_kept_report`), plus the recovery text at :320-322, data-raw/study_area_run.sh:1563-1568 and
  RUNBOOK.md:1241-1244. For most kept reasons, the `groups` column in `<TS>_kept_hosts.tsv` lists groups
  that were **already consolidated and deleted from the host**. Following the printed recovery steps on
  those groups then deletes them from the dispatcher.
  - `CY_UNCONS` is set at accounting to finished ∪ log `done`. That is the same set
    `host_consolidate_bucket` hands to consolidate.
  - `host_release` replaces it with the measured leftovers only in the "streams rows left" branch.
  - In the "dispatch session exited N" and "database did not answer after consolidate" branches, the
    TSV and banner still carry the pre-consolidate set. The same holds for the consolidate-failure exit
    (`exit 1` at study_area_run.sh:1346), where every host is reported as "run stopped before
    consolidate released it". But `schema_consolidate` keeps going after a failed source, so the sources
    before and after it were consolidated and their rows deleted on the host.
  - The banner and RUNBOOK tell the operator to run `schema_consolidate(bucket = <groups>)`.
    `schema_consolidate` DELETEs the bucket from the destination (schema_consolidate.R:283-287,
    autocommit) before it COPYs. The source now has 0 rows for those groups, so the COPY adds nothing,
    the result is `copy_empty` / `ok = FALSE`, and the dispatcher's only copy of those groups is gone.
    The only way back is the `/tmp/<schema>_pre_consolidate_*.dump` that call took, and the
    instructions do not mention it.
  - This turns the path built to prevent data loss into a source of it. The likeliest trigger is a
    dropped ssh session that finished its work: `CY_RUN_RC != 0`, every group consolidated.
  - Fix: write only measured leftovers to the TSV `groups` column. Either probe `host_remaining` for
    each kept host in `burn_cyphers`/`hosts_kept_report` (it costs one ssh per kept host), or label the
    column as "groups the host finished, possibly already consolidated". Change the recovery text to
    "query what streams rows are left on the host, consolidate only those".

- **[severity: fragile]** data-raw/study_area_hosts.sh:44-53 (`.hosts_wsg_sql`), :97-101 (`host_remaining`).
  When `<schema>.streams` is absent, the result is a confident "nothing left", which releases the host
  for burning. On any host that reached dispatch the table must exist: `cypher_prep.sh:334` runs
  `lnk_persist_init(..., force_recreate = TRUE)` before the `=== READY` gate. So "no such table" never
  means "nothing persisted". It means the probe is looking somewhere the pipeline did not write: another
  database, a schema name that differs from what the R side resolved, or a container that is not the
  one R connects to. `to_regclass()` returns NULL for a missing schema as well as a missing table, with
  no error, so any such mismatch reads as "known, empty". This is the fail-toward-burn direction the lib's
  header says it closes. The `log` probe has the same property but only narrows the consolidate bucket.
  Fix: for the release probe, treat a missing table as unknown (emit no `__LNK_END__`, or a distinct
  marker that `host_release` refuses).

- **[severity: fragile]** data-raw/study_area_hosts.sh:282-287 (`.hosts_keep_reason`) and
  data-raw/study_area_run.sh:1558-1559. Under `--keep-cyphers`, a host that is also **held for cause**
  is recorded only as `--keep-cyphers`. The causes are: session exit ≠ 0, database unanswered,
  streams rows left, burn incomplete. `.hosts_keep_reason` tests `KEEP_CYPHERS` before `CY_WHY`, and
  `HOSTS_KEPT` ignores every kept host when `KEEP_CYPHERS=1`.
  - When accounting was complete, the run can exit 0 while a host holds work that `host_release`
    refused to clear. One case is a session that exited non-zero after its loop had finished; another
    is a source DELETE that failed.
  - The TSV then gives no sign that this host differs from the others, and its `burn_command` reads
    as safe to run.
  - Fix: put the `CY_WHY` reason ahead of (or beside) `--keep-cyphers`, and count hosts with
    `CY_HOLD=1` toward `HOSTS_KEPT` even under `--keep-cyphers`.

Not raised (checked, safe direction or pre-existing): `cypher_down` on a workspace `cypher_up` never
created makes `tofu state list` fail, so that host is listed as kept (a false alarm, not a loss); the
default workspace's reserved IP would always read as "burn did not complete", but pre-flight treats
`cypher` as not a run's host; the test stubs never run the real psql `\if` / `\gset` script (verified by
hand per the brief).
