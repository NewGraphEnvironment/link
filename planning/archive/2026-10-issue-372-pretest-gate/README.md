## Outcome

A pre-run gate (link#372) for provincial runs.
- **What it runs:** `data-raw/pretest_run.sh` reads the files changed since the last provincial run, in link and in fresh. A tracked map (`data-raw/pretest_inputs.csv`) gives each file the inputs that drive its cost, and the gate models the groups at each input's extreme into a scratch schema, bounded at 3× their last minutes.
- **What it enforces:** it records a verdict in `<schema>.log_pretest`, and `study_area_run.sh`'s pre-flight refuses a run that no passing record clears. `--pretest-note` runs without one and records the reason.
- **What made it hard:** the record check. The plan review and five code-check rounds kept finding checks that read a stand-in for the code (a SHA, a DESCRIPTION pin, a hand-kept list, a call graph frozen at one fresh, the rulebook at HEAD) and filtered a missing stand-in out instead of refusing. Twice the defect was inside the previous round's fix.
- **How it ended:** round 3 named that mechanism, rounds 4 and 5 enumerated every place it reaches, and every place now refuses or is a documented limit (RUNBOOK §8d, "What it does not cover").
- **The first real gate failed, and that was its job:** two groups were killed at their bounds within minutes, under another session's load. The second, on a quiet database, passed.

## Measurement

- **The near-river walk's cost input is fresh's `conn_max`,** the longest connector run. QUES is first of 246 groups (63.3 km), TAKL second (32.3 km). OKAN is 29th, but first of 143 on CABD dams. **KTSU ranks 119th or lower on every input, so no input picks it.**
- **Picks:**
  - `0.66.6..0.68.0` (bounded on `fresh_default_20261017`'s minutes): 10 groups, QUES and TAKL for the walk, OKAN and SAJR for dams.
  - `1d00c04c..HEAD`: 8 groups, about 55 min of last-run minutes.
- **First real gate:** six groups finished at 36 to 68 % of their 0.68.0 minutes. TAKL (in the walk) and SAJR were killed at 9.5 and 5.0 min while another session ran six modelling workers on the database. SAJR had modelled in 0.8 min alone an hour earlier.
  - **What changed because of it:** the start check had looked only at the persist and `working_` schemas. It now refuses beside any active session (`--allow-busy`), and load is sampled per group.
- **Final gate (`20209b79`, quiet database):** all eight passed at 36 to 75 % of their minutes (TAKL 2.4 min, SAJR 0.9). So the first run's kills were load, not code. `--preflight-only` then accepted the record.
- **Machinery:**
  - The stall hook was killed at its 4.8 min bound with exit 124, and no backend was left running.
  - Every guard added was proved by restoring its defect: 18 code mutants and 3 map mutants, each turning the suite red.
  - Full suite: 4,618 pass, 0 fail.
- **Cost of review:** six review agents (the plan review and five code-check rounds), past the usual bound of about five. Rounds 2 to 5 each found a real fail-toward-pass place.
- The settled findings are in `research/study_area_run.md`, "The pre-run gate".

## Evidence

`data-raw/logs/pretest_372/` (its README indexes it: `reach.md`, `acceptance_0.66.6_0.68.0/`, `gate_1d00c04c_loaded/`, `gate_final/`).

## Owed

- At the next provincial run (#377's runs row), run the gate first. Record its picks and its minutes beside that run's own minutes for the same groups, which tests whether k = 3 is right

Closed by: PR for branch `372-a-scoped-pre-run-gate-model-the-groups-t`
