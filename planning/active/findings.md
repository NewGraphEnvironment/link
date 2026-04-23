# Findings: Wire barriers_definite_control (#44)

## Where the gap lives

Three places where `"barriers_definite_control"` is referenced in link today:

1. **`R/lnk_pipeline_prepare.R` → `.lnk_pipeline_prep_load_aux`** — loads the per-AOI filtered CSV rows into `<schema>.barriers_definite_control` when `cfg$overrides$barriers_definite_control` is non-NULL. Already correct.
2. **`R/lnk_pipeline_prepare.R` → `.lnk_pipeline_prep_gradient`** — `information_schema` probe for the table, then `DELETE FROM gradient_barriers_raw g USING barriers_definite_control c WHERE ... c.barrier_ind::boolean = false`. Already correct. Removes **passable** positions from gradient set before minimal reduction.
3. **`R/lnk_pipeline_prepare.R` → `.lnk_pipeline_prep_overrides`** — does NOT pass `control` to `lnk_barrier_overrides`. This is the gap. `lnk_barrier_overrides` accepts a `control` parameter but is called without one from this site.

## Latent bug in lnk_barrier_overrides control filter

Read `R/lnk_barrier_overrides.R` lines 140–153. The implementation:

```r
ctrl_where <- sprintf("LEFT JOIN %s c ON b.blue_line_key = c.blue_line_key
  AND abs(b.downstream_route_measure - c.downstream_route_measure) < 1", control)
ctrl_filter <- "AND c.blue_line_key IS NULL"
```

Filter treats ANY control row as blocking override — including `barrier_ind = FALSE` rows. Docstring (lines 27–30) says only `barrier_ind = TRUE` rows block.

In practice on bcfishpass input this is masked because `.lnk_pipeline_prep_gradient`'s upstream DELETE removes `barrier_ind = FALSE` positions from `gradient_barriers_raw` before they reach the override step. But falls and user-definite positions are not pruned by control at load time — they stay in `natural_barriers`. If a control row with `barrier_ind = FALSE` exists for a fall or definite-barrier position, the current filter blocks observation overrides on it. Should not block.

Fix: `"AND (c.blue_line_key IS NULL OR c.barrier_ind::boolean = false)"`.

## Manifest-driven gating decision

`.lnk_pipeline_prep_overrides` could probe `information_schema.tables` to discover whether the control table exists (same pattern used there for habitat). Decided against: the manifest key is the direct contract. If `cfg$overrides$barriers_definite_control` is non-NULL the load step wrote the table; if it's NULL no table exists. Manifest gate, not DB probe.

Scope discipline: the existing `information_schema` probe for the habitat table in the same function, and the similar probe in `.lnk_pipeline_prep_gradient` for the control table, work correctly today. Leaving them alone in this PR; filing a follow-up issue for consistency. Using the manifest as the contract is well preferred across the package.

## Tests that need to exist

- `tests/testthat/test-lnk_barrier_overrides.R` does not exist. Creating new.
- `tests/testthat/test-lnk_pipeline_prepare.R` exists — extending with prep_overrides control pass-through tests.

## No `information_schema` probe in the new code

`.lnk_pipeline_prep_overrides`'s new control guard reads `cfg$overrides$barriers_definite_control` directly. That field is populated by `lnk_config()` when the manifest declares the key. No DB round-trip needed.

## Expected rollup direction

Running the pipeline pre-fix vs post-fix on bcfishpass config:

- WSGs with `user_barriers_definite_control.csv` rows having `barrier_ind = TRUE` and upstream observations at those positions → rollup `link_km` shrinks for affected species (positions that were wrongly overridden are no longer overridden). Moves toward bcfishpass reference.
- WSGs with no such rows → rollup unchanged.

Magnitude: unknown. Control-TRUE rows on the four validated WSGs are uncommon, so likely small. Direction matters more than magnitude.

## Reproducibility

The change is a deterministic additional filter clause on a `LEFT JOIN`. No new randomness, no schedule-dependent behaviour. Two back-to-back `tar_make()` runs must produce bit-identical rollups. Will verify with `digest::digest()`.

## Cross-refs

- Plan file: `/Users/airvine/.claude/plans/stateful-hopping-feather.md`
- Issue: link#44
- Parallel cleanup issue (separate PR): link#45 (gradient classes)
- Follow-up to file at end of this PR: "Migrate remaining pipeline probes to manifest-driven gating"
