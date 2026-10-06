# Code-check round 2 — #305 staged diff

Reviewer: subagent, 2026-10-06. Read-only against the repo and docker fwapg (:5432).

Both round-1 fixes look right. `reach.csv` now keeps the tributary tier as `gap_class = ""`.
`needed` keeps a cw-only validator run off the fill, and the predicates fall back to the raw
table only when no expression reads `s.mad_m3s`. Every number in the new research section
matches `data-raw/logs/discharge_fill_305/*.csv` (22 %, 6,243 / 28,122 km, 4,152 / 2,091 km,
4,098 km, 3,407 km, 223 km, 1,862 km in 12 groups, the accuracy and minimum tables, and
433 / 330 / 103 / 193 / 71 km). The exception is the tributary share of `reach.csv`, which the
stale file cannot show, as already noted. With the fill off, the output equals the old
`frs_col_join()` path: `mad_m3s` is `double precision` both ways, `linear_feature_id` is unique
in the discharge table (2,716,652 rows and as many distinct ids), and the log migrates by
`ADD COLUMN IF NOT EXISTS`.

## Findings

- **[bug]** `R/lnk_discharge.R:144-155` (tributary lateral), which defeats
  `data-raw/habitat_variants_build.R:617-628`. In a watershed group the discharge layer does not
  model, the tributary tier turns NULL into a near-zero value taken from whatever stray valued
  line happens to sit upstream.
  - **Measured on LSKE**, which has 0 discharge rows, as do BULK, MORR, KISP and the rest of the
    Skeena: `.lnk_discharge_sql("LSKE", fill = TRUE)` returns 402 lines as `fill_tributary_max`
    with a maximum of 0.00324 m³/s. That includes the order-9 Skeena main stem at its mouth
    (`linear_feature_id` 123065564).
  - **Where the value comes from:** a single order-1, edge 1200 line in TAKL
    (`linear_feature_id` 831798080, `blue_line_key` 360565541) whose wscode falls under the
    Skeena.
  - **Consequence 1, the guard fails toward pass:** the build harness's guard
    (`count(mad_m3s) == 0` means "carries no mad_m3s, stop") now passes for an uncovered group
    under a fill-on `mad` variant. That is the case the guard exists for: the group then
    classifies with no stream habitat, and the result reads as a threshold verdict.
  - **Consequence 2, misses are relabelled:** they move from "no discharge" to "below the
    minimum". That is `mad_null` → `outside_mad_range` in `model_reason.csv` /
    `model_fill.csv`, and the same shift in the validator, which inverts the split #300's
    finding rests on.
  - **Consequence 3, the RUNBOOK check misleads:** its "Check `count(mad_m3s)` before moving a
    group" stops meaning anything on a filled working table.
  - **Scope of the exposure:** 109,500 edge 1250 lines (30,109 km) province-wide sit on a
    `blue_line_key` with no value anywhere, so all of them reach this tier. They are mostly in
    groups with no coverage: TOAD, OWIK, HOMA, LSKE, KITL, LIAR, and so on.
  - **The 12 scored WSGs are unaffected**: only UBTN's Beatton uses the tier there, with
    plausible values.
  - **Fix, either of:**
    - gate the tributary tier, for example by requiring the target's own group to be covered,
      or the tributary to be a real one;
    - make the build guard and the RUNBOOK check count `mad_m3s_source = 'modelled'` rather
      than `mad_m3s`.

- **[fragile]** `R/lnk_pipeline_prepare.R:127-128`. prepare fills whenever the bundle's knob is
  on, whatever the group's model.
  - Round 1 gave the validator `needed` so that a cw-only run neither pays for the fill nor
    depends on it. prepare got no equivalent.
  - `default_tuned` is all-`cw`, yet every `default_tuned` run pays for tributary lookups whose
    result nothing reads.
  - **Measured:** the LSKE fill alone took 6 m 13 s, for the 402 near-zero values above.
  - **Province-wide estimate:** 109,500 tributary-gated lines at about 0.9 s each is on the order
    of a day of serial prepare added to a 217-WSG `default_tuned` run.
  - **Fix:** gate the fill in prepare on the group's model, the way the validator is gated.
    Because the log records the knob, the validator's log check would then also need to compare
    against what was actually applied.

## Note (documented tradeoff, not counted as a finding)

The research section says the lower bound is safe "because every BT, GR and RB maximum is open".
The fill is bundle-wide, though, and applies to every species of a `mad` group. `default_tuned`
carries finite rearing maxima for CH (100), CO (40), ST (60) and WCT (40, and spawning 59.15).
For those species a filled main stem whose true value exceeds the maximum can be admitted where
NULL excluded it. The docstring acknowledges this ("can be wrong against a maximum"). It is worth
remembering before CO, CH, ST or WCT are scored on a `mad` group.
