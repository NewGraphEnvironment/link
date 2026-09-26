# Review round 5 — `*_outside_uhc` counts (commit 9a4c191)

Scope: `.lnk_hv_summary()` new counts/shares, driver `make_totals()` and `diff.csv`.
Tests from a copy (fixture schema renamed `zz_lnk_validate_r5`):
`NOT_CRAN=true devtools::test(filter="habitat_validate")` -> FAIL 0 | PASS 86.

## Checked and consistent (no finding)

- **Pairs with existing counts.** `n_obs_outside_uhc_spawn = n_obs - n_in_uhc_spawn` and
  `_rear` likewise, by construction: the same `d` (stage-subset, unattached rows already
  dropped at `d <- d[!un, ]`) feeds all of them. `in_uhc_*` are SQL `EXISTS`, so never NULL;
  `spawning` / `rearing_any` are NA only on unattached rows, which are removed first.
- **UHC semantics.** `in_uhc_*` tests indicator `= 1` on species + `blue_line_key`, which is
  what `fresh::frs_habitat_overlay()` forces (`lower(trim(k.<hab>::text)) IN ('true','t','1')`,
  keyed on `blue_line_key`, `SET spawning/rearing = TRUE`). Forced `rearing` is inside
  `rearing_any`, so pairing `rearing_any` with `in_uhc_rear` is right.
- **Zero-row groups.** `sum(!logical(0))` is `0L`; the share `ifelse(0 > 0, ..)` gives `NA`,
  matching the `share()` convention for `n_obs == 0`.
- **make_totals.** The new `n_*` columns match `^n_` so they are summed; they are never NA, so
  the all-NA branch cannot misfire; shares are recomputed from summed counts, not averaged.
- **diff.csv across bundles.** Both bundles load byte-identical
  `overrides/user_habitat_classification.csv` (cmp), so the outside-UHC denominators are the
  same observation set on both sides; with `bcfishpass` at `apply_habitat_overlay: no` the
  delta is a like-for-like comparison on the non-overlay population, as intended.

## Finding 1 (real, moderate): at `buffer_m > 0` the outside-UHC share still includes overlay-forced capture

`in_uhc_*` tests the **point** (`a.m BETWEEN u.drm AND u.urm`), but at `buffer_m > 0`
`.lnk_hv_buffered()` also credits habitat on any segment starting in `[a.seg_drm, a.m + buf)`.
An observation just **below** a UHC reach is therefore counted as outside UHC, yet is captured
by the overlay-forced segment inside the reach. The doc added in this commit says the share is
"the part of the score the observations did not decide" — at buffer 100 that is not true.

Size (read-only probe on docker fwapg, bcfishobs A/B, province-wide, not yet filtered to
presence or modelled WSGs): CH locations inside a UHC spawning reach 1764; CH locations
**outside** one but with a UHC spawning reach starting < 100 m upstream on the same
`blue_line_key`: **52**. Rearing: 22 inside, 2 below. BT: no UHC rows. So up to ~52 CH
locations per the full run can move into `n_spawning_outside_uhc` at buffer 100 by
construction — only in the overlay-on bundle, so it also lands in
`share_spawning_outside_uhc_delta` in diff.csv as an apparent model difference.

Same mechanism, smaller, at buffer 0: the attach rule picks a segment **starting within 1 m
upstream** of the point, so a point < 1 m below a UHC start (both are break points) attaches
to a forced segment while `a.m` tests outside.

Fix options: (a) test the reach against the range capture actually reads, e.g.
`u.upstream_route_measure >= a.m AND u.downstream_route_measure <= greatest(a.m, a.seg_drm) + <buf>`
(strict `<` for `buf > 0` to mirror `.lnk_hv_buffered`), accepting that `n_in_uhc_*` then
varies with `buffer_m`; or (b) keep the point test and state in the roxygen that the
outside-UHC share is exact only at `buffer_m = 0`.

Nothing else found.
