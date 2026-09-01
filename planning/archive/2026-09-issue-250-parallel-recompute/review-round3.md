# Round 3 review — link#250 (parallel recompute)

Scope: the branch diff (`45cd983..b7cb5b9`), scrutinising the round-2 fixes
hardest as instructed. Four findings. All claims below were measured on this
machine (bash 5.3.9 and /bin/bash 3.2.57, local docker `fwapg`), not reasoned
about.

---

## The mechanism behind the recurring class

Rounds 1, 2 and 3 are the same defect, one door over each time:

> **A value is validated with one numeric grammar and consumed with another.**

- **Round 1** wrote no shape check: `[ "$width" -lt 1 ]`.
- **Round 2** found it — `[ abc -lt 1 ]` exits 2, the `if` reads that as false,
  and `$((abc - 1))` resolves `abc` as an *unset variable* = 0, so `seq 0 -1`
  is empty, the slot scan never runs, `break 2` is unreachable and the outer
  `while :; sleep 1` spins forever. Fixed with a `case ''|*[!0-9]*` shape check.
- **Round 3 (below)** — the shape check and `[ -lt ]` both parse **base 10**;
  `$(( ))` parses **base 8** on a leading zero. `08` still hangs, `010` silently
  runs the wrong width.

`test`, `$(( ))` and `seq` do not agree on what "a number" is. The durable fix
is not another predicate: it is to **normalise once and consume only the
normalised value** — `width=$((10#$width))` immediately after the shape check —
so there is only one grammar downstream. The same applies to the pre-existing
`--prep-ssh-wait=` / `--vintage-max-days=` pair (`ssh_deadline=$(( $(date +%s) +
PREP_SSH_WAIT_S ))` at `study_area_run.sh:736` has the identical exposure; out
of scope for this diff but the same one-line fix).

---

## Findings

### 1. [bug] `data-raw/study_area_run.sh:2071-2079` (and the parser at `:1204-1213`) — a leading-zero width defeats the round-2 guard: `08` hangs, `010` silently narrows the pool

`case "${width:-}" in ''|*[!0-9]*)` accepts any all-digit string, and
`[ "$width" -lt 1 ]` evaluates it base 10 (bash `test` uses `strtoimax(..., 10)`).
`for slot in $(seq 0 $((width - 1)))` then evaluates the **same string base 8**.

Measured, running the *shipped* `run_recompute_pool` extracted from the script:

```
$ timeout 10 bash pool08.sh          # run_recompute_pool 08, ALL_WSGS="A,B"
pool08.sh: line 31: 08: value too great for base (error token is "08")
pool08.sh: line 35: 08: value too great for base ...   (repeating, once per poll)
exit=124   <- timed out; the pool HUNG. Zero .rc files, no work started.
```

and replicating the argument parser verbatim:

```
--recompute-jobs=08  -> argparse:accepted   pool slots:0   (asked 08)   HANGS
--recompute-jobs=09  -> argparse:accepted   pool slots:0   (asked 09)   HANGS
--recompute-jobs=010 -> argparse:accepted   pool slots:8   (asked 010)  SILENT
--recompute-jobs=016 -> argparse:accepted   pool slots:14  (asked 016)  SILENT
--recompute-jobs=007 -> argparse:accepted   pool slots:7   (asked 007)  SILENT
```

Two distinct failures from one root:

- **`08` / `09`** reproduce *exactly* the round-2 defect — an infinite spin with
  no work started and no output — for a value both validators accept. It lands
  after the cyphers have been spun, used and burned, so the cost is a whole run.
- **`010`–`016`** are worse because they are **silent**: the parser's `-le 16`
  bound passes on the base-10 reading while the pool builds a base-8-sized
  slot array. The operator asks for 16 and gets 14, and nothing says so. The
  same value also reaches the `echo "  recompute -j: $RECOMPUTE_JOBS"` banner
  and the `-j${RECOMPUTE_JOBS}` header, so the log affirmatively records a width
  that was never used.

`recompute_sweep.sh` takes widths from `"$@"` and `recompute_parity.sh` from
`$3`, both unvalidated, so `bash data-raw/recompute_sweep.sh "$WSGS" bcfishpass 08`
hangs the sweep indefinitely too.

**Fix** (one line, at the point the round-2 guard already sits):

```bash
  case "${width:-}" in
    ''|*[!0-9]*) echo "FATAL: ... (got '${width:-}')" >&2; return 1 ;;
  esac
  width=$((10#$width))          # <- one grammar from here on
  if [ "$width" -lt 1 ]; then ... ; fi
```

and the same normalisation in the `--recompute-jobs=*` arm **before** the
`-gt 0` / `-le 16` bounds, so the bound is applied to the value that is used.

---

### 2. [fragile] `data-raw/pool_probe.sh:1978-1988` — the guard's own regression net can only pass or hang, never fail; and its bad-width list misses the shape that still hangs

```bash
for BADW in abc 2x "" -1 1e1; do
  ...
  if ( run_recompute_pool "$BADW" ) 2>/dev/null; then RCB=0; else RCB=1; fi
  EB=$(( $(date +%s) - TB )); ...
  if [ "$RCB" = "1" ] && [ "$EB" -lt 5 ]; then ...
```

The elapsed-time assertion is only ever *reached* if the call returns. There is
no timeout, so a regression that reintroduces the hang does not produce
`FAIL width 'abc' rc=... after ...s` — it produces nothing at all, forever.
Confirmed by restoring the round-1 numeric-only guard and running the same
shape:

```
$ timeout 8 bash old.sh      # run_recompute_pool "abc" under the OLD guard
exit=124 (timed out = HUNG)
```

A guard written specifically to catch a hang, whose test hangs on the hang, is
the "test that cannot go red" case: it is indistinguishable from a working one
until the day it matters, and it will block whatever runs it.

The list is also scope-by-coincidence: `abc 2x "" -1 1e1` are the shapes the
round-2 author had in hand, and finding 1 shows the shape that *still* hangs
(`08`) is not among them. `PASS=32 FAIL=0` today is true and does not mean the
guard holds.

**Fix** — bound the call and add the leading-zero shapes:

```bash
for BADW in abc 2x "" -1 1e1 08 09 010; do
  RC_DIR=$(mktemp -d "${TMPDIR:-/tmp}/poolprobe.XXXXXX"); ALL_WSGS="A,B"
  ( run_recompute_pool "$BADW" ) >/dev/null 2>&1 & PP=$!
  ( sleep 5; kill -9 "$PP" 2>/dev/null ) >/dev/null 2>&1 & WD=$!
  if wait "$PP"; then RCB=0; else RCB=1; fi
  kill "$WD" 2>/dev/null; wait "$WD" 2>/dev/null || true
  ...
```

so "it hung" reports as a FAIL rather than as silence. Note `010` must assert
the *width actually used*, not just a non-zero return — it returns 0 having run
8 slots, which no rc/exit assertion can see.

---

### 3. [fragile] `data-raw/recompute_parity.sh:1042-1048` — the "we measured something" guard is set at exactly half the real row count, so half the evidence can disappear and the run still reports PASSED

```bash
N_ROWS=$(($(wc -l < "$OUT_DIR/${TS}_A.csv") - 1))
if [ "$N_ROWS" -lt "$N_WSG" ]; then
```

`recompute_checksum.sql` emits **one row per (table, WSG)** over two tables, so
the correct expectation is `2 * N_WSG`. The committed evidence confirms it —
`data-raw/logs/recompute_parity/20260901_044856_A.csv` is 8 data rows for 4 WSGs.

The hole is not hypothetical about the number, it is about which failure
survives it. `GROUP BY watershed_group_code` over zero rows produces **no
groups**, so a `streams_mapping_code` that ended up empty for every WSG does not
appear as `n_rows = 0` — its rows vanish from the digest entirely. Then:

- A, B and C are all missing the same four lines, so both `diff`s report equal;
- `N_ROWS` is `4`, which is not `< 4`;
- the script prints `ok digest covers 4 table-WSG row(s)` and
  `=== recompute parity PASSED ===`.

That is precisely the "three identical empty results reported as a pass" the
guard's own comment says it exists to prevent, and the recompute's step 2 is a
DELETE+INSERT into `streams_mapping_code` — i.e. the failure is in the thing
under test, not an exotic one.

**Fix:** `if [ "$N_ROWS" -lt $((2 * N_WSG)) ]; then`, and say `2 tables x N WSGs`
in the message so the constant is tied to its source rather than remembered.

---

### 4. [fragile] `R/lnk_fanout_judge.R:691-709` — a duplicate id in `expected` returns `status = "ok"` with a self-contradicting `1/2 succeeded`

`missing <- sort(setdiff(expected, job))` deduplicates, so a repeated expected
id is neither counted as missing nor reported by any problem branch, while
`n_expected <- length(expected)` counts it. Measured:

```
> lnk_fanout_judge(rcf("A","0"), expected = c("A","A"), quiet = TRUE)
status: ok   ok: TRUE   n_ok: 1   n_expected: 2
msg: [fanout] fanout - OK: 1/2 job(s) succeeded
```

`ok = TRUE` while the message it prints into the run log says one of two jobs
succeeded. The invariant the whole function exists to hold — an affirmative
verdict implies every expected job reported — is broken, and the branch table
has no arm that can report it: duplicates are only checked on the `rc` side
(`duplicated_jobs`), never on `expected`.

Reachability: `study_area_run.sh` is safe, because `ALL_WSGS` is built through
`sort -u` (`:1043-1045`). `recompute_parity.sh` and `recompute_sweep.sh` pass an
operator-supplied `$1` straight through to `fanout_judge.R`, so
`bash data-raw/recompute_parity.sh "LKEL,LKEL,CHWK"` reaches it. The pool also
overwrites `$RC_DIR/$w.rc` for a repeated `w`, so the second run's status is
lost — the two defects compound.

**Fix:** add `expected` duplicates to the problems list (they are a harness bug
in the same sense reported `rc` duplicates are), or deduplicate `expected` on
entry and make `n_expected` the deduplicated length so the counts and the
verdict agree. The first is better — it names the caller's bug rather than
papering it.

Sub-note, same mechanism, much lower reachability: `sort()` drops `NA`, so a row
with `job = NA` and `rc = "0"` is dropped from `succeeded`, from `unexpected`
and from every problem branch — `status` comes back `"ok"` having silently
discarded a row. Not reachable through `data-raw/fanout_judge.R` (`read.delim`
with `na.strings = character(0)` cannot produce `NA`), only from direct R
callers. Worth one `if (anyNA(job))` line rather than a redesign.

---

## Verified clean (checked, nothing to report)

- **`data-raw/recompute_checksum.sql`** — digest is deterministic (two
  consecutive runs byte-identical over 108 rows); the missing-table guard fires
  correctly and stops psql (`ERROR: recompute_checksum: missing in schema
  zzz_nope: streams_access, streams_mapping_code`, rc 3); `(watershed_group_code,
  id_segment)` confirmed unique in both tables (0 duplicate groups each), so the
  `ORDER BY s.id_segment` inside the group is well-defined; `lc_numeric`,
  `extra_float_digits`, `DateStyle`, `TimeZone`, `bytea_output` all accept the
  session `SET` under `ON_ERROR_STOP`. Column enumeration is
  `ORDER BY column_name` as documented, and `ROW(...)::text` distinguishes NULL
  from `''` as claimed.
- **`.lnk_views_execute` shape regex** — the four arms are the complete set
  emitted by Postgres' `checkViewTupleDesc` (drop / name / data type /
  collation); anything else re-raises unchanged, which the test asserts. A
  non-English `lc_messages` degrades to re-raising the original error, which is
  the safe direction.
- **`lnk_fanout_judge` status ordering** otherwise — `all_failed` cannot be
  reached with a clean job set, `ok` requires an exactly-matching id set with
  every status `"0"`, and a job appearing once as `0` and once as non-zero is
  counted as failed. Only the `expected`-duplicate arm above misreports.
- **Other numeric tests in the diff** (`pool_probe.sh` timings, `N_WSG`,
  `N_ROWS`, `${#WIDTHS[@]}`, `FAIL`, `FAILED`) all receive `wc -l`, `date` or
  array-length output — none can carry a non-numeric or leading-zero value.
- **`LNK_SCHEMA` reaches `barriers_views_build.R`** in all three callers
  (`study_area_run.sh:219` exports it globally; both sweep scripts export before
  the call), so a `--schema=` run does not build views in `fresh`.
- **Log redaction** covers the new per-job directory — `redact_log_addresses`'
  second glob `"$LOG_DIR"/"${TS:-}"_*/*` matches `${TS}_recompute.d/<WSG>.log`,
  it runs from the EXIT trap so a killed run is covered, and
  `.gitignore` excludes `*_recompute.d/` as a second line of defence.
- **Test suite** — `lnk_access`, `lnk_barriers_views`, `lnk_fanout_judge` all
  green under `testthat::test_local()`.
- **`pool_probe.sh`** — `PASS=32 FAIL=0` reproduced under bash 5.3.9 here
  (subject to finding 2 about what that number does and does not prove).
