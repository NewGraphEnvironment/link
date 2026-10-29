# The pre-run gate (link#372): evidence

Measured 2026-10-28 on m1 (local docker fwapg), link at the #372 branch
(0.69.3 code), fresh v0.44.0 (`22034c1`). Mechanics: RUNBOOK §8d, "The pre-run
gate (link#372)".

| path | what it holds |
|---|---|
| `reach.md` | which link and fresh files the modelling path reaches, by call graph; the basis of the map's `none` rows |
| `acceptance_0.66.6_0.68.0/` | the acceptance pick: `--since=v0.66.6 --until=v0.68.0` (fresh v0.39.0..v0.42.0), bounded against `fresh_default_20261017`'s minutes (0.66.0, before the walk). Pick only |
| `gate_1d00c04c_loaded/` | the first real gate, `1d00c04c..20d2bc4c`, eight groups modelled; it failed under another session's load (below) |
| `gate_final/` | the gate at the branch's final code (`20209b79`), on a quiet database: PASS, the record `study_area_run.sh --preflight-only` accepts |

## The acceptance pick

The issue asked that a re-run against 0.68.0 from 0.66.6 pick OKAN or QUES for
the near-river walk. It picks QUES (first of 246 on `near_river_conn`, the
walk's prefilter: the longest connector run, 63.3 km) and TAKL (second,
32.3 km), and OKAN through `dams` (first of 143, 233 CABD dams). Ten groups in
all. Bounded on 0.66.0's minutes, QUES gets 14.8 min and OKAN 8.5 min; at 0.68.0
QUES took 9.3 min and OKAN's re-model 7.6 min, so both would pass, and OKAN's
four-hour statement on 2026-10-23 would have been killed at 9 min.

The range is refused as a gate (a warning under `--pick-only`): the history in
`fresh_default` was built at `1d00c04c`, which is not on the line to the
`v0.68.0` tag, so its code would be in no diff. That refusal is the record
check's rule, working.

**Which 2026-10-23 groups no input would have picked.** KTSU, the larger loss,
ranks 119th of 143 on `dams` and lower on every other input (`near_river_conn`
228 of 246, `observations` 186, `gradient` 191, `segments` 152). OKAN ranks 1
on `dams`, 3 on `observations`, 29 on `near_river_conn`.

## The first real gate (`gate_1d00c04c_loaded/`)

`1d00c04c..20d2bc4c` (the last provincial run to the branch's Phase 3 code;
fresh v0.42.0..v0.44.0), modelled from a worktree into
`fresh_pretest_default`:

| group | inputs | last minutes (0.68.0) | bound | this run | verdict |
|---|---|---|---|---|---|
| SETN | gradient, segments | 16.3 | 48.8 | 7.5 | pass |
| QUES | near_river_conn | 9.3 | 28.0 | 4.3 | pass |
| OKAN | dams | 7.6 | 22.7 | 2.7 | pass |
| LFRA | observations | 6.6 | 19.8 | 4.4 | pass |
| TOAD | gradient, segments | 6.0 | 18.0 | 4.1 | pass |
| UPCE | observations | 3.7 | 11.2 | 2.3 | pass |
| TAKL | near_river_conn | 3.2 | 9.5 | killed | bound |
| SAJR | dams | 1.6 | 5.0 | killed | bound |

The six that finished ran at 36 to 68 % of their 0.68.0 minutes, which fits
#326's and #396's fewer segments. TAKL was killed inside fresh's near-river
walk, the statement that stalled OKAN on 2026-10-23 and BULK once in #396.
SAJR was killed early in its build, at 5 min, having modelled in 0.8 min alone
an hour before (the `--only=SAJR` smoke test). Throughout, another session ran
six modelling workers on the same database (`knw_strchk_*` schemas, their own
near-river walks among them).

So the gate did what it is for: it failed within minutes, not hours. It cannot
say whether TAKL's walk is a regression or the load, which is why the gate now:
- refuses to start beside any other active client session (`--allow-busy`
  records an override);
- samples the other sessions per group and prints them beside the minutes.

The start check then looked only at the persist and `working_` schemas, which
the other session's schemas do not match.

## The final gate (`gate_final/`)

`1d00c04c..20209b79` (the same eight picks), after the other session's load had
been gone three minutes (started 23:38 UTC, finished 00:08 UTC on 2026-10-29):

| group | last minutes (0.68.0) | bound | this run | other sessions seen |
|---|---|---|---|---|
| SETN | 16.3 | 48.8 | 7.5 | 1 |
| QUES | 9.3 | 28.0 | 6.6 | 1 |
| OKAN | 7.6 | 22.7 | 2.7 | 1 |
| LFRA | 6.6 | 19.8 | 4.3 | 0 |
| TOAD | 6.0 | 18.0 | 3.3 | 0 |
| UPCE | 3.7 | 11.2 | 1.7 | 0 |
| TAKL | 3.2 | 9.5 | 2.4 | 0 |
| SAJR | 1.6 | 5.0 | 0.9 | 0 |

Every group passed, at 36 to 75 % of its 0.68.0 minutes. TAKL took 2.4 min
where the loaded run killed it at 9.5, and SAJR 0.9 where it was killed at 5. So
the first run's two kills were the other session's load, not this code. One
other session was active during the first three groups.
`study_area_run.sh --preflight-only` then printed
`✓ pre-run gate: gate passed at 20209b798d83 … SETN:pass,…,SAJR:pass`.

## Machinery checks

- **Smoke:** `--only=SAJR` modelled into the scratch schema in 0.8 min (23
  tables and 62 indexes cloned from `fresh_default`). The record is a fail by
  construction.
- **Stall:** `LNK_TEST_STALL_WSG=SAJR --only=SAJR --floor-min=1`. The watchdog
  killed SAJR at its 4.8 min bound and terminated its backend by application
  name (none left). Exit 124 gave the verdict `bound`, and the gate exited 1.
- **Enforcement:** `study_area_run.sh --preflight-only` with no record prints
  `✗ pre-run gate not cleared: no gate record`, and the pre-flight is FATAL.
