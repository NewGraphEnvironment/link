# Review round 2 — link#264 (`fresh_sha` / `bcfishobs_sha` provenance)

Reviewer pass over the full diff (`/tmp/264_diff.txt`, 1467 lines) plus the current
contents of every changed file. Round-1's five accepted fixes were re-read and are
not re-reported; three of the four findings below are *in* or *created by* those
fixes.

Evidence gathered by running things, not by reading:

- `bash` probe of the `{ …; } >> "$RENV"` group in `cypher_prep.sh` (the
  `[ -n "$X" ] && printf` last-command shape) — **does not** trip `errexit`;
  measured `REACHED-AFTER-BLOCK`, exit 0, bash 5.3.9. No finding.
- `installed.packages()` sweep of `RemoteSha` shapes in this library: 303 carry the
  field, 22 hex-shaped (all 40 chars, all `RemoteType: github`), 281 declined. No
  md5/sha256-shaped false accept. The `^[0-9a-f]{7,40}$` guard is empirically right.
- `testthat::test_file()` on `test-lnk_pkg_git_state.R` (33 PASS), 
  `test-lnk_preflight_parity.R` (44 PASS), `test-lnk_git_dirty.R` (13 PASS) —
  0 FAIL, 0 SKIP on this machine.

---

## Findings

### 1. **[bug]** A supported host-update path leaves `fresh_sha` NA, and the new gate that rejects it fires *after* the spend

`R/lnk_preflight_parity.R:71-76` (`keys` + `forbid_na`), `data-raw/study_area_verify.sql:444-451`,
`data-raw/study_area_run.sh:386-640` (`preflight_local`)

This repo ships `scripts/update_hosts.sh` as the documented way to update `link` +
`fresh` on **m4, m1 and cypher**. It deliberately bypasses pak and r-universe:

```bash
curl -sSL -o "${pkg}-main.tar.gz" 'https://github.com/.../heads/main.tar.gz'
tar xzf …; ${need_sudo}R CMD INSTALL "${pkg}-main"
```

`R CMD INSTALL` of an extracted source tarball writes **no `Remote*` fields at all**.
Verified: `fresh`'s source-tree DESCRIPTION has `Remotes:` (the dependency pin) and no
`RemoteSha`, and 30 packages in this library carry `Built:` with no `RemoteType`. There
is also no SHA to record — the tarball is `refs/heads/main`, not a commit.

So on any host last touched by that script:

- `.lnk_pkg_remote_sha("fresh")` → `NA` (tier 2 declines — correctly),
- no `.git` beside the installed package (tier 3 declines),
- `FRESH_GIT_SHA` unset on the dispatcher; on a cypher `cypher_prep.sh` derives it from
  the same `.lnk_pkg_remote_sha()` and therefore writes nothing,
- ⇒ `fresh_sha` is `NA` on that host.

Before this change that was benign. After it, two things fail:

1. `lnk_preflight_parity()` reports `fresh_sha unresolved on: <host>` → `judge_stamps`
   exits 1 → `preflight_hosts` fails → `exit 1` → the EXIT trap **burns the cyphers**.
2. `study_area_verify.sql` RAISEs on every row.

**The placement is the expensive part.** `preflight_local()` gates `fwapg_sha` and
(new, this diff) `bcfishobs_sha` *before spend*, and both abort the run cheaply.
`fresh_sha` — promoted in the same diff to an equally run-failing condition — has **no
pre-spend gate**. It is only discovered in `preflight_hosts()`, which runs after
`cypher_up` + `cypher_prep` (the header puts a snapshot spin at 3–5 min and prep at
~20 min per host, all paid). A dispatcher that resolved `fresh_sha` yesterday and was
updated with `scripts/update_hosts.sh` overnight spins N droplets, preps them, then
throws them away.

Fix: add a `fresh_sha`-resolvable gate to `preflight_local()`, immediately beside the
fwapg / bcfishobs ones, naming the remediation (re-install `fresh` from the git ref, or
export `FRESH_GIT_SHA`). It is one `Rscript -e 'cat(link:::.lnk_pkg_git_state("fresh")$sha)'`
and it converts a burn-after-prep into a pre-spend abort.

**Related, and a factual error in the round-1 fix's own justification.** The comment
defending the shape guard reads:

```
# and `dirty = FALSE` asserting it. `fresh` is r-universe-installable
# (`scripts/update_hosts.sh`), so this is a reachable state, not a hypothetical.
```
— `R/lnk_stamp.R:297-298`

`scripts/update_hosts.sh` does the opposite: its own header says *"Bypasses pak … using
R CMD INSTALL on a downloaded source tarball"* and *"r-universe binaries are
R-version-specific"* is listed as the reason **not** to use them. The guard is still
correct and still worth having, but the cited evidence names a script that produces a
**different and worse** state than the one described (no `RemoteSha` whatsoever, rather
than a version-shaped one) — and that state is exactly the operational regression above.
Re-word the citation, and let it point at the missing gate.

### 2. **[bug]** `fresh_dirty = TRUE` is reported nowhere and asserted nowhere — the verify declares such a run "provenanced"

`data-raw/study_area_verify.sql:179-195` (§1), `:219-250` (§1b), `:329-473` (DO block)

Sweeping every single-fault state against §1b and the DO block, they agree on all nine
states the diff touches — except one, which has no arm at all:

| single fault | §1b verdict | DO block |
|---|---|---|
| `link_sha` NULL | FAIL | raise (`n_prov`) ✓ |
| `fwapg_sha` NULL | FAIL | raise (`n_prov`) ✓ |
| `bcfishobs_sha` NULL | FAIL | raise (`n_prov`) ✓ |
| `link_dirty` TRUE | FAIL | raise (`n_prov`) ✓ |
| `fresh_sha` NULL | FAIL | raise (`n_fresh`) ✓ |
| `bcfp_model_version` NULL, no escape | FAIL | raise ✓ |
| `bcfp_model_version` NULL, `unpinned_ok` | NOTE | NOTICE ✓ |
| `link_dirty` NULL | NOTE | — ✓ |
| `fresh_dirty` NULL | NOTE (new) | — ✓ |
| **`fresh_dirty` TRUE** | **nothing — verdict `OK`** | **nothing — `PASS`** |

So no arm labelled FAIL exits 0, and no FAIL is printed on a run the script declares OK
— the two invariants asked about hold. The hole is the state with **no arm**.

This diff is what makes it matter. Before #264 `fresh_dirty` was NULL on all 39 logged
rows and carried no information; the diff makes it resolvable (tier 2 infers `FALSE`,
tier 1 reads `FRESH_GIT_DIRTY`, tier 3 walks `.git`) and adds a NOTE for the **weaker**
state (`IS NULL`, "provenance unknown"). The **stronger** state — the tree was modified,
so the `fresh_sha` this same script now *mandates* is a lie — is silent in the §1
summary table (which counts `link_dirty` only), silent in the §1b verdict, and silent in
the DO block, whose closing NOTICE reads:

```
'PASS: run % -- % WSG(s), all modelled, recomputed, segmented and provenanced'
```

`link_dirty = TRUE` is a hard FAIL by exact symmetry (`n_prov`). Reachable via
`FRESH_GIT_DIRTY=1`/`true` in the environment or `~/.Renviron`, or via the tier-3 `.git`
walk on any host running `fresh` from a source checkout — which is the ordinary dev/local
configuration, and local runs do write `fresh.log` rows this script verifies.

Fix: one arm in §1b (`FAIL: fresh_dirty set — the recorded fresh_sha does not describe
the tree that ran`) and `OR fresh_dirty` in the `n_prov` predicate, plus
`count(*) FILTER (WHERE fresh_dirty) AS n_fresh_dirty` in §1. Then add it to the
`for col in …` loop in `study_area_verify_negative.sh` — the loop was written precisely
so a third column joins by adding one word.

### 3. **[fragile]** The new bcfishobs dirty probe fails toward "skip", and nothing downstream can detect the miss

`data-raw/study_area_run.sh:523-533`

```bash
if BCFISHOBS_SHA=$(git -C "$bcfo_dir" rev-parse HEAD 2>/dev/null) && [ -n "$BCFISHOBS_SHA" ]; then
    if bcfo_dirty=$(git -C "$bcfo_dir" status --porcelain 2>/dev/null); then
      [ -z "$bcfo_dirty" ] || { echo "  ✗ …dirty…"; fail=1; }
    fi
    export BCFISHOBS_GIT_SHA="$BCFISHOBS_SHA"
    echo "  ✓ bcfishobs_sha ${BCFISHOBS_SHA:0:12} (exported to all hosts)"
```

If `git status` errors (index lock, permissions, an interrupted operation) the inner `if`
is false, **no branch reports anything**, `fail` stays 0, the SHA is exported to every
host and the line prints with a ✓. That is the "assign first, test the exit status, then
test the value" shape from `code-check.md` with the error branch missing.

It matters more here than in the `fwapg` block it copies, because the block's own comment
makes the claim load-bearing:

```
# There is deliberately NO bcfishobs_dirty column —
# this gate is what makes a recorded SHA clean by construction
```

With no `bcfishobs_dirty` column, this gate is the *only* thing standing between a
modified `bcfishobs` checkout and a `bcfishobs_sha` recorded as fact on 217 rows. A
skipped check is unrecoverable after the fact.

Fix: `else echo "  ✗ could not read bcfishobs git status — cannot certify the SHA"; fail=1; fi`.
The same `else` is missing from the fwapg block above it (pre-existing); worth doing both
in one edit.

### 4. **[fragile]** Cross-host `fresh_sha` *disagreement* is invisible post-run, and §1b's heading no longer describes it

`data-raw/study_area_verify.sql:198`, `:260-263`

The diff's thesis is that `fresh_sha` is now "the one field that proves every host is
running the same `fresh` **build**". But the verify script's own section for that
question still reads:

```sql
\echo '=== 2. The distinct SHAs -- all hosts must agree ==='
SELECT DISTINCT link_sha, fwapg_sha, bcfp_model_version
```

`fresh_sha` and the new `bcfishobs_sha` are absent, and every FAIL arm in §1b tests only
`IS NULL`. So a run in which the dispatcher and a cypher carry **two different non-NULL**
`fresh_sha` values passes this script silently — the exact link#246 shape, one step short
of the NULL case the diff hardens against. `lnk_preflight_parity()` covers it, but only
*before* the writes; a cypher re-prepped mid-run (`--auto-install`, or a manual
re-install after a failure) is outside that window, and this script is the post-hoc
authority.

Cheapest fix: add `fresh_sha, bcfishobs_sha` to §2's `DISTINCT`, and assert
`count(DISTINCT fresh_sha) > 1` in the DO block.

Minor, same file: `\echo '=== 1b. Provenance verdict (host-aware) ==='` — the change
removed the host-awareness (`host <> 'm1'` is gone from both the arm and the assertion),
so the heading now misdescribes the check it labels.

---

## Checked and clean

Recorded so a later round does not re-derive them.

- **The round-1 fixes themselves.** The `RemoteType` skip gate is independent of the
  function under test; the hex guard declines all 281 non-hex `RemoteSha` values in this
  library and accepts only 40-char github ones; `identical(sha, remote_sha)` correctly
  refuses to attach tier-2's `FALSE` to an env-supplied SHA that is not the built commit
  (test at `test-lnk_pkg_git_state.R:143-163` restores the wrong-commit case and asserts
  `NA`, then that `FRESH_GIT_DIRTY` still recovers it). `man/*.Rd` matches the roxygen.
- **`cypher_prep.sh` strip + append cannot accumulate keys across preps.** The
  `grep -vE '^(LINK_GIT_SHA|LINK_GIT_DIRTY|FRESH_GIT_SHA|FRESH_GIT_DIRTY)='` filter is
  anchored and includes the `=`, and it runs *before* the append, so a stale
  `FRESH_GIT_SHA` from a previous prep is removed even when the new prep resolves nothing.
  `RC` is captured and only `>1` is fatal, so the ordinary empty-file case survives.
  `FRESH_DIRTY` is set only when `FRESH_SHA` is non-empty, so the two keys cannot
  disagree. `chmod 600` + `umask 077` still cover the temp file.
- **`errexit` on the append group.** Measured, not reasoned: the trailing
  `[ -n "$FRESH_DIRTY" ] && printf …` returning 1 as the group's last command does **not**
  abort under `set -euo pipefail`. Adding the second such line changed nothing.
- **Both ssh legs carry the export.** `BCFISHOBS_GIT_SHA` is inside the quoted command
  string at both `study_area_run.sh:661` (`collect_stamps`) and `:951` (the per-WSG run
  loop) — the link#227 both-legs trap. The recompute pool (`:1012`) runs on the dispatcher
  and inherits the `export` from `preflight_local`, which executes in the current shell
  (`preflight_local || { … }` is an OR-list, not a subshell), so no third leg is needed.
  `host_vintage.R` over ssh needs neither var.
- **INSERT column/value alignment** for both `log` and `log_recompute`: `fresh_sha_source`
  and `bcfishobs_sha` land in matching positions in `cols` and `vals` in both paths.
  No off-by-one.
- **`nullif(c.reltuples, -1)`** and the paired `CASE … THEN NULL ELSE TRUE END` are
  type-safe (float4 vs integer literal resolves; `::bigint` rounding unchanged from the
  prior `c.reltuples::bigint`), and the test asserts the bare form is *gone*, not merely
  accompanied.
- **New columns and cross-host COPY.** `.lnk_log_align_columns()` appends via
  `ADD COLUMN IF NOT EXISTS` on existing tables while a fresh droplet creates them in
  `cols_log` order, so dispatcher and cypher `log` tables can differ in column *order*.
  `schema_consolidate.R:213-260` already resolves the shared column set on both sides and
  emits an explicit ordered column list on both `COPY` statements (link#204), so this is
  safe. No finding.
- **`study_area_verify_negative.sh` cases 5/6/7.** The premise-skip is counted into
  `fails` (`:251`), matching cases 2 and 4. Neither case can pass vacuously: nulling
  `fresh_sha` fires only `n_fresh` (it is not in the `n_prov` predicate) and nulling
  `bcfishobs_sha` fires only `n_prov`, so each case discriminates its own assertion. The
  restores are correlated on `(host, watershed_group_code)` per row, so they do not
  flatten the column for the next iteration, and case 7 re-runs the healthy check to make
  the restores load-bearing. `run_verify` cannot distinguish "the assertion fired" from
  "psql blew up", but cases 1 and 7 bracket that. The loop counter `n` shadows nothing.
  Run against a pre-#264 persist the `n_present` probe errors loudly under
  `ON_ERROR_STOP` rather than skipping silently — acceptable.
- **`forbid_na` addition and existing callers.** `host_stamp.R` only emits a row and never
  calls parity; `judge_stamps()` takes the new defaults deliberately and its
  `forbid_dirty = FALSE` override is unaffected. `.lnk_preflight_stamp_cols()` already
  carries `fresh_sha` at position 5, so the TSV round-trip is unchanged. The only
  behavioural consequence is finding 1.
- **No performance or ordering regression in `.lnk_pkg_git_state()`.** Tier 2 only *adds*
  resolutions (it precedes the `.git` walk, but an installed package has no `.git` and a
  `load_all` tree has no `Remote*`), and `lnk_stamp()` now performs two lookups where it
  previously performed four.
