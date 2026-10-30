# Code-check round 3: link#274 (HEAD df08c728, base 9ae7be27)

## Checklist read

- **code-check.md**: the prose of all 14 H3s under `## Mechanisms`, with table rows skipped. The 23 other headings (stand-alone rules, Security, Spreadsheets and PDFs) were not read.
- **code-check-r.md**: 11 of 111 headings read in full:
  - "`data.frame()` recycles a scalar against a zero-length column"
  - "`system2(stdout = TRUE)` warns on a non-zero exit…"
  - "`read.delim()` quotes by default…"
  - "`strsplit()` drops a trailing empty field…"
  - "Postgres row order is never fixed…"
  - "A database driver's value is not a base R type…"
  - "`match()` treats NA as a matchable VALUE…"
  - "`$` on a list partial-matches…"
  - "`paste()` with a zero-length argument…"
  - "A value compared as `::text`…"
  - "`vapply(..., USE.NAMES = FALSE)`…"

  100 were not read.
- **code-check-shell.md**: 7 of 67 headings read in full:
  - "Reading a file line-by-line drops the last line…"
  - "`wait` with no argument…"
  - "A failed `cd`…"
  - "`for x in $(cmd | grep … || true)`…"
  - "psql does not interpolate `:'var'`…"
  - "A variable in a sed replacement…"
  - "Parallel writers sharing one output file…"

  60 were not read.
- **code-check-spatial.md**: none of its 93 headings were read. The diff uses no spatial tool.

## Mechanism

**The reader's side and the "now" side are two hand-kept lists, and they agree only where someone wrote both entries.** `readers_classify()` holds a reader's build to the facts its log row carries. `recompute_readers_check.R` builds the matching "now" values separately: `expect`, `refuse_all`, the git diff, and the dry run. Both round-1 defects came from this split:

1. `facts` assumed that `last` (the log rows) has one row per reader, the same as `readers`. Nothing ties the two lists together.
2. The reader's `fresh_dirty` had no "now" counterpart.

The same split has a third form. A "now" value can be read from a **stand-in** (a stamp, an env pin) rather than from what `recompute_one` will actually load. Round 1 caught a missing value; this form gives a present but wrong one.

## Enumeration: each fact compared, reader against now

Where "now" comes from: `recompute_readers` runs the check with `cd "$REPO_ROOT"`, `LNK_LOAD=loadall` and the driver's exported environment. `recompute_one` uses the same cwd and environment, plus `LNK_VIEWS_PREBUILT=1`. So both see the same `LNK_SCHEMA` (exported at study_area_run.sh:527), `~/.Renviron`, a cwd `.Renviron`, and `FWAPG_GIT_SHA` (exported by `preflight_local` in a full run, unset in `--recompute-only`).

| Fact | "Now" taken from | Taken from what the recompute runs? | Unknown refuses? |
|---|---|---|---|
| `has_log` | — | n/a | yes: no row gives `no_log` |
| `open` | — | n/a | yes: NA, or the newest row open, gives `newest_build_open` |
| `config_hash` | `lnk_stamp()` → `.lnk_config_hash(lnk_config(config))` in the same tree and process environment as `wsg_recompute_one.R`. It does not depend on the schema or aoi. | **holds** | yes: NA becomes `""`, and a stored hash is always `sha256:…` |
| run groups' `config_hash` | log rows of the run | **holds** | yes: 0 rows or NA gives `config_changed_since_run` |
| `fresh_sha` | `st$software$fresh$git_sha`: tier 1 is `FRESH_GIT_SHA` from the environment, ahead of the installed fresh's `RemoteSha` | **does not hold in `--recompute-only`** (finding 1). In a full run, `preflight_local` refuses a pin that differs from `RemoteSha`, so it holds there. | yes for NA. A stale pin is a known value, so it is not refused. |
| `fresh_dirty` | `st$software$fresh$dirty` → `dispatcher_fresh_dirty` (round-1 fix) | holds, but `FRESH_GIT_DIRTY=false` from the same pin answers it, so it cannot catch finding 1 | yes: NA refuses |
| `fwapg_sha` | `.lnk_fwapg_sha()`: env, then the checkout HEAD | Same stamp as the recompute writes. It stands for the database's FWA load, which no stamp measures, before this branch or after. | yes |
| `link_sha` | `git diff --name-only <sha> -- READERS_PATHS` against the working tree in REPO_ROOT, which `load_all` loads | **holds**. READERS_PATHS covers R/, inst/extdata/, DESCRIPTION, NAMESPACE, the job script, the views build and the two driver files. The repo has no `data/` or `src/`. The log-table step is inline in study_area_finish.sh. | yes: a malformed sha, a failed `cat-file` or a failed diff gives NA, which becomes `sha_unresolvable` |
| `link_dirty` | `git status --porcelain --untracked-files=all -- READERS_PATHS` → `dispatcher_tree_dirty` | **holds**. The scope is narrower than the reader's `link_dirty`, so this can only refuse spuriously. | yes: a failed `git status` refuses |
| `downstream` | `lnk_wsg_downstream_check(on_fail = "warn")`, the same call as the recompute's apart from `on_fail`. Same cfg schema, no override, same outlets. | **holds** | yes: an error or a non-`pass` status gives NA, which refuses. The `"pass"` placeholder is re-tested for every reader classed `recompute`. |
| `bcfishobs_sha` and the tokens | not compared | not read by the recompute: `lnk_access()` passes `observations = NULL`. The tokens follow config and code, which are compared above. | n/a |

The unknown-to-`""` sentinel holds: `same("", "")` is TRUE, but no stamp writes `''` (`.lnk_blank_to_na`, `.lnk_checkout_sha`'s `nzchar`, `.lnk_log_lit` → NULL).

## Enumeration: empty and zero-length values

**recompute_readers_check.R**

| Value | When it is empty | What happens | Verdict |
|---|---|---|---|
| `rebuilt` | `csv("")` gives `character(0)` (probed) | no readers | holds |
| `missing` | the usual case | the `%in%` check passes | holds |
| `deps` | no line rows | stop, which the driver treats as `unchecked`. `recompute_deps.R` refuses to write an empty map. | holds |
| `in_tsv` | `-`, or a header-only file | `character(0)` | holds |
| run_wsgs.tsv | not this run's | stop, then `unchecked` | holds (spurious refusal only) |
| `held`, `in_log` | 0 rows | `readers_outside` returns a typed 0-row frame | holds |
| `readers` | 0 rows | typed `facts`, sentinel `expect`. `write.table` writes the header. | holds |
| `run_hash` | 0 rows | `config_changed_since_run` | holds |
| `last` | 0 rows | `rep(…, nrow(last))` (round-1 fix). Every reader becomes `no_log`. | holds |
| `last$link_sha` | NA | `pc[NA]` is NA, giving `sha_unresolvable` (probed) | holds |
| `shas` | 0 | `vapply` returns `integer(0)` | holds |
| `go` | 0 | no dry run, and no reader is classed `recompute` | holds |
| `dirty` | no output | clean. An error status refuses. | holds |
| `table()` | 0 rows | all counts 0 | holds |

**`readers_classify`**

- `out` empty: returns a typed 0-row frame. Holds.
- A reader with no `facts` row: `no_log`. Holds.
- `reads` is never empty, because `readers_outside` builds it from at least one hit. Holds.

**`recompute_readers` (shell)**

| Value | When it is empty | What happens | Verdict |
|---|---|---|---|
| `RC_DEPS_PID` | empty (early mode already waited) | skips the wait | holds |
| `RC_DEPS` | unset, unreadable, or a wrong header | `unmapped`, and a WARN in the summary | holds |
| `RUN_WSGS` | empty | passed as `""` | holds |
| `COV_MISSING` | empty | passed as `""` | holds |
| `wsgs_tsv` | missing | `-` | holds |
| check exit / TSV | exit 1, missing, or a malformed TSV | the fallback names every line-rule reader as `unchecked`. With zero candidates the summary is silent, which is correct, because the map is complete by construction. | holds |
| `READERS_RECOMPUTE` / `READERS_NAMED` | empty | `.hosts_csv` of nothing is `""` | holds |

**`recompute_readers_lifted` and the report**

- `READERS_RECOMPUTE` empty: returns. Holds.
- The query fails: WARN, and `READERS_LIFTED` is `""`. Holds.
- `READERS_STATE` unset (`recompute_readers` never ran): the report returns. Holds.
- `READERS_LIFTED`, `RUN_LABEL` and `RUN_BOUND` are all read with `:-`. Holds.

**The finish set**

- `ALL_WSGS` is empty exactly when `COV_RECOMPUTE` is. A reader classed `recompute` reads only groups in `RUN_WSGS` minus `COV_MISSING`, which is `COV_RECOMPUTE`. So `CMP_WSGS` is never empty while readers are recomputed. Holds.

## Findings

- **[severity: fragile]** data-raw/recompute_readers_check.R:105-123. In `--recompute-only`, "now"'s `fresh_sha` is read from the env pin, not from the installed fresh the recompute loads.
  - **What happens.** `expect$fresh_sha` is `lnk_stamp()`'s fresh sha. Its first tier is `FRESH_GIT_SHA`. `scripts/update_hosts.sh` writes that pin to `~/.Renviron`, together with `FRESH_GIT_DIRTY=false`. A later install by another route (pak, `--auto-install`, a hand-run `R CMD INSTALL`) leaves the old pin winning. study_area_run.sh:1145-1170 names exactly this case. In a full run, `preflight_local` refuses it (its "stale" field: the pin differs from `RemoteSha`). `--recompute-only` skips `preflight_local` (study_area_run.sh:893-934), and the check does not repeat that test. So a reader built at the pinned sha is classed `recompute`, and the one-way habitat gate then runs under a different installed fresh. The round-1 `dispatcher_fresh_dirty` guard does not catch it, because `FRESH_GIT_DIRTY=false` comes from the same pin.
  - **Measured** in a worktree at HEAD with `FRESH_GIT_SHA=1111…` and `FRESH_GIT_DIRTY=false`. The stamp gave `1111…`, `dirty FALSE`, `source env`. The installed `RemoteSha` was `2c35e3eb…`, and `dispatcher_fresh_dirty` did not fire.
  - **Fix.** Mirror the preflight: `remote <- .lnk_pkg_remote_sha("fresh")`. If `!is.na(remote) && !identical(remote, st$software$fresh$git_sha)`, add `dispatcher_fresh_pin_stale` to `refuse_all`.
  - **Rule:** code-check.md "A proxy is not the property". Also code-check.md "A guard that fails toward pass" ("Read a currency gate from the independent source it is really about, never from the artifact it guards").
  - **Inside a previous fix?** yes. It sits beside the round-1 `dispatcher_fresh_dirty` fix, whose test reads the same stamp.
