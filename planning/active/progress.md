# Progress — Adopt fresh v0.46.0: the walk prefilter (fresh#272) in the recompute (#409)

## Session 2026-10-28

- Plan-mode exploration — phases approved by user
- Created branch `409-adopt-fresh-v0-46-0-the-walk-prefilter-f` off origin/main
- Scaffolded PWF baseline from issue #409 with approved phases
- Next: start Phase 1

- Phase 1: fresh v0.46.0 (`8a5ca763`, equals the tag) in a scratch library holding fresh alone; pak's 26 dependency copies were removed so RPostgres, DBI, sf and withr load from the shared library in both arms. Shared library still 0.44.0 (`22034c1a`). Worktree at `1d00c04c`: all five groups' newest `log` and `log_recompute` rows on m1 are at that SHA (run_uid `20261023_074321-24d85e8c`).
- m1 was busy at 00:57 UTC: another session timing SETN walks against `fresh_default.barriers_*_access` (a `pg_temp.nf281_*` table, fresh#281 work). Phase 2 waits for three quiet minutes; Phase 3 started on m4 meanwhile.
- Phase 4 early: DESCRIPTION pin bumped; fresh's reach from link's path is identical at v0.44.0 and v0.46.0 (`data-raw/logs/prefilter_409/reach.md`), so the 28 `none` rows hold and name both tags. `test-pretest.R` at fresh 0.46.0: 24 tests, 0 failed, 1 skipped (dirty tree).
- Plan review landed (`review-plan.md`); dispositions in `findings.md`. Tie risk to `dam_dnstr_ind` / `remediated_dnstr_ind` counted on the dispatcher: none. `rerun.R` gains per-walk array digests and host load; `compare.R` asserts each build's logged fresh; two tests added and mutation-checked.
- Phase 3 (m4, 00:58–01:17 UTC): ADMS, NATR, ELKR built into `fresh_409b` (fresh 0.44.0) and `fresh_409a` (0.46.0) from one worktree at `64f8de0a`; each build's log names its fresh. 25 of 25 non-empty group-tables identical (20 empty on both sides), barriers included. `data-raw/logs/prefilter_409/model/`.
- Phase 2 queued 01:18 UTC on the dispatcher (`rerun_all.sh`, waits for a quiet database before each run).
