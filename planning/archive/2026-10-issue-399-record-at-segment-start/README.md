# A fish record at a segment's start is not upstream of it (#399)

## Outcome

The access walk's observation call in `lnk_pipeline_access()` now passes
`include_equivalents = FALSE`, so fwapg's same-line measure test counts a record as upstream
of a segment only at `m >= start + 1` (was `start - 1`). With each species' top a break, the
segment starting at a species' highest record on a line normally reads 1. Exploration found
the issue's premise wrong: bcfishpass's own walk passes `False`, so there is no bundle key and
both configs move. `acc-v1` and `acc-bcfp` were retired at 0.72.0 for `acc-v2` and
`acc-bcfp-2` with the same specs. What was learned in review: the rule for where code 2 ends
has to be derived from `fwa_upstream()`'s clauses (same line by measure; other lines by code,
per branch; the measure-blind side-channel clause, which can match the segment's own line)
and from `frs_break_apply()`'s end test (a top within 1 m of an FWA line end does not cut).
Three review rounds each found a carve-out the previous wording missed, until RUNBOOK §2c was
written from the SQL.

## Measurement

Five `default` groups (LKEL, BULK, UPCE, PARS, ELKR) and two `bcfishpass` groups (BULK,
PARS), built before and after on m1's local fwapg in scratch schemas, 2026-10-30:

| config | group-species | km of code 2 to 1 | per group-species | share of observed km |
|---|---|---|---|---|
| `default` | 25 | 346.6 | 0.02 to 73.5 | 0 to 5.4 %, median 1.8 % |
| `bcfishpass` | 7 | 93.6 | 1.9 to 29.7 | 0.6 to 4.2 %, median 1.9 % |

Segments, segment starts, barrier flags, mapping codes and habitat did not move
(`n_violation` 0 on 32 rows; the check was shown to stop on three planted edits). link's
`bcfishpass` builds now equal the reference view's observed km to 0.00 km, steelhead excepted
(the reference, `v0.7.15-50-g620dbe4`, codes it from sockeye records). This replaces #403's
1.9 to 29.7 km gaps, which the before-builds reproduce exactly. #403 expected `default` to
lose more than `bcfishpass`; in BULK it lost nearly the same. Write-ups:
`research/known_suspected_km.md` ("After #399"), `research/observation_breaks.md`
("Since #399"), RUNBOOK §2c ("What reads 2").

## Evidence

`data-raw/logs/record_at_start_399/` (its README indexes it). Code-check rounds:
`review-round*.md` and `enumeration-round3.md` here.

## Owed

- Every persisted group carries the old reading until re-modelled: the recompute passes no observations and keeps a prior 2. `fresh_default` (241 groups) and the `bcfishpass` schema re-model at the next provincial run (#377's runs row), stacked on #326's and #396's owed re-models. The pre-run gate (#372) must run again (`R/lnk_pipeline_access.R` changed).
- `lnk_scenario_export()`'s access-code column (#403 "Not done") still waits for #401.

Closed by: the PR from branch `399-read-a-fish-record-at-a-segment-s-start`
