# Code-check review — round 1 (#282 Phase 1 staged diff)

## Clean

No issues found.

### What was checked

- **Callers of `thresholds_csv`.** Only `lnk_pipeline_run()` (`R/lnk_pipeline_run.R:185-188`)
  and `data-raw/exp_gradient_extra_breaks.R:108-111` call classify/connect; neither passes
  `thresholds_csv`, so both now resolve through `.lnk_habitat_thresholds_csv(cfg)`. With no
  shipped bundle declaring the key, they get fresh's path — the same file as before — plus
  a message. Behaviour unchanged apart from the message.
- **`%||%`.** Defined in `R/utils.R:6`, so it is available with R 4.1 (no dependence on
  base's 4.4 `%||%`).
- **Path resolution.** `lnk_config()` resolves `files:` entries to absolute paths and
  checks they exist (`.lnk_config_resolve_files`), including entries inherited through
  `extends:` (`.lnk_config_absolutize_files`), so the helper returns a usable absolute
  path. A missing fresh install gives `""`, which the existing `nzchar()` / `file.exists()`
  guard still rejects.
- **`$` partial matching.** No `files:` key in any bundle has the prefix
  `parameters_habitat_thresholds`, and every entry is required to carry `path`, so neither
  `$` in `cfg$files$parameters_habitat_thresholds$path` can pick up the wrong key.
- **`local_mocked_bindings(.package = "fresh")`.** This pattern is already used in
  `test-lnk_pipeline_access.R`, so the `testthat (>= 3.0.0)` pin that is lower than 3.2.0
  is not new here. Mocking fresh's namespace binding works for the `fresh::frs_params()`
  call sites, because link does not `importFrom` it.
- **Tests pass** in a copy (`NOT_CRAN=true`, `load_all`): test-lnk_config, classify and
  connect are all green.
- **Can the tests pass while the behaviour is broken?** I restored the bug in a copy
  (connect's default hard-wired to fresh's path, ignoring the bundle), and the "bundle's own
  CSV" and "falls back" tests both went red. The capture helper returns the raw error text
  when `frs_params` is not reached, so a test cannot pass by accident.
- **lintr** on the changed files: only pre-existing `indentation_linter` style lints in
  `test-lnk_config.R`, none on the new lines.

### Non-blocking observations (not defects)

- The existing test `lnk_pipeline_connect errors when species cannot be resolved`
  (cfg_stub with no `name`/`files`) now prints the fallback message
  (`config '<unnamed>' declares no ...`) into the test output. This is noise only.
- `lnk_pipeline_run()` prints the fallback message twice per WSG, once from classify and
  once from connect, until Phase 2 vendors the CSV. This is expected and temporary.
- The planned Phase 2 item "build_rules.R passes each bundle's own thresholds" matters: until
  it lands, `rules.yaml` bakes `rear_lake_ha_min` from fresh's CSV while classify reads the
  bundle's. The working tree already has unstaged Phase 2 edits (`data-raw/build_rules.R`
  and the four vendored `parameters_habitat_thresholds.csv` files) that are not part of this
  staged diff. Keep them out of the Phase 1 commit.
