## Outcome

Re-scored bcfishpass parity at v0.66.6, after #349 settled the habitat flags on `streams_access`
and made barrier lifts count observations province-wide. The 17-group closure of ADMS, BULK,
BABL and ELKR was rebuilt under the `bcfishpass` config into scratch `fresh_parity362` and scored
against the same reference and primitive load as the 2026-10-17 baseline (`fresh_parity246`). It
came back 48/50, the same pairs as before, and every move is explained. Parity now has one
current record, `research/bcfishpass_parity.md`, revised in place; the dated parity files are
listed as its history. TURN BT, the one case that could have shown province-wide lifting against
bcfishpass, cannot be scored: bcfishpass does not model TURN or UKEC. What was learned: the one
move #349 did not predict (ADMS CH) is the run-to-run defect #277, now with a mechanism. A PSCIS
crossing with two modelled crossings on one `linear_feature_id` is matched to different ones by
two builds over the same inputs. #277's body carries that measurement.

## Measurement

- Accessible km: no change on any of the 17 pairs; within 0.07 % of bcfishpass.
- The gate removed BT rearing 0.269 km (BULK), 0.325 (BABL), 0.633 (ELKR), the 0.3 / 0.3 / 0.6
  predicted in `research/access_columns.md`, plus 0.002–0.043 km from ten other pairs. The
  prediction's "0 km of spawning" was these, read at 0.1 km. The expectation was written before
  scoring (`expected.txt`).
- Lifts: 10 override positions added, 0 lost (BT and WCT on the Columbia, held by LARL); none
  reaches a scored pair.
- ADMS CH +0.088 km spawning, +0.167 km rearing from the crossing-pick tie. Across the closure,
  349 segments on 75 lines in 12 of the 17 groups exist in one build only. The tie is
  confirmed on the 8 lines in the scored groups.
- Wrong turns, kept: the plan put the 2026-10-17 run at ~7 h, read from file mtimes that came
  from a checkout; its model leg took 54 min (09:36-10:30 UTC), and this run 57 min end to end
  (17:17:38-18:14:35 UTC). The plan review caught it. The first segment diff joined on start only
  and read segments beside moved breaks as habitat changes. The mechanism was first written as "a
  break moved", then as "modelled crossings that moved"; it is a pick tie. Four code-check rounds,
  findings in `review-round1..4.md`.

## Evidence

`data-raw/logs/parity_0.66.6/` (stamp and file index in its README),
`data-raw/logs/study_area_run/20261020_171738_*`, baseline `data-raw/logs/provincial_246/parity*`.
The current record is `research/bcfishpass_parity.md`.

## Owed

- Operator: drop `fresh_parity246` and/or `fresh_parity362` (3.9 GB each) once the record is merged

Closed by: PR for #362
