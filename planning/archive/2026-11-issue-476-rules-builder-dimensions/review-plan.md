# Plan review for #476 (backlog move 8), 2026-11-22

A Plan agent reviewed the plan read-only against origin/main 8c40e192. I probed its key claims before folding them in:

- fresh's workflow permissions read `read` / `false` (`gh api repos/NewGraphEnvironment/fresh/actions/permissions/workflow`);
- `.Rbuildignore:7` excludes `^data-raw$`;
- the mock at `test-lnk_pipeline_run.R:350` has fixed formals;
- `.lnk_dictionary_columns()` exists at `R/lnk_log.R:478`;
- `rear_no_fw = yes` holds exactly for CM and PK in both bundles;
- `build_rules.R` calls the installed `link::`.

Blockers raised: 4
Owner forks: 7

## Findings and verdicts

### Blockers

- **B1.** Phase 4's arms cannot score on PARS, PCEA and FINA: only BT is there, `dims` edits one species row, and CH's near-river pair needs salmon groups. **Folded:** the measurement is now Phase 1, with BT's bypass on the Peace closure and CH / ST bypass plus CH `both` on #364's groups. CO is skipped and WCT dropped. Choosing groups and species is measurement design, so I treated it as a plan correction, not an owner fork.
- **B2.** fresh's `GITHUB_TOKEN` cannot open PRs, `workflow_dispatch` cannot run a workflow not yet on fresh's default branch, a weekly PR is not idempotent, and the header has two `# Generated` lines. **Folded** into Phase 4. The setting is put to the owner in Open decision 4.
- **B3.** Decision 1 was asked after the regeneration that depends on it. **Folded:** decisions 1 to 7 are asked at the resume, before Phase 1.
- **B4.** The README drift test would sit in `data-raw/`, which is excluded from the build, so it would never run in CI. **Folded:** the renderer moves to `R/`.

### Gaps

- **G1.** No source-tree fallback is needed; reuse `.lnk_dictionary_columns()`; `build_rules.R` must `load_all()`. **Folded.**
- **G2.** The new README needs a pretest map row. **Folded.**
- **G3.** Passing `cfg` breaks the test mock. **Folded:** `cfg = NULL` default, and the mock is updated.
- **G4.** New columns move provenance checksums at every commit. The extrabreaks and rearbreaks bundles cannot run. **Folded:** provenance is updated per commit, and those two bundles are not edited.
- **G5.** `spawn_only` duplicates `rear_no_fw`. **Owner fork:** Open decision 5.
- **G6.** KO is paused, so a KO proof tests nothing, and a cheaper proof on persisted tables exists. **Folded.**
- **G7.** The synced sample changes fresh's fallback in three ways and still is not `default` under fresh's thresholds. **Owner fork:** part of Open decision 4.
- **G8.** Five docs become wrong once the direction flips. **Folded** into Phase 4.
- **G9.** "lnk_vocabulary_resolve() reads no rules.yaml" was wrong: `cfg$species` comes from the rules' keys. **Folded:** reworded as "a rules change that leaves the species set alone reaches no token".
- **G10.** `build_rules.R` builds three rules files, not every bundle, and rewrites dates. **Folded** into Phase 5.
- **G11.** `config_hash` also moves for the three bundles that extend `default`, at near-nil cost, and `log_dimensions` gains columns. **Folded** into Owed and Phase 3.

### Assumptions

- **A1.** #212's count used the wrong species: it is at least 70 and possibly all 83 groups, not 68. **Owner fork:** Open decision 1's evidence was corrected, and the recommendation stands.
- **A2.** "A byte match implies a row-count match" holds only for the synced bundles against bcfishpass's CSVs. **Owner fork:** Open decision 3's wording was corrected.
- **A3.** #316's 156 km is BT only. **Folded** into Open decision 2.
- **A4.** Phase 4 needs a clean, fixed tree and the pinned fresh. **Folded:** it runs first, from a worktree.

### Ordering

- **O1 to O5.** **Folded:**
  - decisions are asked first;
  - provenance is updated per commit;
  - the sample is regenerated in Phase 4;
  - the measurement runs first;
  - the version is fixed before any vocabulary row.

### Scope

- **S1.** The plan narrowed #189 to the persisted path without saying so. **Owner fork:** Open decision 6, which recommends filing the rest for move 9.
- **S2.** One PR is right; the fresh PR is necessarily separate. **No change.**
- **S3.** The renderer must not assume dimensions' columns. **Folded.**

### Acceptance

- **AC1, AC2.** Covered by B4 and B2. **Folded.**
- **AC3.** #327's decision rule must be fixed before scoring. **Owner fork:** Open decision 7.
- **AC4.** Require no new warnings. **Folded.**
- **AC5.** State PARS's roles in `wsg_roles_327.csv`. **Folded.**

## Files the plan names

```
R/lnk_rules_build.R
R/lnk_log.R
R/lnk_mapping_code.R
R/lnk_pipeline_mapping_code.R
R/lnk_pipeline_run.R
R/lnk_config.R
R/lnk_config_verify.R
R/lnk_vocabulary.R
R/lnk_pipeline_prepare.R
data-raw/build_rules.R
data-raw/regen_provenance.R
data-raw/wsg_recompute_one.R
data-raw/habitat_variants_build.R
data-raw/habitat_variants_score.R
data-raw/habitat_score/variants_364.csv
data-raw/habitat_score/wsg_roles_364.csv
data-raw/habitat_score/README.md
data-raw/pretest_inputs.csv
data-raw/recompute_readers.R
data-raw/audit_configs.R
data-raw/sync_bcfishpass_csvs.R
data-raw/logs/wetland_door_364/README.md
data-raw/logs/rearing_diff_324/README.md
data-raw/logs/build_minutes.csv
inst/extdata/configs/dictionary_dimensions.csv
inst/extdata/configs/default/dimensions.csv
inst/extdata/configs/default/rules.yaml
inst/extdata/configs/default/config.yaml
inst/extdata/configs/default/parameters_habitat_thresholds.csv
inst/extdata/configs/default/species_modelled.csv
inst/extdata/configs/default/README.md
inst/extdata/configs/bcfishpass/dimensions.csv
inst/extdata/configs/bcfishpass/rules.yaml
inst/extdata/configs/bcfishpass/config.yaml
inst/extdata/configs/bcfishpass/parameters_fresh.csv
inst/extdata/configs/bcfishpass/presence_groups.csv
inst/extdata/configs/default_rearbreaks/README.md
inst/extdata/parameters_habitat_rules.yaml
inst/extdata/parameters_habitat_dimensions.csv
inst/extdata/vocabulary.csv
tests/testthat/test-lnk_rules_build.R
tests/testthat/test-dictionaries.R
tests/testthat/test-lnk_pipeline_run.R
tests/testthat/test-lnk_config.R
tests/testthat/test-pretest.R
tests/testthat/test-lnk_vocabulary.R
.github/workflows/sync-bcfishpass-csvs.yml
.Rbuildignore
research/habitat_thresholds.md
RUNBOOK.md
CLAUDE.md
NEWS.md
DESCRIPTION
planning/backlog.md
```
