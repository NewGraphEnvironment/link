# Review round 4: #406 `--jobs` for habitat_variants_build.R (branch diff vs 88923b52, data-raw/ only, through 0d5b1878)

## Checklist read

All four indexes read (their headings are the ones CLAUDE.md carries); each index line checked
against the diff.

- **code-check.md**: full prose of all 14 H3s under `## Mechanisms`, table rows skipped. Applied
  hardest: "Zero-length, empty, and unset" (the finding below), "A guard that fails toward pass",
  "A guard's scope, escape hatches, and remedies" (run the remedy for every input the clause can
  receive), "A wrapper's exit is not the work", "One fact derived twice" (analyze.R's two
  derivations of one pass). The 23 stand-alone / Security / Spreadsheets headings checked from
  their index lines only.
- **code-check-r.md**: relied on rounds 1-3's full reads (`on.exit()` at top level, `tryCatch()`
  nests its handlers, `[[` on a named atomic vector, `paste()` with a zero-length argument,
  forked mclapply, Postgres row order). The rest checked from index lines.
- **code-check-shell.md**: index lines checked against run.sh (unchanged since round 3).
- **code-check-spatial.md**: relied on round 1-3's full read of "GDAL reserves 3,276 MB … and
  PSOCK workers outlive their master". The rest checked from index lines.

Verified in a scratch dir (`r4/t1.R`, no database): a 2-worker PSOCK cluster, `clusterApplyLB(cl,
character(0), f)`, then `names(res) <- character(0)`; and `parallel:::dynamicClusterApply`'s body
printed.

## Round 3's table (a), row by row against the code as it stands

| resource | handled now? |
|---|---|
| worker R process | yes. Header :73-82 covers every end at `--jobs > 1` but "build ... done" and the "variant ... failed in ..." stop, naming the dead-worker case; the wrapper at :1074-1083 repeats `attr(cl, "pids")`. The exception is right: that stop is reached only after `clusterApplyLB()` returned every result, so every worker is idle, and `stopCluster()` in the `finally` (:1161) ends them. |
| PSOCK socket | n/a, as before |
| worker's backend | yes, same clause (`pg_terminate_backend()` or `pg_stat_activity`). In the "failed in" case each backend is idle: an R-side error from DBI arrives after the server has answered. |
| open transaction | yes (rolled back on terminate) |
| autocommitted statements | yes: "re-run the variant before scoring it" now applies to every end the clause covers |
| session temp tables | yes |
| working-schema tables | yes: the next variants run's base pass (always in `run_variants`, :580) re-classifies and re-checks the digest |
| persist-schema rows | yes, "re-run the variant" |
| built.csv / variant_timing.csv | yes: the header says "records none of that variant's groups", and the dead-worker error says "Nothing of this variant is recorded". (A stop raised inside `record_pass()` part-way would record some; the remedy still covers it.) |
| log lines | yes, given the orphans are stopped first |

`attr(cl, "pids")` survives: set on the list `makeCluster()` returns (:1003), returned, passed as
`run_variant()`'s `cl`, and read from the handler's enclosing frame. The wrapper does not hide a
group-level failure: `variant_pass()` catches its own errors and returns them as values, so
`clusterApplyLB()` returns normally and the "failed in" path runs; the handler sees only a master-side
error (a dead socket, or `checkForRemoteErrors()` on a worker-level `try-error`, which `variant_pass()`'s
own `tryCatch` makes unreachable in practice; were it reached, the label "a worker died" would be wrong
but every worker would be idle and the remedy harmless). A group's FAILED line is still in the log when
a worker death pre-empts it. The serial path is untouched by 0d5b1878.

## Round 3's table (b), row by row

| sentinel | handled now? |
|---|---|
| `want` NA | yes (:1041 refuses an NA base digest) |
| `sp` NULL | yes |
| `cl` NULL | yes |
| `out$error` NA | yes |
| `out$finished` / `out$tm` | yes |
| `failed` `character(0)` | yes |
| `n_seg` NA | yes |
| **`wsgs_v` empty** | **serial yes, `--jobs > 1` no**: finding 1. Round 3's row tested the serial loop only. |
| `jobs` default `1L` | yes |
| `old$jobs <- "1"` | yes |
| analyze.R "done in" present | yes: 0d5b1878 requires `nrow(chk) == nrow(s)` too. On a correct run every recorded (variant, group) printed its "done in" line (`out$finished` and both `say()` lines precede the return; `record_pass()` runs only on `is.na(error)`), the base pass prints one too, and `persist_init` / `pass_wall` rows are `in_total = FALSE`, so the new condition rejects no correct run. It does reject a run whose `j<N>/` holds timing rows from an earlier invocation with a different `--only` / `--wsgs`, which is the intended refusal. |

## Findings

- **[severity: bug]** data-raw/habitat_variants_build.R:1084 — at `--jobs > 1` a variant with no
  group (`wsgs_v` empty: its species has no role in `--wsgs`, e.g. a pre-flight `--wsgs=` subset)
  stops the build. `clusterApplyLB(cl, character(0), ...)` returns `NULL` (`dynamicClusterApply()`'s
  body is `if (n > 0L && p) {...}` with no `else`), and `names(res) <- ord` then raises "attempt to
  set an attribute on NULL" (measured in scratch). Serially the same input runs zero groups, writes a
  `pass_wall` row, prints "0 groups" and goes on to the next variant, as the pre-#406 loop did; at
  width it ends the build with a message that names nothing, after `lnk_persist_init()` and before
  every later variant. Workers are idle at that point, so nothing is left writing. Fix:
  `res <- if (length(ord) == 0L) list() else tryCatch(parallel::clusterApplyLB(...), ...)`
  (`list()[character(0)]` is `list()` and the record loop then runs zero times), or take the
  serial branch when `length(wsgs_v) < 2L`.

Note, not a code finding: the measurement now running uses the worktree at `0d70696b` (the first
commit, before rounds 1-3), so `j<N>/stamp_build.txt` will name that SHA and its logs carry no
`variants: workers` line; the fixes do not change what this run measures (nine distinct groups, no
NA base digest), and the stamp records it honestly.
