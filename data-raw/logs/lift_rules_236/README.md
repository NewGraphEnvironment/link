# Several observation-lift rules per species (link#236)

**Measured:** 2026-11-24 on m1's local fwapg. **Produced by:** `prove.R`, `measure.R`.

## The mechanism runs where no shipped bundle declares a rule (`prove.R`)

`default` copied to a scratch bundle that declares `parameters_barrier_lifts.csv` with the candidate rule (BT also lifts on two or more salmon or steelhead records since 1990), loaded by path, and ADMS run through load, prepare, crossings, unify and persist into a scratch persist schema at the branch's code. Those phases resolve no vocabulary (only `lnk_pipeline_run()` calls `lnk_vocabulary_resolve()`), so the bundle needs no token.

ADMS's evidence by rule, working and persisted alike (`prove_ADMS_working.csv`, `prove_ADMS_persisted.csv`): BT rule `own` lifts 34 positions, rule `salmon` 3, of which 2 no other BT rule lifts; every other species' rows carry `own` or `habitat`.

## What the candidate rule would add (`measure.R`)

See `candidate_default.csv` once run: per proof group, BT lifts under the own rule and those the candidate adds, working and held.
