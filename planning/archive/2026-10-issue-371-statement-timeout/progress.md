# Progress — study_area_run.sh: bound each modelling statement, so a runaway statement fails as a named group (#371)

## Session 2026-10-23

- Plan-mode exploration — phases approved by user
- Measured the default: longest finished group of `20261023_074321-24d85e8c` is SETN 16.3 min (`fresh_default.log`); KTSU 65.4 is the stall
- Created branch `371-study-area-run-sh-bound-each-modelling-s` off main
- Scaffolded PWF baseline from issue #371 with approved phases
- Next: start Phase 1
- Phase 2: `.lnk_timeout_statement()` passes 10/10, including a live cancel through RPostgres (DBI's frames hold the SQL as `statement`). Probe of `wsg_run_one.R` on ADMS: `PGOPTIONS='-c statement_timeout=3s' LNK_TEST_STALL_WSG=ADMS` printed `statement_timeout=3s`, then `TIMEOUT after 3s: SELECT pg_sleep(3600) -- LNK_TEST_STALL_WSG`, rc=1, nothing written; without `PGOPTIONS` it printed `statement_timeout=0` and refused the hook (the control: so `PGOPTIONS` is what reached the connection).
- E2E acceptance on pre-review code (run_uid `20261024_011513-4e796a4c`, scratch `fresh_371`, MUSK + LEUT, `--statement-timeout=2`, `LNK_TEST_STALL_WSG=LEUT`): LEUT `TIMEOUT after 2min: SELECT pg_sleep(3600) -- LNK_TEST_STALL_WSG`, MUSK done in 0.9 min, INCOMPLETE names LEUT under `statement bound hit`, exit 1. Hand re-model of LEUT (bound 30min) rc=0; `--recompute-only` found both groups' rows, but LEUT's recompute stopped at the #227 guard (a downstream dam in a group outside the 2-group scratch schema) and the compare failed (MUSK is RB-only under `default`; bcfp has no RB). Both are the test's scope, not #371; re-run on final code with groups free of both.
- Plan review folded in (review-plan.md): G1 reproduced and fixed; B1 not reproduced.
- E2E acceptance on final code (`data-raw/logs/statement_timeout_371/run2_nbnk_euch/`): run `20261024_012623-309b2f46` NBNK + stalled EUCH, bound 2 min: EUCH named with statement, NBNK recomputed + compared, printed re-model bounded, exit 1; printed re-model rc 0; `--recompute-only` 2/2, compare written, exit 0. Scratch `fresh_371` dropped.
- Mutations (scratch worktrees): ssh-leg export, zero bound, report call, helper, message-first, unanchored match, printed PGOPTIONS, LNK_STATEMENT_TIMEOUT_MIN ssh export: each red; clean green.
- `/code-check branch`: R1 (sed abort on invalid UTF-8 kills the report under set -e; re-model printed the default bound under --recompute-only) fixed in 740cd5f0; R2 (the raise-it note broke the printed command's continuation; inside R1's fix) fixed in 951e2273 with a bash -n test; R3 (RUN_BOUND took a truncated `=30` as 30 ms; inside R1's fix) fixed in 29acc903, plus the RUNBOOK recipe; R3's enumeration of the mechanism (text read or printed as structured data, unchecked) covers 18 members, all hold. Each fix mutation-checked red.
