# Task Plan: configs/default/ + compound rollup (#51)

## Goal

Ship a runnable NGE default habitat-classification config bundle, distinct from the bcfishpass reference. Prove the config-swap architecture works end-to-end, surface per-WSG comparison numbers between default + bcfishpass, produce research visuals and rollup tables. Prerequisite fresh PR (#164) shipped as fresh 0.16.0 — `wetland_rearing` boolean column now in `streams_habitat` output.

Resolved design decisions (from comms thread discussion):
- Option B rollup: separate columns for `rearing_km`, `lake_rearing_ha`, `wetland_rearing_ha`. No multiplier.
- New `wetland_rearing` column on `streams_habitat` (shipped in fresh 0.16.0).
- Species lake-rearing list is already in `inst/extdata/parameters_habitat_dimensions.csv`.
- Polygon-area aggregation uses existing `frs_aggregate()` — no fresh extension needed.

## Phase 1: config bundle scaffolding

- [ ] `DESCRIPTION` — pin `fresh (>= 0.16.0)` under Imports.
- [ ] `inst/extdata/configs/default/config.yaml` — manifest mirroring the bcfishpass variant's shape, pointing at the default-specific CSVs and shared override mirror.
- [ ] `inst/extdata/configs/default/dimensions.csv` — copy of existing `inst/extdata/parameters_habitat_dimensions.csv` (already encodes the newgraph deltas: rear_lake=yes, rear_wetland=yes, river_skip_cw_min=yes for BT, etc.).
- [ ] `inst/extdata/configs/default/parameters_fresh.csv` — start as copy of bcfishpass variant; annotate deltas if any emerge during testing.
- [ ] `inst/extdata/configs/default/rules.yaml` — generate via `lnk_rules_build()` from the default dimensions.csv.
- [ ] `inst/extdata/configs/default/overrides/` — either symlink or copy the bcfishpass mirror (shared physical barriers / modelled fixes / PSCIS overrides are jurisdiction data, not method choice).
- [ ] Verify: `lnk_config("default")` loads cleanly; fields match bcfishpass variant shape.

## Phase 2: compound rollup

- [ ] `lnk_aggregate()` extended to produce the three-column rollup — `rearing_km` (stream segments), `lake_rearing_ha`, `wetland_rearing_ha`. Polygon-area calls use `frs_aggregate()` with `fwa_lakes_poly` + `fwa_wetlands_poly` as feature tables.
- [ ] Decide whether to exclude lake/wetland centerline segments from `rearing_km` (to avoid double-counting once area is in its own column). Research doc captures the decision and rationale.
- [ ] Update `compare_bcfishpass_wsg()` to return the compound rollup — bcfishpass comparison is per-column, not single `diff_pct`.

## Phase 3: targets pipeline

- [ ] `data-raw/_targets.R` — extend with `comparison_default_<wsg>` targets mirroring the bcfishpass ones, using `lnk_config("default")`.
- [ ] Rollup target gains bundle identity — either long format (`config`, `wsg`, `species`, `habitat_type`, ...) or per-config rollup with a suffix.
- [ ] Bit-identical reproducibility across consecutive runs per config.

## Phase 4: research doc + artifacts

- [ ] `research/default_vs_bcfishpass.md` — per-WSG per-species per-column comparison, biological rationale paragraph per departure.
- [ ] Visuals for the research doc: per-WSG pivot of rearing_km / lake_rearing_ha / wetland_rearing_ha, highlighted where default > bcfishpass vs default < bcfishpass.
- [ ] Vignette updates — `reproducing-bcfishpass.Rmd` might need a sibling or a note pointing at default config once shipped.

## Phase 5: ship

- [ ] NEWS entry for 0.8.0.
- [ ] DESCRIPTION bump 0.7.0 → 0.8.0.
- [ ] `/code-check` on staged diff.
- [ ] PR with SRED tag.

## Dispatch strategy

Run heavy work on M1 (targets, local_install, vignette regen) so M4 stays free for interactive work. Always sync M1 (`git pull` + `pak::local_install()`) before dispatching.

## Versions at start

- fresh: 0.16.0 (just shipped)
- link: 0.7.0 → 0.8.0 target
- bcfishpass: ea3c5d8 (reference config)
