# Code-check round 2 — staged diff for #290 (lnk_species_pooling + config hash)

Reviewer scope: staged diff only (unstaged data-raw/ and research/ edits excluded).

## Findings

- **[fragile]** `inst/extdata/configs/dictionary_species_pooling.csv:2-6` and
  `inst/extdata/configs/dictionary_species_groups.csv:2-3` — every `consumed_by`
  file:line ref is stale. The round-1 fixes pushed the code down and the dictionaries were
  not updated. Measured against the staged `R/lnk_species_pooling.R` (the staged copy and
  the working tree match):

  | column | dictionary says | line it names | actual line |
  |---|---|---|---|
  | species_pooling.species_code | 258 | `stop("species_pooling names '"...` | 264 (`t_code <- up(p$species_code[i])`) |
  | species_pooling.species_obs | 259 | the stop message | 265 (`o_code <- up(p$species_obs[i])`) |
  | species_pooling.scope_level | 225 | `bad <- which(is.na(v) ...` | 231 (`level <- tolower(trimws(p$scope_level))`) |
  | species_pooling.pool | 231 | the scope_level line | 237 (`pool <- tolower(trimws(p$pool))`) |
  | species_pooling.scope | 237 | the pool line | 243 (`key <- up(p$scope)`) |
  | species_groups.group_code / species_code | 171 | a lone `}` | 182 / 183 |

  Round 1 accepted the file:line convention itself, but these refs are wrong. That matters
  because CLAUDE.md presents `consumed_by` as machine-verified (24/24), and three of the
  refs point at a different column's parse line, which misleads anyone tracing a column.
  No test or audit checks these refs, so nothing will catch the drift.

- **[fragile]** `tests/testthat/test-lnk_species_pooling.R` (last block, "the shipped
  default bundle resolves over every region") — both assertions on `pooled` pass when it
  has zero rows: `expect_false(anyNA(character(0)))` and `expect_true(all(logical(0)))`.
  So if `lnk_load_overrides()` stopped surfacing `species_pooling` (a key rename, a failed
  read), the default bundle would pool nothing and this test would stay green. Today the
  shipped bundle gives 129 pooled rows (Fraser 52, Mackenzie 49, Skeena 12, Columbia 9,
  Kootenay 7), so the test does exercise something. Only the guard is vacuous.

## Checked and clean

- **Config hash is host-independent.** The regions file is named by the fixed string
  `link:wsg_regions.csv` and digested by content. `system.file()` resolves to `inst/` under
  load_all and to the installed copy under R CMD check, with identical bytes.
  `wsg_regions.csv` is git-tracked and not in `.Rbuildignore`. The hash moves only for
  bundles that declare `species_pooling`: `default` and `default_tuned` (which inherits
  it). `bcfishpass`, `default_extrabreaks` and `default_rearbreaks` are unchanged. The
  `default` hash moves anyway because two new files are declared, so a changed hash
  against pre-#290 log rows is expected, not a regression.
- **The mocked test is valid.** `local_mocked_bindings()` with no `.package` targets the
  link namespace, and `.lnk_config_hash()` looks `.lnk_wsg_regions_path` up there, so the
  mock is seen. The test fails if the mock did not take, because the edit goes to the
  tempfile only. The repo already uses the same pattern (test-lnk_access.R,
  test-lnk_pipeline_load.R), and it does not use `.package`, so the testthat >= 3.0.0 pin
  is fine for it.
- **The round-1 fixes hold.**
  - `aoi` and `species` are de-duplicated after normalising.
  - An unknown species errors. It is checked against the presence *columns*, independent of
    which WSGs have presence rows.
  - Row selection uses `which()`, and more than one presence row errors.
  - An NA `region` in a caller frame produces NA rows in `hit`, but
    `hit$target %in% present` drops them, so no all-NA row reaches the output.
  - A WSG absent from presence yields no rows. That matches `lnk_pipeline_species()`,
    which returns `character(0)` for an absent AOI.
- **Zero-length and recycling traps.**
  - `self` is built only when `present` is non-empty.
  - The pooled frame uses `rep(w, nrow(won))`.
  - `data.frame(grid, ...)` is built only when `nrow(grid) > 0`.
  - The empty-output schema matches the populated one.
- **Provenance and loading.**
  - `lnk_config_verify("default")` reports no drift or missing file for the two new
    provenance entries.
  - The `source: link (hand-authored...)` form matches `dimensions.csv` and
    `parameters_fresh.csv`, and `sync_bcfishpass_csvs.R` filters on the exact smnorris URL,
    so it ignores these entries.
  - The loaded tracker comes back all-character, with `pool` as "yes"/"no".
- **Tests.** The pooling, log and dictionaries test files pass under `NOT_CRAN=true`.
