# Progress

## Session 2026-04-24 — #51 kickoff

- fresh#164 merged + tagged v0.16.0 (wetland_rearing column).
- Branched `51-configs-default-compound-rollup` off link main.
- M1 synced: fresh 0.16.0 installed, link main up to date.
- Initialized PWF.
- Next: Phase 1 scaffolding — DESCRIPTION bump + `inst/extdata/configs/default/` bundle assembly.
- Phase 1 shipped (commit `9cc30fc`) — `inst/extdata/configs/default/` bundle + fresh pin (>= 0.16.0) + PWF init. `lnk_config("default")` loads cleanly.
- Comms — closed (not really) then reopened by rtj-claude with explicit asks. Ran `habitat-classify-test` baselines: M4 4m45s, M1 4m20s. Logs + README rows committed to rtj main (`b0345c5`). Thread closed (`3465ec2`).
- Caveat on those baselines — versions didn't match (M4 fresh 0.14.0 vs M1 fresh 0.16.0; M1 link 0.1.0 vs M4 link 0.7.0). Need rebaseline with version-matched envs.
- rtj driver patch (`d83cbb5`) — install workloads now use `upgrade = FALSE, ask = FALSE` (caught pak trying to tail-upgrade Rcpp to a CRAN Transit release that doesn't exist).
- Phase 2 shipped (commit `7ddbac7`) — compound rollup in `compare_bcfishpass_wsg.R`. 4 rows per species (spawning/rearing in km, lake_rearing/wetland_rearing in ha). Option b-amended on bcfishpass side — same methodology joining `habitat_linear_<sp>` + `fwa_*_poly`. Smoke-tested link-side against DEAD: sensible nonzero values.
- Phase 3 shipped (commit `7f0ff9c`) — `_targets.R` runs both configs side-by-side, unified rollup with `config` identity column.
- Phase 4 doc scaffold (commit `b534318`) — `research/default_vs_bcfishpass.md` with methodology + departures + TBD tables.
- Compare fn gate-on-existence fix (commit `0d49bf5`) — species without `habitat_linear_<sp>` (e.g. RB in bcfishpass) now return zeros on the reference side rather than erroring.
- Full 10-target `tar_make()` on M1: rollup pulled to M4 at `/tmp/rollup_51.rds`, 204 rows, digest `4a04a6e6932262d779e6f0aba7e19723`.
- Phase 4 tables populated — `research/default_vs_bcfishpass.md` now carries numeric results for all 5 WSGs with observations section.
- Four key findings captured in research doc: (1) `lake_rearing_ha` / `wetland_rearing_ha` identical across configs — fresh classifier ignores dimensions.csv `rear_lake` / `rear_wetland` flags (gap to file); (2) km inflation under default driven by intermittent + river-polygon + spawn-gradient departures; (3) SK spawning inflates massively because `spawn_connected` rule not yet in default bundle (blocked on fresh#133); (4) RB newly modeled under default across all WSGs.
- fresh follow-up filed as [fresh#165](https://github.com/NewGraphEnvironment/fresh/issues/165) for the classifier gap on `rear_lake` / `rear_wetland` flags.
- PR #54 opened targeting main.
- User feedback: address SK `spawn_connected` distortion in this PR, not defer. Investigation found fresh#133 already merged (2026-04-12) — the bug was entirely in `configs/default/dimensions.csv`: missing 5 columns (`rear_stream_order_bypass`, `spawn_connected_direction`, `spawn_connected_gradient_max`, `spawn_connected_cw_min`, `spawn_connected_edge_types`) that `lnk_rules_build()` needs to emit the `spawn_connected:` YAML block. Without `direction: downstream`, fresh applies the 3km connected-distance filter in any direction.
- Fix committed (`c215b1f`) — added the 5 columns to the CSV, populated SK + KO with matching bcfishpass values, regenerated `rules.yaml`. First M1 rerun (19m52s) showed SK spawning numbers unchanged — spawn_connected YAML block alone wasn't the driver.
- Root-caused further: `spawn_lake=yes` in default for SK/KO was emitting a `waterbody_type: L` spawn rule. Lake centerlines (Babine 177 km) were counting as SK spawning habitat within the 3 km connected-distance cap. Real bug.
- Fix committed (`a65942a`) — `spawn_lake=no` for SK + KO in default, regenerated rules.yaml. Matches bcfishpass convention (stream-spawning sockeye only).
- Second M1 rerun (19m14s) confirms: SK spawning deltas shrink from 10-20× to order-of-magnitude-reasonable — ADMS +4.45 km, BULK +17.9 km, BABL +93.3 km, DEAD +0 km. Residual lift explained by intermittent + river-polygon departures.
- Workflow-hygiene lessons codified: `link/CLAUDE.md` gained a "Config change workflow" section (commit `9e45858`); soul r-packages convention updated to "bump version as final branch commit" (soul commit `78cb772`).
- Research doc per-WSG tables + observation #3 refreshed with post-fix numbers.
- Next: commit research doc refresh + progress update, verify final state, close PR.
