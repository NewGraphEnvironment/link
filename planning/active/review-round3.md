# Code-check round 3 (#338): enumeration of published claims

Reviewer: round-3 subagent, 2026-10-14. Branch `338-readme-lead-with-intrinsic-habitat-poten` at `3246ca72`.
Scope: README.md (whole), DESCRIPTION (Title, Description, Authors@R), CITATION.cff, NOTICE.md
(bcfishpass software row), man/link-package.Rd, man/figures/readme-pars.png and its caption,
data-raw/readme_figure.R, .github/workflows/update-citation-cff.yaml. Nothing in the repo was
modified; CITATION.cff was regenerated in a scratch dir.

## Mechanism

Confirmed, with one refinement. Every claim that fails below can be traced to a prose source:
- the CLAUDE.md "Exported Functions" list (`lnk_match`, the `lnk_pipeline_*` helper list);
- the restoration pitch in the issue ("which barrier it is");
- the sync workflow's header, which says "weekly sync" and does not name the bundles it covers.

None was read off the code path that produces the output. The refinement is that the surviving
errors are compositional. Each clause is true of *some* function or *some* member, but the
sentence binds it to the run or quantifies it over the whole set. Examples:
- `lnk_match()` exists and matches by network position, but the run never calls it.
- The weekly sync exists, but it covers two of five bundles.
- Some phases are `lnk_pipeline_*()` calls, but not every phase.
- Access arrays name the barriers in memory, but only booleans persist.

R2's `lnk_aggregate()` finding had the same shape. So the check that ends the loop asks two
things of each sentence:
- **Which code path does the run take?** Not "does a function exist that does this".
- **For a quantifier** ("every", "each", "both"), does it hold for every member? Count them.

## Claims table

| # | file:line | claim (short) | code evidence (file:line) | verdict |
|---|---|---|---|---|
| 1 | README:3, DESCRIPTION Title, CFF:10, Rd:7 | Intrinsic habitat potential and fish passage connectivity for stream networks | habitat from gradient/width/MAD rules (`lnk_rules_build.R`, fresh `frs_habitat_classify`); access `lnk_pipeline_run.R:252-282` | TRUE |
| 2 | README:5, DESC, CFF:13, Rd:11 | Models where habitat could be and whether fish can reach it | `lnk_pipeline_run.R:185-282` (classify, connect, access) | TRUE |
| 3 | README:5, DESC, CFF, Rd | For each species classifies stream, lake and wetland reaches as spawning or rearing **from gradient and channel width or discharge** | Stream rules are gradient + cw/mad. Lake/wetland rules carry `thresholds: false`: polygon type and area only. fresh `R/frs_habitat.R:16-20`: "No channel-width or discharge test applies". README:46 states it correctly. | OVERSTATED |
| 4 | README:5, DESC, CFF, Rd | Resolves which reaches each species can reach past falls and steep gradients | `lnk_barriers_unify.R:20-40` (gradient per species threshold, falls, subsurface, user-definite); `lnk_pipeline_run.R:252-268` | TRUE |
| 5 | README:5, DESC, CFF, Rd | Uses fish observations and habitat confirmations as evidence of passage | `lnk_barrier_overrides.R:1-40` (obs count upstream, UHC bypasses control); views `lnk_barriers_views.R` subtract overrides | TRUE |
| 6 | README:5, DESC, CFF, Rd | **Records the road and rail crossings and dams below each reach** | Per segment, persisted `streams_access` holds booleans only: `has_barriers_{anthropogenic,pscis,dams,remediations}_dnstr`, `dam_dnstr_ind`, `remediated_dnstr_ind` (`lnk_persist_init.R:46-54,78-87`). The ID arrays "stay in-memory ... not persisted". Only crossings with `barrier_status IN ('BARRIER','POTENTIAL')` count (`lnk_barriers_unify.R:200`). It records *whether* a barrier crossing or dam of each kind lies below, not *which*. | OVERSTATED |
| 7 | README:5 | Result shows where a human-made barrier stands between fish and habitat they could reach | mapping_code token2 MODELLED/ASSESSED/DAM on accessible reaches (`lnk_pipeline_mapping_code.R:197-210,276`) | TRUE |
| 8 | README:5 | **"...and which barrier it is"** | No per-segment barrier identity is persisted or exported. `streams_access` is booleans (as #6). The export schema `inst/extdata/schemas/habitat_fwa_v1_segment.yaml:118` carries one `has_barriers_dnstr`, and mapping_code carries a type token. The output gives the barrier's kind, never its identity. | FALSE |
| 9 | README:5, DESC, Rd | Runs on the BC Freshwater Atlas through fresh | `whse_basemapping.fwa_*` reads (`lnk_pipeline_prepare.R:343+`); fresh imports | TRUE |
| 10 | README:7, DESC, CFF, Rd | Experimental; APIs change without notice | status | TRUE |
| 11 | README:9 alt | Reaches coloured by GR spawning, rearing, access, and barrier type below | `readme_figure.R:26-36,66`; PNG inspected | TRUE |
| 12 | README:11 | Grayling in PARS, from link's `default` config | gpkg GR token from `fresh_default.streams_mapping_code` (`wsg_vignette_data.R:153-171`), the default bundle. Note: the build is from 2026-07-04 (`679729e9`), before #307/#310/#311, and the caption says "cached data". | TRUE |
| 13 | README:11 | Every reach drains to Williston Reservoir behind W.A.C. Bennett Dam | geography; data: 0 km of any `;NONE` token among 4,368 classified km (every accessible reach has an anthropogenic barrier below) | TRUE |
| 14 | README:11 | So most carry "dam below" (purple) | gpkg: `*;DAM` 2,717.6 of 4,368.3 classified km (62 %); gq `#ae7dd6` is purple | TRUE |
| 15 | README:11 | Orange and red sit above a road or rail crossing modelled or assessed as a barrier | GR uses the resident flavour (`lnk_pipeline_run.R:299-300`). MODELLED/ASSESSED only when the next anthropogenic barrier is not a dam (`lnk_pipeline_mapping_code.R:198-203`). Anthropogenic = PSCIS/CABD/modelled with BARRIER/POTENTIAL. Colours `#ff9f85`/`#ef4545`. | TRUE |
| 16 | README:11 | Habitat grayling could reach but for that crossing | As #15. GR is resident above the dam, so the next barrier is the crossing. | TRUE |
| 17 | README:11 | Grey reaches lie above a natural barrier to grayling | Grey = GR token empty (`readme_figure.R:27,62`). Empty is emitted only when `has_barriers_gr_dnstr` is TRUE or NA (`lnk_pipeline_mapping_code.R:234-236,281`). The access set is natural + user-definite (`lnk_pipeline_run.R:256-260`). 2 of 227 user-definite rows are "Spillway". | TRUE |
| 18 | README:11 | Made by `data-raw/readme_figure.R` from the vignette's cached data | `readme_figure.R:14` reads `inst/vignette-data/pars.gpkg` | TRUE |
| 19 | README:16 | Install with `pak::pak("NewGraphEnvironment/link")` | public repo | TRUE |
| 20 | README:21 | Reads and writes a PostgreSQL with the FWA through fwapg | `lnk_pipeline_persist.R`; `whse_basemapping.*` | TRUE |
| 21 | README:21 | Same setup fresh uses; fresh's `docker/` for a local one | `~/Projects/repo/fresh/docker/{docker-compose.yml,load.sh}` exist | TRUE |
| 22 | README:21 | A run reads PSCIS assessments, CABD dams, modelled crossings, fish observations from that DB | `lnk_pipeline_crossings.R:80` (`whse_fish.pscis_assessment_svw`); `lnk_pipeline_prepare.R:792` (`cabd.dams`); `lnk_crossings_union.R:57` (`fresh.modelled_stream_crossings`); `lnk_pipeline_prepare.R:101` (`bcfishobs.observations`) | TRUE |
| 23 | README:21 | `snapshot_bcfp.sh` loads them | `data-raw/snapshot_bcfp.sh:9-14,194-302` | TRUE |
| 24 | README:21 | `lnk_db_conn()` reads `PG_*_SHARE`, falls back to `PG*` | `lnk_db_conn.R:39-48` | TRUE |
| 25 | README:23 | Model downstream groups first; access and barrier codes read what is persisted for groups below | `lnk_pipeline_run.R:229-250` (pre-persist, then views over persist barriers) | TRUE |
| 26 | README:23 | `lnk_wsg_downstream_check()` checks the dams below a group are in place | `lnk_wsg_downstream_check.R:284-301` (blocking dams on the downstream path, each persisted) | TRUE |
| 27 | README:27 | Example models one WSG under `default`, reads back accessible, spawning and rearing km per species | `lnk_rollup_wsg.R:117-127` default metrics `accessible_km, spawning_km, rearing_km, rearing_lake_connection_km` | TRUE |
| 28 | README:27 | Not run here: needs the database | — | TRUE |
| 29 | README:33-35 | `lnk_config("default")`; `cfg$pipeline$schema <-` sets where results persist; `lnk_load_overrides(cfg)` | `utils.R:163` (`.lnk_table_names` reads `cfg$pipeline$schema`); default YAML `schema: fresh` (config.yaml:80); same pattern as `wsg_run_one.R:46-47` | TRUE |
| 30 | README:37-41 | Call signatures `lnk_pipeline_run(conn, aoi, cfg, loaded, mapping_code)` and `lnk_rollup_wsg(conn, aoi, species, schema)` | `lnk_pipeline_run.R:117-127`; `lnk_rollup_wsg.R:116-128` (species `^[A-Za-z]+$`) | TRUE |
| 31 | README:46 | Spawning/rearing rules come from gradient, cw or MAD, and lake/wetland size | `default/dimensions.csv` (`rear_lake_ha_min`, `rear_wetland_ha_min`); thresholds CSV; method CSV | TRUE |
| 32 | README:46 | Rearing reported in km separately for stream/lake/wetland, and lake/wetland by area | `lnk_compare_rollup.R:222-286` (`rearing_{stream,lake,wetland}_km`, `lake_rearing_ha`, `wetland_rearing_ha`); `lnk_rollup_wsg` `waterbody` alias | TRUE |
| 33 | README:46 | In `default`, lake/wetland counts towards that area only where same species spawns on or near it (SK/KO excepted) | `default/dimensions.csv`: `rear_{lake,wetland}_connected_distance_max = 10000` for every lake/wetland-rearing species except SK, KO. fresh `frs_habitat.R:1299-1312,26-35` filters the bucket only. | TRUE |
| 34 | README:46 | For groups modelled on discharge, `default_tuned` fills discharge gaps on main stems of large rivers | `default_tuned/config.yaml` `discharge_fill: true`; `lnk_discharge.R:203-208` (only `mad` groups or rule-level `mad:`; default rules have none); fill on edge 1250 lines | TRUE |
| 35 | README:46 | `lnk_pipeline_run()` runs the whole sequence for a WSG | `lnk_pipeline_run.R:170-327` | TRUE |
| 36 | README:46 | **Each phase is its own `lnk_pipeline_*()` call, so a run can be stopped, inspected and resumed** | Phases 9-10b are `lnk_persist_init`, `lnk_barriers_unify`, `lnk_barriers_views` and `lnk_mapping_code`, not `lnk_pipeline_*` (`lnk_pipeline_run.R:211-312`). The run log is opened only inside `lnk_pipeline_run` by private `.lnk_log_*` (`:152-168`), so a hand-stepped run records no provenance. `lnk_pipeline_run` has no resume: it always starts at setup with `overwrite = TRUE` (`:175`). Only `cleanup_working = FALSE` keeps the working schema to inspect. | OVERSTATED |
| 37 | README:48 | Access resolved per species from natural barriers | `lnk_pipeline_run.R:252-264`; `lnk_barriers_views.R` per-species access views | TRUE |
| 38 | README:48 | A barrier blocks only the species it should; 15 % stops salmon and grayling, not bull trout | `default/parameters_fresh.csv`: CH/CM/CO/PK/SK/GR/KO 0.15, BT 0.25; gradient blocks species with `access_gradient_max <= class/100` (`lnk_barriers_unify.R:27-29`) | TRUE |
| 39 | README:48 | Observations and habitat confirmations upstream lift a natural barrier (`lnk_barrier_overrides()`) | `lnk_barrier_overrides.R:1-40` | TRUE |
| 40 | README:48 | Road/rail crossings and dams recorded against every reach above them, as modelled, assessed, remediated barriers or a dam | per-source arrays for every AOI segment (`lnk_pipeline_access.R:172-197,250-257`); tokens `lnk_pipeline_mapping_code.R:197-210` | TRUE |
| 41 | README:48 | So a map shows where human-made barriers cut fish off from habitat | mapping_code + gq symbology (figure, vignette) | TRUE |
| 42 | README:48 | **Crossings from different inventories are matched by network position (`lnk_match()`)** | `lnk_match()` has no caller in `R/` or `data-raw/` (grep). The run matches PSCIS to modelled crossings in `.lnk_pipeline_pscis_build` (`lnk_pipeline_pscis_build.R:1-31`): a multi-stream spatial snap, candidates on the same blk within 100 m, picked by name and width score then planar weighted distance, with xref CSV overrides. `lnk_match()` itself does match on blk + measure (`lnk_match.R:1-5`), but the sentence places it in the run's connectivity model. R2's `lnk_aggregate` finding had the same shape. | OVERSTATED |
| 43 | README:48 | **`lnk_mapping_code()` gives every segment a code for its habitat and the barrier below it** | Token2 (barrier below) is emitted only for accessible segments. An unreachable segment gets `""`, or an orphan `SPAWN`/`REAR` (`lnk_pipeline_mapping_code.R:262-286`; 0.2 km NA and 0.0 km bare `REAR` in the PARS gpkg). | OVERSTATED |
| 44 | README:48 | Ready to style in QGIS | gq `streams_salmon` registry keyed on the tokens; `data-raw/build_species_views.R` | TRUE |
| 45 | README:50 | Thresholds, rules, species and observation-evidence pooling are CSVs in a bundle, each with a data dictionary | `parameters_habitat_thresholds.csv` + `dictionary_parameters_habitat_thresholds.csv`; `dimensions.csv` (→ rules.yaml, → `cfg$species`, `lnk_config.R:117`) + `dictionary_dimensions.csv`; `species_pooling.csv`/`species_groups.csv` + dictionaries | TRUE |
| 46 | README:50 | `default` holds link's biological defaults; `default_tuned` values being calibrated against observations | `default/config.yaml:2-14`; `default_tuned/config.yaml:2-16` | TRUE |
| 47 | README:50 | Both model RB, KO, GR alongside salmon, steelhead, BT, WCT | `default/rules.yaml` species: BT CH CM CO PK SK ST WCT KO RB GR; `default_tuned` `extends: default` | TRUE |
| 48 | README:50 | Most method changes are a reviewed row edit | config-as-data; `parameters_habitat_method.csv` provenance "reviewed edit" | TRUE |
| 49 | README:52 | `lnk_habitat_validate()`: share of observations on accessible/spawning/rearing, km cost, why each miss | `lnk_habitat_validate.R:1-11` | TRUE |
| 50 | README:52 | `lnk_habitat_validate_band()` scores a threshold change on the reaches it moves | `lnk_habitat_validate_band.R:1-15` | TRUE |
| 51 | README:52 | `lnk_species_pooling()` resolves observation-to-model species, region by region | `lnk_species_pooling.R:1-20` (region/subregion/wsg scopes) | TRUE |
| 52 | README:54 | Each run records inputs, parameters and source versions in log tables beside its results | `lnk_log.R:12-14,388-408,502-508` (log_input `artifact_*`, log_parameters_*); `log = TRUE` default | TRUE |
| 53 | README:54 | `lnk_log_read()`, `lnk_artifact_record()` | NAMESPACE exports; `lnk_log.R:589`, `lnk_artifact.R:204` | TRUE |
| 54 | README:54 | `lnk_scenario_export()` writes per config and species Parquet + manifest | `lnk_scenario_export.R:1-7` | TRUE |
| 55 | README:54 | `lnk_catalog()` reads it; `lnk_db_load()` loads into another database | `lnk_catalog.R:1-15`; `lnk_db_load.R:1-15` | TRUE |
| 56 | README:58 | Reference lists every exported function, grouped by name | `_pkgdown.yml` has no `reference:` (auto index) | TRUE |
| 57 | README:59 | Vignette: a full run for one WSG, maps for both species, comparison with the reference model | `vignettes/pars-habitat-connectivity.Rmd:2,210-238,277+` | TRUE |
| 58 | README:65 | link: intrinsic habitat potential and connectivity, per species | as #1 | TRUE |
| 59 | README:66 | fresh: segment, classify, cluster, aggregate | fresh DESCRIPTION; `frs_break_apply`, `frs_habitat_classify`, `frs_aggregate` | TRUE |
| 60 | README:67 | wet: stream flow and water temperature for the FWA | wet DESCRIPTION Title | TRUE |
| 61 | README:68 | crate: canonical schemas and validation for input data | crate DESCRIPTION; `lnk_load_overrides` → `crate::crt_ingest` | TRUE |
| 62 | README:69 | gq: shared symbology, used for the habitat and access codes | `readme_figure.R:21-22`; vignette:277-278 | TRUE |
| 63 | README:71 | Discharge comes from fwapg's modelled table today | `lnk_habitat_validate.R:920-922` `whse_basemapping.fwa_stream_networks_discharge` (fwapg `load.sh:154`) | TRUE |
| 64 | README:71 | wet's per-segment flow not yet read (#331) | #331 OPEN "Read discharge from wet's ..." | TRUE |
| 65 | README:75, NOTICE:12 | Connectivity model follows bcfishpass's method | `lnk_pipeline_run.R:252-261` mirrors `model_access_bt.sql`; `lnk_crossings_union.R:3-4` | TRUE |
| 66 | README:75 | bcfishpass built by Simon Norris, maintained with contributions from many groups | attribution | TRUE |
| 67 | README:75 | Every link config reads the listed correction files | All 5 bundles declare fixes, PSCIS status, xref, definite, control, UHC and misc (`configs/*/config.yaml`; `default_tuned` inherits). Read at `lnk_pipeline_load.R:116-168`. | TRUE (see #68 for misc) |
| 68 | README:75 | **"...and other crossings"** (as correction data the configs use) | `user_crossings_misc` is appended to `<schema>.crossings` (`lnk_pipeline_load.R:116-128`). `.lnk_crossings_union` then drops and rebuilds that table from PSCIS, CABD and modelled crossings only (`lnk_crossings_union.R:120-123`). Misc crossings never reach barriers or output: read, no effect. | OVERSTATED |
| 69 | README:75 | **These are synced from bcfishpass weekly, upstream commit and checksums recorded, so corrections stay in one place** | `sync-bcfishpass-csvs.yml:41` weekly cron, but `data-raw/sync_bcfishpass_csvs.R:51-52` syncs only `configs/bcfishpass` and `configs/default`. `default_extrabreaks` and `default_rearbreaks` carry their own copies (`synced: '2026-04-27'`, `upstream_sha: e48d713`), and `user_pscis_barrier_status.csv` differs in bytes from the synced copy (md5 `716c9dce…` vs `a358a457…`). Two of the five shipped configs read stale, unsynced corrections. | OVERSTATED |
| 70 | README:75, NOTICE:12 | The `bcfishpass` config applies bcfishpass's own rules and thresholds so results can be checked | `configs/bcfishpass/` frozen parity inputs; `lnk_compare_rollup` | TRUE |
| 71 | README:75 | Observations from bcfishobs; network from fwapg and the BC FWA | `snapshot_bcfp.sh:13-14,248-302`; `whse_basemapping.*` | TRUE |
| 72 | README:80-83 | `citation("link")`; metadata in CITATION.cff | no `inst/CITATION`, so citation is auto from DESCRIPTION; CFF exists | TRUE |
| 73 | README:87 | Redistributed bcfishpass data carries its own license (NOTICE, LICENSE-bcfishpass) | NOTICE.md:13-32 | TRUE |
| 74 | NOTICE:12 | bcfishpass software not redistributed | no bcfp code vendored | TRUE |
| 75 | DESC/CFF/Rd | Every rule and threshold is a row in a config bundle | Rules are generated from `dimensions.csv` rows (`config.yaml` provenance `rules.yaml: generated_from: dimensions.csv`). Thresholds are CSV rows. `pipeline.spawn_connected.SK.gradient_max` in config.yaml is unread: grep finds no `cfg$pipeline$spawn_connected` reader, and the value comes from dimensions. | TRUE |
| 76 | DESC/CFF/Rd | Every run records its inputs, so a result traces to the rule that produced it | `lnk_log.R` config snapshot + log_input; `log = TRUE` default | TRUE |
| 77 | DESC Authors@R, CFF:22-35, Rd:22-29 | Irvine aut/cre (email, ORCID 0000-0002-3495-2128); Norris ctb; company cph/fnd | ORCID matches 21 sibling DESCRIPTIONs and 41 CFFs; old `0009-…` used nowhere else | TRUE |
| 78 | CFF:6-35 | CFF generated from DESCRIPTION by the workflow's command | Re-ran the workflow command with cffr 1.4.2 in a scratch dir: byte-identical, `cff` valid. Repo has no topics, so no keyword drift in CI. | TRUE |
| 79 | workflow:27-29 | doi/repository dropped because of an unrelated CRAN `link` | accepted decision | TRUE |

## Findings

All but one are low. None blocks the release on its own; #8 is the one a reader would act on.

1. **#8 FALSE (medium): README:5 "…and which barrier it is".**
   - **Code:** No barrier identity per reach is persisted (`lnk_persist_init.R:53-54`: "Array columns … stay in-memory … not persisted") or exported (`habitat_fwa_v1_segment.yaml:118`). The output names the barrier's *kind* (modelled crossing, assessed crossing, dam, remediated), via `mapping_code` token 2.
   - **Why it matters:** A restoration reader would look for the crossing's ID and not find it.
   - **Fix:** "…and what kind of barrier it is" (a modelled or assessed crossing, or a dam).

2. **#42 OVERSTATED (low-medium): README:48 "Crossings from different inventories are matched by network position (`lnk_match()`)".**
   - **Code:** `lnk_match()` has no caller in the package or `data-raw/`. The run matches PSCIS to modelled crossings in `.lnk_pipeline_pscis_build()`: spatial snap, then a name/width score and planar weighted distance among candidates within 100 m on the same blue line, then xref CSV overrides.
   - **Fix:** Describe what the run does: "PSCIS assessments are matched to modelled crossings as bcfishpass does, with the community xref of known matches". Name `lnk_match()` only as a standalone tool, outside the run's description.

3. **#69 OVERSTATED (low-medium): README:75 "synced from bcfishpass weekly … so corrections stay in one place", after "Every link config reads".**
   - **Code:** The sync script covers `configs/bcfishpass` and `configs/default` only (`sync_bcfishpass_csvs.R:51-52`). `default_tuned` inherits, but `default_extrabreaks` and `default_rearbreaks` hold their own copies from 2026-04-27 that differ in bytes.
   - **Fix, either:**
     - scope the sentence ("The `bcfishpass` and `default` bundles, and those that extend `default`, sync weekly"); or
     - file an issue to make the two variants `extends: default` / re-sync them.

4. **#6 OVERSTATED (low): README:5, DESCRIPTION, CITATION.cff and Rd "records the road and rail crossings and dams below each reach".**
   - **Code:** What is recorded per reach is whether a crossing or dam of barrier status (BARRIER/POTENTIAL) lies below, by source type. Passable crossings are not recorded, and the crossings themselves are not attached. Same root as #8.
   - **Fix:** "records whether a road or rail crossing or a dam that may block fish lies below each reach". DESCRIPTION → CFF via the workflow, then `devtools::document()` for the Rd.

5. **#3 OVERSTATED (low): README:5, DESCRIPTION, CITATION.cff and Rd "classifies stream, lake and wetland reaches … from gradient and channel width or discharge".**
   - **Code:** Lake and wetland rearing is by polygon type and area with no gradient, width or discharge test (fresh `frs_habitat.R:16-20`; link L/W rules `thresholds: false`). README:46 says it correctly.
   - **Fix:** "…from gradient and channel width or discharge, and lake and wetland size".

6. **#36 OVERSTATED (low): README:46 "each phase is its own `lnk_pipeline_*()` call, so a run can be stopped, inspected and resumed".**
   - **Code:** Four steps are `lnk_persist_init` / `lnk_barriers_unify` / `lnk_barriers_views` / `lnk_mapping_code`. The run log exists only inside `lnk_pipeline_run()`, so a hand-stepped run is unlogged. `lnk_pipeline_run()` cannot resume.
   - **Fix:** "each phase is an exported function, and `cleanup_working = FALSE` keeps the working schema for inspection", or drop "and resumed".

7. **#43 OVERSTATED (low): README:48 "`lnk_mapping_code()` gives every segment a code for its habitat and the barrier below it".**
   - **Code:** Only reaches the species can reach get the barrier token. Unreachable reaches get an empty code (`lnk_pipeline_mapping_code.R:276-286`).
   - **Fix:** "gives every segment a species can reach a code for its habitat and the barrier below it".

8. **#68 OVERSTATED (low): README:75 "…and other crossings".**
   - **Code:** `user_crossings_misc` is read into the working crossings table, then discarded when `.lnk_crossings_union()` rebuilds it (`lnk_crossings_union.R:120-123`). It reaches no barrier or output.
   - **Fix:** Drop "and other crossings" from the list. The dead read is a code question, separate from this PR; CLAUDE.md already records the crossings CSV as vestigial.

Non-claim bugs: none found.
- **CITATION.cff:** the workflow reproduces it byte for byte and it validates.
- **Workflow:** triggers and permissions are correct, and the bot commit is guarded by `git diff --quiet` on a tracked file.
- **`readme_figure.R`:**
  - Legend vectors are all length `keys + 2`.
  - The only unregistered tokens (`REAR` alone, 0.0 km; NA, 0.2 km) fall to `#999999` with no legend entry, which is invisible at this scale.
  - Paths assume the repo root, as its header says.
- **`.Rbuildignore`:** excludes CITATION.cff.

The figure is from the 2026-07-04 build of `default`. #307, #310 and #311 have changed `default` since; the caption says "cached data" but not the date. This is not a false claim and is not a finding.
