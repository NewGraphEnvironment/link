# Task: Per-bundle habitat thresholds CSV in config.yaml (#282)

The numeric habitat thresholds (`spawn_gradient_max`, `spawn_channel_width_min`, `rear_gradient_max`, …) come from fresh's `inst/extdata/parameters_habitat_thresholds.csv`. `lnk_pipeline_classify()` and `lnk_pipeline_connect()` take a `thresholds_csv` argument that defaults to fresh's copy (`R/lnk_pipeline_classify.R:58-62`, `R/lnk_pipeline_connect.R:66-69`). `lnk_pipeline_run()` never passes one (`R/lnk_pipeline_run.R:185-188`), and `config.yaml` has no key for it. `dimensions.csv` → `lnk_rules_build()` emits edge, waterbody and area rules but no gradient or channel width, so the rules inherit fresh's CSV at classify time.

Every bundle — `bcfishpass`, `default`, `default_rearbreaks`, `default_extrabreaks` — therefore runs identical thresholds.

Related staleness: `default/config.yaml`'s description says the bundle ships `spawn_gradient_min 0.0025`. `default/parameters_fresh.csv` ships 0; the floor was tested and reverted (`research/default_vs_bcfishpass.md:443-450`).

**How it is wired today:**
- `lnk_pipeline_classify()` and `lnk_pipeline_connect()` take `thresholds_csv =` with
  fresh's file as the default (`R/lnk_pipeline_classify.R:58`,
  `R/lnk_pipeline_connect.R:66`), and pass it as a path to `fresh::frs_params(csv =)`.
- `lnk_pipeline_run()` passes nothing (`R/lnk_pipeline_run.R:185-188`).
- `lnk_rules_build(thresholds =)` also reads fresh's file, and bakes
  `rear_lake_ha_min` into `rules.yaml` (`R/lnk_rules_build.R:281,376`).
- `.lnk_config_hash()` (`R/lnk_log.R:52`) already hashes every `cfg$files` path, so a
  vendored CSV comes under provenance with no hash change needed.
- `.lnk_log_config_snapshot()` (`R/lnk_log.R:629`) logs `parameters_fresh` and
  `dimensions` rows per config_hash, driven by dictionary CSVs (#233 pattern).
- `extends:` is implemented (`R/lnk_config.R:160-230`), but no shipped bundle uses it.
  `tests/testthat/test-dictionaries.R` reads `<bundle>/<stem>.csv` straight from disk,
  so a thin bundle would break it.
- Stale text: `default/config.yaml` description and `default/README.md` both claim
  `spawn_gradient_min 0.0025`; the bundle ships 0, because the floor was reverted
  (`research/default_vs_bcfishpass.md:443-450`).

**Decided at the gate:** log the threshold values in a new
`log_parameters_habitat_thresholds` table (with a dictionary). `default_tuned` is thin
(`extends: default`), and the dictionary tests are changed to resolve paths through
`lnk_config()`.

## Phase 0: Housekeeping for parked #284
- [x] Save the #284 Plan-agent review (arrived after parking; 3 blockers: the
  observation↔segment join is ill-defined because observations are break points, the
  metric is recall-only with no use-vs-availability, and the `fshclctn_id` key is wrong)
  to `planning/active/review-plan.md` on branch `284-research-calibrate-ch-and-bt-gradient-a`.
  Commit and push there, then return to main.

## Phase 1: Resolve thresholds from the bundle
- [x] Tests first (`test-lnk_pipeline_classify.R`, `test-lnk_pipeline_connect.R`, new
  helper tests):
  - With a bundle that declares the file, `frs_params` receives that bundle's path
    (mock `fresh::frs_params` via `local_mocked_bindings`).
  - With no declaration, it gets fresh's path and a message naming the fallback.
  - An explicit `thresholds_csv` argument still wins.
- [x] Internal helper `.lnk_thresholds_csv(cfg)` (named `.lnk_habitat_thresholds_csv` — `lnk_thresholds()` already means crossing severity) returning
  `cfg$files$parameters_habitat_thresholds$path`, or fresh's copy with a `message()`.
  Change the `thresholds_csv` default in classify and connect to `NULL`, resolved through
  the helper. `lnk_pipeline_run()` needs no change, since classify and connect resolve
  from `cfg`. Update roxygen and `devtools::document()`.
- [ ] `lnk_load_overrides()` already loads any `files:` CSV. Confirm
  `loaded$parameters_habitat_thresholds` arrives as a data frame (used by the log
  snapshot in Phase 3).

## Phase 2: Vendor the CSV into the shipped bundles
- [ ] Copy fresh's `parameters_habitat_thresholds.csv` byte-for-byte into `bcfishpass/`,
  `default/`, `default_rearbreaks/` and `default_extrabreaks/`. Add a `files:` entry and
  a `provenance:` block to each: `source: fresh`, fresh version and SHA,
  `derived_from: smnorris/bcfishpass parameters/example_newgraph@4699d0f`, `synced`,
  `checksum`, `shape_checksum`. Use `data-raw/regen_provenance.R` if it covers this.
  `source` is not the bcfishpass GitHub URL, so `sync_bcfishpass_csvs.R` will ignore the
  file; state that in the bcfishpass bundle README ("frozen parity input; change only
  deliberately").
- [ ] `data-raw/build_rules.R`: pass each bundle's own thresholds CSV to
  `lnk_rules_build(thresholds =)`. Regenerate and confirm `git diff` on `rules.yaml` is
  empty apart from the header date.
- [ ] `lnk_config_verify()` passes for all four bundles.

## Phase 3: Log the threshold values
- [ ] `inst/extdata/configs/dictionary_parameters_habitat_thresholds.csv` (column,
  type, group, owner, consumed_by, default_when_absent, description, related), covering
  all 14 columns, with `consumed_by` checked against real file:line in fresh and link.
- [ ] `test-dictionaries.R`: shape, coverage and no-orphan tests for the new dictionary.
  Bundle reads go through `lnk_config(b)` resolved paths (`cfg$dimensions`,
  `cfg$files$<stem>$path`), so thin bundles work.
- [ ] `R/lnk_log.R`: add `.lnk_cols_log_parameters_habitat_thresholds()` and a
  `log_parameters_habitat_thresholds` table spec (PK `config_hash, species_code`) in
  `.lnk_log_create_tables()`, plus a spec entry in `.lnk_log_config_snapshot()` fed by
  `loaded$parameters_habitat_thresholds`. When the bundle does not declare the file,
  snapshot fresh's copy so a run never logs nothing. Tests follow the existing
  log-snapshot tests.
- [ ] `data-raw/audit_configs.R`: add the new dictionary to the coverage checks.

## Phase 4: `default_tuned` bundle + stale text
- [ ] `inst/extdata/configs/default_tuned/`: `config.yaml` (`extends: default`,
  `pipeline.schema: fresh_default_tuned`, `files.parameters_habitat_thresholds` pointing
  at its own CSV, provenance) plus a README saying it is where #284's calibrated CH/BT
  values land. The CSV starts identical to default's.
- [ ] Tests: `lnk_config("default_tuned")` resolves inherited files as absolute paths
  and its own thresholds path. Changing `rear_gradient_max` in a temp copy changes what
  `frs_params` sees, while `bcfishpass`'s path and checksum are untouched.
- [ ] Fix the stale `spawn_gradient_min 0.0025` sentence in `default/config.yaml` and
  `default/README.md` (the bundle ships 0; the floor was reverted, see
  `research/default_vs_bcfishpass.md:443`).

## Phase 5: Live verification (docker fwapg)
- [ ] ADMS then BULK under `bcfishpass`: the classify output (`streams_habitat` flags
  per segment) before and after the branch is identical. Record the result with a stamp
  in `data-raw/logs/`.
- [ ] ADMS under a temp bundle extending `default` with CH `rear_gradient_max` changed:
  CH rearing differs, and other species are unchanged.
- [ ] RUNBOOK §7 and CLAUDE.md: note where thresholds live now and that the bcfishpass
  copy is frozen.

## Validation
- [ ] `devtools::test()`, `devtools::check()` and `lintr::lint_package()` clean
  (baseline counts recorded first)
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive`, then `/gh-pr-push` (Fixes #282, relates to #284)
