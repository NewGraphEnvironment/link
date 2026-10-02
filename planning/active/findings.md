# Findings — Tune MAD (discharge) thresholds for BT, GR, KO and RB (#302)

## Issue context

**If done:** a `mad` watershed group keeps stream habitat for every modelled species, on
discharge windows set from evidence. **If never:** any group moved to `mad` loses all
stream spawning and rearing for BT, GR, KO and RB by construction. That is not a finding
about the fish. Only waterbody rules (wetlands, lakes, the 1050/1150 edges) keep them.

## Problem

`parameters_habitat_thresholds.csv` carries `spawn_mad_*` for CH, CM, CO, PK, SK, ST and
WCT, and `rear_mad_*` for CH, CO, ST and WCT only (`default`, `default_tuned` and
`bcfishpass` alike). The gap was inherited from bcfishpass `example_newgraph`. Under
the `mad` model, fresh writes `FALSE` in place of the size test for a species with no
range, as bcfishpass does. Since #299, `lnk_habitat_validate()` names a miss the missing
range alone explains `no_mad_threshold`. Misses from the same cause also read
`width_null` (no discharge on the line) or `fails_gradient_and_width` (gradient fails
too), so that label is a floor on the loss, not a count of it. On ADMS on `mad`, 27 BT
locations read it against spawning and 8 more read `fails_gradient_and_width`
(`data-raw/logs/habitat_validate_299/`). The operator's direction (2026-10-02,
#299 plan gate): tune and add the thresholds, rather than leave them missing in the long
run.

## Proposed Solution

- **Measure first.** Use #300's held-out, discharge-covered groups (Peace, Fraser,
  Columbia). Take the distribution of `mad_m3s` at BT / GR / KO / RB observation locations
  by stage (pooled DV per `species_pooling.csv`), alongside accessible availability. This
  is the #284 method with discharge in place of width.
- **Literature and FISS** for each species' discharge range, recorded in
  `research/habitat_thresholds.md` as one verdict per threshold.
- **Land the values in `default_tuned`** (a thin bundle) first, scored out-of-sample with
  `lnk_habitat_validate_band()`. `default` stays untouched until a score supports a move.
- **Score before/after with capture and cost** (`share_*`, `*_km`) and
  `lnk_habitat_validate_band()`, not with `no_mad_threshold`. Once a range exists, the
  label cannot fire, so its "after" is 0 whatever the value.

Depends on #299 and #300. Relates to #284, #286.

## Decisions (operator, 2026-10-02, mid-run after the plan review)

- **Thin spawn cell** (spawn-staged n < 30): fill from the species' any-stage P05 on
  spawn-tested segments, labelled `fallback: any stage`. Reason: BT and GR cluster
  rearing on spawning (`cluster_rearing = TRUE`), so a NA spawn range would also wipe
  their stream rearing under `mad`.
- **n-floor of record:** `decision_expected_floor` (locations expected at the core's
  rate in the band) decides; the found-count reading is reported beside it. A walk that
  only loosens from a tight anchor is where the found-count floor cannot refuse.
- **Underpowered first loosening step:** P05 lands, recorded as unscored (as #284's
  step 1-4 verdict stood). KO, with no held-out group, lands the same way.

## Plan review (Plan agent) — see `review-plan.md`

Key mechanics confirmed by reading fresh 0.36.2:
- `build_wb_pred` (`frs_habitat_predicates.R`) gates lake/wetland rearing with the rear
  size window whenever one exists, under cw too; under `mad` with no rear range it is
  polygon membership alone. So adding `rear_mad_min` makes `mad` mirror `cw` there.
- `frs_params.R`: NA `*_mad_max` becomes `Inf` when `*_mad_min` is set.

## Phase 1 instrument

`data-raw/query_habitat_thresholds_mad.R` replaces "generalise the obs script": the obs
script is CH/BT-specific throughout (presence, sets, UNION of `_ch`/`_bt`, candidates),
while `lnk_habitat_validate()` already attaches pooled, staged observations to segments
and returns `mad_m3s` on a `mad` group. Run with every calibration WSG on `mad`.

Code-check round 1 (`review-round1.md`): the rear stream rule has no
`in_waterbody: false`, so stream edges inside lakes/wetlands are tested unless the
species' own L/W rule admits them — fixed with a per-stage segment class. Moved GR rear
P05 on ADMS+PARS from 2.561 to 2.478 (rule value 2.5 → 2.4).

## Errors Encountered

| Error | Resolution |
|-------|------------|
| Zotero MCP: missing `ZOTERO_LIBRARY_ID` / `ZOTERO_API_KEY` | Literature read from the local Zotero full-text caches (read-only sqlite); MCP env reported to the operator |
| `stats::aggregate()` drops NA group keys (anchor `value_from` is NA) | `value_from` joined back after the aggregate |

## Harness regression (2026-10-02)

The modified `habitat_variants_score.R` (model/set, anchor, `_min` direction,
method sha; before `--floor`) re-scored #284's committed build (`score284_*`, a
scratch copy of `data-raw/logs/habitat_score_284/`). All nine outputs (verdict,
bands, bands_pooled, totals, habitat_change, taper, elevation_adjusted,
bridge_band, summary) equal the committed ones on every shared column; summary
gains only the validator's `model` column (#299).

## Lake / wetland rearing under a rear range (Gap 1, narrowed)

fresh 0.36.2 `frs_habitat_classify.R`: `rearing` is the main rear predicate alone;
`lake_rearing` and `wetland_rearing` are separate columns from `build_wb_pred()`. The
main predicate's L/W rules inherit no thresholds (`.frs_rule_to_sql()`), so a
`rear_mad_min` does **not** cut `rearing` in lakes/wetlands. It gates only the
`lake_rearing` / `wetland_rearing` bucket columns (size AND membership), exactly as a
channel width does under `cw`. Report those columns' km before/after; RUNBOOK §7's
"inherit nothing under either model" is true of `rearing`, not of the bucket columns.

## fresh: `wetland_ha_min` ignored by the rear predicate (code-check round 2)

`.frs_rule_to_sql()` applies `lake_ha_min` (L = lakes + manmade) but not
`wetland_ha_min`; the W rule admits every wetland size into `rearing`. Upstream defect,
not worked around: the driver follows fresh as compiled (it now builds the waterbody
admission from `fresh:::.frs_rule_to_sql()`). Issue drafted for operator review, not
filed.
