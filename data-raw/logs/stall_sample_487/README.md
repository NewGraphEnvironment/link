# A stalled statement leaves samples (link#487)

Runs on m1's local docker fwapg (PostgreSQL 17.5) on 2026-11-15 UTC, with `--config=default`: the
driver run at the branch's commit `5237b7b0`, the one-group rows after code-check rounds 2 and 3 at
their fixes. The driver runs were dispatcher-only, from a
worktree, into a scratch schema, `fresh_487`, that was dropped afterwards.
`LNK_TEST_STALL_WSG` stalls one group on `SELECT pg_sleep(3600)` until the statement bound
cancels it.

| step | run_uid / command | result |
|---|---|---|
| one group | `wsg_run_one.R ADMS default` with `LNK_TEST_STALL_WSG=ADMS`, bound 1 min, `LNK_STALL_AFTER_MIN=0.25`, `LNK_STALL_EVERY_S=10`, `LNK_RUN_UID=20261115_000000-0000test` | four `leader` rows waiting on `Timeout`/`PgSleep`, then `TIMEOUT after 1min` and `stall samples: 20261115_000000_stall_ADMS.tsv`; exit 1; no sampler process 4 s later (`wsg_run_one_adms.log`) |
| after round 2 of code-check | the same group under bound 1 min with `LNK_STALL_AFTER_MIN=0.5` (the driver's default under `--statement-timeout=1`) and checks every 60 s, so every 30 s once the threshold is under a minute | one `PgSleep` row, then the `stall samples:` line (`wsg_run_one_adms_after05.log`); with `LNK_STALL_AFTER_MIN=5` no row can be written before the bound, and no `stall samples:` line is printed: the line now waits for the sampler's marker that it wrote a row (`wsg_run_one_adms_after5.log`) |
| after round 3 of code-check | the same group under bound 1 min with `LNK_STALL_AFTER_MIN` unset, so `wsg_run_one.R` takes half the bound (0.5 min) and the sampler, given the bound, checks every 15 s | two `PgSleep` rows inside the 30 s window, then `stall samples: the [wsg_stall] ADMS lines above (20261115_000003_stall_ADMS.tsv in a driver run)` (`wsg_run_one_adms_r3_default.log`); with `LNK_STALL_AFTER_MIN=5` the group prints `stall sampler off: LNK_STALL_AFTER_MIN=5 is not below the bound (1min)` (`wsg_run_one_adms_r3_after5.log`) |
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
