# #441: the provincial minimal-breaks run

## Outcome

Six PRs took the next provincial run from plan to a built schema. #443 pinned fresh 0.52.0 and let the pre-run gate borrow a parent config's history (0.78.0). #445 proved #415's minimal network is the full one with fewer cuts. #447 showed `default` at this code equals its last builds and held `bcfishpass` parity at 48/50. #448 refreshed m4's and m1's primitives. #449 recorded the gate's pass on `default_minimal` and a rehearsal through the real driver on six groups and four hosts. The sixth PR is the run: `default_minimal` into the new `fresh_default_minimal`, all 241 groups, from m4 with m1 as a worker and three cloud hosts. Driver exit 0, and every check passed. What it taught: packing at equal speeds left the cloud hosts setting the end, and the calibrator's first update corrects for it. A worker's consolidate goes at the speed of its Tailscale path, which was a relay mid-copy and direct two hours later. And a run's write-up drifts in the same way code does: each of the four code-check rounds found claims written from an in-session reading or an earlier block rather than from a committed artifact, and the loop ended only on an enumeration of all 101 claims.

## Measurement

Run `20261102_203300-60ab009d`, link `193cb8aa` (0.78.1), fresh 0.52.0, tokens `cut-min acc-v5 grad-seg q-fwapg` on all 241 rows.

- Legs: m1 87.4 min (49 groups), m4 103.3 (48), job2 159.8, job3 168.1, job1 183.0 (48 each), against the plan's 202 to 203 each at equal speeds. Overall 0.69 of the plan's minutes.
- Critical path 228.2 min. Consolidates: m1 47.6 min (`barriers` and `streams` at about 550 and 870 kB/s), cloud 12.8 to 13.3. Early recompute 126.8 min summed; tail 12.3 min past the last consolidate.
- `fresh_default_minimal`: 4.99 M segments, 19 GB.
- Learned speeds after this run: m1 1.18, m4 1.11, cloud 0.95.
- Checks: `study_area_verify.sql` at 241, the negative cases, `verify_extra.sql`, `recompute_audit.R` (2,191 of 2,191 pairs), no host kept, no droplet left.

The durable write-up is `research/study_area_run.md`, "The province-wide `default_minimal` run"; RUNBOOK §8d gains the worker-path note.

## Evidence

`data-raw/logs/minimal_run_441/` (launch, packing, `checks/`), `data-raw/logs/study_area_run/20261102_203300_*`, `data-raw/logs/host_speeds*.tsv`. Earlier phases: `data-raw/logs/gate_borrow_442/`, `data-raw/logs/minimal_breaks_415/`, `data-raw/logs/hosts_ready_439/`, `data-raw/logs/pretest/20261102_102658_default_minimal/`, `data-raw/logs/rehearsal_418/`.

## Owed

- #418's gated rehearsal script (picker, `log_rehearsal`, launch refusal, seeded failures), left open with a note on #418 and #441.
- knowledge#120, the first consumer of `fresh_default_minimal`.
- The host-speed calibrator's second and third runs (#163's three-run acceptance) on the runs that follow.
- `fresh_default` and `fresh` re-models owed by earlier status blocks; #369, #371, #374, #375 and #376 left open for the operator to judge against this run's numbers; #259's and #261's re-fits; #446.

Closed by: PR from branch `441-minimal-run` (merge is the operator's)
