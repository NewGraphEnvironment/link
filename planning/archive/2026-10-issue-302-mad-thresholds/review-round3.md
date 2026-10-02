# Review round 3: data-raw/query_habitat_thresholds_mad.R (#302)

Reviewed: the staged file (385 lines) against fresh v0.36.2-1-gc341a59 (`R/utils.R`
`.frs_rule_to_sql`, `.frs_waterbody_tables`; `R/frs_habitat_predicates.R` `model_rules`,
`area_only` filter, `build_wb_pred`; `R/frs_params.R` `.frs_build_ranges`) and link's
`R/lnk_habitat_validate.R` (attachment, `access`, stage dedup, discharge join).

## Verdict

**Clean: no defect that changes a number today.** The round-2 fix holds. Three latent
instances of the mechanism remain (below). None fires on the default rules or the
current DB.

## The mechanism

The script decides from its own reading of rules.yaml and params which segments
fresh's mad predicate tests, when fresh's compiled predicate could answer that
directly. Round 2 moved the waterbody admission onto fresh's SQL. The CASE around it
(river first, stream edge set, `waterbody_key IS NULL`) and `inherits_size()` are
still hand-written.

## How it was checked (by measurement, not by reading)

For each species I built fresh's own predicates with
`frs_habitat_predicates(spp, model = "mad")`, with a size range set so that inheritance
happens. I then compiled each predicate twice: once with `s.mad_m3s` replaced by `1.0`
(open) and once by `-1.0` (closed). In both copies `s.gradient` was replaced by `0`.
"fresh tests size here" = `open AND NOT closed`. I cross-tabbed that against the
script's `seg_class_sql()` over every segment in `fresh_default.streams`: 1.88M
segments, all WSGs, BT and GR, spawn and rear. ADMS+PARS was also run for all four
species. Script: `scratchpad/r3/cmp.R`.

Result: **the two agree on every segment.**

- `river_poly` and `stream` are always TRUE for spawn and rear.
- `stream_in_waterbody` is TRUE for rear and FALSE for spawn.
- `waterbody_rule` and `other` are never tested. They are FALSE, or NULL in the closed
  predicate, which fresh's `CASE WHEN` treats as FALSE.
- KO rear has no inheriting rule.

I also did a pre-flight run on ADMS and PARS (a frozen copy, output in the scratchpad).
It finished, and `obs_mad.csv` has no duplicated location (868 rows, 0 duplicates).

## Each place the mechanism reaches

| Place | fresh / validator does | Script | Verdict |
|---|---|---|---|
| Stream edge set 1000/1100/2000/2300 | `edge_types_explicit` on the stream rules, the same for all four species | hard-coded `edges_stream` | agrees (measured) |
| Spawn `in_waterbody: false` | `s.waterbody_key IS NULL` | `WHEN s.waterbody_key IS NULL THEN 'stream'`; spawn excludes `stream_in_waterbody` | agrees (measured) |
| River polygons | `s.waterbody_key IN (SELECT waterbody_key FROM fwa_rivers_poly)`, no edge filter | `fwa_waterbodies.waterbody_type = 'R'`, checked first | agrees today, see F3 |
| River rule under `mad` | `model_rules()` drops rule-level `channel_width`; inherits gradient + mad | treated as tested for spawn and rear | agrees (compiled predicate shows `mad_m3s BETWEEN` on the R arm) |
| Waterbody (L/W) admission | `.frs_rule_to_sql` of L/W rear rules, **after** the `area_only` filter and `model_rules()` | `.frs_rule_to_sql` of L/W rules, no `area_only` filter, no `model_rules()` | agrees today, see F1 |
| 1050/1150 carve-out (`thresholds: false`) | admitted with no size test | `other` | agrees |
| `inherits_size()` | fresh inherits on any rule without `thresholds: false`, with no L/W type and no rule-level `mad:` (R rules included) | needs a non-waterbody rule with 1000 or 1100 in `edge_types_explicit` | agrees for BT, GR, KO and RB, see F2 |
| `access IN (1,2)` | validator `access_<sp> IN (1, 2)` (the `lnk_rollup_wsg` definition) | `access %in% c(1L, 2L)` on use; `a.access_<sp> IN (1, 2)` on availability | agrees |
| Stage flags | validator `.lnk_hv_dedup`: source flag first, then bcfishobs wording, OR-ed per location | `is_spawn %in% TRUE`, `is_rear %in% TRUE` | agrees |
| `mad_m3s` | fresh `frs_col_join(fwa_stream_networks_discharge, by = linear_feature_id)` on the working streams; validator joins the same table on the same key | use from the validator; availability joins the same table on the same key | agrees (`linear_feature_id` unique: 2,716,652 / 2,716,652) |
| Presence | validator `.lnk_wsg_species_present`: `identical(x, "t")` | `%in% "t"` | agrees |
| `fwa_waterbodies` join fan-out | n/a | LEFT JOIN on `waterbody_key` | safe: 538,743 rows, 538,743 distinct keys |

New additions:
- **`any_spawn` fallback.** It is used consistently in `stage_sets`, `coverage`,
  `quant` and `selection` (spawn classes on availability), and in `cands`. When
  spawn-staged n < 30, the primary row gets `decides = FALSE` and the fallback row
  gets `decides = TRUE`. That matches the header and the operator decision.
  Pre-flight: BT spawn-staged n = 1, so the fallback (n = 315) gives 0.046.
- **`floor_signif2`.** Fuzzed on 200k log-uniform values from 1e-5 to 1e4, plus
  binary-noise cases (`0.3 * 0.08`, 0.57, 0.58, 1.15). The result never exceeds `x`,
  is always two significant figures, and never drops more than one step.
  `round(x / e, 9)` can lift a value that sits within about 5e-10 relative below a
  two-figure boundary. That has no practical effect.

## Findings (latent; nothing changes a number today)

- **[fragile]** `data-raw/query_habitat_thresholds_mad.R:144`
  - **What is wrong:** `wb_admit_sql()` does not drop `area_only: true` rules. fresh
    does: `frs_habitat_predicates()` filters them out of the main `rear` predicate.
  - **When it would bite:** a bundle that flags an L or W rule `area_only`. Stream
    edges in those polygons would then be size-tested by the stream rule, but the
    script would label them `waterbody_rule` and drop them from the rear evidence and
    availability.
  - **Today:** no `area_only` in default's rules.
  - The same function also skips fresh's `model_rules()`. That only matters if an
    L/W rule carries `channel_width:`, and none does.
- **[fragile]** `data-raw/query_habitat_thresholds_mad.R:318-324`
  - **What is wrong:** `inherits_size()` re-derives inheritance. It ignores a species
    whose only inheriting rule is `waterbody_type: R` (under `mad` that rule inherits).
    It also counts a rule with an explicit `mad:` as inheriting, when that rule
    overrides the CSV range.
  - **Today:** correct for BT, GR, KO and RB. It could misfire on `--species=` input
    with other rules.
- **[fragile]** `data-raw/query_habitat_thresholds_mad.R:153`
  - **What is wrong:** `river_poly` is decided from `fwa_waterbodies.waterbody_type = 'R'`.
    fresh decides it from `fwa_rivers_poly`, and the two tables differ: 17,282 of
    37,001 distinct `fwa_rivers_poly` keys are **absent** from `fwa_waterbodies`.
  - **Today:** no persisted segment carries one of those keys. All 143,915 `fresh_default`
    segments on river-polygon keys resolve to type R. So this is a DB-state
    coincidence, not a guarantee.
  - **When it would bite:** a segment on one of the absent keys. It would fall to
    `other` (edges 1250/1350/1450) or to `stream_in_waterbody`, so the spawn and rear
    evidence would lose locations that fresh tests.

**One fix retires all three.** Derive "tested" from fresh's compiled predicate, the way
this review measured it: `frs_habitat_predicates(spp, "mad")[[stage]]` compiled with
`s.mad_m3s` replaced by an always-pass value and then a never-pass value (gradient
neutralised), and tested = `open AND NOT closed`. Use it in place of the hand-written
CASE and `inherits_size()`. Optional, since nothing is wrong today.
