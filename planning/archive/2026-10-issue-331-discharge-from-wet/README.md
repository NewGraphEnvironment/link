## Outcome

A bundle now chooses where mean annual discharge is read from (`pipeline: discharge_source: fwapg | wet`, default `fwapg`), threaded through prepare, the run log, the validator, the export manifest, the scoring harness, the MAD producers and host prep (`lnk_preflight_discharge()`, `data-raw/discharge_wet_load.R`, `study_area_run.sh` / `cypher_prep.sh`). Only `default_tuned` reads wet (operator), and BT's MAD minima there move 0.078 / 0.078 → 0.043 / 0.043: rearing scored on held-out groups, spawning set to the same any-stage percentile because the held-out core holds 3 spawning-staged locations. The main thing learned: wet's lower BT percentiles are not a disagreement between sources. On locations both value, they agree; the shift comes from nine Skeena groups fwapg carries no discharge for, and that was found only after the operator had picked a Skeena-weighted spawning value (0.012), which they then changed. At the shipped values `mad` is the closer model for BT on both sources. The fwapg SQL is unchanged; its byte-identity was shown on the generated SQL for every argument shape, not by a data run on ADMS.

## Measurement

- Coverage: wet values 4,503,352 lines (4,532,843 picks, 29,491 zeros), fwapg 2,003,189 (2,716,652 rows). BT observation locations with a value: 89.8 % fwapg, 99.8 % wet. Edge 1250 km with no value in #302's BT groups: 506 → 5.
- Width-to-discharge conversion barely moves: BT spawning 2 m 0.043 (wet) / 0.042 (fwapg); rearing 1.5 m 0.023 / 0.021. `default` stays on fwapg.
- On BT locations both value, P10 0.075 (wet) / 0.076 (fwapg). The 1,178 locations in nine Skeena groups only wet covers sit at P10 0.019; 41 of 58 tested spawning-staged locations are Skeena.
- Build A (one segmentation, `--floor=expected`): rearing on wet P10 0.043 → P05 refused (21 found / 241 expected); fwapg controls 0.083. Spawning on wet underpowered on spawning-staged records; on any-stage records P10 0.012 → P05 refused (4 / 195).
- Build B at 0.043 / 0.043: `cw`-only BT rearing used at 0.18 of the size-matched core, `mad`-only at 1.64; spawning 0.14 / 0.69. `mad` keeps −19.8 % BT rearing on wet, −21.3 % on fwapg (#305: −32 % at 0.078).
- `cw` unchanged: NATR, one prepare, both joins: `mad_m3s` differs on 189,092 of 189,200 rows, 0 habitat rows differ.
- Wrong turns kept: the score first ran with the script's default `--floor=found`; the spawning value was first landed at 0.012 before the Skeena split was measured; the follow-up issue first asserted an unmeasured cause; Build B's first run died on a full DB volume (62 stale schemas dropped, 40 GB freed).

## Evidence

`data-raw/logs/discharge_wet_331/`, `data-raw/logs/habitat_score_331/`, `data-raw/logs/habitat_score_331_spawn_any/`, `data-raw/logs/habitat_score_331m*/`. Write-up: `research/habitat_thresholds.md`, "MAD on wet's discharge (#331)". Follow-ups: #343 (GR, KO, RB on wet), NewGraphEnvironment/wet#88 (per-part load record).

Closed by: PR for #331 (link 0.66.0)
