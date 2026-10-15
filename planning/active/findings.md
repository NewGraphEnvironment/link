# Findings — README: lead with intrinsic habitat potential (#338)

## Issue context

## Problem

The README still describes link at roughly its v0.4x shape: an interpretation layer plus bcfishpass reproduction. The package is at v0.65.0, and its core idea, intrinsic habitat potential per species, is not named anywhere a reader lands.

## Findings

**Missing core framing**
- "Intrinsic habitat potential" is not in the README, the DESCRIPTION or the vignette. It was in DESCRIPTION from NEWS 0.18.1 ("three habitat axes (intrinsic potential, accessibility under connectivity, per-feature rollups)") and came out in 05a18135 (2026-04-29). fresh's vignette `habitat-pipeline.Rmd` uses the phrase in its title.

**Shipped but not in the README (underselling)**
- Habitat scored against fish observations: `lnk_habitat_validate()`, `lnk_habitat_validate_band()` (v0.51.0; #283, #284)
- `lnk_species_pooling()` (#290)
- More than one config bundle (`default`, `default_tuned`), and species bcfishpass does not model, such as Arctic grayling (`pars-habitat-connectivity` vignette)
- Discharge gap-fill (v0.58.0); rearing split into stream, lake and wetland (v0.61.0 to v0.63.0)
- Run provenance, `lnk_artifact_*` (v0.64.0); parquet export with a manifest, `lnk_scenario_export()`, `lnk_catalog()`, `lnk_db_load()` (v0.65.0)
- `lnk_rollup_wsg()`, `lnk_mapping_code()`, `lnk_wsg_resolve()`
- The vignette is not linked from the README

**Ahead of the code (overselling)**
- README line 5, "network-agnostic by design": everything runs on the Freshwater Atlas through fresh today. Describe what runs today.

**Cross-package**
- The ecosystem table (README.md:57-63) omits wet. Discharge comes from fwapg's table through the internal `lnk_discharge()` today; reading it from wet is #331. State the current wiring.
- DESCRIPTION `Remotes:` pins `fresh@v0.39.0`; fresh is at v0.40.0.

## Tasks

- [ ] Open with intrinsic habitat potential per species, access, and the barrier in the way
- [ ] Restore intrinsic potential in DESCRIPTION
- [ ] Add a "what it does" section covering the capabilities above, and link the vignette
- [ ] Replace the network-agnostic claim with what runs today
- [ ] Update the ecosystem table: wet, and the current discharge wiring
- [ ] Group the `_pkgdown.yml` reference index by purpose. It has no `reference:` sections today, so the docs site shows a flat alphabetical list.

## Context

Audited 2026-10-14 against `origin/main` @ `1e84df2`, from README, DESCRIPTION, NEWS, NAMESPACE and vignettes. Verify each item against the code before acting. Versions cited are where a capability landed.

The New Graph website will describe this package from its README (NewGraphEnvironment/newgraphenvironment.github.io#53), so the README is the source of truth for the public one-liner. Plain language in the opening paragraph: what it does today, and what restoration planning, implementation or monitoring decision it informs.


## Errors Encountered

| Error | Resolution |
|-------|------------|
