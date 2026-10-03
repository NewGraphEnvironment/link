# Code-check round 2: #300 diff (build + score, incl. uncommitted)

Reviewer: subagent, read-only. Read in full: cc_diff2.patch, data-raw/habitat_variants_build.R,
data-raw/habitat_variants_score.R, R/lnk_habitat_validate_band.R, data-raw/habitat_score/README.md,
variants.csv, variants_302.csv, variants_300.csv, wsg_roles_300.csv, research/habitat_thresholds.md
"`cw` against `mad`", review-round1.md, and `.lnk_hv_discharge_tbl()` in R/lnk_habitat_validate.R.
R probes ran in the scratchpad only. DB: read-only psql on localhost:5432 fwapg; neither script was run.

## Clean

No issues found.

## What was checked

### Round-1 fixes

- **Reconciliation (fix 1).** It now iterates over `mp` rows and sums `tot` for both the band class
  and `core`. A missing per-segment class sums to 0 and stops on any `mp` row with km or n, so the
  check fires in both directions. `mp` repeats `core_km` / `n_core` on its added and removed rows, and
  each sums the WSG core once, so comparing against `tot` class `core` is correct. Every WSG x
  direction always has an `mp` row, because the band function merges onto `aoi`. So no `tot` key can
  exist without an `mp` row. The band function counts observation rows (`count(*)`), and so does
  `table(paste(...))`. `id_segment` is int4 in streams, so the paste key cannot pick up `1e+05`
  formatting.
- **reading_of (fix 2).** It names the decided half and returns "open" only when both halves are
  underpowered. It is called only when exactly one cw-only and one mad-only of-record row exist.
- **ratio_to_core (fix 3).** It is guarded against 0 and NA.

### Plan-review fixes

- **order_groups().** Probed on 8 vectors and matches the rule: walk up from order 1, start a new
  group once the running core reaches 10, merge a short last group into the one before, and make one
  group when the total is under 10. Group labels are unique, so the rates per label are correct.
- **Pricing.** `expected` = Σ class band km × `core_per_100km_used` / 100, with the rate per role,
  stage and flag. `n_expected_pooled` = `density_core` (per km, from `.lnk_hvb_density`) × `band_km`.
  The units agree.
- **Unknown order.** Order 0 or NULL goes to `unknown`. It takes its own rate when its core n is at
  least 10, and the pooled core rate otherwise. In score302_default only 3 segments (0 km) have
  order 0 and none are NULL, so the small difference between the merged-group rate and the pooled
  rate (which includes unknown) cannot move a number.
- **model_reason.** `fwa_stream_networks_discharge` is unique on `linear_feature_id` (2,716,652 rows,
  all distinct), so the LEFT JOIN cannot fan out. A fan-out would also trip the reconciliation. The
  persisted streams carry `linear_feature_id`, `channel_width` and `stream_order`. The threshold
  columns exist in default_tuned. An NA bound (KO `rear_mad_*`) binds as NULL, and the OR/CASE
  logic degrades it to an in-range reading, which is reported only.
- **No focal WSG.** The validation loop skips the variant. The obs-retention check then compares
  `character(0)` with `character(0)`. The built check passes on an empty `w_v`. The stamp's
  `min(character(0))` returns NA with a warning, not an error.
- **Pooling** comes from `base_bundle` through `hv_pooling`.
- **Model-only validation** runs in both scripts. One small asymmetry: a whitespace-only `set`
  passes the build and stops the score. It fails loud, so it is not reported as a finding.
- **The UHC stop.** `default` holds no BT, GR, RB or KO rows, so it will not fire falsely.

### Rule fidelity (research doc, "`cw` against `mad`")

- **Bands.** schema = variant (mad) and schema_ref = base (cw), so `added` = mad-only and
  `removed` = cw-only. This matches `mb_dir` and the per-segment CASE. The core is base ∩ variant.
- **Record.** `of_record` is `held_out` and stage `any`, for both flags. KO is in-sample only and
  never reaches the record rows.
- **Decision.** Underpowered when expected < 10, habitat when found / expected ≥ 0.5. The pooled
  (#302) reading and the found floor are written beside it.
- **model_verdict columns.** `km_merged_rate` and `km_pooled_rate` report how much band km rests on
  merged or pooled pricing.

### #284 / #302 regression

- **Base row.** In `variants.csv` and `variants_302.csv` the single row with an empty `step_from` is
  `default`. It has an empty `column`, `model` cw (or absent), and `equals_bundle = default`, which
  equals the `--base` default. So both new guards pass with no flag.
- **Same rows as before.** `steps_from[variant != base]` selects the same rows as the old
  `[!is.na(column)]`. `steps`, the set-ladder check, `ladder_of`, `tips` and `value_of` still key on
  `!is.na(column)`. `model_only` is empty, so its local() blocks are no-ops on a zero-row frame. The
  early `quit()` cannot fire.
- **Bundle text.** For `base_bundle = "default"`, the build's provenance `source` string and
  description reduce to the exact pre-change text. #284 and #302 bundles therefore re-write byte for
  byte. The score's `thr_now` and `thr_default` read the same file as before.
- **write_stamp().** In both scripts it is defined after every object it reads. In the score,
  `stages` stays at top level, ahead of both of its uses.
