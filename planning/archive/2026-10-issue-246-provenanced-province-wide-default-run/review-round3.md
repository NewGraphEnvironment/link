# Code-check round 3 (#246)

Scope: `cc_round3.diff` (branch) + `cc_round3_fixes.diff` (round-2 fix), with each changed
file read in full: `study_area_run.sh`, `cypher_prep.sh`, `study_area_buckets.R`,
`parity_crosssection.R`, `verify_extra.sql`. Read-only probes only. Every SQL probe ran under
`PGOPTIONS='-c default_transaction_read_only=on'`. Mutation tests ran in
`scratchpad/cc3_work/`.

## The mechanism

Both earlier findings come from one assumption: **a check is written for the values it
usually sees, so the case where the thing being judged is missing, or has an unusual value,
lands on the pass side.**

- **r2 (absence read as agreement).** An aggregate or an allowlist looks at the observed
  values and says "no disagreement". That is also its answer when there are no values: NULLs
  that `count(DISTINCT)` skips, a host that logged nothing, an empty group. So a measurement
  that is missing scores the same as a healthy one.
- **r1 (benign-looking values trusted).** A value goes into a context that re-parses it (a
  remote shell string in `'...'`, SQL). Normal values never contain the characters that matter,
  so nothing checks for them where the value is used.

## Findings

- **[severity: bug]** `data-raw/parity_crosssection.R:110-113, 162-165, 201`. When link's value
  for a (group, species, metric) is under 1 km and bcfp's is 1 km or more, the row goes into
  `absent`. It is printed as "#189 residence, excluded" and never counted in `n_fail`.
  - The allowlist has no key. `hab_parked` names `BULK:SK`, but `absent` takes any group, any
    species and any metric, including `accessible`. #189's residence species (CT, DV) are not
    in `species` at all.
  - So the worst regressions the sweep exists to catch exit 0:
    - a species whose `streams_habitat_<sp>` has no rows for the group. The inner JOIN in
      `.lnk_rollup_wsg_sql` drops the species row, so `lk_row` is empty and `lkv` is 0;
    - a group whose `streams_access` rows are missing, for example after a failed recompute.
      The LEFT JOIN gives `access` NULL, so `accessible_km` is NULL, `num()` turns it into 0,
      and every species' accessible row becomes "absent";
    - a barrier bug that zeroes one species' access.
  - Proved with a mock that sources the script's own loop (lines 93–123) and verdict
    (196–210). It gives link BT `accessible_km = NA` and no ST row, against a bcfp of
    500 / 300 / 50 / 80 km. Output: four "link-absent" lines, then
    `OVERALL: 2/2 parity pairs within tolerance … — PASS`, `exit=0`.
  - The absent rows are also never added to `rows`, so they are missing from the
    `LNK_PARITY_OUT` CSV. The plan's "count UNEXPLAINED rows" step cannot see them either.
  - This is round 1's `no_link` fix applied to a group but not to a species or a metric.
  - Fix: count `absent` in `n_fail`, except entries on an explicit list like `hab_parked`.
    Or put them in `rows` with `link = 0`, `diff_pct = -100` and `ok = FALSE`, so that the
    verdict and the taxonomy both judge them.

- **[severity: fragile]** `data-raw/logs/provincial_246/verify_extra.sql:76` (check 5a).
  `count(DISTINCT coalesce(artifact_version_id, '<NULL>')) <> 1` treats "no host recorded a
  version id" as one value on which every host agrees, so the check passes.
  - Nothing upstream stops all of them being NULL:
    - The dispatcher's vintage gate (`.lnk_vintage_stamp`, `R/lnk_preflight_vintage.R:283`)
      requires a `loader` row with `loaded_at`, not a non-NULL `version_id`.
    - `artifact_record.R` accepts a manifest row with an empty `version_id`: `na.strings = ""`,
      and the only read-back check is version-without-Last-Modified.
  - A systematic cause hits every host the same way and shows up here as "agree". Examples: a
    capture that stops parsing `x-amz-version-id`, or an object served without the header.
    `cabd.dams` already holds a NULL-version loader row on m1 today; it is not in 5a's table
    list.
  - One host NULL against the others' ids still fails, correctly.
  - Fix: also require `count(i.artifact_version_id) = count(*)` per table, so no NULLs at all.
    It is also worth asserting that both tables appear, because `GROUP BY` over zero matching
    rows passes. Today check 3 and the fixed VALUES list in `.lnk_log_inputs` guarantee the
    rows exist, but only through check 3's "at least one row_count" rule.

## Where the mechanism reaches in this diff

### Absence read as agreement (r2's shape)

| place | input that would pass when it should fail | handled? |
|---|---|---|
| verify_extra 1a `count(DISTINCT wgc) <> en` | run_uid with zero rows gives 0 ≠ 241; empty, missing or non-numeric `expected_n` makes `''::int` / an uninterpolated `:'expected_n'` error out (exit 3) | yes |
| 1a: failed groups (`date_end` NULL) | counted as logged | yes, by `study_area_verify.sql` §6 `date_end IS NULL` RAISE, which the run also uses |
| 1b NULL `config_hash` / `config_drift` | `IS DISTINCT FROM false` catches NULL | yes |
| 1c `count(DISTINCT config_hash)` | skips NULLs, but 1b already fails them; zero rows gives 0 ≠ 1 | yes |
| 4 `config_hash = $1` with `h` NULL | `= NULL` gives 0 rows and fails; with two hashes, 1c fails first | yes |
| 2 groups in streams vs newest log row | fresh_default's 56 groups are all in the 241, checked against `buckets_default.md`, so there is no false fail | yes |
| 3 any non-NULL `row_count` per run_id | one INSERT per run_id writes all 12 primitives, so it is all or nothing | yes |
| 5a loader version ids | all hosts NULL | **no** (finding 2) |
| 5a tables absent from log_input | `GROUP BY` yields no group | indirectly (check 3 + the fixed VALUES list) |
| 5b `count(DISTINCT row_count) > 1` | skips NULLs | yes, by 5c |
| 5c per (host, table) `count(row_count) = 0` | mutation-tested in a read-only CTE: nulling cypher-job2's bcfishobs rows and dropping cypher-job1's cabd rows both fire (2 pairs), while 5b stayed 0 | yes |
| 5c host identity | hosts are distinct node names (`m1`, `cypher-job1`, `cypher-job2` in run `20260901_234743-6628379d`) | yes |
| final `array_length(fails,1) > 0` | NULL on an empty array, so pass only when nothing failed | yes |
| parity: group missing from schema | `no_link` (round 1) | yes |
| parity: species or metric missing on the link side | `absent`, excluded | **no** (finding 1) |
| parity: group missing on the bcfp side | `coalesce(sum,0)` gives 0, link ≥ 1 gives `pct = Inf`, `ok = FALSE` | yes (fails loud) |
| parity: missing `streams_habitat_<sp>` table / `access_<sp>` column | SQL error, exit non-zero | yes |
| parity: `UNEXPLAINED` count | printed only, not in exit; by design (diagnostic) | n/a |

### Benign-looking values trusted (r1's shape), for every value in the ssh strings at `study_area_run.sh:1021` and `:1088`, and the SQL in parity

| value | origin | handled? |
|---|---|---|
| `CONFIG`, `SCHEMA_OVERRIDE` | charset check (this diff) | yes |
| `SCHEMA` with no override | YAML via `resolve_schema`; only reachable for `bcfishpass` (`fresh`) | yes, by the guard at line 237 |
| `DISCHARGE` | `case fwapg\|wet` | yes |
| `WET_LOAD` | refuses `'` (the only character that matters inside remote `'...'`) | yes |
| `RUN_LABEL` | charset check | yes |
| `RUN_UID` | generated from TS and hex | yes |
| `FWAPG_GIT_SHA`, `BCFISHOBS_GIT_SHA` | `git rev-parse HEAD` | yes |
| `LINK_BRANCH` | unchecked | accepted |
| `LNK_BCFP_MODEL_VERSION` | `bcfp_baselines.csv` ledger, unchecked; values are `vX-N-gSHA` | no, low risk |
| `B_SPACE` (bucket codes) | stdout of `study_area_wsgs.R`, unquoted in the remote `for`; now under `load_all`, which writes to stderr | no, low risk (our own script's output) |
| parity `schema` / `w` in `sprintf`/`glue` SQL | `lnk_rollup_wsg()`'s `stopifnot` regexes run first for every group, before any interpolated SQL | yes, transitively |

## Checked and clean

- `cypher_prep.sh`:
  - `bash -n` is clean.
  - The new R lines carry no `'` inside the single-quoted `-e`.
  - `cfg$pipeline$schema` reaches `lnk_persist_init` through `.lnk_table_names`.
- `study_area_wsgs.R` takes `[config]` as arg 2 and honours `LNK_LOAD`. A failure inside
  `$( )` aborts under `set -e`.
- The bash ≥ 4 guard comes before the first `declare -A`.
- The ssh `-o` options come before the host.
- `verify_extra.sql` ran read-only against `fresh` / run `20260901_234743-6628379d` with checks 4c
  and 5a stubbed out (both tables or columns predate the run there). Checks 1–3 and 5b/5c
  executed. The only failure was check 2's expected 67-group mismatch for a 34-group run.
