# Code-check round 3 — #354 (branch `354-schema-consolidate-deletes-the-destinati`)

Diff: `git diff 3b6e591e...HEAD` (excluding `*.out` evidence and `review-*.md`).

## Mechanism

The fact "which build a group's persist rows hold" now has one producer in code: the
newest-log guard in step 3.5 (`max(date_start)` per group, destination against source).
Rounds 1 and the plan review both found the same thing: prose that restates that code path
or the history rule, and drops a condition the code has. Round 1's instance was "a group the
host no longer holds loses the dispatcher's rows", which the guard actually refuses. This
round enumerated every restatement and every reader of "newest log row":

| where | restates | verdict |
|---|---|---|
| `schema_consolidate.R` step 3.5 guard | newest by `max(date_start)` | the producer |
| `lnk_log_read()`, `.lnk_export_runs()`, `.lnk_hv_check_log()`, `habitat_variants_build.R:530` | newest by `date_start DESC` | consistent with the guard |
| `habitat_diff_segments.R:164`, `query_habitat_thresholds_fiss.R:226` | `date_end DESC NULLS LAST` | stamps only, decide nothing; fine |
| guard's epoch compare, DBI double vs `as.numeric()` of psql text | equality on a re-copied row | measured: 0 mismatches over 241 real `fresh_default` groups and 20,000 synthetic 16-digit epochs |
| PK replace by `run_id` / `recompute_id` | one key = one build | host-prefixed ids, distinct hostnames in `fresh_default.log` (m1, cypher-job1..3), no `set.seed` in R/ or data-raw; holds |
| `dunc_default_328/README.md` | verify.R now sees 2 DUNC rows | measured: DUNC 2 rows; documented |
| header comment, `.lnk_log_specs()` roxygen, data-raw/README | which tables are history, and that they are never deleted by group | finding 1 |
| RUNBOOK §8d, `study_area_hosts.sh:467-470` and `:525-526` | when the guard refuses | finding 2 |

## Findings

- **[severity: fragile]** `data-raw/schema_consolidate.R:34-38`, `R/lnk_log.R:497-501`,
  `data-raw/README.md:93`: they say more about the log tables than the code does.
  - The header says "The log tables ... carry `watershed_group_code`, so they are discovered
    and copied like the rest". The roxygen says consolidate "replaces their rows by primary
    key". Both refer to the six `.lnk_log_specs()` tables.
  - In fact only `log`, `log_input` and `log_recompute` carry the column. I checked
    `information_schema` for `fresh` and `fresh_default`. The three config-snapshot tables
    (`log_parameters_fresh`, `log_parameters_habitat_thresholds`, `log_dimensions`) are never
    discovered and never leave a cloud host. RUNBOOK §6b says so correctly ("they do not yet
    travel between hosts"), and the test comment in `test-schema_consolidate.R:27-28` agrees.
  - The header, the roxygen and data-raw/README also say the log rows are "never deleted by
    group". Step 5 (`schema_consolidate.R:622-626`) does delete the log tables by
    `watershed_group_code` on the source, because they are in `copied_tables`. This loses no
    data, since the rows were copied first. The RUNBOOK's "already consolidated, then deleted
    from the source, log rows included" relies on that deletion.
  - Effect: a reader of the code comments would conclude that a config snapshot built only on
    a cloud host survives the burn. It does not.
  - Fix: qualify the three sentences. Say "the three that carry `watershed_group_code`", and
    "never deleted by group on the destination".

- **[severity: fragile]** `data-raw/study_area_hosts.sh:469-470` and `:525-526`, RUNBOOK.md
  §8d (around line 1280): the refusal is stated without its precondition.
  - The docs say a group the host no longer holds at all "has no log row there, so
    consolidate refuses it". `consolidate_newer_on_dest()` refuses only a group that **has a
    log row on the destination** (`merge(..., all.x = TRUE)` on `dest`).
  - Where the dispatcher holds a group's persist rows with no log row (builds from before the
    log tables existed), the guard passes. The bucket DELETE then removes those rows, and
    nothing replaces them. The coverage check in `study_area_run.sh` detects this only
    afterwards.
  - Today `fresh_default` has 0 such groups. `fresh` has **59 of 98** (measured:
    `fresh.streams` groups minus `fresh.log` groups).
  - So in a `bcfishpass`-config recovery, the operator text printed by `hosts_kept_report`
    promises a refusal that the code does not make.
  - Fix: add the condition, e.g. "is refused when the dispatcher has a log row for it (any
    build since the log tables, #127); a group with only pre-log rows here is still deleted
    and not replaced".

No bugs, security issues or data-loss paths found in the code itself. Checked:

- The staged replace runs as one transaction (`-1` and `ON COMMIT DROP`).
- The guard and the `log_pk_unshared` check run before any DELETE.
- `copy_empty` still behaves correctly on a re-consolidate, because the persist tables are
  re-added.
- A refusal makes the driver exit non-zero and keep the cyphers
  (`study_area_run.sh:1352-1358`).
- An empty source result parses to a zero-row frame. NA epochs fail closed.

Not raised: the source-log status check cannot see a failed remote query over a transport
that loses the exit status (Tailscale SSH to a Mac). It then refuses under the wrong stage
name. That fails closed, and every other ssh call in the file has the same pattern.
