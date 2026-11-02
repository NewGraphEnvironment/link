## Checklist read

- code-check.md: under `## Mechanisms`, prose without table rows, read "A guard that fails toward pass" (from "Assign first"), "A fixture that cannot reach the failure mode" (to its fixture-types paragraph), "A proxy is not the property", "Verification that reads its own output", "A guard's scope, escape hatches, and remedies" (to its literal-rule paragraph). The other nine by index line. Stand-alone sections by index line only.
- code-check-shell.md: extracted "Over Tailscale SSH to a Mac", "A second `trap … EXIT`", "psql does not interpolate", "A heredoc whose body"; output went to the same file and was read in part. Others by index line.
- code-check-r.md: extracted "`on.exit()` at a script's top level", "`$` on a list", "A `data-raw/` script", "An `information_schema` lookup", "`tryCatch()` nests"; same caveat. Others by index line.
- code-check-spatial.md: nothing this diff uses; 0 read.

## The mechanism

"History" began as one list: one schema, one config, one reader. The branch split it into three sources: the bundle's own rows, the borrowed rows, and the schema a record names. The code that decides was moved to the new state one site at a time; the code that merely talks about, or starts from, "the history" was not. Rounds 1 and 2 are that: a guard keyed to `borrowed`, then a label and a minutes line that still read one list.

Beside it, "borrowing" has no single definition. It is re-derived at each site: `own_complete` plus flags (pick), `identical(src$config, config)` (check), `nzchar(HISTORY_SCHEMA)` (run.sh, verdict), non-NA `history_*` (record). I looked for a state where these disagree and found none: the pick refuses flags on a complete bundle, so they agree by that refusal.

Where it reaches, by my walk:

| where | assumes one list | state now |
|---|---|---|
| `pretest.R` `pretest_history_uncoverable()`, via `pretest_pick.R:92-95` and `pretest_record_check()` | "history" in the message means the schema being read | **wrong under borrowing: finding 1** |
| `pretest.R` `pretest_since_covers()` ("after history built at"), via `pretest_pick.R:111-117` | same | names a SHA only; same finding |
| `pretest_pick.R:100-104` `--since` from `built` alone | the history is all there is to cover | an own build older than it refuses; loud, and the message names both SHAs (round 2's call stands) |
| `pretest.R` `pretest_since_default()` dirty and no-SHA branches ("pass --since=") | | now unreachable from the pick: `:94-95` refuses first, and `--since` no longer helps. Dead text, no effect |
| `pretest_pick.R:17-18` "picked only if <schema>.log has a finished build of it, so the config can model it" | the history's config is the run's | false in general under a borrow. Measured: 0 groups in `fresh_default_history` that `default_minimal` does not model, 0 the other way (241 each). Latent; a pick of such a group would fail the gate loudly |
| `pretest_pick.R:15-21` header ("default --schema") | | stale text; the code reads `hist_src$schema` |
| `pretest_pick.R:202-204` | | fixed in round 2 |
| `pretest_pick.R:165` | | fixed in round 2 |
| `data-raw/study_area_buckets.R:332-339` packer minutes | | no config filter at all, so `--minutes-schema=<history>` works for a borrowing run, and a schema holding two configs mixes them. Pre-existing, not on this branch |

## Findings

- **[severity: fragile]** data-raw/pretest.R:402-411 (`pretest_history_uncoverable`), reached from data-raw/pretest_pick.R:92-95 and data-raw/pretest_check.R:63-66 — while borrowing, a build of the bundle's own that no range can cover refuses the gate with a message that names the wrong thing and no way out.
  `held` merges own rows into the history, so one own row from a dirty tree prints `REFUSED: history holds a build from a dirty tree, whose code is not its link_sha; a gate on it cannot clear a run`. It names no schema and no group. An operator who has just passed `--history-schema=fresh_default_history` reads that as the history they named, which is clean; reloading it changes nothing. `pretest_since_default()`'s "pass --since=" no longer applies, and `--since` does not help.
  The way out is to re-model that group from a clean tree, or delete its row. Neither message nor RUNBOOK says so. The RUNBOOK line says only that own builds "must be in the range too". The door is `default_minimal`'s own README, which prints `LNK_SCHEMA=fresh_default_minimal Rscript data-raw/wsg_run_one.R ADMS default_minimal`.
  Reproduced in a temporary worktree at `8aba3b84`, schema `zzrev3_own` (dropped), one ADMS row under `default_minimal`, borrowing `fresh_default_history`:
  - no own rows: picks, exit 0. Own row dirty: the refusal above, exit 2, with and without `--since=`. Own row with NULL `link_sha`: `history holds a build with no link_sha`, exit 2.
  - own row at a SHA off the line: `the range starts at 1d00c04cc5b2, after history built at 5d451e349cfe`. That SHA is the only clue that it is not from the history.
  - launch check on a pass record: `the gate's history holds a build from a dirty tree`, exit 1. The driver then prints `Run: bash data-raw/pretest_run.sh`, and that run refuses as above. Own row made clean: exit 0, "gate passed".
  It stops loud, so no wrong run results; the cost is an operator stuck at launch looking in the wrong schema. Naming the source and the groups (`own builds in <schema>.log: ADMS`) and the remedy would close it. `pretest_run.sh` is under `PRETEST_RULES`' glob with `pretest.R`, so edit before the gate runs.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

## The author's enumeration (findings.md, "Code-check enumeration")

Not complete, because its domain was reads of data, and the defect that remains is in text about the data. Rows:

| row | verdict |
|---|---|
| `pretest_pick.R:76-81` own for completeness | true; the call runs to :82 |
| `:84-89` history for groups and minutes | true |
| `:92-95`, `:98-100` own and borrowed for coverage | claim true for :92-95; `:98-100` is wrong. Those lines are the short check's end and the `--since` default; the coverage call is `:111-112` |
| `:96-97` short check | true; it runs to :99 |
| `:101` `--since` "from the borrowed one, the earlier" | **"the earlier" is not guaranteed.** Reproduced: an own row at the repo's root commit gives `--since` 1d00c04c and `the range starts at 1d00c04cc5b2, after history built at 0c1b9a319017` |
| `:164-165` label | true |
| `:202-204` minutes | true. Only reachable by naming `--minutes-schema` |
| `pretest_run.sh:99-100`, `:199-213` | true; also `:112`, `:115` (labels), `:190` (echo), all true of the history schema |
| `:175` live check | true |
| `:284`, `pretest_verdict.R` | true: the verdict reads `<scratch>.log`, the catalog and writes `log_pretest` only |
| `pretest_check.R:49-66` "as the pick" | true: own, record, borrowed, same rbind. Same source at launch as at pick, by the record |

Missing: the row of finding 1; `pretest.R`'s `pretest_since_default()` and `pretest_since_covers()` message texts; `pretest_pick.R:17-18`; `pretest_pick.R:241`'s "among groups with history" (true of the borrowed); `pretest_override.sql` (writes NULL `history_*`; its `override` rows are filtered out at both readers, so true); `study_area_run.sh:1194-1208` (reads nothing of the schema itself).

## Every message on this state, and whether following it works

| message | where | following it |
|---|---|---|
| `<schema>.log does not cover ...; borrow from a config it extends: --history-schema=<schema> --history-config=<parent>` | `pretest.R:364` | works. For a chain deeper than two it names the immediate parent, which may have no builds; none exists today |
| `--history-schema and --history-config go together` | `pretest_run.sh:94`, `pretest.R` | works |
| `bad --history-schema`, `bad --history-config`, `is the scratch schema` | `pretest_run.sh:95-97`, `pretest.R:373` | works |
| `--history-config X is not a config Y extends (chain: ...)` | `pretest.R:376` | works |
| `<schema>.log covers every group ...; leave out --history-schema and --history-config` | `pretest.R:380` | works, tried in round 2 |
| `<s>.log does not exist: no history` | `pretest_pick.R:86` | states the state; the loader is not named, RUNBOOK does. Reproduced with a dropped history. Works once loaded |
| `<s>.log has no finished rows under config` | `pretest_pick.R:89` | states the state; right |
| `history holds a build ...; a gate on it cannot clear a run` | `pretest_pick.R:95` | **no way out named, and wrong source: finding 1** |
| `<history> holds N of M groups ...; load the full history ..., model it under the parent first or launch on --pretest-note` | `pretest.R:423` | works. Loader on a real schema (`--to=fresh_default` on m4) refuses with "not a history schema", which is right; pick another name |
| `the range starts at X, after history built at Y`, `; a gate on this range cannot clear a run` | `pretest_pick.R:116` | for an old own build `--since=` works, unsaid; for an off-line own build only a re-model does (finding 1) |
| `pick exited N` | `pretest_run.sh:142` | carries the above |
| `the checkout has uncommitted changes` | `pretest_check.R:42` | works |
| `no gate record (<schema>.log_pretest does not exist)` | `pretest_check.R:45`, then the driver's Run lines | works: on an absent schema `to_regclass` reads NULL, the driver names the flags |
| `<schema> does not cover the groups ..., and its gate borrowed no history to hold it to` | `pretest_check.R:57` | works with the driver's hint |
| `the gate borrowed a short history: ...` | `pretest_check.R:60` | works: a reload then voids the range, and the gate is re-run |
| record's history schema dropped: `relation "<s>.log" does not exist`, exit 2, `(the check itself could not run)` | `pretest_check.R:53` | honest. RUNBOOK says it must still exist. The re-gate's `does not exist: no history` leads on to the loader |
| `the gate's history holds a build ...` | `pretest_check.R:65` | **finding 1** |
| `Run: ... (a bundle that extends another ... adds --history-schema= and --history-config=...)` / `--pretest-note (recorded; $SCHEMA must exist first)` | `study_area_run.sh:1204-1207` | works, save finding 1's state |
| loader `REFUSED` and `FAILED` lines | `pretest_history_load.sh` | work. `--to` holding anything else is refused and names why |

## Checked and sound

Temporary worktree at `8aba3b84` (removed), schemas `zzrev3_own`, `zzrev3_h` (dropped).

- `test-pretest.R` with `NOT_CRAN=true`: 128 expectations, 0 failed, 0 errors, 2 skipped.
- Modelable, from the source tree: `default`, `default_minimal`, `default_tuned` 241 each, `bcfishpass` 217. `fresh_default_history`: 241 under `default`, and matches `default_minimal` both ways. Local `fresh_default`: 4 under `default`.
- NEWS and CLAUDE.md's 11 picks are `pick_241_groups.tsv`'s 11, same names. fresh's 0.51.0 NEWS holds the overlay and `frs_order_child()` sentence; the bridged overlay now requires `watershed_group_code` on `bridge` and `to`, which `R/lnk_pipeline_classify.R:149-152` passes `<schema>.streams` for; ADMS's smoke build at 0.52.0 ran through it, per `minimal_breaks_415/README.md`. Not rebuilt here.
- `pretest_history_load.sh`, read: count and trailer before anything local changes; awk renames outside COPY only and counts rows; `psql -1` under `set -e`; EXIT trap is the only one; `$FROM`, `$TO` and `$CONTAINER` are regex-checked before the remote strings. Its one load on this host is the comment on `fresh_default_history` (241 groups). Not re-run: round 1 ran it through a stub ssh.
- `pretest_run.sh`: `"${history_args[@]}"` empty is safe at its bash floor; `CREATE SCHEMA` runs before the verdict with `set -e`, including on zero picks. Not run end to end: no gate has modelled a pick on a log-only scratch, as the plan's gate phase is the first.
- Proof scripts (`minimal_breaks_415/`) write to scratch schemas, so they do not reach finding 1.
