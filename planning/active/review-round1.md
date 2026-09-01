# Code review — link#264 (round 1)

Reviewed: `R/lnk_stamp.R`, `R/lnk_log.R`, `tests/testthat/test-lnk_pkg_git_state.R`,
`tests/testthat/test-lnk_log.R`, `tests/testthat/test-lnk_stamp.R` against
`soul/conventions/code-check.md` and link's `CLAUDE.md`.

Suite on this machine: `test-lnk_pkg_git_state.R` 28 pass / 0 skip,
`test-lnk_log.R` 251 pass / 0 skip, `test-lnk_stamp.R` 39 pass / 0 skip.

## Findings

### 1. [bug] tests/testthat/test-lnk_pkg_git_state.R:27,76,90,105,159 — every tier-2 test is gated by the function it tests, so the regression they guard makes them all *skip* and the suite stays green

Five tests cover the new `RemoteSha` tier. All five are guarded by
`skip_if(is.na(.lnk_pkg_remote_sha("fresh")), ...)` — the skip condition is
computed by the very function whose output they assert on. That includes the
one at line 27 written explicitly as the premise ("If a future install method
stops recording RemoteSha, THIS fails and names the real cause").

Restore-the-bug, patching both bindings so the tier returns `NA` — which is
exactly the pre-change behaviour and exactly the defect link#264 exists to fix:

```r
for (e in list(asNamespace("link"), as.environment("package:link"))) {
  unlockBinding(".lnk_pkg_remote_sha", e)
  assign(".lnk_pkg_remote_sha", function(pkg) NA_character_, e)
}
# PROOF patch took, fresh remote sha now: NA
testthat::test_file("tests/testthat/test-lnk_pkg_git_state.R")
```

Result: **FAIL 0, ERROR 0.** Five tests report `SKIP — installed fresh has no
RemoteSha`, including the premise test. Nothing turns red for the regression
the file was written to catch. (Normal run: 0 skips, so the skips appear only
when the function breaks — which is the failure mode, not a property of this
machine.)

This is the repo's own "Tests that silently do not run" plus "A guard's escape
hatches are where it goes to die" in one place: a skip is not a pass, and here
the skip is *derived from the thing under test*.

Fix: key the skip on an independent fact, so a regression in the function under
test cannot silence its own tests. `packageDescription("fresh")$RemoteType` is
`"github"` here and is not produced by any code in this diff:

```r
skip_if(!identical(utils::packageDescription("fresh")$RemoteType, "github"),
        "installed fresh was not installed from a git ref - tier unexercised")
```

Better still for at least one of them: write a fixture DESCRIPTION into a
`withr::local_libpaths()` temp library so the tier is exercised unconditionally
in CI, where no `fresh` install is guaranteed at all.

### 2. [bug] R/lnk_log.R:1116 — the roxygen states an export that does not exist, and without it `bcfishobs_sha` is NULL on every cypher row

```
#' Same three tiers as [.lnk_fwapg_sha()], and exported to every host by
#' `data-raw/study_area_run.sh`'s `preflight_local()` for the same reason:
#' a cypher has no `bcfishobs` checkout at all, so without the export every
#' cypher row would land NA.
```

`BCFISHOBS_GIT_SHA` appears in **no** shell script:

```
$ grep -rn "BCFISHOBS" data-raw/*.sh scripts/*.sh
(no output)
$ grep -n "export FWAPG_GIT_SHA" data-raw/study_area_run.sh
502:    export FWAPG_GIT_SHA="$FWAPG_SHA"
925:  ssh "cypher@$IP" "... export FWAPG_GIT_SHA='${FWAPG_GIT_SHA:-}' ..."
```

`preflight_local()` resolves and exports `FWAPG_GIT_SHA` (line 490-507) and
`LNK_BCFP_MODEL_VERSION` (line 509-534) and nothing for bcfishobs. The ssh
command string at line 925 carries neither. A cypher has no
`~/Projects/repo/bcfishobs`, so `.lnk_checkout_sha()` falls through to
`NA_character_` and the new column lands NULL on every cypher row — the
identical hole `fwapg_sha` had in #246 and the one this issue exists to close.

`planning/active/task_plan.md:74` has `- [ ] preflight_local() resolves
BCFISHOBS_GIT_SHA` still unchecked, so this is half-landed work whose docstring
already reads as done. Either land Phase 3 before this ships, or reword the
block to describe the intent rather than assert the mechanism — a comment
claiming a shortcut is safe is load-bearing, and this one is currently false.

### 3. [fragile] R/lnk_stamp.R:375-383 — `dirty = FALSE` is inferred from `RemoteSha` even when the reported `sha` came from the env tier and is a different commit

```r
dirty <- if (!is.na(env_dirty)) env_dirty
         else if (!is.na(remote_sha)) FALSE      # <- about remote_sha's commit
         else if (!is.null(git$dir)) .lnk_git_dirty_at(git$dir)
         else NA
```

`sha` and `dirty` walk their own tier lists (deliberate, and right for the
cypher case), but the tier-2 dirty inference is a statement about the commit
`RemoteSha` names, and it is applied to whatever `sha` ended up being.
Measured:

```
installed RemoteSha : 7f12d99115b7d20302d5ed043188cb870f90f83b
reported sha        : 0000000000000000000000000000000000000000   (FRESH_GIT_SHA)
reported source     : env
reported dirty      : FALSE   <- clean asserted about a sha never built here
```

Benign today only because `cypher_prep.sh:150-152` derives `FRESH_SHA` **from**
`packageDescription("fresh")$RemoteSha`, so the two agree by construction. But
`FRESH_GIT_SHA` is documented as an operator knob (`RUNBOOK.md:475`), and
`fresh_dirty` is the one field that exists to say "this SHA cannot be trusted".
Presence of a `RemoteSha` is not provenance for a *different* sha.

One-line fix that preserves the cypher case exactly (there `env_sha ==
remote_sha`, so it still resolves FALSE) and closes the false one:

```r
} else if (!is.na(remote_sha) && identical(sha, remote_sha)) {
  FALSE
```

Note `tests/testthat/test-lnk_pkg_git_state.R:158-165` currently **pins the
wrong behaviour** — `FRESH_GIT_SHA = "abc123"` followed by
`expect_false(.lnk_pkg_git_dirty("fresh"))` asserts clean about a sha the
machine never built. That assertion needs to move to `expect_true(is.na(...))`
if the fix lands.

### 4. [fragile] R/lnk_stamp.R:289-294 — `RemoteSha` is a package *version string*, not a commit, for `RemoteType: standard` installs

`.lnk_pkg_remote_sha()` returns whatever is in the field, unvalidated. Measured
on this machine's library:

```
n packages with RemoteSha : 300
non-40-hex RemoteSha       : 278      (all RemoteType: standard)
  abind      standard  "1.4-8"
  arrow      standard  "25.0.0"
  bcdata     standard  "0.5.3"
```

`fresh` is `RemoteType: github` today, so the tier is correct as installed. But
if `fresh` is ever installed from a CRAN-like repo — and
`scripts/update_hosts.sh:36` shows r-universe is explicitly on the table for
these two packages — the resolver writes `fresh_sha = "0.33.0"` with
`fresh_sha_source = "remote_sha"` and `fresh_dirty = FALSE`. That is a version
string silently landing in a column documented and asserted-on as a commit:
`data-raw/study_area_verify.sql:216,426` branch on `fresh_sha IS NULL` per host,
and `lnk_preflight_parity` compares SHAs across hosts, so a mixed-install fleet
would compare `"0.33.0"` against `7f12d99…` and a uniform one would compare
`"0.33.0"` against itself and pass while the commit is unknown.

The test at line 30 already asserts the shape (`^[0-9a-f]{40}$`); the production
code does not. Guard it there:

```r
sha <- .lnk_blank_to_na(d$RemoteSha)
if (!is.na(sha) && !grepl("^[0-9a-f]{40}$", sha)) return(NA_character_)
sha
```

Failing toward NA falls through to the `.git` tier and then to an honest NULL,
which is the documented preference.

### 5. [bug] man/lnk_stamp.Rd — the regenerated Rd is not in the diff

The `@return` roxygen for `lnk_stamp()` changed (`fwapg_sha`, `bcfishobs_sha`,
`sha_source`) and `man/lnk_stamp.Rd` was not regenerated. `devtools::document()`
on the reviewed tree produces a real diff against a tree that was otherwise
clean:

```
$ git status --porcelain   # before
M  R/lnk_log.R
M  R/lnk_stamp.R
...                        # man/ absent
$ Rscript -e 'devtools::document()'
$ git status --porcelain
 M man/lnk_stamp.Rd        # +9 / -2, the new slots
```

"Running a generator is not committing what it generated" — `?lnk_stamp` and the
pkgdown reference would ship the old three-slot list. (I reverted the file so
the tree is as I found it.)

## Checked and clean

Stating scope so it is auditable:

- **`nullif(c.reltuples, -1)::bigint` and the `CASE`** — verified against a live
  PG, not reasoned about: `pg_typeof(nullif((-1)::float4, -1))` is `real`, the
  `CASE` resolves to `boolean` (the `ELSE TRUE` types the untyped NULL), the
  cast rounds normally, and the `-1` sentinel does become NULL. `-1` is exactly
  representable in float4, so the equality is not approximate.
- **`row_count_estimated` readers** — none. `grep -rn row_count_estimated` over
  `*.R`/`*.sql`/`*.sh` finds only the DDL, the INSERT, two tests and one
  RUNBOOK sentence. Nothing branches on it, so the new NULL cannot silently
  drop rows from a reader. (Side effect worth knowing: a table `to_regclass`
  cannot resolve now also gets `row_count_estimated = NULL` rather than `TRUE`
  — more honest, but broader than the "never analyzed" case the docstring
  describes.)
- **The `log_input` premise discriminates.** `expect_false(grepl("[^)]c\\.reltuples::bigint", ins))`
  returns TRUE against the old SQL text and FALSE against the new — it is a real
  restore-the-bug guard, not decoration.
- **No vacuous `expect_match`.** This testthat version errors on `character(0)`
  ("Expected `character(0)` to have at least one element") for both
  `all = TRUE` and `all = FALSE`, so the un-length-guarded `expect_match(ins, …)`
  in the INSERT tests cannot pass on an empty grep.
- **INSERT column/value ordering** matches in both paths (`log`:
  `fresh_dirty, fresh_sha_source, crate_version, fwapg_sha, bcfishobs_sha,
  arg_dams` against the same order in `vals`; same for `log_recompute`).
- **`.lnk_checkout_sha()` cannot read the other repo's env var or directory** —
  both call sites pass their own three arguments positionally, and
  `test-lnk_log.R:171-177` sets both env vars at once and asserts each resolver
  returns its own.
- **Env override parity with the old wrappers.** `"0"`/`"true"`/`"yes"`/`"t"`
  handled identically; `.lnk_blank_to_na()` additionally makes a set-but-empty
  or whitespace-only var fall through instead of reading as FALSE, which is a
  strict improvement.
- **Uninstalled package / no-tier-resolves** — `.lnk_pkg_remote_sha()`'s
  `is.list()` guard is correct (`packageDescription()` returns a bare `NA` and
  `NA$RemoteSha` errors), and `.lnk_pkg_git_state("nosuchpkg")` returns NA on
  all three fields.
- **One behaviour change, in the safe direction, not a finding.** Old
  `.lnk_pkg_git_dirty()` ran `git status` in the first directory carrying a
  `.git` regardless of whether HEAD read; `.lnk_pkg_git_lookup()` now requires
  HEAD to read before it will hand that directory to `.lnk_git_dirty_at()`. So
  ".git present but HEAD unreadable" degrades from a measured dirty flag to
  `NA`. That fails toward "unknown", which is the direction `.lnk_git_dirty_at()`'s
  own comment demands.
- **`load_all` path preserved.** Probed directly: under `pkgload::load_all()`,
  `packageDescription("link")` resolves to the *source* DESCRIPTION (no
  `Remote*` fields), so tier 2 declines and `link` still resolves
  `source = "git"` with a real dirty flag. Tier 2 sitting above tier 3 does not
  hijack a source checkout.
- No shell scripts, SQL files or `.Rbuildignore` touched; no secrets, no new
  `system2()` arguments reaching a shell unquoted (the new test quotes its
  paths with `shQuote()` and gates on `Sys.which("git")`).
