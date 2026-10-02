# Code-check round 1: #300 diff (build + uncommitted score)

Reviewer: subagent, read-only. Read in full: cc_diff.patch, data-raw/habitat_variants_build.R,
data-raw/habitat_variants_score.R, R/lnk_habitat_validate_band.R, data-raw/habitat_score/README.md,
variants.csv, variants_302.csv, variants_300.csv, wsg_roles_300.csv, and research/habitat_thresholds.md
"`cw` against `mad`". Probes ran in R in the scratchpad only. Nothing was run against the DB.

## Verdict

There are no blocking bugs. The #284 and #302 paths read the same rows as before. Three
findings: two fragile, one where the code departs from the written rule.

### Regression check (#284 / #302): clean

- Base selection moved from `is.na(column)` to `is.na(step_from)`. In `variants.csv` and
  `variants_302.csv` the same single row (`default`) has both fields empty, so `base_variant` is
  unchanged. Both base rows declare `equals_bundle = default`, which matches the `--base` default,
  so the new equals_bundle stop passes with no flag.
- `steps_from <- variants$step_from[variants$variant != base_variant]` selects the same rows as
  the old `[!is.na(column)]` in both files, in both scripts.
- Every other ladder path still keys on `!is.na(variants$column)`: `steps`, the set-ladder check,
  `ladder_of` (`NA %in% column` is FALSE) and `tips`. So model-only rows can never enter a
  ladder.
- No `cfg_default`, `thr_default` or `meth_default` references are left in the build. The score's
  `thr_default` is read from `cfgs[[base_variant]]`, so it is the base.
- `stages` is still defined at top level before both of its uses. `uhc` is re-read in the ladder
  section.
- The early `quit()` fires only when no row has a `column`. For 284 and 302 it never fires.
- `write_stamp()` is defined after every object it reads (`built`, `pool`, `abs_note`,
  `absences`, `floor_of_record`, `head_sha`, `dirty`).

### Rule check (model-only section against the research doc): matches, except finding 2

- The band direction is right. `schema` = the variant (mad) and `schema_ref` = the base (cw), so
  `added` is mad-only and `removed` is cw-only. That matches `mb_dir` and the per-segment CASE.
- The core is base ∩ variant (`schema_core = sch_pair`), the same as the per-segment `core`
  class.
- Expected = Σ over (order class) of band km × the core rate in that class. The core rate is
  pooled per role, so held-out rows use the held-out core. `unknown` is its own class. A class
  with no core km (NA rate) falls back to the role's pooled core rate. `km_pooled_rate` and
  `km_unknown_order` report both cases.
- The record decision is underpowered when expected < 10, habitat when found/expected ≥ 0.5.
  The #302 reading (`density_core * band_km`) and the found floor sit beside it.
- `of_record` is held-out and stage `any`. KO is in-sample only, so it never reaches the record
  rows.
- No `user_habitat_classification` rows exist for BT, GR, RB or KO in `default`, so the UHC stop
  will not fire. Its `spawning` and `rearing` columns exist, so the guard is not a NULL no-op.
- `id_segment` is an integer in both the persisted streams and the validator's output, so the
  `paste()` keys in `mseg` cannot drift (no `1e+05` formatting).

## Findings

- **[severity: fragile]** data-raw/habitat_variants_score.R, the "one fact derived twice" check
  (`chk` against `mp`, around diff lines 376-386). It is one-directional, and it does not cover
  the core.
  - It matches `chk` → `mp`. So an `mp` row with `band_km > 0` that has no `chk` row passes the
    check. That would happen if the per-segment query lost a class or a WSG, for example through
    the `if (nrow(d) == 0L) next`.
  - In that case the band's `expected` drops to 0 through `mv$expected[is.na(...)] <- 0` and
    reads "underpowered", with no error.
  - More important, the guard reconciles only the band classes. The per-class **core** km and
    counts, which are the denominator of every size-adjusted decision, are never checked against
    the band function's `core_km` / `n_core`.
  - Both sides use the same definition today, so this is not wrong now. But the check was added
    to guarantee "the size adjustment reads the same rows", and it does not guarantee that for
    the core.
  - Fix:
    - Also check, per `key_s`, that `sum(ms$km[class == "core"])` equals `mp$core_km`, and
      likewise for `n` against `n_core` (`mp` repeats `core_km` on the added and removed rows,
      so take one direction).
    - Check that every `mp` row with `band_km > 0` or `n_band > 0` has a `chk` match.

- **[severity: rule deviation]** data-raw/habitat_variants_score.R `reading_of()` (around diff
  line 421).
  - The research doc says "An underpowered band leaves **its half** of the reading open". The
    code returns `"open"` for the whole variant × flag as soon as either band is underpowered.
  - The doc's power note predicts exactly this for BT and GR: the mad-only band is thin. So the
    `reading` column for BT and GR rearing will say only "open", even when the cw-only half is
    decided (habitat or not).
  - The per-band decisions are still in `decision_size_adjusted`, so no number is wrong. But
    the reading column throws away half of what the rule says to report.
  - Fix: either write the decided half (for example "cw-only habitat; mad-only open"), or change
    the doc sentence to match the code.

- **[severity: fragile]** data-raw/habitat_variants_score.R `ms$ratio_to_core <- ms$per_100km /
  ms$core_per_100km_used` (around diff line 369).
  - When a class's core rate is 0 and the band has locations, this writes `Inf` into
    `model_size.csv`. When both are 0 it gives `NaN`, which `write.csv(na = "")` writes as
    blank. Probed in R: NaN is written as "", Inf as "Inf".
  - The package's own `.lnk_hvb_density()` exists to avoid exactly this ("NA ..., never 0 or
    Inf").
  - It is a diagnostic column and is not used in any decision, but it is the per-class figure
    a reader will quote.
  - Fix: guard it as `ifelse(!is.na(x) & x > 0, per_100km / x, NA_real_)`.

## Checked and not a problem

- Score `hv_pooling(..., pooling_cfg = "default")` is still hard-coded under
  `--base=default_tuned`. `default_tuned` extends `default`, does not override
  `species_pooling` or `wsg_species_presence`, and so resolves identically.
- `.lnk_hvb_check_habitat` on KO rearing: the band function requires habitat rows, not TRUE
  flags, so KO's all-FALSE stream rearing passes. Its per-segment `d` is empty, so it is skipped,
  and the one-directional check tolerates that (see finding 1).
- In the build, `write_bundle()` for a model-only row: the cells are an empty named vector, the
  loop runs zero times, `n_diff == 0 == length(cells)`, and the description takes the
  `length(cells) == 0L` branch. The `equals_bundle` NA skips the md5 check.
- On the score side, a model-only bundle must differ from the base in 0 threshold cells. Its
  method table must put every scored WSG on `mad`, which the build guarantees by writing every
  role WSG for the species.
- `aggregate()` is used on data frames, not formulas, so NA values are not dropped. An empty
  subset would error (no band anywhere), which fails loud.
