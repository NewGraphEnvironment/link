# #259 — pack hosts from measured minutes; learn host speeds from each run (folds in #163)

## Outcome

Scored the two packing weights out of sample and built the learned-speed loop #163 asked for.
Fitted on the 2026-10-17 provincial run and scored on 2026-10-23's buckets, measured minutes beat
FWA segments by eight times on leg balance, and equal host speeds did as well as fitted ones. So
minutes stay the weight and the state starts equal. `data-raw/study_area_packing.R` holds the
shared packing and calibration helpers. `study_area_buckets.R` reads learned speeds keyed by
alias name (every cloud host is one `cloud` class) and writes a per-group plan.
`host_speeds_calibrate.R` turns that plan and a run's phases into one damped, clamped, drift-free
update with an append-only history, and the run's summary prints the command. Most of the
learning is in the review. Six code-check rounds, three of them finding a defect inside the
previous round's fix, kept finding one mechanism: a host's identity, or a speed, read in two
places from two sources that agree only on the default path. Closing it took:

- re-projecting each leg at the stored factor;
- carrying raw minutes and their measuring class in the plan;
- matching hosts by group set within the cloud role;
- leaving out legs that hold groups measured by a host the state does not know.

Round 6's enumeration showed every remaining row tied or an accepted tradeoff. The verdict is in
`research/study_area_run.md`, "How hosts are packed"; the mechanics are in RUNBOOK §8d, "Learned
host speeds".

## Measurement

The largest error in a leg's share of the mean leg, fitted on 10-17 and scored on 10-23 with
KTSU's and OKAN's stalls left out:

| weight | share error | as logged |
|---|---|---|
| minutes | 3.6 points | 16.4 |
| FWA segments | 28.9 points | 28.5 |
| minutes, normalized by the measuring host | 3.4 points | |
| minutes, with speeds fitted on 10-17 (cloud 1.04 of m1) | 6.0 points | |

- **Drift, not speed.** Every leg ran 12 to 20 % over the estimate because the same groups, summed
  per class, took 13 to 16 % longer on 10-23 (m1 1.130, cloud 1.159). That drift is what the
  calibrator now divides out.
- **Why the state starts equal.** Only 10 of 239 groups moved class between the runs. A fitted
  10-23 "seed" (cloud 0.964 of m1) is the two classes' drift ratio (0.976), not their speed.
- **A wrong turn, kept.** That seed was the plan's first intent, and the plan review disproved it.
- **The simulation.** Whole-leg calibration converges on a true 0.7 ratio (0.706 after 20 runs);
  #163's per-group means run away (0.13 to 0.15).
- **Rounds 4 and 5.** Round 4 measured a default-named worker skewing the learned ratio to 0.63
  to 0.76. After its fix, round 5 measured 0.702 to 0.706.

## Evidence

`data-raw/logs/packing_259/` (its README indexes it); the review record is `review-round*.md` in
this directory.

## Owed

- On the next provincial run (#377's runs row): pack with `--minutes-schema --host-names --minutes-exclude=KTSU,OKAN --plan-out`, run the calibrator, re-run
  `packing_259/fit.R` on post-#326 minutes, and close #163's acceptance (3 runs converging,
  idle time after the fastest cloud host < 10 min) over the runs that follow
- fresh#272's release changes the dispatcher's speed (recompute beside its leg); the damping
  absorbs it over later runs — note it on #377 when it lands

Closed by: PR (this branch), closing #259 and #163
