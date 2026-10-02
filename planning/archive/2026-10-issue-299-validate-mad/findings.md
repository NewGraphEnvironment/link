# Findings — lnk_habitat_validate() scores mad watershed groups as if they were cw (#299)

## Issue context

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


## Facts from exploration that shape this

- fresh 0.36.2 `frs_habitat_predicates(spp, model = "mad")`: size column `mad_m3s`; an
  absent MAD range inherits as `FALSE` (no `s.mad_m3s` reference, so relaxation can't
  rescue it); rule-level `channel_width` (river-polygon bypass) dropped; rule-level
  `mad:` emits `s.mad_m3s BETWEEN`. Lake/wetland rules inherit nothing under either
  model, so BT keeps wetland rearing on mad.
- Persisted `<schema>.streams` carries `linear_feature_id` but not `mad_m3s` (#286
  decision); prepare joins it from `whse_basemapping.fwa_stream_networks_discharge` on
  `linear_feature_id` (`R/lnk_pipeline_prepare.R:697`).
- Classify resolves the group model with `params_method$model[match(aoi, ...)]`
  (`R/lnk_pipeline_classify.R:165`), unlisted → cw. Validator will share that, not
  re-derive it.
- The stream-order rearing bypass is never modelled by the validator (no reference to
  it), so it cannot be credited on a mad group; a test pins that a mad order-1 child
  miss gets a predicate reason, not `post_predicate`.
- Test fixture (`local_validate_fixture`) has no `linear_feature_id`; BT only.


## Errors Encountered

| Error | Resolution |
|-------|------------|
