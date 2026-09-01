# link#250 — code review, round 2

Scope: the branch diff (v0.47.2 → v0.48.0), with particular attention to the five
round-1 fixes. Everything below was measured against the live docker `fwapg`
(PostgreSQL 17.5) and against the shipped shell functions extracted with the same
`sed`/`awk` the scripts themselves use — not read off the page.

## Findings

- **[bug]** `data-raw/study_area_run.sh:896-905` (`run_recompute_pool` width guard,
  round-1 fix #2) — **the guard does not cover a non-integer width, and the pool
  then hangs forever with no output.** This is the exact defect the fix was written
  to prevent, reproduced for a different input class.

  `[ "${width:-0}" -lt 1 ] 2>/dev/null` errors with status 2 on a non-numeric
  operand (`bash: [: abc: integer expression expected`). The `2>/dev/null` discards
  the diagnostic, and a non-zero `if` condition means only "don't take the branch" —
  so control falls straight through to `for slot in $(seq 0 $((width - 1)))`. In
  arithmetic context `abc` is an unset variable name → `0 - 1` → `seq 0 -1` is
  empty → the slot scan never runs → `break 2` is unreachable → the outer
  `while :; sleep 1` spins forever.

  Measured against the extracted shipped function (each case killed at 4-5 s):

  | width | result |
  |---|---|
  | `0`, `-1`, `''` | `FATAL: run_recompute_pool needs width >= 1` — guard fires ✓ |
  | `abc`, `2x`, `1e1` | **hangs** (exit 137 = my killer) |
  | `-j4`, `4x` | **hangs** — realistic typos for this caller |
  | `3`, `' 2'` | runs normally ✓ |

  Reachability is exactly what the guard's own comment names: `--recompute-jobs=`
  validates numerically, but `recompute_parity.sh` (`WIDTH="${3:-4}"`) and
  `recompute_sweep.sh` (`WIDTHS=("$@")`) pass a width straight through unvalidated.
  `bash data-raw/recompute_sweep.sh "LKEL" bcfishpass -j4` — a plausible mistake,
  since every other tool in this repo spells widths `-jN` — wedges indefinitely.

  Worse in that caller: `recompute_sweep.sh:1473` invokes the pool as
  `run_recompute_pool "$w" >/dev/null 2>&1`, so the FATAL message is discarded too.
  The width-0 case therefore exits the sweep silently mid-line (`set -e`, no
  output), and the non-numeric case hangs silently. The guard's diagnostic never
  reaches the operator from the caller most likely to trigger it.

  Fix — validate the shape before comparing, so a bad width can never reach the
  arithmetic:
  ```bash
  case "${width:-}" in
    ''|*[!0-9]*) echo "FATAL: run_recompute_pool needs a positive integer width (got '${width:-}')" >&2
                 return 1 ;;
  esac
  [ "$width" -ge 1 ] || { echo "FATAL: width must be >= 1 (got '$width')" >&2; return 1; }
  ```
  and drop `>/dev/null 2>&1` from the sweep's pool call (or at least keep `2>&1`
  on stderr) so the refusal is visible.

  **Why round 1 missed it:** `pool_probe.sh:107-119` adds a width-0 case only. A
  fixture set that cannot reach the failure mode is not validation — width 0 fails
  *inside* the `[` comparison (status 0/1, guard fires), while a non-numeric width
  fails *the comparison itself* (status 2, guard skipped). They are different arms.
  Add `abc` and `-j4` rows to the probe alongside `0`, asserting both return
  non-zero and return fast.

## Verified clean — the other four round-1 fixes

- **Fix #1, `R/lnk_barriers_views.R:292-294` shape-change regex.** Enumerated
  Postgres' refusals against the live server (17.5) rather than trusting the docs:

  ```
  cannot change name of view column "a" to "zzz"
  cannot change data type of view column "a" from integer to text
  cannot change collation of view column "b" from "default" to "C"
  cannot drop columns from view
  ```
  Column **reorder** and **mid-list insert** both surface as the *rename* message,
  so those four are the complete set. The regex matches all four and none of
  `relation ... does not exist`, `canceling statement due to statement timeout`,
  `permission denied for schema fresh`. The test's four-message table is now
  faithful to the server.

  I also checked the premise the DROP removal rests on: the view column list is
  **byte-identical across all four commits** that have touched
  `R/lnk_barriers_views.R` (`9e350d2`, `2f385cb`, `2beb42f`, `4cf9e09`), and all 19
  live views in `fresh` carry exactly that shape. So `CREATE OR REPLACE` cannot fail
  on the real schema for shape reasons. Claim holds.

- **Fix #3, `RECOMPUTE_FAIL_STAGE`.** `RECOMPUTE_LOG` / `RC_DIR` / `RC_TSV` are all
  assigned before the views build, so no `set -u` exposure; the `views` branch names
  `${TS}_recompute_views.log` (which does exist) and the `pool` branch names the two
  that exist only in that path. Default `${RECOMPUTE_FAIL_STAGE:-pool}` is the safe
  side. Correct.

- **Fix #4, sweep per-width summary `|| true`.** `||` binds to the whole pipeline, so
  the command substitution's status is 0. Tested under `set -euo pipefail` for a
  missing directory (glob unexpanded, grep exit 2) and for a present directory with
  no matching lines (grep exit 1) — both yield an empty `TIMES` and reach the
  explicit empty branch. The grep pattern `recomputed in [0-9.]* min` + `awk '{print $3}'`
  matches `wsg_recompute_one.R:148`'s actual `cat()` format.

- **Fix #5, sweep `N_WSG > 0`.** Fires before any pass; placed after the `eval`s so
  `csv_lines` exists. Correct.

## Also checked, no defect found

- **Parallel safety of the fan-out.** `lnk_pipeline_access` and
  `lnk_pipeline_mapping_code` write only to the caller-supplied target
  (`dbWriteTable(overwrite = TRUE)`); everything else a job touches is WSG-scoped
  (`zz_lnk_streams_<wsg>`, `zz_lnk_access_scratch_<wsg>`, `zz_lnk_mc_scratch_<wsg>`)
  or row-scoped (`UPDATE ... WHERE watershed_group_code`, `DELETE`+`INSERT` in a
  transaction). `streams_habitat_long_vw` is created by `lnk_persist_init`, never in
  the recompute path. No remaining shared mutation after the views hoist.
- `lnk_access(build_views = FALSE)` verifies the per-species `_access` views for the
  **active** species, which is always `intersect(cfg$species, present)` — a subset of
  what `barriers_views_build.R` builds. No gap.
- `redact_log_addresses`'s second glob reaches `${TS}_recompute.d/*.log`; both globs
  degrade safely (non-matching glob → literal → discarded by `[ -f ]`), and the
  directory itself is skipped by the same test.
- `ALL_WSGS` is the single source for both the pool's iteration and the judge's
  `expected`, so the two sides of that comparison cannot drift.
- `[ "$BASE" = "0" ] && BASE=$SEC` inside the sweep loop does **not** trip `set -e`
  (verified: all three iterations run, exit 0).
- `find -exec ... +` used everywhere rc/log files are concatenated — no `cat dir/*`
  ARG_MAX exposure at 217-WSG scope.
- `devtools::load_all()` + `test_local(filter = "lnk_fanout_judge|lnk_barriers_views|lnk_access")`
  — all pass, including the live-DB `.lnk_table_exists`-on-a-view premise test.

## Minor (not findings, flagged only because they sit inside a round-1 fix)

- `R/lnk_barriers_views.R:279-291` — the round-1 edit left the **old** comment line
  ("Postgres' three shape-change refusals...") immediately above the new one
  ("Postgres' four..."), so the block now contradicts itself twice over. Two lines to
  delete; a future reader will otherwise trust the stale count.
