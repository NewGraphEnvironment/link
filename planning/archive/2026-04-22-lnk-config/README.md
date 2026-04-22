# Archive: lnk_config (closed 2026-04-22)

## Outcome

Config bundle abstraction shipped in link 0.2.0 — PR #39 merged as `59e363a`. `lnk_config(name_or_path)` loads a directory-bundle (rules YAML, dimensions CSV, parameters_fresh, overrides, pipeline knobs) with manifest validation; bcfishpass variant relocated to `inst/extdata/configs/bcfishpass/`; compare script switched to the loader.

Code-check caught one real bug — `.lnk_config_resolve_dir` originally gave `dir.exists()` priority, so `lnk_config("bcfishpass")` from a CWD with a local `bcfishpass/` folder silently shadowed the bundled config. Fix: require `/` in input to treat as path. Regression test added.

## Closed via

- #37 → closed by PR #39

## What superseded it

- New PWF cycle 2026-04-22 for `_targets.R` pipeline (link#38)
- `configs/default/` variant deferred — real biological departures live in #19, #20, #21
