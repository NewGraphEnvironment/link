# A stalled statement leaves samples (link#487)

Runs on m1's local docker fwapg (PostgreSQL 17.5) on 2026-11-15 UTC, at the branch's
commit `5237b7b0`, with `--config=default`. The driver runs were dispatcher-only, from a
worktree, into a scratch schema, `fresh_487`, that was dropped afterwards.
`LNK_TEST_STALL_WSG` stalls one group on `SELECT pg_sleep(3600)` until the statement bound
cancels it.

| step | run_uid / command | result |
|---|---|---|
| one group | `wsg_run_one.R ADMS default` with `LNK_TEST_STALL_WSG=ADMS`, bound 1 min, `LNK_STALL_AFTER_MIN=0.25`, `LNK_STALL_EVERY_S=10`, `LNK_RUN_UID=20261115_000000-0000test` | four `leader` rows waiting on `Timeout`/`PgSleep`, then `TIMEOUT after 1min` and `stall samples: 20261115_000000_stall_ADMS.tsv`; exit 1; no sampler process 4 s later (`wsg_run_one_adms.log`) |
| run | `20261115_001427-474338b7`, `--focal=NBNK,EUCH --buckets-exact --statement-timeout=2 --stall-sample-after=1 --pretest-note=…`, `LNK_TEST_STALL_WSG=EUCH`, `LNK_STALL_EVERY_S=15` | the banner shows `stall:`; NBNK done in 0.7 min, under the 1 min threshold, so no rows; EUCH writes a header and four `PgSleep` rows (00:17:43 to 00:18:28Z, its statement started 00:16:41Z), then `TIMEOUT after 2min` and `stall samples: 20261115_001427_stall_EUCH.tsv`. The summary lists the file. INCOMPLETE names EUCH under `statement bound hit` with `samples:` under its statement. Exit 1 (`driver_run.out`, `20261115_001427_*`) |
| re-model through a pipe | EUCH re-modelled under the run's uid without the hook, its output piped through `cat` (a pipe reader is held open the way an ssh channel is) | done in 0.6 min; the pipe closed 1.2 s after the R process exited, so the sampler let go within its 2 s parent check (`remodel_EUCH_pipe.out`) |
| finish | `--recompute-only --run-uid=20261115_001427-474338b7` | the summary lists the same file again (rewritten under the run_uid's timestamp); `study_area_run done`, exit 0 (`driver_recompute_only.out`) |

`20261115_001427_stall_EUCH.tsv` is what the driver split out of
`20261115_001427_run_local.log`. Its `n_active` reads 1 because the sampler leaves itself out.

Not run here:

- **A remote leg** (a persistent worker or a cloud host). A worker run would be refused before
  any spend, because m1 and m4 hold different modelled crossings since m1's 2026-11-13 reload.
  The pipe re-model measures the same thing on one host: how long the sampler holds its
  group's stdout. The export of `LNK_STALL_AFTER_MIN` over ssh is covered by
  `test-study_area_remote.R`.
- **A lock wait.** The lock case is `test-lnk_stall.R`: a session holding `ACCESS EXCLUSIVE`
  on a table that the stalled statement reads gives a `Lock` leader and a `blocker` row naming
  that session's pid and its `LOCK TABLE` query.
- **A real stall.** That is #487's second acceptance line, owed to the next one.
