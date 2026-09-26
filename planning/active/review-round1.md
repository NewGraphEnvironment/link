# Code-check round 1 — lnk_habitat_validate() (#283)

Reviewer: subagent, 2026-09-26. Diff: `diff_r1.patch` (R/lnk_habitat_validate.R,
tests/testthat/test-lnk_habitat_validate.R). Tests run from a copy of the repo with the
fixture schema renamed (`zz_lnk_validate_rev1`): `[ FAIL 0 | PASS 71 ]`. Live read-only
run: `aoi = c("MORR","BULK")`, `species = c("CH","BT","CO")`, `schema = "fresh_default"`,
cfg `default` (13 s).

Checked and clean: the full-key joins (all three persist tables carry a unique
`(id_segment, watershed_group_code)` index; `fwa_waterbodies.waterbody_key` is unique, so
the waterbody join cannot fan out); the tiebreaks in the attach LATERAL (no two segments share
`(blue_line_key, watershed_group_code, downstream_route_measure)` in `fresh` or
`fresh_default`); the predicate re-evaluation against the pipeline (0 rows with
`rearing_any` TRUE and `pred_rear` FALSE; spawning TRUE with `pred_spawn` FALSE only on
UHC-forced rows); relaxation to the stage minimum (min gradient is 0 and min widths are
2 / 1.5 / 4 / 2.1 for every species in both bundles, so no rule branch rejects the relaxed
value); the Releases filter (every release source starts `Releases Database`); the exclusion
filter matching `.lnk_pipeline_prep_observations`; SQL interpolation (all identifiers and
literals validated or quoted); and the zero-row paths.

## Findings

- **[bug — silently wrong number]** `R/lnk_habitat_validate.R:444-449` (the `in_uhc` EXISTS)
  and `:732` (`n_in_uhc`), against the roxygen at `:61-63`. `in_uhc` is TRUE for any
  `user_habitat_classification` row of the species whose range contains the point. It
  ignores the row's `spawning` / `rearing` indicator values and which habitat type the stage is
  about. `fresh::frs_habitat_overlay()` forces a flag only where that type's indicator is
  `1` (`lower(trim(k.<hab>::text)) IN ('true','t','1')`), and it forces whole segments contained
  in the range, not points. The docs say "with `overlay_applied` TRUE those are captured by
  construction", and `n_in_uhc` sits beside `n_spawning`, `n_rearing` and `n_rearing_any` on
  every stage row, so a reader will subtract it to get out-of-sample capture. For rearing that
  subtraction is almost entirely wrong. The bundled UHC (15,696 rows) has `rearing` NA on
  15,033 rows, and it also carries confirmed non-habitat rows (`-1` / `-4`; 546 rows with no
  `1` in either column). Measured:
  - Live MORR+BULK run: 123 `in_uhc` locations. 122 are spawning-only reaches and 1 is
    rearing-only. BULK CO `stage == "rear"` reports `n_in_uhc = 10`, but only 1 of those 10
    locations is in a reach that forces rearing.
  - Province-wide, A/B records by species: 20,415 fall inside a UHC reach. For 20,149 (98.7%)
    no containing row has `rearing = 1`. For 68, no containing row has a `1` in either column:
    these are confirmed non-habitat, and they are counted as "captured by construction".
  - The fixture's UHC frame has no `spawning` / `rearing` columns, so the tests cannot reach
    this.

  Fix: compute per-type flags (for example `in_uhc_spawn` from `spawning` = 1, and
  `in_uhc_rear` from `rearing` = 1) and count the one that matches each capture column.
  Alternatively, restrict to rows with an indicator of 1 and reword the doc. To match the
  overlay exactly, test the segment range, not the point.

- **[fragile]** `R/lnk_habitat_validate.R:423` (`count(*) OVER () AS n_cand`). Postgres
  `count()` is `bigint`, so RPostgres returns `n_cand` as `bit64::integer64`. That type is
  inconsistent with every other integer column in the returned `observations` frame
  (`id_segment`, `access` and `edge_type` are all `integer`). It computes correctly only while
  bit64's S3 methods are registered. After `saveRDS()`/`readRDS()` in a session that has not
  loaded bit64, the values read as denormal doubles: measured `sum(o$n_cand)` = `6.59e-321`,
  `max()` = `9.88e-324`. `ifelse()`, `c()` with doubles, and most serializers strip or corrupt
  it the same way. Fix: `count(*) OVER ()::int AS n_cand`.

- **[fragile — inconsistent definition under one name]** `R/lnk_habitat_validate.R:660-661`
  and `:697`. `n_absence_rearing` counts
  `h.rearing OR h.lake_rearing OR h.wetland_rearing`, which is the *any*-rearing definition.
  The capture columns it will be compared against name that `rearing_any`, and keep
  `n_rearing` / `share_rearing` for stream rearing (`:442`, `:67-68` of the docs). So a
  false-positive rate built from `n_absence_rearing` and a capture rate built from
  `share_rearing` measure different things with no signal. The same split affects the miss
  reasons: `miss_reason_rear` keys on `rearing_any` (`:632`), so the rear misses in
  `table(miss_reason_rear)` — the `@examples` pairs it with `share_rearing` — do not add up to
  `n_obs - n_rearing`. Lake- and wetland-rearing locations are `NA` (captured) there while
  counting as misses in `share_rearing`. Fix: either name it `n_absence_rearing_any` (and say in
  the Miss reasons section that "captured" means `rearing_any`), or count stream `rearing` there.

- **[minor — mislabel]** `R/lnk_habitat_validate.R:572-578` with `:615`. Gradient is relaxed
  to the stage minimum (0), but 7,122 `fresh_default.streams` segments have
  `gradient < 0`. On those segments `BETWEEN 0 AND max` fails for being *below* the window,
  relaxing to 0 passes, and the miss is reported as `fails_gradient`, the label that is read as
  "the max gradient threshold is binding". Raising that threshold would not capture them.
  Measured: 46 A/B records sit on negative-gradient segments province-wide, all on waterbody
  or non-stream edge types (none in MORR/BULK). The effect is small, but it points the
  calibration evidence (#284) the wrong way. Fix: attribute `gradient < 0` separately, or
  relax to `max(value, min)` only when the value is above the window.
