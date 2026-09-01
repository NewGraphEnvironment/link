# Code review — link#250 parallel recompute (round 1)

Reviewer: code-check subagent. Branch diff + full changed files read; checklist
(`code-check.md`) walked item by item. Live verification against the local
docker `fwapg` (PostgreSQL 17.5) and against `/bin/bash 3.2.57`.

## What was verified rather than reasoned about

- `data-raw/pool_probe.sh` run under `/bin/bash` 3.2.57 → **PASS=25 FAIL=0**,
  including the empty-list, trailing-comma, bounded-width and
  unrelated-background-job cases.
- `test-lnk_fanout_judge.R`, `test-lnk_barriers_views.R`, `test-lnk_access.R`
  all pass under `pkgload::load_all()` (42 assertions, 0 failures, 0 skips —
  the DB-backed `.lnk_table_exists` view test actually ran).
- `data-raw/recompute_checksum.sql` executes end-to-end against `fresh` and
  emits the expected `tbl,watershed_group_code,n_rows,digest` shape; the
  `SET`/`DO` chatter on stdout is correctly filtered by `digest()`'s grep.
- No shared-state hazard found in the per-WSG recompute beyond the barrier
  views the hoist removes: `lnk_mapping_code` is AOI-filtered
  (`R/lnk_mapping_code.R:145,150,165,185`), `fresh::frs_network_features` issues
  no DDL, and every scratch object is WSG-suffixed
  (`zz_lnk_streams_<wsg>`, `zz_lnk_access_scratch_<wsg>`, `zz_lnk_mc_scratch_<wsg>`).
- `ALL_WSGS` is `sort -u`'d at `study_area_run.sh:1021`, so the pool cannot run
  the same WSG twice into the same scratch names.
- The `@details` claim that the view column list has never changed is true —
  checked `9e350d2`, `2f385cb`, `2beb42f`, all identical column lists — so
  dropping `DROP VIEW` cannot break an upgrade from an existing schema.
- `man/lnk_fanout_judge.Rd`, `man/lnk_access.Rd`, `man/lnk_barriers_views.Rd`
  are regenerated and carry the new params.

## Findings

### 1. [bug] `R/lnk_barriers_views.R:281-283` — the shape-change matcher cannot match the drop-column refusal it enumerates

```r
shape_re <- paste0("cannot (change name of|change data type of|",
                   "drop columns from) view column")
```

Postgres does **not** say `cannot drop columns from view column`. Measured
against the live server:

```
CREATE OR REPLACE VIEW … (fewer cols)  -> ERROR: cannot drop columns from view
CREATE OR REPLACE VIEW … (renamed col) -> ERROR: cannot change name of view column "b" to "zzz"
CREATE OR REPLACE VIEW … (retyped col) -> ERROR: cannot change data type of view column "b" from integer to text
```

`grepl()` confirms: the rename and retype messages match, `cannot drop columns
from view` does **not** (and neither does the fourth refusal `view.c` can
raise, `cannot change collation of view column …`).

So one of the three cases the regex names — and one of the four the
`@param recreate` docs promise ("rename, retype, reorder or **drop** an output
column") — falls through to `stop(e)` and the operator gets the bare Postgres
error with no pointer to `recreate = TRUE`. That is the whole reason the branch
exists.

Failure scenario: someone removes a column from the `_access` view definition,
runs `barriers_views_build.R`, and gets `cannot drop columns from view` with no
remedy named — exactly the "escape hatch nobody can find" the docstring argues
against.

The test suite cannot catch this: `test-lnk_barriers_views.R:1646` only ever
feeds the **rename** message, so the fixture set reaches one of three arms
while reading as coverage of all of them.

Fix: `"cannot (change name of view column|change data type of view column|drop
columns from view)"`, and add the drop message (and ideally the collation one)
to the mocked cases.

### 2. [fragile] `data-raw/study_area_run.sh:891-905` — the pool spins forever on a width of 0

`seq 0 $((width - 1))` yields nothing at `width=0`, so the inner slot scan never
runs, `break 2` is never reached, and the `while :; … sleep 1` loops
indefinitely. Reproduced with the shipped function extracted verbatim:

```
starting width 0
exit=124        # timeout 8, no output, no progress
```

`study_area_run.sh` itself validates `--recompute-jobs` (`>0`, `<=16`), so the
production path is safe. The two **new** consumers do not:

- `data-raw/recompute_parity.sh:38` — `WIDTH="${3:-4}"`, passed straight to
  `run_recompute_pool`.
- `data-raw/recompute_sweep.sh:26-27` — `WIDTHS=("$@")`, every element passed
  straight through.

A silent, output-free hang is the worst failure shape available, and it is the
one an operator sweeping widths would most plausibly trigger (`… bcfishpass 0 1 2 4`
to get a "no pool" control arm reads as reasonable). One guard inside the pool
— `[ "$width" -ge 1 ] || { echo "run_recompute_pool: width must be >= 1" >&2; return 1; }`
— covers all three call sites, and `pool_probe.sh` has no case for it.

### 3. [fragile] `data-raw/recompute_sweep.sh:115` — the new per-width summary aborts the script under `pipefail`

```bash
grep -ho 'recomputed in [0-9.]* min' "$D"/*.log 2>/dev/null \
  | awk '{print $3}' | sort -rn | awk '…'
```

`grep` exits 1 when a width's `.d` holds no matching line — which is precisely
the case where every job in that pass failed, i.e. when you most want the
summary. Under the file's `set -euo pipefail` the pipeline's non-zero status
kills the script. Reproduced:

```
  -j1    (sum 0.0 min, slowest = 0% of it)
exit=1                      # "REACHED END" never printed
```

Consequences: the remaining widths' summaries never print, and a sweep that
otherwise completed and printed a valid table exits non-zero for a reason
unrelated to the measurement. Append `|| true` to the `grep`, or gate on a
match first.

### 4. [fragile] `data-raw/study_area_run.sh:1179` — the recompute-failure guidance names files that do not exist on the view-build path

`RECOMPUTE_LOG` and `RC_TSV` are only created inside
`if [ "$RECOMPUTE_FAIL" = "0" ]` (lines 1126, 1128). When `RECOMPUTE_FAIL` is
raised by the **barrier-view build** failing (line 1116), neither file is ever
written, yet the final block still prints:

```
  See <…>_recompute.log (and <…>_recompute.tsv for per-WSG exit status).
```

The operator is sent to two absent files while the real evidence is in
`<…>_recompute_views.log`. This is the same class the block's own comment
argues against ("sends the operator to the wrong host"). Either branch the
message on which cause raised the flag, or name
`${TS}_recompute_views.log` alongside.

### 5. [fragile] `data-raw/recompute_sweep.sh:96-100` — a zero-WSG sweep reports clean

`WSGS="${1:?…}"` rejects unset/empty but not `","` or `" "`. `csv_lines` then
yields nothing, `N_WSG=0`, the pool runs zero jobs, and the failure marker is
gated on `[ "$NRC" = "$N_WSG" ] && [ "$NFAIL" = "0" ]` — `0 = 0` and `0 = 0`, so
the table prints per-width timings with no warning that nothing was measured.
This is the "an empty result set is not a pass" case the sibling scripts handle
correctly via `lnk_fanout_judge`; `recompute_sweep.sh` is the one consumer of
the pool that does not call the judge. `[ "$N_WSG" -gt 0 ] || { echo "FATAL: no
WSGs"; exit 1; }` after line 96 closes it.

## Checked and clean (no action)

- Empty-array-under-`set -u` on bash 3.2: `SLOT_PID=()` pre-seeded before any
  `${SLOT_PID[$slot]}` read; `WIDTHS` guarded with `${#WIDTHS[@]}`.
- `wait` scoping: the pool waits on `$all_pids` only, and the sweep's sampler is
  `disown`ed — the regression the probe's last case pins.
- `find -exec … +` used everywhere instead of `cat dir/*` (ARG_MAX at 217 WSGs).
- `.rc` written last, after the log, so a killed job is judged "never reported".
- `lnk_fanout_judge` branch table: `none_expected` / `none_ran` / `all_failed` /
  `ok` / `partial` orderings all behave as documented under hand-checked inputs,
  including duplicate-with-mixed-status (`all_failed` when nothing net-succeeds)
  and unreadable rc (`grepl` returns `FALSE` on `NA`, so `unreadable` is `TRUE`
  — correct direction).
- `data-raw/fanout_judge.R`: `read.delim(fill = TRUE)` turns a truncated
  one-field row into `rc = NA` → unreadable → failure. Correct direction.
- `redact_log_addresses` two-glob change: the first glob's directory match is
  discarded by `[ -f ]`, the second reaches the per-job logs, and
  `.gitignore` covers `*_recompute.d/` so a killed run cannot commit 217 files.
- `recompute_checksum.sql` determinism: alphabetical column enumeration,
  `ORDER BY id_segment` within `watershed_group_code` (correct given the
  `(id_segment, watershed_group_code)` PK), `ROW(…)::text` with no coalesce
  sentinel, and all five session GUCs are settable at session scope.
- `recompute_parity.sh` A/B/restore/C ordering is correct, and a failed pass
  aborts the script (`SEC_A=$(run_pass …)` propagates the subshell's `exit 1`
  through `set -e`).
- `statement_timeout = 600000` is not at risk under `-j4`: the slowest measured
  WSG is 226 s and `pg_stat_activity` sampling showed ~1.1 active backends.
