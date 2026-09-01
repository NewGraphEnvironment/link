# Code review — round 2 (#246, `main..HEAD`)

Scope: `git diff main..HEAD`, all changed files read in full from the working
tree. Focus per the round-2 brief: the six round-1 fixes in commit `0b618ca`,
and invariants held together by two lists agreeing.

Round-1 fix verdicts:

| # | fix | verdict |
|---|---|---|
| 1 | `is_unresolved()` / NA normalisation / `na.strings = character(0)` | **works**, both halves; verified by reproducing the drift the tests describe |
| 2 | unreachable schema-collision guard removed | **works** — the name-based guard at :131 covers every config, and the branch it was in was provably dead |
| 3 | `cypher_prep.sh` grep branches on exit status | **BROKEN — see finding 1.** The new guard is unreachable *and* it hard-aborts prep on the ordinary case |
| 4 | `wsgs_run_pipeline.sh` passes `CYPHER_PREP_BRANCH` | **works**; swept for other callers — all in-repo call sites now pass it (the only omission left is a prose snippet in `research/post_compact_provincial_handoff.md`) |
| 5 | `--preflight-only` reports what it did not check | **works** |
| 6 | `LNK_PREFLIGHT_DO_URL` restricted to https | **works** as described (TLS only — the comment claims no more than that) |

Also checked and found clean, so they need no further attention:

- **`study_area_buckets.R` union-find** is correct. Path-halving with `<<-`
  behaves (superassignment resolves `parent` in the script's global frame and
  the indexed form writes back); `seen[[m]]` on a missing key returns `NULL`,
  not an error; `parent` stays integer end-to-end because both `union2()`
  arguments originate in `seq_along()` (a double would coerce the vector and
  break the `vapply(..., integer(1))` — verified, but not reachable here).
  Replicated the whole loop on a 5-node fixture: correct components.
- **LPT pack + host relabelling** are correct and deterministic. `order(-w)`
  and `which.min()` both break ties by first index; `relabel` maps old→new
  correctly and `load_h[host_order]` stays consistent with it. Confirmed
  against the committed `research/study_areas.md` (dispatcher = heaviest).
- **`--write` path resolution** works from the repo root via
  `commandArgs(FALSE)`, and fails loud (`stop("cannot locate research/...")`)
  when `--file=` is absent, e.g. under `R -f`.
- **`check_bucket_complete`**: `local done_n` is declared separately, so
  `done_n=$(grep -c …) || done_n=0` captures grep's status correctly; `$3` can
  never be empty (`grep -c` always prints a number, and the `||` fallback
  covers the pipefail case). BSD grep on macOS *does* support `\|`/`\(` in a
  BRE — measured against `/usr/bin/grep`, 2 matches — so the alternation is
  fine. `wsg_run_one.R` emits both sentinels (`… done in`, `… SKIP —`) on
  stdout at line start.
- **Empty arrays under `set -u`**: `"${CY_WS_ARR[@]}"` is expanded
  unconditionally in several places and *does* abort under bash 3.2 — but
  `declare -A` (pre-existing, :560/:578) already requires bash 4+, and
  `env bash` resolves to 5.3 here. Not a new exposure.
- No other `|| true` on a truncating redirect, and no other bare-command-then-`$?`
  under `set -e`, anywhere in the changed scripts.
- `devtools::test(filter = "preflight")`: `FAIL 0 | PASS 90`.

---

## Findings

### 1. **[bug]** `data-raw/cypher_prep.sh:162` — round-1's `.Renviron` guard aborts prep on every fresh cypher, and its FATAL branch can never run

```bash
grep -vE '^(LINK_GIT_SHA|LINK_GIT_DIRTY|FRESH_GIT_SHA)=' "$RENV" > "$RENV.tmp"
RC=$?
if [ "$RC" -gt 1 ]; then ... fi
```

The file opens with `set -euo pipefail` (:80) and this grep is a bare simple
command at top level — not in an `if`, not in an `&&`/`||` list. `grep -v`
exits **1** when it selects no lines, so `set -e` kills the script *at the
grep*. `RC=$?` and the entire FATAL branch round 1 added are unreachable: the
exit-2 read error it was written to catch would abort the same way, silently.

Reproduced:

```bash
$ cat t1.sh
set -euo pipefail
: > empty.txt
grep -vE '^(A|B)=' empty.txt > empty.tmp
RC=$?
echo "REACHED RC=$RC"
$ bash t1.sh; echo "exit=$?"
exit=1              # "REACHED" never prints
```

When it fires:

- **`~/.Renviron` empty or absent** — `touch` creates it empty, grep selects
  nothing, exit 1. This is the expected state of a fresh droplet, so it is the
  *first* prep on every cypher.
- **Idempotent re-prep** of a host whose `~/.Renviron` contains only the three
  keys this block owns — same result. The header advertises "Idempotent — safe
  to re-run", and `study_area_run.sh --auto-install` (:481) re-runs
  `cypher_prep.sh` on this same path.

Blast radius: the prep dies with **no message** (the `echo` is past the abort),
after `git reset`, `pak::local_install` and the provenance line have already
run. `study_area_run.sh`'s `grep -qx "=== READY"` then reports `FATAL:
cypher[$WS] prep failed` and the EXIT trap burns — so spin cost is paid and the
operator gets a log that just stops mid-file. Round 1 traded a
fail-toward-silence bug for a fail-toward-abort one on the common path.

Fix — keep the branch, make the status reachable:

```bash
RC=0
grep -vE '^(LINK_GIT_SHA|LINK_GIT_DIRTY|FRESH_GIT_SHA)=' "$RENV" > "$RENV.tmp" || RC=$?
if [ "$RC" -gt 1 ]; then
  echo "FATAL: could not read $RENV (grep exit $RC); refusing to overwrite it" >&2
  rm -f "$RENV.tmp"; exit 1
fi
```

Test it against both known answers before shipping: an empty `.Renviron` (must
proceed) and an unreadable one, e.g. `chmod 000` (must print FATAL and exit 1).
Neither case currently reaches the code that distinguishes them.

---

### 2. **[bug]** `data-raw/study_area_run.sh:426` vs `R/lnk_preflight_stamp.R:62` — nothing enforces `STAMP_COLS` matches the R field order, and a one-column drift makes the parity gate report "OK" for hosts on different commits

The mechanism question. `judge_stamps()` passes the shell constant

```
STAMP_COLS="host,link_version,link_sha,fresh_version,fresh_sha,repo_sha,repo_dirty,config_hash,fwapg_sha,r_version"
```

as `col.names` to `read.delim()`, while the row itself is produced by
`lnk_preflight_stamp()`. Two independently-maintained lists.

`test-lnk_preflight_parity.R:99-106` carries the comment *"This is what keeps
the shell's STAMP_COLS and the R field order from silently diverging"* — but it
asserts `names(s) == .lnk_preflight_stamp_cols()`, i.e. **R against R**. Nothing
in the repo reads `study_area_run.sh`. The invariant is held only by the two
lists happening to agree today.

`read.delim()` does not fail on the drift. With **fewer** data fields than
`col.names` it left-shifts every column past the removed one and pads the last
with `""` — no warning:

```r
# R's stamp drops `fresh_sha`; STAMP_COLS unchanged. cy-job2 is on a
# DIFFERENT commit (clean).
s <- read.delim(tsv, header = FALSE, colClasses = "character",
                na.strings = character(0), col.names = shell_cols)
lnk_preflight_parity(s, n_expected = 3, quiet = TRUE)
#> ok = TRUE
#> [preflight] host parity - OK across 3 host(s): m1, cy-job1, cy-job2
```

The real `repo_sha` lands in the `fresh_sha` column, which is deliberately not
a key; the `repo_sha` *key* now holds `repo_dirty` ("FALSE" everywhere), so it
agrees. `forbid_na` sees nothing empty or `"NA"`. A cypher running a different
commit passes — exactly the failure #246 exists to close, reported as clean.
(A `+1` drift is loud but for the wrong reason: the extra field wraps onto a new
row and the gate reports "a host did not report".)

Fix, and it removes the second list rather than guarding it: `judge_stamps()`
already runs `pkgload::load_all()`, so it can read the column names from the one
definition and drop `STAMP_COLS` entirely —

```r
cols <- link:::.lnk_preflight_stamp_cols()
s <- utils::read.delim(a[1], header = FALSE, colClasses = "character",
                       na.strings = character(0), col.names = cols)
```

then assert `ncol(s) == length(cols)` and that no row parsed short, so a
future shape change fails on the shape rather than on a shifted comparison.

---

### 3. **[fragile]** `data-raw/study_area_run.sh:279` — `git fetch … || true` lets the branch-pushed gate print a false green

```bash
git -C "$REPO_ROOT" fetch --quiet origin "$LINK_BRANCH" 2>/dev/null || true
```

The comment two lines above states the fetch is load-bearing: *"@{upstream} is
a LOCAL ref, so without this the check compares against a stale copy and is a
false green."* `|| true` then makes a failed fetch indistinguishable from a
successful one, and the `rev-list --count '@{upstream}..HEAD'` below runs
against exactly the stale ref the comment warns about — printing
`✓ origin/$LINK_BRANCH is at HEAD`.

Concretely: the remote branch has been deleted (or auth/network failed) while a
local `refs/remotes/origin/<branch>` still exists at HEAD → gate green → the
run spins droplets → `cypher_prep`'s `git reset --hard origin/$BRANCH` fails →
caught only by the READY grep, after paying for the spin. The whole point of
`preflight_local` is "predict before spend".

Not rated higher because `preflight_hosts`' `repo_sha` comparison is a genuine
backstop for the drift direction that survives to prep — but that check runs
*after* the spin, which is what this gate was added to avoid.

Fix: branch on the fetch, the same shape used everywhere else in this file.

```bash
if ! git -C "$REPO_ROOT" fetch --quiet origin "$LINK_BRANCH" 2>/dev/null; then
  echo "  ✗ could not fetch origin/$LINK_BRANCH — cannot verify the branch is pushed"
  fail=1
fi
```
