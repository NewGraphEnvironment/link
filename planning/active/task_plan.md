# Task: A vocabulary for link's outputs: how streams were cut, how attributes were measured, where flow came from (#414)

Configs are named for how they were made: `default`, `default_tuned`, `default_extrabreaks`, `default_rearbreaks`, `bcfishpass`. A config's contents change over time while its name stays, and a provincial run renames its schema `fresh_default_<date>`, so neither a config name nor a schema name says what an output holds. Downstream, habitat-threshold tuning is starting to store runs on several of link's outputs side by side (the same species tuned on differently cut networks, with differently measured gradients), and it needs names that say what each one is and stay true. Only `bcfishpass` is defined by something outside us; every other name here is early and can still be chosen well.

Consumers: knowledge#119 (archive layout `tune/CH_rear/<setup tokens>/`), knowledge#120, link#415 (minimal network).

## Decided at the gate (operator, 2026-10-29)

- **Four axes, not three.** The first test (findings.md) found that `break_order` + `observation_breaks` don't fix where streams are cut. `gradient_classes` moves cuts, and so does access: since #326, gradient positions cut only where a present species' access changes, so access gradients, lift rules, presence and pooling move segments. The operator's example: a species moving from 30 % to 18 % adds cuts.
  - `cut` (method): effective `break_order`, `observation_breaks` (only when `observations` is a source) and `gradient_classes`.
  - `acc` (access rules): digest of `parameters_fresh` (`species_code`, `access_gradient_max`, `observation_*`), `wsg_species_presence`, `observation_exclusions`, the modelled species (`cfg$species`), and two rules held in code (the access-class map, `lnk_presence()`'s groups). Species pooling (validator-only) and `observation_exclusions` (data vintage; operator, 2026-10-29) stay out. The digest is over the parsed values sorted by key, not the file bytes, so a quoting change mints nothing.
  - `grad`: `segment` (no knob exists yet).
  - `flow`: `discharge_source` + `discharge_fill`.

  Data vintage (observation records, the weekly bcfishpass CSVs, FWA) gets no token: it identifies a build and is in `log` / `log_input`. Habitat thresholds and rules are tuning results and get no token either.
- **Derived, not declared.** The table gains a sixth column, `spec`, which `lnk_vocabulary_resolve(cfg)` matches per axis. Configs declare nothing.
- **Names:** `inst/extdata/vocabulary.csv`, `lnk_vocabulary_read()` (the table) and `lnk_vocabulary_resolve(cfg)` (returns `c(cut=, acc=, grad=, flow=)`). Log columns: `token_cut`, `token_acc`, `token_grad`, `token_flow`. The operator chose these over `lnk_vocab_table` / `lnk_vocab_tokens`: accurate verbs, the noun in full, like `lnk_wsg_resolve()`.
- **A bundle loaded by path is refused like any unnamed config** (operator, 2026-10-29): a new kind of output gets a name in link's one table first.
- **No tokens for `default_extrabreaks` / `default_rearbreaks`** (operator): they are stale `extends: ~` copies, and running them refuses until someone adds rows.
- **First rows (permanent once merged):**
  - `cut-full-top`: default, default_tuned.
  - `cut-full-ssf-all`: bcfishpass.
  - `acc-bcfp`: bcfishpass's access rules, the one set defined outside us.
  - `acc-v1`: default's access rules. Following the operator's steer, our own sets are numbered revisions rather than named after the company; the next edit is `acc-v2`.
  - `grad-seg`: every config.
  - `q-fwapg`: every config except default_tuned.
  - `q-wet-fill`: default_tuned.

## Phase 1: First test and table
- [x] `research/output_vocabulary.md`: the five configs described per axis. It covers what moves cuts (gradient_classes and the access inputs, from the CSV diffs), what doesn't (`cabd_additions_barriers` moves only DAM tokens, #367), and why vintage stays in the build record. Add a row in `research/README.md`.
- [x] `inst/extdata/vocabulary.csv` with columns `token, axis, definition, spec, introduced, retired` and the seven rows above.
- [x] Tests (`test-lnk_vocabulary.R`): tokens match `^[a-z0-9]+(-[a-z0-9]+)*$` and are unique; axis is one of {cut, acc, grad, flow}; the prefix matches the axis; no two live rows share an axis + spec; `retired` is empty or ≥ `introduced`.
- [x] Append-only guard (the comparison is mutation-tested on fixtures; the live test skips until main holds the table, so it first runs after merge): against `origin/main`'s copy (`git show`), no row is removed and no `token`/`spec`/`introduced` is edited; only an empty `retired` may be filled. It skips outside a git checkout. Restore a rename and confirm the guard fires.

## Phase 2: Resolver
- [x] `R/lnk_vocabulary.R`: `lnk_vocabulary_read()` and `lnk_vocabulary_resolve(cfg, loaded = NULL)`. It builds each axis's spec from the effective values: reuse `.lnk_resolve_classes()`, `.lnk_observation_breaks()`, the break_order default from `lnk_pipeline_break.R:105`, `.lnk_discharge_source()` and `.lnk_discharge_fill()`. The acc digest comes from `lnk_load_overrides(cfg)`. It refuses (`stop`) when a spec matches no row, naming the axis and the spec, and when the match is retired. Runnable `@examples`.
- [x] Tests: the first test as unit tests. bcfishpass gives `cut-full-ssf-all / acc-bcfp / grad-seg / q-fwapg`; default gives `cut-full-top / acc-v1 / grad-seg / q-fwapg`; default_tuned gives `cut-full-top / acc-v1 / grad-seg / q-wet-fill`; extrabreaks and rearbreaks refuse. Negative cases: an edited break_order, an edited access gradient, a retired match, and a quoting-only CSV change that still resolves.

## Phase 3: Build record and refusal
- [x] `R/lnk_log.R`: add the four `token_*` columns to `cols_log` and write them in `.lnk_log_run_start()`.
- [x] `R/lnk_pipeline_run.R`: resolve before `.lnk_log_run_start()` (line 163), so a refused build writes no log row and touches no schema. Pass the tokens through.
- [x] Check that `schema_consolidate.R` copies `log` by column name, so a host without the new columns still consolidates. The habitat export's `provenance/.../log.parquet` copies whole rows, so the tokens reach the manifest without a change.
- [x] `data-raw/pretest_inputs.csv`: map `R/lnk_vocabulary.R` and `inst/extdata/vocabulary.csv` (`any`, the orchestration class) so the gate does not refuse an unmapped file.
- [x] Update the tests in `test-lnk_log.R` / `test-lnk_pipeline_run.R` for the new columns and the refusal.
- [x] Plan review fixes (`review-plan.md`): the cut spec records which barrier input files the bundle declares; the acc digest adds the code-held access-class map and `lnk_presence()` groups; `study_area_run.sh`'s local pre-flight resolves the config's tokens before any spend; the `q-wet-fill` definition says the fill applies where discharge is read.

## Phase 4: Docs and release
- [x] RUNBOOK: a short "Output vocabulary" section (the axes, the rules, how to add a row, why a run refuses).
- [x] NEWS, the CLAUDE.md status, and a version bump as the final commit.

## Owed at the end (reported, done after merge)
- [ ] Before the next provincial run, the pre-run gate (#372) re-runs, because `R/` changed.
- [ ] knowledge#119 reads the table through `lnk_vocabulary_read()` / `vocabulary.csv` at a tag (its own issue).
- [ ] #415 adds `cut-access` (or whatever name it settles on) when its minimal network is built.

## Validation
- [x] Tests pass
- [x] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: `devtools::test()`, `devtools::check()` and `lintr::lint_package()`. Then a live single-group build of ADMS under `default` into a scratch schema, whose `log` row should carry `cut-full-top / acc-v1 / grad-seg / q-fwapg`. A `default_extrabreaks` run against the same scratch schema should refuse with no log row written. Each guard's mutation (rename a row, edit a spec) should fail its test.
