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

## Errors Encountered

| Error | Resolution |
|-------|------------|
