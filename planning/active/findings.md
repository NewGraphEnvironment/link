# Findings — #367

## Issue context

**If done:** the next provincial `default` run (#361) is built at a release whose output is reproducible run to run and whose Columbia groups see the US dams below them. **If never:** that run ships with both known gaps, and the next run that fixes either has to re-model every group again.

## Scope

One branch, released as v0.68.0 before the run is dispatched. Cyphers reset to `origin`, and every log row stamps the link version, so this has to be tagged first.

1. **#277: make the PSCIS-to-modelled-crossing pick deterministic.** When two modelled candidates share a `linear_feature_id`, the pick ties (`R/lnk_pipeline_pscis_build.R`), so two identical builds can differ by a segment. That happened on 8 lines across the four parity-scored groups at v0.66.6 (#362). Fix: end the ordering on a unique key. Test: build the tie and assert one answer.
2. **#244: `cabd_additions` dams become barriers.** The `usa` CTE in `.lnk_pipeline_prep_dams()` hardcodes `passability_status_code` NULL, and `.lnk_crossings_union()` has no arm for it, so Grand Coulee, Chief Joseph and Ross are dropped. Dams never block access, so this moves mapping codes (the `DAM` token in Columbia groups), not accessible km.
   - `lnk_wsg_downstream_check()` applies the same filter and documents that the placeholders "never appear" (`R/lnk_wsg_downstream_check.R:176-178`). Decide whether the guard should now report them for Columbia groups, and keep the two in step.
   - Re-pin the golden dams test while it is open (#345: 8 ADMS dams pinned, 7 in `cabd.dams`).

## Measured and left out: #316

Construction lines (1200 / 1400) inside wetlands reach no rear rule in `default`. Since #364, 1050 / 1150 lines there rear through the stream door, so the question was whether admitting 1200 / 1400 the same way would matter. Measured on `fresh_default` (run `20261017_004619-3f4c713b`, 241 groups; lines matched to `fwa_wetlands_poly` by `waterbody_key`):

| edge type | km in wetlands | km with a channel width | km passing BT's stream test (width ≥ 1.5 m, gradient ≤ 0.1049) | of which BT-accessible |
|---|---|---|---|---|
| 1200 | 10,294 | 320 | 173 | 92 |
| 1400 | 5,190 | 190 | 155 | 64 |

97 % of these lines have no width, so they would fail the stream door anyway. At most 156 km province-wide would become BT rearing. They stay out of this run; the measurement is recorded on #316.

## Verification

- Prepare once and re-classify (CLAUDE.md, "Full-run digests are not reproducible on main") on ADMS, one Columbia group (SLOC or KOTL) and NATR, reporting the change in mapping codes and rearing km per species.
- Two builds of the same group from the same inputs give identical digests (#277).
- Release bar: `devtools::test()`, `devtools::check()`, `lintr::lint_package()`.

## Not in scope

#326 (breaks only where access changes), #327 (order-1 exception in `default`) and fresh#258 (break tolerance) stay out of this run.

Relates to #361, #277, #244, #316, #345, #364.


## Errors Encountered

| Error | Resolution |
|-------|------------|
