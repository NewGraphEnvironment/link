# Review: #299 Phases 1-3, round 2 (branch vs main, R/ + tests/)

Scope: `git diff main -- R tests` (p23.diff, 859 lines), plus full reads of the changed
functions and fresh 0.36.2's `frs_habitat_predicates()`, `.frs_rule_to_sql()`,
`.frs_habitat_models()`, `.frs_preds_by_model()` and `frs_habitat_classify()`'s model
resolution.

Tests run in a copy of the tree (`NOT_CRAN=true`, local docker fwapg):
test-lnk_habitat_validate.R 180 pass, test-lnk_config.R 158 pass,
test-lnk_preflight_fresh.R 39 pass, 0 fail / 0 skip.

## Findings

- **[fragile]** R/lnk_habitat_validate.R `.lnk_habitat_miss_reason()` (the new
  `set(p_nomad, "no_mad_threshold")` line), with `.lnk_hv_stage_exprs()` building
  `_nomad` with the size relaxed to 0. A miss on a mad group, for a species with no
  MAD range, on a segment whose `mad_m3s` is NULL reads `no_mad_threshold`. The
  decision recorded for #299 says this label means the missing range is the ONLY
  thing in the way. Here it is not: supply a range and the segment still fails,
  because the discharge is NULL. `_nomad` substitutes a constant for `s.mad_m3s`, so
  it cannot see a NULL. On cw the same situation, size relaxed passes and the value
  is NULL, reads `width_null`. The `width_null` arm never fires for these rows,
  because `p_w` still carries fresh's literal `FALSE` and so is always FALSE.
  The test fixture pins the current behaviour without saying so: `o2` sits on AAAA
  segment 1, which `local_mad_fixture()` gives the `mad_m3s IS NULL` line, and the
  test expects `miss_reason_spawn == "no_mad_threshold"`. The comment there gives only
  the persisted-spawning reason.
  Impact: in real mad groups with discharge gaps, NULL-discharge misses for BT, GR,
  KO and RB are counted as missing thresholds rather than missing data. That
  overstates what adding a MAD range would recover, which is the question this
  label exists to answer.
  Fix, if the stated meaning is kept: gate it as
  `set(p_nomad & !is.na(size), "no_mad_threshold")` and route
  `p_nomad & is.na(size)` to `width_null`, mirroring the cw order. Then update the
  `o2` expectation. If the current behaviour is deliberate, put that in the test
  comment and in the roxygen.

## Checked and clean

- cw output: `.lnk_hv_stage_exprs(spp, "cw")` equals the pre-#299 construction apart
  from the two `NULL::boolean` `_nomad` columns (test-pinned). `size` is
  `channel_width` for cw, and `p_nomad` is NA so it cannot set a reason. The only
  cw-visible changes are the added `model`, `mad_m3s` and `pred_*_nomad*` columns.
  `mad_m3s` is inserted mid-frame, between `channel_width_source` and `edge_type`.
  Nothing in R/ or data-raw/ reads by position.
- Discharge join: `fwa_stream_networks_discharge` has a unique PK on
  `linear_feature_id` (2,716,652 rows, 2,716,652 distinct). So the scalar subquery in
  `.lnk_hv_obs` cannot raise "more than one row" and the LEFT JOIN in
  `.lnk_hv_predicates` cannot fan out. The persist's `cols_streams` carries
  `linear_feature_id`, and prepare joins the same table on the same key, so the
  validator reads what classify read.
- `.lnk_wsg_model()` delegates to fresh's resolver, so it matches classify. fresh
  0.35.0, the DESCRIPTION floor, has both `.frs_habitat_models` and
  `frs_habitat_predicates(model=)`. The preflight declares both. The `exists()` loop
  fix is correct: `exists()` is not vectorised.
- `lnk_pipeline_classify`: swapping `match()` for `.lnk_wsg_model()` keeps the bypass
  decision identical, because an unlisted group or NA is cw and was never `"mad"`
  either way. It errors on a bad table earlier, which fresh would have done anyway.
- `.lnk_hv_relax(size_col = "mad_m3s")` leaves `s.mad_m3s_x` alone (`\b`). MAD
  minimums in every bundled thresholds CSV have at most 5 significant digits, so
  `format()` cannot round a relaxed value outside its window. fresh's `frs_params()`
  leaves `ranges$<st>$mad_m3s` NULL, never `c(NA, NA)`, when the CSV is NA, so the
  `is.null()` test in `no_range` is the right one.
- The `_nomad` construction substitutes `c(0, 0)` and relaxes the size to 0. That
  makes the inherited `BETWEEN 0 AND 0` or `>= 0 AND <= 0` true, and keeps the lake
  and wetland branches polygon-equivalent.
- `.lnk_hv_predicates` per (species, model) combos: each (species, id_segment, WSG)
  key falls in exactly one combo, because the model is per WSG. So the `match()`
  merge is 1:1. The empty-`seg` path still returns `NULL` from `rbind`, as before.
- `out$mad_m3s[out$model != "mad"] <- NA_real_` is safe if `model` were ever NA
  (length-1 value), and every observation's group is in `aoi` via `lnk_vd_spec`.

## Note (not a finding)

The roxygen `@section Miss reasons:` (R/lnk_habitat_validate.R ~L95-110) still says
"channel-width model" and does not list `no_mad_threshold`, so the label is absent
from the man page that presents the list as complete.
