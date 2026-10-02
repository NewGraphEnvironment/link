# Review round 2: data-raw/query_habitat_thresholds_mad.R (#302)

Reviewer: code-check subagent, 2026-10-02. I read the full script and the round-1 fix
(`wb_rules()`, `seg_class_sql()`, `seg_class_r()`, `area_sql`). I checked them against
installed fresh 0.36.2: `.frs_rule_to_sql()` and `.frs_waterbody_tables()` in R/utils.R,
`frs_habitat_predicates()`, and the INSERT in `frs_habitat_classify()`. I also checked
default `rules.yaml` and `R/lnk_habitat_validate.R`, where the observations' `waterbody_type`
comes from `fwa_waterbodies` on `waterbody_key`, the same source as the SQL side.

I ran a copy of the script over all 46 calibration WSGs (7 min, rc 0) into the scratchpad
and probed the local DB read-only. No repo file was modified apart from this one.

## Findings

- **[severity: bug]** data-raw/query_habitat_thresholds_mad.R:32-35, 138, 149-152, 166-167.
  The wetland rear rule's area floor is applied here, but fresh never applies it in the
  `rear` predicate.
  - **What fresh does.** `.frs_rule_to_sql()` reads only `lake_ha_min`. For a
    `waterbody_type: W` rule it ignores `wetland_ha_min` and emits no area clause. Rendered
    from installed fresh, the BT/RB W rule is:
    `(s.edge_type IN (1000, 1100) AND s.waterbody_key IN (SELECT waterbody_key FROM whse_basemapping.fwa_wetlands_poly))`
  - **Where the floor does apply.** `wetland_ha_min` is honoured only by `build_wb_pred()`,
    which feeds the separate `wetland_rearing` column. `rearing` is `rear_cond` alone
    (`frs_habitat_classify.R`, INSERT).
  - **Effect.** Under `mad`, every edge-1000/1100 segment in *any* wetland is admitted to
    BT and RB rearing by the W rule, without a discharge test. The script admits it only at
    `area_ha >= 1`. So 1000/1100 edges in wetlands under 1 ha are classed
    `stream_in_waterbody`, which counts as tested, on both the use and the availability side.
    - Wetland polygons under 1 ha: 159,876 of 375,178 province-wide.
    - In `fresh_default`: 2,270 such stream segments (108 km), of which 1,566 segments
      (76 km) are BT-accessible.
  - **Measured on the full 46-WSG run.**
    - One BT location is affected. BT `rear_mad_min` primary P05 moves from 0.027356 to
      0.027343, and `rule_value` stays 0.027. RB has none, and no candidate changes today.
    - `selection.csv` availability for BT `any`/`rear` still carries those ~76 km
      (minus non-calibration WSGs) as tested.
    - So: wrong classification, immaterial at this data state, silently material if
      observations move.
  - **The header claim (l.33-34, "edge and area per rules.yaml") is true of rules.yaml and
    false of fresh.** The task is to agree with what fresh tests, so either:
    - drop the area test for W rules in both `seg_class_sql` and `seg_class_r` and say so in
      the header (matches today's classify), or
    - treat fresh as the defect and keep the floor. In that case file it in fresh: a
      validated rules key, `frs_params.R:242-256`, is dropped by the main-predicate compiler.
      Then note in the header that the script models the intended rule, not the current one.

    A decision for the operator. Either way, the two sides must stop disagreeing silently.

- **[severity: fragile]** data-raw/query_habitat_thresholds_mad.R:150, 166, 178-182.
  The lake rule's polygon set differs from fresh's.
  - In fresh, `.frs_waterbody_tables("L")` is `fwa_lakes_poly` **plus**
    `fwa_manmade_waterbodies_poly`. fresh admits a reservoir key (fwa_waterbodies type `X`,
    368 keys; 1,812 manmade polygons) when any of its polygons meets `lake_ha_min`.
  - The script requires `waterbody_type = 'L'` and takes area only from lakes ∪ wetlands.
    So a 1000/1100 edge in a qualifying reservoir would be classed `stream_in_waterbody`
    (tested) when fresh admits it without a discharge test.
  - **Measured.** `fresh_default` has 0 stream-edge (1000/1100) segments inside type-`X`
    waterbodies, and 1 inside an `L`. So there is no effect today. Fixing it means
    `wb.waterbody_type IN ('L','X')` for L rules and adding the manmade table to `area_sql`.
    That is the same divergence class as the finding above.

## Checked and fine

- **SQL CASE vs R `case_when`.** They agree on every input the data can produce.
  - `edge_type` is never NULL in `fresh_default.streams` (0 of 1,764,956). So the one
    asymmetry, SQL `NOT IN` with NULL falling through while R `!NA %in%` gives `other`, is
    unreachable. An observation with no segment gets `other` and `access` NA, so it is
    excluded either way.
  - A key missing from `fwa_waterbodies` gives NULL/NA type on both sides, then
    `stream_in_waterbody` on both.
  - NULL area fails the admission on both sides (`>=` NULL in SQL, `!is.na()` in R).
  - `edges` NA (KO's L rule) drops the edge test on both sides.
- **Multiple polygons per key.** fresh's `key IN (SELECT ... WHERE area_ha >= x)` is
  equivalent to the script's `max(area_ha) >= x`. No key sits in both lakes and wetlands
  (INTERSECT 0), nor in both lakes and manmade, so the lakes ∪ wetlands max never mixes
  types.
- **River polygons.**
  - `wb.waterbody_type = 'R'` coincides exactly with membership in `fwa_rivers_poly` for
    every keyed segment: 87,915 both, 0 in only one.
  - Segments in R polygons are only edges 1250/1350/1450, so no 1050/1150
    thresholds-false rule overlaps `river_poly`.
  - Every species has a spawn R rule, so `river_poly` is spawn-tested for all four.
- **Spawn and rear tested sets** match the predicates:
  - Spawn is the stream rule (`in_waterbody: false`) plus the R rule.
  - Rear is the stream rule with no `in_waterbody`, plus the R rule, OR'd with W/L rules
    that do not inherit size (`inherit_thresholds` is forced FALSE for L/W). 1050/1150 edges
    are correctly `other`.
- **Decision rule vs header.** It matches:
  - `any` uses rear-tested classes, and the primary rear evidence is `any`, with rear-staged
    as comparison.
  - `n` is non-NULL discharge in the `tested` subset, and `n >= 30` reads it.
  - `floor_signif2` floors to two significant figures.
  - `inherits_size()` returns FALSE for KO rear only.
  - `coverage.csv` is computed from the same `stage_sets` as the quantiles.
- **Note, not a defect.** KO's spawn evidence includes locations that `requires_connected:
  rearing` (3 km to a 200 ha lake) would reject whatever their discharge. The P05 is
  therefore over a wider population than the one the threshold ever gates. This is a
  population choice for the operator, not a classification error.
