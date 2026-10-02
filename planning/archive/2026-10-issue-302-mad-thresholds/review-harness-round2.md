# Review: variants harness for MAD ladders (#302), round 2

Scope: the working-tree diff of `data-raw/habitat_variants_build.R`,
`data-raw/habitat_variants_score.R`, `data-raw/habitat_score/README.md` and
`data-raw/query_habitat_thresholds_fiss.R`, with round 1's fixes reviewed in particular.
Reviewed by reading. Read-only DB probes only; neither build nor score was run.

## The mechanism

Round 1's two bugs came from code that assumed a ladder is a nested, one-direction,
single-cell chain walked out from `default`. That cw base also cuts the core on every axis it
tests. The #302 fixes moved the anchor out of the walk and the band labels, but the
**cw base is still a member of every MAD ladder's core** (`ladder_of()` always prepends
`base_variant`). The cw base tests axes the mad rungs do not test: channel width, NULL width,
and any cell a rung's `set` changes. So the core is cut on those axes and the bands are not.
Findings 1 and 2 are this mechanism. Finding 3 is the "single-cell chain" assumption, which
is still unasserted.

## Findings

- **[severity: fragile, could bias verdicts]** `data-raw/habitat_variants_score.R:423-426, 448`
  (`ladder_of()` → `schema_core`), and the README claim "a band's verdict is about discharge
  alone":
  - The core of a MAD ladder is cw base ∩ every rung. Under `mad`, fresh drops the width test
    (`frs_habitat_predicates.R:110`, `size_col <- "mad_m3s"`), and a cw rule fails a NULL
    `channel_width` (BETWEEN with NULL).
  - So the core also carries the cw base's `*_channel_width_min` floor and excludes NULL-width
    segments. A post-anchor band (P05 & !P10) carries neither cut.
  - The band therefore differs from the core on width as well as on discharge. That is
    round 1's finding 2 one axis over: gradient was fixed by policy, width cannot be.
  - Sized with a read-only probe on `fresh_default.streams` joined to
    `fwa_stream_networks_discharge` (PARS, KOTL, MORR and BULK; gradient <= 0.1049), as the
    share of km with mad >= X that the cw width test drops:

    | mad >= X | narrow (< 1.5 m) | NULL width | wide | share dropped |
    |---|---|---|---|---|
    | 0.05 | 75 km | 176 km | 4,859 km | ~5 % |
    | 0.02 | 379 km | 717 km | 5,490 km | ~17 % |

  - The low-discharge bands are where the narrow and NULL-width segments sit, so the band
    holds a stream class the core has none of. The bias is probably small at P10, but its
    direction is unknown.
  - Remedy: for a ladder past its anchor, take the core from the mad rungs only (that is
    #284's "the habitat no step moves"; the plan's reason to add a reference was the
    *no-range* base, which is not in the ladder). Or keep the cw base in the core and write
    the km it removes from the mad-rung intersection beside the verdict. Either way, correct
    the README sentence.

- **[severity: fragile]** `data-raw/habitat_score/README.md` "The rungs carry `default`'s
  gradient cutoffs"; `habitat_variants_score.R:115-128, 252-262`. Round 1's finding 2 was
  fixed only by documentation.
  - Nothing stops a MAD rung's `set` from carrying a cell the cw base also tests, such as
    `rear_gradient_max=0.1349` (the plan's original shape) or a `*_channel_width_*` cell.
  - The score checks that such a cell holds its value and stays fixed along the ladder, then
    scores the band against a core cut at default's value. That is the round-1 bias, and it
    passes silently.
  - Cheap guard (build and score): a `mad` variant's `set` may name only `*_mad_*` columns,
    which the cw base never reads.

- **[severity: fragile]** `habitat_variants_score.R:410-422` (`value_of`, `loosens`,
  `direction`), with no check anywhere that a ladder is a single-cell chain.
  - Neither script asserts that a non-base step has the same `species_code`, `column`, `flag`
    and `obs_stage` as its `step_from`. Today the chain is walked by `step_from`, while the
    core, taper and elevation group by `species_code` × `column`.
  - Before #302, a step whose column differs from its step_from's got `value_from` = default's
    (non-NA) value, so the output was wrong but visible.
  - On a MAD column, default's value is NA. So `loosens` is NA and `direction` is
    `ifelse(FALSE | NA, ...)` = NA.
  - `aggregate()` then drops that step's rows from `bands_pooled.csv` (NA in `step_direction`,
    a key). It has no verdict row, `walk()` gets `dec` NA and reports
    "underpowered at <step> - the step 1-4 verdict stands" instead of stopping.
  - Mixed `obs_stage` in one ladder also makes the taper count every location
    (`identical(st, "spawn")` is FALSE for a length-2 `st`, line 661).
  - Guard: for every step whose `step_from` is not the base, assert those four fields equal
    the step_from's, beside the set-fixed check at 117-128. Also assert `!anyNA(steps$direction)`.

- **[severity: fragile]** `habitat_variants_build.R:85` `--working-prefix` defaults to
  `working_score_`. That is #284's prefix whatever `--prefix` is.
  - Round 1's finding 6 is fixed only if the operator remembers a second flag.
  - `--prefix=score302_` without `--working-prefix` rebuilds BULL, CLRH, ELKR, LILL, REVL and
    UARL into #284's `working_score_*`. #284 then cannot be extended without a fresh base (a
    later digest or segmentation check stops it, so the loss is not silent).
  - Guard: stop when `--prefix` is not `score284_` and `--working-prefix` is the default, or
    derive the default from `--prefix`.

- **[severity: fragile, low]** `habitat_variants_score.R:253-256`: the per-cell `set` check
  compares `as.numeric()` of both sides. A non-numeric cell (`*_edge_types`) is NA on both
  sides, so `all.equal(NA, NA)` passes whatever value the bundle holds. Only `n_diff` then
  guards it. Compare as strings, or numerically only for numeric columns.

- **[severity: fragile, low]** `data-raw/query_habitat_thresholds_fiss.R:44`: `--out` still
  defaults to #284's committed `data-raw/logs/habitat_thresholds_284/`. A #302 run with
  `--species=BT,GR,KO,RB` and no `--out` overwrites #284's `fiss_presence.csv` (the CH rows go)
  and its stamp. Also, a default re-run adds the `segment mad_m3s` rows to #284's file, so a
  byte-identity claim against HEAD's outputs can hold only for the pre-existing rows.

## Checked against an anchor + `_min` ladder, and fine

- 1 % against-direction stop:
  - Anchors are excluded.
  - For `_min` rungs, `step_direction` is "added" and the clustering leak is P10 & !P05,
    which is correct.
  - It is safe when every step is an anchor (empty `tapply`).
- `bands_pooled` and `rule`:
  - The anchor keeps its "added" row and has both directions in `bands_pooled`.
  - `value_from` is joined back after `aggregate()`, so the #284 output columns are unchanged.
- `chain_to`, `tips` and `walk`:
  - The chain is [anchor, P05, P02]; the anchor is forced to "take".
  - "Refused at P05" gives the anchor's value; "underpowered" gives NA.
  - `stop_at == 1` cannot be reached through the anchor.
  - A one-rung ladder gives "taken through anchor".
- `value_of`: the anchor gives NA from default, and later rungs give their step_from's own
  value.
- `habitat_change`: each variant against the cw base, as documented.
- `bridge_band`:
  - The anchor row is the mad-added half only, consistent with "added".
  - `in_window` is NULL for MAD and anchor steps.
  - `_gradient_min` rearing columns are not read by any code, so the max-only window is
    unreachable for a `_min` ladder.
- `taper`, `elevation` and `elevation_adjusted`:
  - With threshold steps first and the anchor last, every post-anchor band label now matches
    `bands.csv`'s added set, traced segment by segment, cw/P10/P05/P02.
  - Zero-row `anc` and `thr_steps` are handled.
- `obs_key`: `models` only adds a column (`R/lnk_habitat_validate.R:281-307`), and the attach
  key does not depend on the model.
- `species_of`, `aoi_of`, the built-WSG set, `run_variant`'s `wsgs_v`, and the score's
  method-table check agree on focal ∩ role WSGs.
  - The score's hand-rolled "unlisted is cw" matches `.frs_habitat_models` via `.lnk_wsg_model`.
- `record_built`:
  - The method sha is added.
  - A pre-#302 file gains an NA column, and `write.csv` "NA" reads back as NA under
    colClasses character.
- Base digest check:
  - The base always runs first in each variants pass.
  - Classify and connect only touch `streams_habitat` for the given species.
  - Connect never tests width or model.
- Set-fixed check: skips anchors and steps from the base, and is order-insensitive.
- FISS:
  - Name matching is case-insensitive. Probed `species_list` tokens: 'Bull trout' 130,
    'Rainbow trout' 93, 'arctic grayling' 2, all match.
  - There is no Steelhead or Sockeye/Kokanee mixed token.
  - Presence has `gr`, `ko` and `rb` columns, and the names collide with no site or snap column.
  - `mean(x < NA)` gives NA where default has no range, which is honest.
  - `fwa_stream_networks_discharge` has a UNIQUE index on `linear_feature_id` (2,716,652
    rows, all distinct), so the scalar subquery cannot raise. It is the same table and key
    that `lnk_pipeline_prepare.R:697` joins `mad_m3s` from. `fresh.streams` carries
    `linear_feature_id`.
