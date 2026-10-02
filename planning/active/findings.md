# Findings — Thread fresh params_method (per-WSG cw/mad) through lnk_pipeline_classify (#286)

## Issue context

**If done:** link configs can put watershed groups on bcfishpass's discharge (`mad`) habitat model and have it take effect. **If never:** every link run classifies on channel width, whatever a config's `parameters_habitat_method.csv` says. Nothing breaks either way, since the fresh default is the bundled all-`cw` table.

fresh v0.35.0 (NewGraphEnvironment/fresh#220, PR #224) added `params_method` to `frs_habitat_classify()` and `frs_habitat()`: a data frame with `watershed_group_code` and `model` (`cw` or `mad`). `lnk_pipeline_classify()` calls `frs_habitat_classify()` by name without it (`R/lnk_pipeline_classify.R:95`). The config's method CSV needs to be loaded (`lnk_config()`?) and passed through.

Under `mad`, fresh follows bcfishpass in three ways. Species with no MAD thresholds get no stream habitat from inheriting rules. Rule-level `channel_width` (the river-polygon bypass) is ignored. SK/KO lake rearing is based on polygon membership. fresh does not implement bcfishpass's `stream_order >= 8` spawning bypass, which is worth knowing when comparing against bcfishpass for `mad` groups.

### Comment (2026-10-01)

Literature input for the `cw` vs `mad` choice: we reviewed 17 Pacific Northwest intrinsic-potential models
(Oregon, Washington, California, Alaska and BC; Sheer et al. 2009 Table A1 and later work) for how each one
sized streams.

- **None thresholds on gauged flow.** Wherever mean annual flow is used (Burnett 2007, Agrawal 2005, Lindley
  2006 and others), it is a regression of gauge flows on drainage area and mean annual precipitation.
- **Five models threshold directly on modelled channel width.** Cooney & Holzer 2006, for example, regress
  field widths on drainage area and precipitation.
- **The exception is BC's own MAD.** Rebellato et al. 2024 use a hydrologic model where modelled MAD exists,
  and modelled width as the discharge surrogate everywhere else.

So outside existing MAD coverage, building MAD by regression would repeat the width model's inputs. The open
question is whether the process-based MAD carries information width does not, for example in snowmelt- and
glacier-fed basins. That is measurable: compare `cw` and `mad` classification where both exist.

Thresholds in both currencies, with verbatim quotes, are in NewGraphEnvironment/knowledge#30 (`research/ip_models.md`).


## Phase 1 — fresh pin (2026-10-01)

- Installed fresh before this branch read `0.34.0`, a dev install, yet already had
  `params_method`. That is a version string that is not the release: the reason the
  preflight guard asserts the formal, not the version. Now `fresh 0.36.2` (`github`,
  `v0.36.2`, `e3a37f0`).
- `lnk_preflight_fresh()` gains `required_formals`, default
  `list(frs_habitat_classify = "params_method")`. Stubbing
  `.lnk_fresh_missing_formals` to return nothing turns 3 tests red, so the guard fires.
- **fresh 0.36.0 `frs_db_conn()` order flip does bite here.** Inside R on this machine
  both `PG*` and `PG_*_SHARE` are set, with the same host but a different port and
  database. So a bare `fresh::frs_db_conn()` in `data-raw/wsg_vignette_data.R:204` would
  have moved from the tunnel to the local fwapg. It is swapped to `lnk_db_conn()`, which
  still reads `PG_*_SHARE` first. `lnk_db_conn()`'s roxygen claimed to work "identically
  to `frs_db_conn()`", which is now false, so that is corrected too.

## Phase 2 — method table (2026-10-01)

- `smnorris/bcfishpass@f8db4b9` `parameters/example_newgraph/parameters_habitat_method.csv`
  (last touched `1fae4ea`) has **188 groups, all `cw`**, unquoted. fresh's
  `inst/extdata/parameters_habitat_method.csv` has the same rows, quoted, **minus PINE
  (187)**. That makes no difference to the output, since fresh treats a group its table
  does not list as `cw`. All four base bundles carry the bcfp copy, which is
  byte-identical across them: `sha256:9802bb71…`.
- The checksum and shape_checksum come from `.lnk_shape_fingerprint()`, and
  `lnk_config_verify()` reports no drift on all five bundles. `audit_configs.R` reports
  "No findings".
- **`config_hash` changes for every shipped bundle** (new declared file). For a custom
  bundle with no method file it changes too, because fresh's copy is now hashed. Mutation
  check: dropping the fallback digest turns `test-lnk_log.R:1234` red.

## Phase 3 — classify (2026-10-01)

- `.frs_run_connectivity` is not method-aware: it clusters on gradient and adjacency.
  `lnk_pipeline_connect` is unchanged.
- `method_csv` is read with `colClasses = "character", na.strings = character(0)`, so a
  group coded `NA` stays a code, which read.csv's default would not do.

## Plan review + code-check round 2 triage (2026-10-01)

Plan review: `planning/active/review-plan.md`. Round 2: `review-p23-round2.md`. **Both
independently found B1**, which was the one real bug.

| finding | disposition |
|---|---|
| B1 csv-sync would auto-merge the method CSV | **fixed.** Source is now `link (frozen copy; not csv-synced…)`, with `derived_from: smnorris/bcfishpass@1fae4ea …` and `upstream_sha` = the last commit touching the file. Test: `test-lnk_config.R` "the method table is frozen". |
| G1 stale mad docs | **fixed.** Four `*_mad_*` rows in the thresholds dictionary (with fresh `utils.R:334-340` refs), the RUNBOOK §7 bullet, CLAUDE.md, and all five bundle READMEs. |
| G2 discharge not fingerprinted | **fixed.** Added to `.lnk_input_primitives()` (`rep(fwapg, 8L)`). The "seven FWA tables" wording in the vintage doc and test now says "the FWA tables". The DB-gated existence test ran (SKIP 0) and finds it. |
| G3 stream-order bypass under mad | **fixed.** Skipped when the AOI's model is `mad`. Tests cover the cw/mad pair. |
| G4 connect reason | recorded precisely in RUNBOOK. No code change. |
| G5 join / persist-shape tests | **added** (`test-lnk_pipeline_prepare.R`). |
| G6 cross-package contract | **added** (`test-dictionaries.R`). |
| G7 audit section | **scoped out.** `test-dictionaries.R` already checks domain, duplicates and missing codes per bundle, plus the fresh header contract, and it runs in CI where `data-raw/audit_configs.R` does not. |
| G8 follow-up draft | updated (persist has no `mad_m3s`). The stale v0.33.0 rationale was fixed in Phase 1. |
| O1 isolate column + fresh bump | **done.** A0/A/A_nocol/B/B2 (Phase 4). |
| O2 thin bundle → `fresh` schema | avoided. The mad runs pass `method_csv` on scratch schemas; nothing persists. |
| O3 Phase 1 boxes | already flipped in `bd2f8ff`; the review read a pre-commit tree. |
| O4 cypher re-prep | in RUNBOOK and the PR body / NEWS draft. |
| A3 `loaded` vs path | documented in the `method_csv` roxygen. |
| AC1–AC3 invariants | `mad_check.R`: classify only, overlay off, stream vs waterbody split. |
| AC4 verify loop | **added** (`test-lnk_config.R`). |

## Follow-up issue draft (NOT filed — needs body review)

**Title:** `lnk_habitat_validate()` scores `mad` watershed groups as if they were `cw`

> **If done:** observation validation reports the right miss reasons for groups a bundle
> puts on discharge. **If never:** a `mad` group's "missed for width" counts are computed
> against channel width the classification never used. Nothing is affected until a
> bundle actually sets a group to `mad`, and none does today.
>
> Since #286, `lnk_pipeline_classify()` passes the bundle's
> `parameters_habitat_method.csv` to fresh, and a `mad` group classifies on `mad_m3s`.
> `lnk_habitat_validate()` still builds its predicates with
> `fresh::frs_habitat_predicates(spp)`, which is the cw model
> (`R/lnk_habitat_validate.R:823`). It then relaxes width by rewriting `s.channel_width`
> (`.lnk_hv_relax()`, `:772-786`), with minimums taken from
> `ranges$<stage>$channel_width` (`.lnk_hv_stage_min()`, `:763`). On a `mad` group:
> - the predicate is not the one that classified the segment, so `pred_*` can disagree
>   with the persisted `spawning`/`rearing`;
> - width relaxation rewrites a column the mad predicate does not reference;
> - `width_null` (`.lnk_hv_miss_reason()`) tests `channel_width`, where it should test
>   `mad_m3s`. The persist does not carry `mad_m3s` (decided in #286), so the validator
>   would join it from `whse_basemapping.fwa_stream_networks_discharge` on
>   `linear_feature_id`.
> - The stream-order rearing bypass is skipped for `mad` groups (#286), so a miss
>   reason must not credit it there.
>
> fresh >= 0.35.0 has `frs_habitat_predicates(model = "mad")`. Resolve each scored
> group's model from the bundle's method table, build the predicates per model, and relax
> `s.mad_m3s` for mad groups. `test-lnk_habitat_validate.R` "the predicate call stays on
> the channel-width model" pins today's behaviour and should change with it.

## Errors Encountered

| Error | Resolution |
|-------|------------|
