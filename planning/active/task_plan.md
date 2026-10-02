# Task: Thread fresh params_method (per-WSG cw/mad) through lnk_pipeline_classify (#286)

**If done:** link configs can put watershed groups on bcfishpass's discharge (`mad`) habitat model and have it take effect. **If never:** every link run classifies on channel width, whatever a config's `parameters_habitat_method.csv` says. Nothing breaks either way, since the fresh default is the bundled all-`cw` table.

## Context

fresh v0.35.0 (fresh#220) added `params_method` to `frs_habitat_classify()`, a data
frame of `watershed_group_code` and `model` (`cw`/`mad`). link calls it without that
argument (`R/lnk_pipeline_classify.R:95`), so every run classifies on channel width
whatever a config wants. Exploration found three things the issue body does not say:

- **No bundle carries a method CSV.** "The config's method CSV" does not exist yet.
- **Working streams have no `mad_m3s`.** `.lnk_pipeline_prep_network()`
  (`R/lnk_pipeline_prepare.R:689`) joins only `channel_width`. fresh stops before any
  write when a `mad` group's table has no `mad_m3s`. The source is
  `whse_basemapping.fwa_stream_networks_discharge`, keyed on `linear_feature_id`. Local
  fwapg holds 2.7M rows across 150 WSGs, and 2.0M of them have a non-NULL `mad_m3s`.
- **link pins `fresh@v0.33.0`.** That release has no `params_method`. The latest is
  v0.36.2. v0.36.0's `frs_db_conn()` change reaches link only through
  `data-raw/wsg_vignette_data.R:204`.

All three bundle thresholds CSVs already carry `*_mad_min`/`*_mad_max`, so nothing
needs adding there.

**Decisions made at this gate:**
1. Every base bundle declares `parameters_habitat_method.csv`, the #282 pattern. A
   custom bundle that declares none falls back to fresh's copy, which is hashed into
   `config_hash` by a fixed name.
2. `mad_m3s` goes on the **working** streams table only. The persist shape does not
   change.
3. Provenance comes through `config_hash` only. No new log table and no new log column.

## Phase 1: fresh pin + capability guard
- [x] DESCRIPTION: `fresh (>= 0.35.0)`, `Remotes: NewGraphEnvironment/fresh@v0.36.2`. Reinstall fresh at the tag and confirm `params_method` is in `formals(fresh::frs_habitat_classify)`
- [x] `lnk_preflight_fresh()` (`R/lnk_preflight_fresh.R`): assert the `params_method` formal on `frs_habitat_classify` (a capability, not a version). Add a test that restores the defect and shows the guard fires
- [x] Check `data-raw/wsg_vignette_data.R`'s bare `fresh::frs_db_conn()` against the 0.36.0 behaviour change, and note the result in findings

## Phase 2: method table as bundle data
- [x] Add `parameters_habitat_method.csv` to `bcfishpass`, `default`, `default_extrabreaks` and `default_rearbreaks`: a frozen copy of `smnorris/bcfishpass@1fae4ea parameters/example_newgraph/parameters_habitat_method.csv` (188 groups, all `cw`). Diff it against fresh's bundled copy first and record the result. `default_tuned` inherits it through `extends`
- [x] For each, add a `files: parameters_habitat_method:` entry and a provenance block (source, upstream_sha, synced, checksum, shape_checksum), the same as the thresholds entries
- [x] Add a `.lnk_habitat_method_csv(cfg)` resolver in `R/lnk_config.R`, next to `.lnk_habitat_thresholds_csv()`: the bundle's path, else fresh's copy with a message
- [x] `config_hash` (`R/lnk_log.R` ~L73/117): hash fresh's fallback as `fresh:parameters_habitat_method.csv` when the bundle declares none
- [x] Add `inst/extdata/configs/dictionary_parameters_habitat_method.csv` and its shape/coverage/no-absent-column tests in `test-dictionaries.R`, following the #282 block
- [x] `lnk_config_verify` / audit pass clean on all bundles

## Phase 3: thread through classify + `mad_m3s` on working streams
- [x] `.lnk_pipeline_prep_network()`: add `fresh::frs_col_join(..., from = "whse_basemapping.fwa_stream_networks_discharge", cols = "mad_m3s", by = "linear_feature_id")` next to the channel_width join. Check that `frs_break_apply` carries it through splits
- [x] `lnk_pipeline_classify()`: add a `method_csv = NULL` argument, mirroring `thresholds_csv`. Resolve it as `method_csv %||% .lnk_habitat_method_csv(cfg)`, read it, and pass `params_method =` to `frs_habitat_classify()`. Update the roxygen
- [x] Tests in `test-lnk_pipeline_classify.R`, following the #282 capture pattern with mocked `frs_habitat_classify`: the bundle's table is passed, the undeclared fallback uses fresh's copy and says so, and an explicit `method_csv` wins
- [x] `lnk_pipeline_connect` stays as it is. `.frs_run_connectivity` is not method-aware (clustering is on gradient), so record that in findings rather than change it

## Phase 4: live verification (local docker fwapg, scratch schema)
- [ ] State the run decisions (config, scratch schema, WSGs, species) before launching
- [ ] **No-change proof.** Run ADMS with the `default` bundle at HEAD and on the branch, reclassifying on one prepared schema. `streams_habitat` must be byte-identical (digest). The all-`cw` table plus the extra `mad_m3s` column must move nothing
- [ ] Repeat the no-change proof on a second, larger WSG (HORS or BULK)
- [ ] **mad takes effect.** Run a thin bundle (`method_csv`) that sets one WSG with discharge coverage to `mad`. It must run, CO/CH/ST habitat must differ from cw, and BT must get no stream habitat from inheriting rules (fresh's documented behaviour). Record km by species in findings
- [ ] A `mad` WSG with no discharge coverage (BULK has none): confirm and record what happens. Every segment fails the mad rule, so expect zero stream habitat. Surface this, and do not add a workaround

## Phase 5: docs + follow-ups
- [ ] RUNBOOK §7 "Where habitat thresholds live": add the method table, the fallback, and that `mad_m3s` exists only in the working schema
- [ ] NEWS entry (the version bump comes at merge, through `/gh-pr-merge`)
- [ ] Draft the follow-up issue body in findings, for review and not filed: `lnk_habitat_validate()`'s width relaxation (`R/lnk_habitat_validate.R:759-781`) is channel-width only and gives wrong miss reasons for `mad` groups. `frs_habitat_predicates(model=)` exists to fix it

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
