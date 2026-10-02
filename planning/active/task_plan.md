# Task: lnk_habitat_validate() scores mad watershed groups as if they were cw (#299)

**If done:** observation validation reports the right miss reasons for groups a bundle
puts on discharge. **If never:** a `mad` group's "missed for width" counts are computed
against channel width the classification never used. Nothing is affected until a
bundle actually sets a group to `mad`, and none does today.

Since #286, `lnk_pipeline_classify()` passes the bundle's
`parameters_habitat_method.csv` to fresh, and a `mad` group classifies on `mad_m3s`.
`lnk_habitat_validate()` still builds its predicates with
`fresh::frs_habitat_predicates(spp)`, which is the cw model
(`R/lnk_habitat_validate.R:823`). It then relaxes width by rewriting `s.channel_width`
(`.lnk_hv_relax()`, `:772-786`), with minimums taken from
`ranges$<stage>$channel_width` (`.lnk_hv_stage_min()`, `:763`). On a `mad` group:
- the predicate is not the one that classified the segment, so `pred_*` can disagree
  with the persisted `spawning`/`rearing`;
- width relaxation rewrites a column the mad predicate does not reference;
- `width_null` (`.lnk_hv_miss_reason()`) tests `channel_width`, where it should test
  `mad_m3s`. The persist does not carry `mad_m3s` (decided in #286), so the validator
  would join it from `whse_basemapping.fwa_stream_networks_discharge` on
  `linear_feature_id`.
- The stream-order rearing bypass is skipped for `mad` groups (#286), so a miss
  reason must not credit it there.

fresh >= 0.35.0 has `frs_habitat_predicates(model = "mad")`. Resolve each scored
group's model from the bundle's method table, build the predicates per model, and relax
`s.mad_m3s` for mad groups. `test-lnk_habitat_validate.R` "the predicate call stays on
the channel-width model" pins today's behaviour and should change with it.


**Decisions taken (user, plan gate):**
- Size miss labels **keep their names** (`fails_width`, `width_null`,
  `fails_gradient_or_width`, `fails_gradient_and_width`) and mean "the group's size
  dimension"; observations gain `model` and `mad_m3s` so a reader can split them.
- **New reason `no_mad_threshold`**: a miss on a `mad` group where the species has no MAD
  range for that stage (BT, GR, KO, RB today) and only that stands in the way. Longer
  term the user wants those thresholds tuned and added rather than left missing; a
  follow-up issue body is drafted for review (not filed).

## Phase 1: Shared model resolution

Resolver is fresh's own `.frs_habitat_models()` via `getFromNamespace()` (added to the preflight's required internals), not a link copy.

- [x] Add `.lnk_habitat_method_read(path)` and `.lnk_wsg_model(params_method, wsg)` beside `.lnk_habitat_method_csv()` in `R/lnk_config.R` (character read as classify does; unlisted → `"cw"`; error on a model other than cw/mad)
- [x] `lnk_pipeline_classify()` uses both for its read and its `aoi_model` (behaviour-preserving)
- [x] Unit tests: unlisted group is cw, bad model value errors, classify still skips the bypass only for mad

## Phase 2: Model-aware predicates and relaxation
- [ ] Test first: replace "the predicate call stays on the channel-width model" with a test that the call passes `model =`; unit tests for a new pure helper `.lnk_hv_stage_exprs(spp, model)` — mad exprs reference `s.mad_m3s` not `s.channel_width`, relaxed variants replace `s.mad_m3s`, cw exprs byte-identical to today's
- [ ] `.lnk_hv_stage_min(spp, model)` reads `ranges$<stage>$mad_m3s` on mad (absent → 0)
- [ ] `.lnk_hv_relax(pred, gradient, size, size_col)` rewrites the model's size column
- [ ] `.lnk_hv_predicates()`: resolve each scored WSG's model, put it on `lnk_vd_seg`, run one query per species × model present; mad queries read `streams` LEFT JOINed to the discharge table on `linear_feature_id` (aliased so predicates still see `s.mad_m3s`)
- [ ] `pred_<stage>_nomad`: on mad groups whose species lacks that stage's MAD range, the predicate rebuilt with the range filled and gradient + size relaxed; `NA` elsewhere

## Phase 3: Miss reasons and output columns
- [ ] `.lnk_hv_obs()` attaches `model` per WSG and `mad_m3s` (joined only when some scored group is mad, so a cw-only call issues no new query; `NA` otherwise)
- [ ] `.lnk_habitat_miss_reason()` takes the size value (`channel_width` on cw, `mad_m3s` on mad) for `width_null`, and a `p_nomad` arm placed after `fails_gradient_and_width`, before `rule_excludes`
- [ ] `summary` gains `model`
- [ ] DB tests on the fixture: add `linear_feature_id` drawn from the live discharge table (skip if absent), a method table putting AAAA on mad; assert BT stream misses read `no_mad_threshold`, `mad_m3s` is populated, `model` columns, and every existing cw assertion unchanged
- [ ] Unit test: `width_null` keys on the size value passed, so a mad row with NULL discharge and a width reads `width_null`

## Phase 4: Docs and driver
- [ ] Roxygen: Miss reasons section (size dimension per model, `no_mad_threshold`, model from the bundle's method table, caveat that a schema built under a different method table is not detected); `@return` columns; `devtools::document()`
- [ ] `data-raw/habitat_validate.R`: carry `model` into `misses.csv` / `misses_binned.csv`; bin width on cw rows only
- [ ] RUNBOOK §7 bullet, `research/habitat_validation.md`, CLAUDE.md "cw-only (#299)" fact
- [ ] Draft (not file) follow-up issue: tune and add MAD thresholds for BT/GR/KO/RB

## Phase 5: Live verification (local docker fwapg)
Run decisions: config `default` with a temp method table putting **ADMS** on `mad`;
persist schema **`zz299_mad`** (scratch, dropped after); WSG ADMS only (no closure);
species from config × presence; `mapping_code = TRUE` (validator needs `streams_access`);
no `--refresh-primitives`.
- [ ] cw no-change: validate ADMS on `fresh_default` with branch vs main — `observations` and `summary` identical apart from the new columns
- [ ] mad: model ADMS into `zz299_mad`, validate CH/CO/BT; count locations where persisted `spawning`/`rearing` is TRUE but `pred_*` FALSE outside UHC — expect ~0 on branch, show main's count for contrast; tabulate reasons (BT → `no_mad_threshold`)
- [ ] Log under `data-raw/logs/habitat_validate_299/` with env stamp

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
