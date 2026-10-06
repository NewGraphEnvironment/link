# Plan review — #305 (Plan agent, 2026-10-06)

Read-only agent; findings returned in its reply and transcribed here. Disposition is in
`task_plan.md` (revised 2026-10-06) and below.

| id | finding | disposition |
|---|---|---|
| B1 | `frs_col_join()` with a subquery `from` creates `text` columns (fresh `R/frs_col_join.R:85-87,113-115`) — first `mad` classify would fail `text BETWEEN numeric` | prepare adds `mad_m3s double precision` / `mad_m3s_source text` itself and UPDATEs; test asserts the type |
| B2 | #300 bundles `extends: default_tuned`; once the knob is on, a re-score reads fill on against schemas built raw | `built.csv` records `discharge_fill` (absent = FALSE); the harness sets each variant cfg's fill from it |
| B3 | #300's own regressions were not byte-identical for double sums (9.5e-15 rel) | acceptance: integer/character identical, numeric within 1e-12 relative, name the byte-identical files |
| G1 | more discharge reads: `.lnk_hv_check_mad`, #302 calibration scripts (`query_habitat_thresholds_{mad,fiss}.R`); validator labels use `mad_m3s` | calibration scripts stay raw (thresholds calibrated with NULLs excluded) — stated in research; labels follow the fill (intended) |
| G2 | validator reads fill from `cfg`, fill happens in prepare; old schemas would be scored on filled values silently | `discharge_fill` column in `<schema>.log`; validator stops on a logged WSG whose value differs from `cfg`'s |
| G3 | `lnk_log.R:206` is input primitives, wrong place | log column instead (G2) |
| G4 | WSG scoping breaks the #299 fixture (`AAAA` WSG with real lines) | validator scopes the fill by the scored `<schema>.streams` lines; fixture pinned |
| G5 | absent rows need enumeration from `fwa_stream_networks_sp` | builder already does; test fills an absent-row line |
| G6 | tiers 1–2 reach ≤ 48 %; a downstream-line tier overestimates | measured: 330 km of #300's BT band is the Beatton (no rows anywhere). Tier 3 is the upstream tributary max (lower bound), not the downstream line |
| G7 | `.lnk_pipeline_prep_network()` has no `cfg` | threaded |
| G8 | validator's per-observation scalar subquery would re-run laterals | materialise once per call into a `pg_temp` table |
| G9 | no dictionary for config knobs | `lnk_config()` doc knob list + config.yaml comment + inheritance test |
| O1 | candidates SQL landed in Phase 1 | accepted; plan updated |
| O2/O3 | regression ordering; type test before Phase 4 | covered by B2 mechanism and the B1 test |
| A1 | full rebuild confounds the fill with PSCIS-tie segmentation noise | Phase 4 reuses `working_score300_*`: refill `mad_m3s` in place, `--step=variants` into new variant names |
| A2 | score300 schemas existence unchecked | checked: all present |
| A3 | single-line masking underestimates error | long-gap (≥ 10 km) sample + tributary sample added to Phase 1 |
| A4 | neighbour may be any edge type / any WSG | stated in plan and builder doc |
| A5 | upstream-first rarely changes classification | noted |
| S1 | `default_extrabreaks` / `default_rearbreaks` don't inherit | knob absent → FALSE there; stated |
| S2 | knob in `default` moves `default`'s config_hash and costs every default WSG | knob in `default_tuned` only |
| S3 | 1250-only vs band composition (71 of 504 km non-1250) | recorded with numbers in research |
| S4 | expose `mad_m3s_source` in validator obs output | done |
| AC4 | disk (colima 82 G free); no repo edits during detached run | reuse avoids a second closure; rule kept |
