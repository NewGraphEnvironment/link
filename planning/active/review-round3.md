# Code-check round 3 — #305 discharge fill (staged diff)

## Mechanism

The fill state is never read back from the data it describes. Every consumer
re-derives "was this line filled" from inputs (the `discharge_fill` knob, the
method table, the rules, a group set), and the R1/R2 defects were places where
two consumers re-derived it from different inputs: the validator and prepare
each held their own copy of the decision (R1, then R2's prepare half), and the
fill SQL and the build's `count(mad_m3s) == 0` guard each held their own idea of
"this group has discharge" (R2 coverage). `.lnk_discharge_fill_applied()` now
centralises the per-group decision, but its "something reads discharge here"
half is still a second list: a YAML text grep (`.lnk_hv_rules_read_mad()`)
standing in for what fresh's compiled predicates actually read (which
`.lnk_hv_predicates()` tests separately, on the compiled SQL,
`\bs\.mad_m3s\b`). The two agree today only because no rules file carries a
`mad` key at all.

## Where the mechanism reaches (each checked)

| place | inputs | group set | verdict |
|---|---|---|---|
| prepare (`.lnk_pipeline_prep_network`) | cfg, aoi | one WSG (prep_network quotes a single aoi) | OK |
| run log `discharge_fill` | same cfg, same aoi, same call | one WSG | OK |
| validator `.lnk_hv_check_log` | cfg passed to validate | per WSG | OK; NULL/absent column read as off, matches pre-#305 builds |
| validator `.lnk_hv_discharge_src` | cfg passed to validate | **any over aoi** | see finding 1 |
| validator `.lnk_hv_obs` | disch | mad groups only (cw nulled) | OK |
| validator `.lnk_hv_predicates` | disch | groups whose compiled exprs read `s.mad_m3s` | see finding 1 |
| build `run_variant` refill + `record_built` | same `cfgs[[v]]` object, same w | per WSG | OK; base refill uses cfg_base = the base step's cfg, so the base digest check holds |
| build `count(mad_m3s)` guard | after refill | per WSG | OK (uncovered groups stay unfilled) |
| score knob from built.csv | built.csv's recorded applied state | per variant (must be uniform) | OK; mixed is unreachable via the method table because the `m_w == model_of(v)` check already refuses a mixed table, and reachable only for a genuinely mixed build, where stopping is right |
| score model_reason `.lnk_discharge_sql(w_sp, ...)` | reconstructed cfg | any over w_sp | OK; w_sp == w_v, all on mad |
| score validator calls | reconstructed cfg | as above; variant schemas' `log` is empty (verified: `score300_bt_mad.log` 0 rows), so only the base schema is log-checked | OK |
| #300 re-score | no built.csv column -> FALSE; base log has no column -> NULL -> off | | agree |
| `discharge_fill_count.R` "covered" | `count(mad_m3s) > 0` per group | | same predicate as the SQL's `cov` |
| `query_habitat_thresholds_mad.R` | raw table | | reads raw by design (threshold producer); not a fill consumer |
| fill-off path | `.lnk_discharge_sql(fill = FALSE)` | | same values and type (`double precision`, linear_feature_id unique in the table: 2,716,652 = 2,716,652 distinct) as `frs_col_join`; persist projects explicit `cols_streams`, so the extra `mad_m3s_source` working column does not reach outputs |
| `lnk_pipeline_classify()` called on a working schema prepared under another cfg | reads whatever fill prepare wrote | | the only in-repo caller doing this (the build) refills first; standalone classify does not check the fill against its cfg (same class as the documented `method_csv =` invisibility); noted, not a finding |

The scoped tests (`test-lnk_discharge.R`, `test-lnk_habitat_validate.R`,
`test-lnk_pipeline_prepare.R`) pass on a copy of the staged tree with
`NOT_CRAN=true`.

## Findings

- **[severity: fragile]** `R/lnk_habitat_validate.R:291` (`.lnk_hv_discharge_src(..., fill = .lnk_discharge_fill_applied(cfg, aoi))`) together with `R/lnk_habitat_validate.R` `.lnk_hv_rules_read_mad()` and `R/lnk_discharge.R` `.lnk_discharge_fill_applied()`.
  The validator decides the fill **any-over-aoi** and materialises it for every
  line of every aoi group, while prepare decided **per WSG**. On a `cw` group in
  a mixed aoi these agree only if `.lnk_hv_rules_read_mad()` (a regex
  `^[[:space:]-]*mad[[:space:]]*:` over the YAML text) says the same thing as
  the compiled predicate that `.lnk_hv_predicates()` tests
  (`\bs\.mad_m3s\b`). They can disagree. Probed on a copy of the tree: a rules
  file whose BT spawn river rule is written in flow style,
  `- {waterbody_type: R, mad: [0.5, 9999]}`, gives
  `.lnk_hv_rules_read_mad()` FALSE, `fresh::frs_params()` parses
  `mad = c(0.5, 9999)`, the compiled cw exprs read `s.mad_m3s` (TRUE), and
  `.lnk_discharge_fill_applied(cfg, "ADMS")` is FALSE. A quoted key (`"mad":`)
  is missed the same way. Then, with `discharge_fill: true` and an aoi holding
  one `mad` group B and one `cw` group A:
  - prepare for A does not fill, so classify reads raw discharge on A's main stems;
  - the validator's `disch` is filled (B is `mad`, so any-over-aoi is TRUE), and
    `.lnk_hv_predicates()` joins it for A's cw combos because the compiled exprs
    read `s.mad_m3s`. A's predicates are re-run on filled values that classify
    never saw.
  - `.lnk_hv_check_log()` cannot catch this, because logged and wanted are both
    FALSE for A.

  The result is miss reasons and `pred_*` columns that disagree with the
  persisted habitat for no visible reason. The generated `rules.yaml` is block
  style and carries no `mad` today, so this is latent rather than live. Either
  of two changes removes the dependence:
  - scope the validator's fill per WSG: fill only the lines of groups where
    `.lnk_discharge_fill_applied(cfg, w)` holds, and give the rest the raw
    value;
  - derive "a rule reads discharge" from `fresh::frs_params()` (any rule with
    a non-NULL `mad`) rather than from the text.

  The second also stops the knob being silently skipped for a `cw` group
  under such a rule.

/Users/airvine/Projects/repo/link/planning/active/review-round3.md
