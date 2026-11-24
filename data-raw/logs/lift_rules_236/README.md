# Several observation-lift rules per species (link#236)

**Measured:** 2026-11-24 on m1's local fwapg. **Produced by:** `prove.R`, `measure.R`.

## The mechanism runs where no shipped bundle declares a rule (`prove.R`)

`default` copied to a scratch bundle that declares `parameters_barrier_lifts.csv` with the candidate rule (BT also lifts on two or more salmon or steelhead records since 1990), loaded by path, and ADMS run through load, prepare, crossings, unify and persist into a scratch persist schema at the branch's code. Those phases resolve no vocabulary (only `lnk_pipeline_run()` calls `lnk_vocabulary_resolve()`), so the bundle needs no token.

ADMS's evidence by rule, working and persisted alike (`prove_ADMS_working.csv`, `prove_ADMS_persisted.csv`): BT rule `own` lifts 34 positions, rule `salmon` 3, of which 2 no other BT rule lifts; every other species' rows carry `own` or `habitat`.

## What the candidate rule would add (`measure.R`)

On the AFTER-386 `default` proof build's kept working schemas (`w386ad_*`), with `observations_province` rebuilt and dropped per group, `lnk_barrier_overrides()` run with each species' own rule and with the candidate added (`candidate_default.csv`):

| group | BT lifts, own rule | added by the candidate | of those, beside a barrier the group holds |
|---|---|---|---|
| ADMS | 34 | 2 | 2 |
| TABR, LSAL, SALR, ELKR, BULK, UPCE, PCEA, LPCE, FINA, PARS | 0 to 200 | 0 | 0 |

Two lifts in eleven groups. Where salmon reach a BT barrier on these groups, BT records already lift it, or the salmon records are below two. Whether `default` adopts the rule is a follow-up issue, which would measure it province-wide.
