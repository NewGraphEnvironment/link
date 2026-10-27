# Code review, round 1: branch 326-break-streams-only-where-a-present-speci (#326)

Diff: `/var/folders/.../cc_link/diff.patch` (a34d5357..1b69ad7c, logs and planning excluded).

## Checklist read

- **code-check.md** (330 KB): the prose of all 14 H3s under `## Mechanisms`, table rows skipped. Of the 23 H3s outside Mechanisms (Rules that stand alone, Security, Spreadsheets and PDFs), I read the index lines only, not the bodies. None of them names something this diff uses. The nearest, "Bare `y`/`n` … are booleans in YAML 1.1", does not apply: `dimensions.csv` holds `"yes"` in a CSV, and `lnk_rules_build` emits `true`.
- **code-check-r.md** (178 KB): of 111 headings I read 11 in full, and 100 as index lines only. The 11: "A `data-raw/` script must load the source tree", "testthat counts an uncaught error under `error`", "`$` on a list partial-matches", "A database driver's value is not a base R type", "`identical()` on two reader results", "R's `yaml` returns a mixed int/float sequence as a list", "Postgres row order is never fixed…", "A `function(...)` mock hides arguments…", "`expect_message(regexp = "...$")`…", "`load_all()` refuses an installed dependency below the `Imports:` floor", and "Under `R CMD check`, tests run from a temp dir…" (first part).
- **code-check-spatial.md** (156 KB): of 93 headings I read 2 in full, and 91 as index lines only. The 2: "FWA `upstream_route_measure` misses the next segment's start" and "FWA main flow is not edge type 1000 alone".
- **code-check-shell.md** (125 KB): index only, 67 headings. The diff contains no shell.

## Findings

- **[severity: bug] `inst/extdata/configs/bcfishpass/config.yaml:110-121`. The provenance checksums for `rules.yaml` and `dimensions.csv` were not regenerated after both files changed.**
  - main's checksums (`bcf4096…`, `27ebfa…`) matched main's files. The branch's files now hash to `e9b9ea7…` and `a48aadd…`.
  - `lnk_config_verify(lnk_config("bcfishpass"))` warns "2 file(s) drifted (rules.yaml, dimensions.csv)".
  - `tests/testthat/test-lnk_config.R` fails "every shipped bundle's provenance verifies clean". I ran it in a copy: 1 failed, 161 passed.
  - Every bcfishpass build at this commit would log `config_drift = TRUE` (`lnk_stamp()` → `<schema>.log`).
  - #364 changed the same files and updated `config.yaml` in the same commit (`de3e672e`).
  - Fix: `Rscript data-raw/regen_provenance.R`, then commit the `config.yaml` diff.

- **[severity: fragile] `data-raw/breaks_diff.R:51-73`. The census labels link breaks MINIMAL / NON_MINIMAL from `working_<wsg>.gradient_barriers_minimal`, but both configs share that schema.**
  - `lnk_pipeline_run()` and `wsg_run_one.R` name the working schema `paste0("working_", tolower(aoi))` for every config.
  - So after Phase 4's planned re-models of PCEA / FINA / PARS / LKEL × {`bcfishpass`, `default`}, `--schema=fresh` reads whichever config modelled the group last. If that was `default`, bcfishpass's breaks get labelled against `default`'s reduced set. There is no warning; the output only reads "working minimal read".
  - Guard: before trusting `has_min`, require that the working schema belongs to the persisted build. For example, require `count(*)` of `working_<wsg>.streams` to equal the group's count in `<schema>.streams`, or that their break positions agree. Otherwise fall back to the `has_min = FALSE` path and say so.

- **[severity: fragile] `R/lnk_pipeline_prepare.R:709` against `R/lnk_barriers_views.R:214`. The reduction lifts a barrier only by this group's own `barrier_overrides`; the access view lifts it by any group's persisted rows.**
  - The access view's `NOT EXISTS` has no `watershed_group_code` filter, so a position several groups hold (the shared-line copies of #349) counts as lifted when any group's row matches it.
  - Where another group H lifts a copy of barrier Y and this group G does not, G's `barriers_<sp>_min` keeps Y. Y then prunes a frontier X above it, and X is not broken. In the access view Y is lifted, so X is the real frontier, and the segment straddling X is labelled accessible above X.
  - Two causes produce this:
    - group-filtered controls: `barriers_definite_control` is AOI-filtered, which is the "2 rows today" CLAUDE.md names;
    - H's override rows coming from a build at another bcfishobs vintage (a partial re-model, or `--recompute-only`).
  - Before #326, X always broke, so a disagreement only moved access on the Y–X stretch.
  - The recompute cannot repair this, because it does not re-segment.
  - Low frequency and bounded to one segment per case. It does weaken the claim, in the roxygen and in RUNBOOK §2b, that the reduction is "the same recipe as the access view". The recipe is the same; the lift scope is not.
  - Possible remedies:
    - anti-join the reduction against the union of this group's overrides and the persisted province-wide `barrier_overrides` for the lines `streams_blk` holds;
    - or state it as a known residual next to the 2-row note.

- **[severity: fragile, measured 0 on FINA] `R/lnk_pipeline_classify.R:271`. The claim "Reducing must not move access" holds for `streams_access` but not for classify's own gate.**
  - `.lnk_pipeline_classify_build_breaks` filters the gradient barriers to `s.watershed_group_code = aoi`. `gradient_barriers_raw`, and so `barriers_<sp>`, also holds positions on the parts of shared lines outside the AOI.
  - An out-of-AOI barrier Y can therefore prune an in-AOI frontier X. Classify sees X but not Y, so the segment straddling X is classify-accessible above X.
  - Before #326, X broke there, and only the stretch between Y and X was affected (mechanism B in CLAUDE.md).
  - `lnk_habitat_gate()` settles the flags on `streams_access`, which does see Y. Connectivity steps that run before the gate (cluster / connected rules) read the coarser classify result.
  - Measured on `working_fina` from this branch's pre-flight run: 0 in-AOI positions pruned only by an out-of-AOI barrier (19,799 pruned of 23,678 in-AOI rows). Worth one count on a group that sits on a shared main stem (a Fraser or Peace group) during Phase 4 before calling it negligible.

## Checked and clean (no finding)

- **Species-code case.** `cfg$species` and `parameters_fresh.species_code` are uppercase, and so is `barrier_overrides.species_code` (verified in `working_fina`: BT, CH, CM, CO, PK, SK, ST). `lnk_presence()$present` is lowercase, and `tolower(sp) %in% pres$present` handles that. The literal reaching SQL is `m$code` (`'BT'`).
- **Semantics against `barriers_<sp>_access`.**
  - Natural sources are the same: gradient at classes ≥ amax, which matches unify's `blocks_species` CASE because no bundle has a class ≥ 0.15 outside `.lnk_classes_bcfp`. So are falls and subsurface (inside `n`, so liftable, as in the view).
  - `USER_DEFINITE` is outside the anti-join, as in the view.
  - The anti-join is the same: `abs(…) < 1` against the raw measure.
  - Falls additionally filtered on the FWA segment's group, NULL ltrees and the ~1 mm double-join can only drop positions or duplicate them. Neither can prune a frontier wrongly.
- **Types across the UNION ALL.** `blue_line_key` is integer in every source across all ten working schemas surveyed; R reads falls and definite as `int`. `drm` is cast to double, so it matches `fwa_upstream(integer, double, …)`.
- **Stale tables.**
  - `lnk_pipeline_setup(overwrite = TRUE)` drops the working schema at run start.
  - `frs_barriers_minimal` drops `to` first.
  - The union is built from this run's `minimal_tbls` only.
  - Subsurface gates on `break_order`, not on the table existing.
- **Old against new `rules.yaml`.**
  - Compiled predicates (`frs_habitat_predicates`) are identical for BT, CH, CO, ST and WCT. BT's `- []` became a mapping holding only the passthrough key, and fresh ignores that key in the rule engine.
  - Rebuilding `rules.yaml` to a tempfile matches the committed file byte for byte.
- **`.lnk_order_child_bounds`.** `ranges$rear` is `c(min, max)` numeric (`.frs_build_ranges`), so `[[1]]` and `[[2]]` are right, and a NULL `ranges$rear` falls through to the error. A rule's `channel_width`/`gradient` are validated numeric length-2 by fresh, so a yaml list never reaches link. The bypass is taken from the first carrying rule, which is the stream rule (not the river rule's `[0, 9999]`) for all five species. The bcfishpass thresholds give every one of the five a rear width minimum and gradient maximum.
- **Tests.** The prepare, classify, rules_build, preflight_fresh and dictionaries test files pass in a copy (223 / 44 / 351 / 41 / 99, 0 failures, 0 errors). The `function(...)` mock of `frs_order_child` is backed by the formals guard in `.lnk_fresh_required_formals()`.

## Note on what this review ran

I ran the tests from a copy (`rsync` to the scratchpad) with `NOT_CRAN=true`. `test-lnk_pipeline_prepare.R`'s live tests created and dropped their own scratch schemas in the shared fwapg: `working_usa_dams`, `working_golden_dams` and `zz_lnk_obs_scope_probe`. Those schemas are owned by the tests, not any model run, and none is left behind. My own probe used `zz_review_r1x`, which is dropped. The repo itself was not edited, apart from this file.
