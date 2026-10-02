# Code-check round 3: #300 diff (build + score, incl. uncommitted)

Reviewer: subagent, read-only. Read: `git diff main -- data-raw research`, the current
data-raw/habitat_variants_build.R and data-raw/habitat_variants_score.R in full,
R/lnk_habitat_validate_band.R, data-raw/habitat_score/README.md, variants_300.csv,
wsg_roles_300.csv, research/habitat_thresholds.md "`cw` against `mad`", rounds 1 and 2, and the
checklist's "One fact derived twice" mechanism. R probe in the scratchpad only. DB: read-only psql on
localhost:5432 fwapg; neither script was run.

## The mechanism behind rounds 1's three findings

One quantity is built by **two producers whose coverage the code assumed to coincide**, so it
checked or guarded only the side it happened to iterate:

- the band function's pooled rows (`mp`) against the per-segment split (`mseg`): the check walked
  `mp`'s band rows and took the core on trust;
- the `cw` half and the `mad` half of a reading: their power state was assumed shared;
- a found count (from `mp`) divided by an expected count (from `ms`): their zero sets were assumed
  to coincide (`Inf`).

## Every place it reaches in the new code, checked

1. `mp` against `tot` (reconciliation). Every `mseg` key is a key of `mb` (same variant,
   species, flag, stage and role match), and each `mp` row checks its band class and the core,
   so every `tot` (key, class) is compared and an `mp` row with no `mseg` rows compares against
   0. Both directions, core included. Clean.
2. `merge(mp, mv)`. A band missing from `eb` is filled with expected 0. Given (1), that happens
   only when its band km is 0. Clean.
3. `n_band / expected`. Guarded on `expected > 0`. An expected of 0 or NA (a zero or absent core
   rate) reads "underpowered" through `decide()`, never as a ratio. Clean.
4. `ratio_to_core` in `model_size.csv`. Guarded. Clean.
5. `reading_of()`. Each half is decided on its own. A variant × flag with no held-out rows (KO)
   gets no reading. Clean.
6. `n_absence_band`: `b` and `ab` are aligned by row position. Both come from the same call with
   the same aoi, species and flag, sorted the same way. Clean.
7. Rate groups. `order_groups()` cuts on the core `n`, and the group rate uses that same group's
   core km. I traced the examples by hand: `c(12,3,11,2)` gives `1`, `2-4+`; `c(5,5,0,0)` gives
   `1-4+`; `c(10,0,0,10)` gives `1`, `2-4+`. All match the pre-registered rule, as do the `-`
   label and `km_merged_rate`. Clean.
8. `unknown` pricing: its own rate at core n ≥ 10, otherwise the role's pooled core rate. The
   pooled rate includes `unknown`, so with a single ordered group the size-adjusted ratio is not
   exactly the pooled ratio. In scored data this is immaterial: order 0/NULL is 1 segment, 0 km,
   per WSG at most (score302_default, all 20 WSGs). No action.
9. The thresholds behind `reason` (`thr_base`) are the base's. A model-only bundle is asserted to
   differ from them in 0 cells, so they are also the variant's. Open maxima (9999), and a NULL
   bound under the SQL's three-valued OR, classify correctly. The discharge join is 1:1:
   `fwa_stream_networks_discharge` has 2,716,652 rows and as many distinct `linear_feature_id`.
   It is also the table and key the validator uses.
10. Observations: `mseg` and the band function filter the same species, WSG and stage
    population (`%in% TRUE`). Any divergence fails the reconciliation loudly.
11. KO rearing. Round 1 wrote that it is all FALSE; it is not. Under cw, KOTL holds 639 TRUE
    segments and PARS 43, all on waterbody edges (lake rules, `thresholds: false`). They are the
    same under both models, so they are core, the bands are 0 and `d` is not empty. That breaks
    nothing, and KO is in-sample only.
12. Build: `model_only` (empty `sets`), `write_bundle()` with zero cells, the method table over
    every role WSG of the species, `--step=bundles` (respects `--only`, no schema write), and
    the base selected by `step_from` together with the `equals_bundle == --base` stop. Score: the
    `built.csv` sha, the method-model and 0-cell checks for model-only bundles, the access digest
    and the observation identity. All consistent.
13. UHC stop: `default_tuned` has no `user_habitat_classification` rows for BT, GR, KO or RB, so
    it cannot block #300.
14. Early `quit()`: every object `write_stamp()` reads is defined before it, `model_*.csv` is in
    the unlink list, and `min(character(0))` in the stamp warns rather than errors.

## Clean
No issues found.
