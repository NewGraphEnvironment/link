# Review round 1: data-raw/query_habitat_thresholds_mad.R (#302)

Reviewer: code-check subagent, 2026-10-02. Read the diff and the full script. Checked it
against R/lnk_habitat_validate.R, fresh v0.36.2 `frs_habitat_predicates()` and
`.frs_rule_to_sql()`, and the default bundle's rules.yaml, thresholds and presence. Ran a
copy of the script into the scratchpad (`--wsgs=ADMS,PARS`) and probed the local DB
read-only. No repo file was modified.

## Findings

- **[severity: bug]** data-raw/query_habitat_thresholds_mad.R:25-28, 124-128, 144, 206-208.
  The rear population leaves out segments the rear rule does test on `mad`.
  - The header defines the size-tested set as "a stream line (edge
    1000/1100/2000/2300 outside a waterbody)". That is the **spawn** stream rule, which
    carries `in_waterbody: false`.
  - The BT, GR and RB **rear** stream rule in rules.yaml has no `in_waterbody` key.
    `.frs_rule_to_sql()` therefore emits no `waterbody_key IS NULL` clause for it. Under
    `mad` it tests `s.mad_m3s` on edge 1000/1100/2000/2300 segments inside wetlands and
    lakes too.
  - The script sends every such segment to `other_waterbody`, on the use side
    (`!is.na(waterbody_key)` precedes the edge test in `case_when`) and on the
    availability side (`s.waterbody_key IS NULL`). Both sides drop them from
    `tested`, the quantiles, the candidates and `selection.csv`.
  - In ADMS + PARS that is 2,003 `W` / edge-1000 segments, 237 km of network.
  - Measured effect on this run:
    - One accessible GR location sits on edge 1000 in a 335 ha wetland, at
      mad 2.27. GR has no `W` rear rule, so `mad` alone decides that segment.
    - Including it moves the GR `rear_mad_min` primary P05 from 2.561 to 2.478.
    - `rule_value` therefore moves from **2.5 to 2.4**.
  - A segment that a non-inheriting `W` or `L` rear rule already admits is not decided by
    `mad`, so it should stay out:
    - BT and RB: edge 1000/1100 in a wetland of at least 1 ha, or a lake of at least
      10 ha.
    - GR: edge 1000/1100 in a lake of at least 40 ha.
    - This run's one RB `W`/1000 location sits in a 2.7 ha wetland, so excluding it is
      correct. GR's is not covered by any such rule.
  - Fix:
    - For `rear` (the `any` and `rear` sets), count the stream-edge segments inside
      waterbodies that no non-inheriting `W`/`L` rule admits.
    - Make the same change in the availability SQL, so use and availability stay one
      population.
    - Fix the header's set definition per stage.
  - The sibling `query_habitat_thresholds_obs.R` uses the same definition, so the
    omission is inherited. There it only labels misses; here it moves a threshold
    value.

## Checked and fine

- **River polygons:** under `mad`, fresh's `model_rules()` drops the R rule's
  `channel_width`, so the rule inherits the MAD range. Including `river_poly` is correct.
- **`inherits_size()`:**
  - Returns TRUE for BT, GR and RB spawn and rear, and for KO spawn.
  - Returns FALSE for KO rear, whose only rear rule is lake-only.
  - No `$` partial-match trap, because no longer sibling keys exist.
- **Join fan-out:** `fwa_waterbodies.waterbody_key` is unique (538,743 rows and distinct
  keys), and so is `fwa_stream_networks_discharge.linear_feature_id` (2,716,652 / 2,716,652).
  The availability LEFT JOINs cannot fan out, and `wsg_regions.csv` is unique per WSG.
- **Access:** the use side and availability use the same definition (`access_<sp> IN
  (1, 2)` on the full key), the same WSGs, and the same presence parse: the
  presence columns are character `"t"`/`""`, matching `.lnk_wsg_species_present()`.
- **Method override:** reaches the validator through
  `cfg$files$parameters_habitat_method$path`, and the `model == "mad"` guard holds.
- **Floor and decision rule:**
  - `floor_signif2()` matches the header, `n` counts non-NULL discharge only, and the
    n ≥ 30 floor reads that `n`.
  - The stage sets match the header (spawn, then any, with rear-staged as comparison).
- **Discharge values:** none are negative (min 0, 559 zeros), so the `NULL` bin holds only
  missing discharge.

## Note, not a defect

- `access_rb` is 0 on every PARS segment (97k segments).
  - So 280 of RB's 351 locations drop out of the RB evidence set, and RB's
    `rear_mad_min` rests on 42 ADMS locations.
  - The use and availability sides agree, and `coverage.csv` shows the drop. It is a
    property of the access model, not of this script, but it shapes what the RB number
    means.
