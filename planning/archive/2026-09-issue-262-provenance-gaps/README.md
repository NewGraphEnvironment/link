# Provenance gaps before the 217-WSG run (#262, #257)

Closed the four provenance gaps that cannot be retrofitted, before the 217-WSG
provincial run. Shipped as **v0.49.0** via PR #263.

**Two of the four reported gaps were wired and unfed, and a third named the wrong
source.** `run_label` had been threaded to the INSERT since #127 — NULL only
because nothing set `LNK_RUN_LABEL`. `.lnk_bcfp_log_current()` had been called at
run open just as long — NULL because it queries `bcfishpass.log` and the local
docker fwapg holds zero `bcfishpass` tables. Implementing the issue literally
would have added code beside working code twice and recorded a wrong value the
third time. The corrections came from querying `fresh.log` rather than reading
the schema, and they changed what got built.

What landed: `run_uid` (one per dispatch, all hosts) beside `run_id` (one per WSG);
`<schema>.log_recompute`; a tunnel-free three-tier bcfp pin with `bcfp_pin_source`;
a `link_dirty` predicate that excludes only the run's own tracked logs; and a
`study_area_verify.sql` that keys on `run_uid`, asserts via `RAISE`, and has a
negative test proving it fails when it should *and passes when it should*.

## Measurement

Audited against the 34-WSG field run `20260831_232553`: **37 rows, 37 distinct
`run_id`, 0 `run_label`, 0 `bcfp_model_run_id`, 0 `bcfp_model_version`, 22
`link_dirty`** — and `information_schema.tables WHERE table_schema='bcfishpass'`
returning **0** on the pipeline's own database, which is what explained two of
those zeros.

End-to-end on UTRE, clean tree: both a `log` and a `log_recompute` row sharing one
`run_uid`, `link_dirty = f`, `bcfp_model_version = v0.7.15-47-ga702229` from
`bcfp_pin_source = ledger`. `link_dirty` was `TRUE` mid-development with modified
tracked files, so the predicate discriminates rather than merely returning false.

Suite **1825 pass / 0 fail**, against a HEAD baseline of **1719** — +106 tests,
16 warnings both sides.

## Evidence

- `planning/archive/2026-09-issue-262-provenance-gaps/review-round{1,2,3,4}.md`
  — the four code-check rounds, verbatim
- `data-raw/study_area_verify_negative.sh` — the executable proof, six cases
- PR #263

## Six traps, and five were invisible to reading

Each of these reads correctly on the page and fails at run time. That is the
durable lesson of this issue, more than any individual fix:

| trap | how it failed |
|---|---|
| `on.exit()` at an Rscript's top level | never fires — the global env does not exit. Two dead handlers already in the file, the likely source of #246's 49 orphaned `zz_lnk_mc_scratch_*` tables |
| `system2()` pastes args raw | `:(top,exclude)`'s parens eaten by the shell; the dirty predicate returned `NA` for every input |
| psql `:'var'` in a dollar-quoted string | not interpolated; the assertion block failed at run time |
| `\quit 1` | ignores its argument and exits **0** — the FATAL guard reported success |
| a second `trap … EXIT` | replaces the first rather than adding to it |
| env var exported on the local leg | does not cross ssh — cyphers would have written NULL |

And one only an end-to-end run could catch: the recompute row landed with
`run_uid` NULL, because the env default was wired into `lnk_pipeline_run()` only.
Every unit test passed the value explicitly and so never exercised the default.

## The review rounds are the record

Rounds 1–3 each found real defects **in the previous round's fixes**. Round 3's
headline was an ordered-`CASE` arm shadowing a more serious one — for the **third**
time, each fix reproducing the class one axis over:

1. round 1 put a NOTE above a FAIL, hiding `fresh_sha NULL on a cypher`;
2. round 2 partitioned the arms and wrote the invariant down;
3. round 3 found the `unpinned_ok` escape had put a *conditionally* sanctioned
   state into a FAIL slot still above it, hiding it again.

The invariant was never "FAILs before NOTEs" but "every arm above the line is
*unconditionally* a failure" — a rule no comment enforces, because adding an arm
is the natural edit and ranking it is a judgement. So §1b became an **accumulator**
(`concat_ws` over per-condition expressions): severity ordering stopped being
load-bearing, which removes the class rather than the instance.

Round 3 also found the two round-2 negative-test fixes **interacting** — adding
`ON_ERROR_STOP` made the setup heredoc abort inside the window the early trap was
added to protect, reopening the exact leak it closed. Both individually right;
neither measured against the other.

**Convergence was established by enumeration, not by assertion** — round 4 named
all five ways `concat_ws` could hide an arm and showed none reachable, then checked
all seven verdict arms against the five assertions and found one residual
(`fresh_sha`, a FAIL that exited 0). Fixing that one arm terminated the class, and
a nine-state sweep confirmed it: every FAIL exits 3, every NOTE and OK exits 0.

## Deliberate deviations from the issue

- `log_recompute` carries no `bcfp_*` columns and no `log_input` rows. The issue
  asked for "the same provenance columns"; the recompute reads persisted tables,
  not the reference or the DB primitives.
- `bcfp_model_run_id` is NULL on the tunnel-free path. `log.json` has no such key,
  and a fabricated id is worse than honest absence.

## Known exposure, carried into RUNBOOK §6c

`schema_consolidate.R` DELETEs its bucket from every discovered table before
COPYing, and `log_recompute` is populated *after* consolidate — so a second or
resumed consolidate over the same bucket wipes those rows.
