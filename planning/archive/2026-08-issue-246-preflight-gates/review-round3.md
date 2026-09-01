# Code review — round 3 (#246 branch, `main..HEAD` @ 02b2e44)

Scope: narrow + deep on the files edited most (`data-raw/study_area_run.sh`,
`data-raw/cypher_prep.sh`), verification of round 2's three fixes, then a sweep
of the whole diff for the recurring classes.

## Round 2's fixes — verified

### 1. `cypher_prep.sh:167-174` `.Renviron` strip-and-append — **behaviour correct**

Exercised the exact block in a sandbox across all five cases. Results:

| case | outcome |
|---|---|
| `.Renviron` absent | `touch` creates it, RC=1, keys appended, exit 0 |
| empty | RC=1, keys appended, exit 0 |
| only owned keys | RC=1, old keys stripped, new appended, exit 0 |
| unrelated keys only | RC=0, unrelated preserved, keys appended |
| mixed | RC=0, unrelated preserved, owned key replaced (not duplicated) |

`RC > 1` FATAL is reachable for a genuine read error, and the `rm -f "$RENV.tmp"`
before `exit 1` means a real grep error leaves the original file untouched. If
the redirect itself fails, RC=1 (indistinguishable from "no lines matched") but
the subsequent `mv` then fails loudly under `set -e`. `touch "$RENV"` failing
also aborts under `set -e`. Correct in all cases. *(One non-functional problem
with this block — see finding 2.)*

Also checked the adjacent `{ ...; [ -n "$FRESH_SHA" ] && printf ...; } >> "$RENV"`.
CLAUDE.md warns that a false leading test in a bare `&&` list aborts under
`set -e`; measured on bash 5.3 it does **not** — errexit stays suspended for the
whole `&&` list and for the enclosing brace group, and execution continues.
Confirmed empirically with an empty `FRESH_SHA`. Not a bug.

Swept the rest of `cypher_prep.sh` for bare commands whose exit 1 is ordinary:
the pak block, the fresh-override block, the export assertion, the snapshot and
`persist_init` all use the `if ! cmd > tmp` idiom; `git rev-parse` / `git status`
are assign-then-test. Nothing else abort-prone.

### 2. `study_area_run.sh:454-478` `judge_stamps()` — **arg shift correct**

`judge_stamps` now takes 2 args (`$1` tsv, `$((N_CY+1))`), read as `a[1]`/`a[2]`;
`STAMP_COLS` is gone and `col.names` comes from `.lnk_preflight_stamp_cols()`.
Verified `.lnk_preflight_stamp_cols()` resolves under `pkgload::load_all()` in a
fresh `Rscript` (export_all default) — returns 10 names. Ran `host_stamp.R`
end-to-end: emits exactly 10 tab-separated fields, no stray stdout. `$1` is an
absolute path so the `cd "$REPO_ROOT"` is harmless.

The "two lists happening to agree" residue — `lnk_preflight_stamp()`'s literal
field order (`R/lnk_preflight_stamp.R:48-57`) vs `.lnk_preflight_stamp_cols()`
(`:67-70`) — **is guarded**: `tests/testthat/test-lnk_preflight_parity.R:107`
asserts `identical(names(s), .lnk_preflight_stamp_cols())`. Measured the failure
direction anyway: a dropped field left-shifts and pads (silent false green), an
added field wraps into a second row (`nrow != n_expected`, fails). The test
closes the dangerous direction.

### 3. `study_area_run.sh:284-305` branch gate `if/elif/else` — **no orphaned arm**

Three arms, all setting `fail=1` or printing `✓`: fetch-failed, no-upstream, and
the else with its own assign-then-test on `rev-list --count` plus an explicit
error arm. Detached HEAD (`LINK_BRANCH=""`) makes `git fetch origin ''` fail →
arm 1 → `fail=1`, so it cannot silently ship cyphers to `main`.

## Sweep — other recurring classes

- **Bare exit-1-normal commands.** Every `grep`/`pg_isready` added by the diff is
  guarded (`|| RC=$?`, `|| n=0`, `|| { …; fail=1; }`, `if !`). `$(( ))` is
  arithmetic *expansion*, not the `(( ))` command, so no exit-status hazard.
  `check_bucket_complete`'s two `grep -c` calls are `$(...) || var=0` and are
  additionally inside a function invoked via `||` (errexit suspended) — safe.
- **`grep -c '^\[wsg_run_one\] .* \(done\|SKIP\)'`** uses GNU BRE `\|`. Tested
  against `/usr/bin/grep` on this Darwin box: alternation works, counts 2/2 on
  real-shaped input. Not the documented BSD portability trap.
- **`grep -qx "=== READY"`** correctly rejects `=== READY (install stage only; …)`.
  Verified the anchoring claim in the comment.
- **Coverage post-condition** (`:769-784`): `psql -c` returns **1** on a SQL error
  (measured against the live fwapg), so a missing `${SCHEMA}.streams` takes the
  `else` FATAL branch rather than producing an empty `$MISSING` false green.
- **Empty-bucket paths**: `study_area_wsgs.R:42` `stop()`s on an empty resolve, so
  the `grep -v '^$'` pipelines at `:584` / `:731` / `:753` cannot be reached with
  all-empty input under `pipefail`. Not a live abort.
- **`export FWAPG_GIT_SHA`** inside `preflight_local` reaches the parent shell —
  the function is not a subshell and `||` does not make it one. Verified the
  consumers at `:444` and `:676`.
- **R side**: all 90 preflight tests pass; all four new `@examples` blocks run
  clean via `pkgload::run_example()`. `.lnk_fresh_required()` is drift-guarded by
  `.lnk_fresh_callsites()` (namespace walk, includes `formals()`), the version
  floor is derived from DESCRIPTION and cross-checked, `.lnk_vintage_primitives()`
  is derived from `.lnk_input_primitives()`. Union-find in
  `study_area_buckets.R:114-138` is correct (verified against a hand-built case),
  and the host relabel at `:192-195` does put the heaviest bucket on host 1
  (traced with concrete loads). Disjointness is asserted, not assumed.

## Findings

### 1. [bug — data loss] `data-raw/study_area_run.sh:717-722`

The new completeness gate `exit 1`s **before** consolidate while `CYPHERS_UP=1`
(set at `:604`), so the `trap burn_cyphers EXIT` at `:219` destroys every cypher
droplet. Every WSG the cyphers *successfully* modelled — sitting in their local
persists, not yet copied — goes with them. One failed WSG on any one host throws
away the whole paid run, unrecoverably.

This is the accident the comment 60 lines above names verbatim (`:651-655`):

> It must NEVER abort the host and trip the trap-burn before consolidate — that
> lost a whole run + the cyphers' data on 2026-05-25 (one species-less WSG ->
> exit 1 -> FATAL -> burn).

The gate's own comment reasons only about the DELETE ("Refusing to consolidate —
consolidate DELETEs before it COPYs"), which is correct, and says nothing about
the burn that follows. Refusing is right; burning first is not. The operator's
only pre-emptive escape is having passed `--keep-cyphers` at launch.

**Amplifier.** `done_n` comes from `grep`ping a literal log string produced by a
*different* file — `wsg_run_one.R:56` (`SKIP —`) and `:88` (`done in %.1f min`).
Nothing ties the regex to those `cat()` calls; no test crosses that seam. Reword
either message and `done_n` becomes 0 on **every** host simultaneously, which
routes straight through this gate to the burn. The failure direction of a
string-matching contract is normally "stop", which is fine — here "stop" means
"destroy the run's output".

Failure scenario: 3 cyphers × 28 WSGs, one WSG on cy[job2] errors (a DB blip, a
guard error, anything the soft-fail was built to absorb). `check_bucket_complete`
reports 27/28, `complete_fail=1`, `exit 1`, trap fires, all three droplets
destroyed. 83 successfully-modelled WSGs lost; hours of paid compute; no recovery
path.

Suggested fix, keeping the spend safety-net intact: consolidate the *successful*
subset — `schema_consolidate`'s DELETE and COPY are both scoped to the per-source
`bucket=` (`schema_consolidate.R:272-276`, `:313-316`), so narrowing each source's
bucket to the WSGs that actually reported `done`/`SKIP` consolidates what exists
without deleting anything for the missing ones — then fail loudly *after* the burn
with the incomplete WSGs named. Cheaper alternative: set `KEEP_CYPHERS=1` and
print the exact manual `schema_consolidate` invocation plus the IPs before
`exit 1` (accepting the idle spend as the price of not discarding the work).

### 2. [security] `data-raw/cypher_prep.sh:156-174`

The strip-and-append rewrite replaces `~/.Renviron` with `$RENV.tmp`, which is
created by a plain `>` redirect at the default umask — so the file's mode is not
preserved. Measured:

```
before:  -rw-------  .Renviron   (PG_PASSWORD_SHARE=…)
after:   -rw-r--r--  .Renviron   (same contents + the three new keys)
```

`~/.Renviron` is exactly where this stack keeps DB credentials — CLAUDE.md
"Database Connection" documents `PG_*_SHARE` / `PG*` env vars as the connection
path, and this block's own header comment assumes "the image may keep unrelated
settings here". Every re-prep silently widens the mode; it never narrows back.
The intermediate `~/.Renviron.tmp` holds the full contents at the same widened
mode, at a predictable path, for the duration of the block.

Low blast radius (single-user droplet, short-lived), but it is a credentials file
being world-readable by a script whose stated purpose is to preserve what is in
it.

Fix — one of:

```bash
umask 077                              # around the block, restore after
# or
grep -vE '…' "$RENV" > "$RENV.tmp" || RC=$?
chmod 600 "$RENV.tmp"                  # before the mv
```

Better still, mirror the original: `chmod --reference` is GNU-only, so capture
`stat -f '%Lp'` (BSD) before and re-apply after the `mv`.

## Adjacent, pre-existing (not introduced by this diff)

`burn_cyphers` at `:212-214` fails toward "clean":

```bash
if doctl compute droplet list --no-header 2>/dev/null | grep -qi cypher; then
  echo "  ✗ doctl still shows cypher droplets"; clean=0
else echo "  ✓ doctl: no cypher droplets"; fi
```

An expired/unreachable `doctl` produces empty output, `grep` exits 1, and the
`else` prints an affirmative "no cypher droplets" on the strength of a command
that never ran successfully — leaked droplets, reported clean. Unchanged by this
branch, but this PR's own pre-flight exists *because* both DO tokens expired on
2026-08-30, so the scenario is live, and finding 1 makes the burn path much more
reachable. Branch on `doctl`'s exit status separately from the grep.
