# link 0.6.0

Honour `user_barriers_definite_control.csv` at the observation-override step.

- `lnk_barrier_overrides()` now excludes observations upstream of control-flagged positions from counting toward the override threshold, matching bcfishpass's access SQL. Previously controlled positions (concrete dams, long impassable falls, diversions) could be re-opened by upstream historical observations ([#44](https://github.com/NewGraphEnvironment/link/issues/44)).
- Gated per-species by a new `observation_control_apply` column in `parameters_fresh.csv` — TRUE for CH/CM/CO/PK/SK/ST; FALSE for BT/WCT; NA for CT/DV/RB. Residents routinely inhabit reaches upstream of anadromous-blocking falls (post-glacial headwater connectivity, no ocean-return requirement), so their observations still override. Matches bcfishpass's per-model application.
- Habitat-confirmation override path intentionally bypasses the control table — expert-confirmed habitat is higher-trust than observations, and bcfishpass's `hab_upstr` CTE has no control join either.
- `.lnk_pipeline_prep_overrides` now passes the control table to `lnk_barrier_overrides()` when the config manifest declares `barriers_definite_control`. Manifest key is the contract; no DB probe.
- `.lnk_pipeline_prep_load_aux` now always creates a schema-valid (possibly empty) `barriers_definite_control` table when the manifest declares the key — fixes an asymmetric gating bug that would have raised "relation does not exist" on AOIs with zero control rows.
- End-to-end validation WSG: DEAD (Deadman River) added to `data-raw/_targets.R`. It has a single `barrier_ind = TRUE` control row at FALLS (356361749, 45743) with six anadromous observations upstream and zero habitat coverage — the unique combination that actively exercises the filter. All four prior WSGs (ADMS/BULK/BABL/ELKR) were rescued by either the observation threshold or habitat path, making them parity checks rather than filter tests.

# link 0.5.0

Documentation and narrative for the targets pipeline.

- New vignette: "Reproducing bcfishpass with link + fresh" — three-line entrypoint, rollup interpretation, BULK chinook habitat map (mapgl), reproducibility framing. Data-prep script at `data-raw/vignette_reproducing_bcfishpass.R` generates `inst/extdata/vignette-data/{rollup,bulk_ch}.rds` from a real run; vignette loads the `.rds` so pkgdown builds don't need fwapg access. Follows the CLAUDE.md convention for vignettes that need external resources ([#38](https://github.com/NewGraphEnvironment/link/issues/38))
- Research doc (`research/bcfishpass_comparison.md`) updated with bit-identical rollup numbers from 2026-04-22 and a new "Targets orchestration" section showing how `_targets.R` composes the per-WSG runs.
- `mapgl`, `sf` added to DESCRIPTION Suggests.
- Retired `data-raw/compare_bcfishpass.R` — `data-raw/_targets.R` + `data-raw/compare_bcfishpass_wsg.R` supersede it. Git history preserves the prior form.

# link 0.4.0

Targets-driven comparison pipeline for all four validated watershed groups.

- Add `data-raw/_targets.R` — `tar_map(wsg = c("ADMS", "BULK", "BABL", "ELKR"))` over a per-AOI target function, synchronous execution, `dplyr::bind_rows` rollup. `fresh.streams` is a shared schema so single-host parallelism would collide — runs serially today; distributed runs (M4 + M1) are a follow-up alongside a fresh upstream change for per-AOI output paths ([#38](https://github.com/NewGraphEnvironment/link/issues/38))
- Add `data-raw/compare_bcfishpass_wsg(wsg, config)` — per-AOI target function. Wraps the six `lnk_pipeline_*` phases, diffs the output against `bcfishpass.habitat_linear_*` reference on the tunnel DB, returns a ~10-row tibble (`wsg × species × habitat_type × link_km × bcfishpass_km × diff_pct`). KB-scale — safe to ship over SSH.
- Promote `.lnk_pipeline_classify_species` to an exported `lnk_pipeline_species(cfg, aoi)` — canonical public API for "species this config classifies in this AOI." Used by `lnk_pipeline_classify` and `lnk_pipeline_connect` internally and by the targets per-AOI function externally. Removes the duplicate private helper that was briefly inlined in `data-raw/`.
- End-to-end verification (`data-raw/logs/20260422_11_tar_make_final.txt`) — 4 WSGs / 34 rows produced over 8.5 minutes wall clock (serial). **Reproducibility:** consecutive `tar_make()` invocations on the same DB state produce bit-identical rollup tibbles. **Parity to bcfishpass (informational):** all 34 `diff_pct` values within 5% of reference; research-doc drift (BT rearing: -0.7 → -1.1 pp) traces to env state between 2026-04-15 and today, not to pipeline non-determinism.

# link 0.3.0

Pipeline phase helpers extract the bcfishpass comparison orchestration into composable building blocks. The 635-line `data-raw/compare_bcfishpass.R` is now 136 lines of sequenced helper calls.

- Add `lnk_pipeline_setup()` — create the per-run working schema ([#38](https://github.com/NewGraphEnvironment/link/issues/38))
- Add `lnk_pipeline_load()` — load crossings and apply modelled-fix and PSCIS overrides
- Add `lnk_pipeline_prepare()` — load falls / definite / control / habitat CSVs, detect gradient barriers, compute per-species barrier skip list, reduce to minimal set via `fresh::frs_barriers_minimal()`, load base segments
- Add `lnk_pipeline_break()` — sequential `frs_break_apply` over observations / gradient / definite / habitat / crossings in config-defined order
- Add `lnk_pipeline_classify()` — assemble access-gating breaks table and run `fresh::frs_habitat_classify()`
- Add `lnk_pipeline_connect()` — per-species rearing-spawning clustering and connected-waterbody rules
- Canonical signature `(conn, aoi, cfg, schema)` — `aoi` follows fresh convention (WSG code today; extends to ltree / sf polygons / mapsheets later), `schema` is the caller's per-run namespace (`working_<aoi>` by convention) so parallel runs do not collide
- `cfg$species` parsed from the rules YAML at `lnk_config()` load — intersects with `cfg$wsg_species` presence to pick per-AOI classify targets
- Requires fresh 0.14.0 (for `frs_barriers_minimal`)

# link 0.2.0

Config bundles for pipeline variants.

- Add `lnk_config(name_or_path)` — load a config bundle (rules YAML, dimensions CSV, parameters_fresh, overrides, pipeline knobs) as one list object. Bundles live at `inst/extdata/configs/<name>/` with a `config.yaml` manifest, or any directory containing `config.yaml` for custom variants ([#37](https://github.com/NewGraphEnvironment/link/issues/37))
- Relocate bcfishpass config files into `inst/extdata/configs/bcfishpass/` (rules.yaml, dimensions.csv, parameters_fresh.csv, overrides/). All R scripts and data-raw/ references updated.

# link 0.0.0.9000

Initial release. Crossing connectivity interpretation layer — scores,
overrides, and prioritizes crossings for fish passage using configurable
severity thresholds and multi-source data integration.
