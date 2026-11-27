# Task: Backlog move 9: Mapping codes as rules, and the persist and run API (#477)

**If we do it:** mapping-code tokens come from a rules file, the persist functions form one family, and a failed run cleans up its working schema. **If we never do:** each new token is a code change and the API keeps its old seams.

## Context

Move 9 of `planning/backlog.md`: two batches, one PR, one release (0.95.0, minor: it breaks exported names).
Batch 12 (mapping codes as rules): #197, #153, #191, #351, plus #512 (folded in at the gate).
Batch 13 (persist and run API): #177, #176, #159, #204.
Persisted output must not move: one parity check (a persist rebuild before and after) shows every mapping-code digest identical.

## Decided at the gate (owner, 2026-11-27)

- **Renames are hard, and the expired aliases go.** `lnk_pipeline_persist()` becomes `lnk_persist_write()`, `lnk_compare_wsg()` becomes `lnk_compare_run()`, with no shims. Every caller in `R/`, `data-raw/` (live scripts; `data-raw/logs/` evidence scripts stay as written) and tests moves. `resident_species`, `anadromous_species`, `spawn_only_species` (`lnk_pipeline_mapping_code()`) and `with_mapping_code` (`lnk_compare_wsg()`), promised removal at v0.41.0, are removed. NEWS names each break. #191's shim tests are moot; it gets the rest.
- **#512 joins batch 12** (added to #477's member table; closed by this PR).
- **The mapping-code rules CSV is per bundle, declared under `files:`** in `default` and `bcfishpass`. `config_hash` moves for them and the bundles that extend them; the re-model #479 already owes settles it.
- **#204 lands as an additive species-column check**, separate from the GENERATED check so #169 can remove that later: a missing `access_<sp>` / `has_barriers_<sp>_dnstr` / `mapping_code_<sp>` column is added (catalog read first, so an up-to-date schema issues nothing and takes no lock, as #369's rule); an extra column is named in a message and kept.
- `""` for an absent species is the design (backlog gate, batch 12).

### Mechanism decided in the plan

- The rules CSV (`parameters_mapping_code_rules.csv`): columns `residence` (`resident` / `anadromous`, the `dimensions.csv` vocabulary from #476), `precedence`, `token`, `when`. `when` is a restricted boolean grammar, not free R: identifiers from a fixed alias set (`any_anth`, `any_pscis`, `any_dam_resident`, `any_dam_anadr`, `any_remed`), `&`, `|`, `!`, parentheses, `TRUE`. Validated by walking the parsed expression; anything else refuses. Each residence needs a last `TRUE` row, so no NA leaks.
- The aliases stay code (one helper beside the evaluator), reading the access columns as today; the persisted source-flag column list (`.lnk_cols_streams_access_source_flags()`) is not data-driven here.
- A bundle that declares no rules file reads a package copy, `inst/extdata/parameters_mapping_code_rules.csv`, so `lnk_pipeline_mapping_code()` works with no `cfg`. No hard-coded chain remains: the package copy is the fallback.
- A dictionary `configs/dictionary_parameters_mapping_code_rules.csv`, rendered into `configs/README.md` by `.lnk_dictionary_readme()` (#476), and a validator in the shape of `R/lnk_barrier_rules.R` (#341).
- #512: `cfg = NULL` on `lnk_mapping_code()` and `lnk_pipeline_mapping_code()`; `species_*` default `NULL` and resolve through `.lnk_species_residence(cfg, cfg$species)` (`R/lnk_mapping_code.R:311`) when a `cfg` is given, else today's defaults (`c("bt","wct")`, `c("ch","cm","co","pk","sk","st")`, `c("cm","pk")`), so a call without `cfg` returns what it does today. The `cfg` also supplies the rules file.
- #153 layer 1: `lnk_pipeline_mapping_code()` reads a missing `spawning_<sp>` / `rearing_<sp>` column as 0, as `lnk_mapping_code()` already pre-allocates (`R/lnk_mapping_code.R:175`). The persisted path is unchanged. The `data-raw/compare_bcfp_mapping_code.R` workaround it names no longer exists; roxygen on `lnk_pipeline_species()` and `lnk_presence()` says which question each answers. Layer 2 (wide `streams_habitat_linear`) stays out, as the issue says.
- #159: the named drivers are gone; the live form is `lnk_pipeline_run()`, which drops `working_<aoi>` only on success. With `cleanup_working = TRUE` the drop also runs on error, through the existing `on.exit` (`R/lnk_pipeline_run.R:209`), never on `cleanup_working = FALSE` (`wsg_run_one.R`, the variants build's focal groups keep theirs).
- #176: the internal `.lnk_compare_wsg_*` helpers serve `lnk_compare_rollup()`, so they rename to `.lnk_compare_rollup_*` (review S2).
- No run-log table for the rules: `config_hash` and the export's config files are the record (review G7). The package fallback is not hashed; only `default_rearbreaks` and `default_extrabreaks` read it, and both refuse to run (review G13, written down).
- The comments naming `lnk_pipeline_persist` in `default_rearbreaks` / `default_extrabreaks` `config.yaml` stay as they are: those files are hashed (review S1).

### Corrections from the Plan review (`planning/active/review-plan.md`)

- B1: the rules end each residence on `NONE,TRUE` (today's `!any_anth` row is equivalent; the grid proves it).
- B2: #159's error-path drop gets its own flag and `on.exit`, registered right after `lnk_pipeline_setup()`, independent of `log`; the success-path drop stays.
- B3 / G2: one resolver of the three sets, called at the top of both exported functions; a species in both the resident and anadromous sets refuses.
- B4: `data-raw/pretest_inputs.csv` rows renamed for the two moved files, and rows added for `R/lnk_mapping_code_rules.R`, the bundle CSV and the package copy (`none`).
- G3: the argument is `rules_mapping_code`; G11: new arguments go last.
- G4 / G5: tokens match `^[A-Z][A-Z_]*$` and are not ACCESS, SPAWN, REAR or INTERMITTENT; `when` parses to one expression of aliases, `&`, `|`, `!`, `(`, `TRUE` (no `T`/`F`, numbers, `&&`, `||`), evaluated in an environment whose parent is `emptyenv()`.
- G12: one reader, every column read as text (`read_as: text`).
- G8 / G9 / G10: the drift check skips a table absent from the catalog, leaves all alone on an unreadable catalog, uses `ADD COLUMN IF NOT EXISTS` under `SET LOCAL lock_timeout`, and names extra columns once per session.

## Phase 1: Mapping-code fixes and tests (#351, #153, #191)

- [x] Before any code change: capture the parity baseline (Phase 5's script, BEFORE side) from this branch's base.
- [x] `R/lnk_access.R:234`: the merge `CASE` keeps `-9` first (`WHEN sc.access_<sp> = -9 THEN -9`). DB test on a fixture schema with an absent species, which fails on the old `CASE`.
- [x] `lnk_mapping_code(presence = NULL)` runs: `lnk_pipeline_mapping_code()` accepts a named logical vector beside an `lnk_presence` object (`.lnk_presence_fn()`); its codes equal a call given the equivalent `lnk_presence` (test).
- [x] #153: missing habitat columns read 0 in `lnk_pipeline_mapping_code()`; roxygen; roxygen on `lnk_pipeline_species()` / `lnk_presence()`.
- [x] New `tests/testthat/test-lnk_pipeline_mapping_code.R`: token 1 (ACCESS/SPAWN/REAR/""), both residence chains, spawn-only, intermittent, absent species `""`, NA barrier flag `""`.
- [x] #191 rest: `test-lnk_mapping_code.R` (query construction, pivot, residence pass-through, empty-table errors, mocked); `test-lnk_persist_init.R` (wide tables and long view exist with per-species columns); persist write gating; `lnk_pipeline_run(mapping_code = TRUE)` calls the build, `FALSE` does not (extend the existing test at `test-lnk_pipeline_run.R:489` where it already covers it).

## Phase 2: Mapping-code tokens from a rules file (#197) and residence from a bundle (#512)

- [x] `inst/extdata/parameters_mapping_code_rules.csv` (package copy) holding today's two chains verbatim; the same file in `configs/default/` and `configs/bcfishpass/`, declared under `files:` with provenance (source: link).
- [x] `R/lnk_mapping_code_rules.R`: read, validate (grammar, aliases, unique precedence, a `TRUE` fallthrough per residence, residences present), evaluate first match wins. Validator tests, each restoring a defect to prove it fires.
- [x] `lnk_pipeline_mapping_code()` evaluates the rules in place of the two chains (`R/lnk_pipeline_mapping_code.R:198-212`); `rules =` argument and `cfg =` (#512); `lnk_mapping_code()` passes both; `.lnk_mapping_code_persist()` passes the run's `cfg`.
- [x] Dictionary in the owner/`consumed_by` shape, its stem added to `test-dictionaries.R`'s list, `configs/README.md` regenerated (`data-raw/dictionary_readme_build.R`).
- [x] `data-raw/pretest_inputs.csv` rows for the new R file, the bundle CSV and the package copy.
- [x] Tests: the package rules reproduce the old chains on an exhaustive grid of the five flags (32 rows, both residences) and on a raw-column grid (`dam_dnstr_ind` present or absent, `remediated_dnstr_ind` or `has_remediated_dnstr`, NA cells); a bundle that inserts `FALLS` after `DAM` emits it with no code change; #512's smoke test (BT plus a CT row set `anadromous` builds `mapping_code_ct` with the anadromous token, no argument overridden).
- [x] Remove the three expired `*_species` aliases; update roxygen and the roxygen that still names them (`R/lnk_mapping_code.R:52-59`).
- [x] Roxygen: with `cfg` and no species arguments the exported functions code every modelled species of the bundle, where the persisted build codes the group's active ones.

## Phase 3: Persist family and run API (#177, #176, #159)

- [x] `git mv R/lnk_pipeline_persist.R R/lnk_persist_write.R`, rename the function; callers in `R/lnk_pipeline_run.R`, `data-raw/habitat_variants_build.R`, `data-raw/exp_gradient_extra_breaks.R`, comments in `wsg_recompute_one.R`, `cypher_prep.sh`, `query_schema_delta.R`, the `R/` roxygen and comments (`lnk_parity_annotate.R`, `lnk_compare_rollup.R`, `lnk_pipeline_prepare.R`, `lnk_preflight_fresh.R`, `lnk_mapping_code.R`, `lnk_persist_init.R`, `lnk_barriers_views.R`, `lnk_barriers_unify.R`), the mocks in `test-lnk_pipeline_run.R`; tests renamed; `pretest_inputs.csv:28` renamed.
- [x] `git mv R/lnk_compare_wsg.R R/lnk_compare_run.R`, rename the function; the rollup helpers move to `.lnk_compare_rollup_*` (callers in `R/lnk_compare_rollup.R`, the mock in `test-lnk_compare_rollup.R`); drop `with_mapping_code`; tests renamed; `pretest_inputs.csv:76` renamed. No live `data-raw/` script calls it.
- [x] #159: working schema dropped on error when `cleanup_working = TRUE`, by its own handler registered after setup (with `log = FALSE` too); tests with a phase mocked to error, one that `FALSE` keeps it, and one that an error before setup drops nothing. NEWS and the close comment say `wsg_run_one.R` keeps its schema (`cleanup_working = FALSE`).
- [x] `devtools::document()`; `pkgdown::check_pkgdown()`; NAMESPACE.

## Phase 4: Species-column drift in `lnk_persist_init()` (#204)

- [x] A check of its own, after the tables' CREATE, skipping a table the catalog does not list and leaving all alone on an unreadable catalog: expected per-species columns of `streams_access` and `streams_mapping_code` from `species` plus `cfg$species_paused`, read from the catalog; missing ones added with `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` under `SET LOCAL lock_timeout` (types from `.lnk_cols_streams_access_per_sp()` / `.lnk_cols_streams_mapping_code_per_sp()`); extra ones named in a message once per session.
- [x] Tests: mocked catalog (missing adds, extra messages, up-to-date issues nothing); one DB test that a table built for fewer species gains the column and keeps its rows.

## Phase 5: Parity, docs, release

- [x] Parity: `data-raw/logs/mapping_code_rules_477/parity.R` rebuilds mapping codes from persist (`lnk_mapping_code()`, nothing written) for ADMS, BULK, ELKR, HORS, PARS in `fresh_default` and BULK, ELKR, PARS in `fresh` (it holds no ADMS or HORS), at the base commit (a `git worktree`) and at the branch, run back to back, and compares digests per group and species. Expect all identical. A count of `access_<sp> = -9` in both schemas shows the #351 merge change persisted nothing. A README records the stamp and result.
- [x] RUNBOOK (mapping-code mechanics: the rules file; persist family names), CLAUDE.md Exported Functions (persist family heading, `lnk_compare_run`, the rules), NEWS 0.95.0 with each break, a status block in CLAUDE.md.
- [x] Add #512 to #477's member table.
- [x] `devtools::test()`, `devtools::check()`, `lintr` per-file baseline compare against `origin/main` (renamed files mapped old to new).
- [x] The PR body says which acceptance items were moot or met differently (#153's ADMS re-run; #197's fallback; #204's additive form, source flags still a code list).

## Owed at the end (reported, done after merge)

- [ ] The re-model #479 already owes also settles `config_hash` for `default`, `bcfishpass` and the bundles extending them, but only if it starts after 0.95.0 merges; one started earlier leaves them reading as another bundle.
- [ ] Each host's wide tables checked, or `lnk_persist_init()` run once at a quiet time, before the next run that adds a species (the ADD COLUMN takes an ACCESS EXCLUSIVE lock).
- [ ] The pre-run gate runs again before the next provincial run (`R/` and `inst/extdata/` changed).
- [ ] Hosts and jobs calling `lnk_pipeline_persist()` or `lnk_compare_wsg()` outside this repo move to the new names.

## Validation

- [x] Tests pass
- [x] `/code-check` clean (once over the branch with `/code-check branch`)
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion


Verification: the parity digests (Phase 5) prove persisted output unchanged; the 32-row grid proves the rules reproduce the chains; each guard (grammar, fallthrough, `-9` CASE, drift ADD COLUMN, error-path cleanup) gets a test that fails with the defect restored.
