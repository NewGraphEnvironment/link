# Task: Backlog move 8: The rules builder and dimensions.csv as the source of truth (#476)

**If we do it:** the dictionary documents and validates the columns, residence comes from `dimensions.csv`, fresh's copy of the rules stays current, and the two open rearing questions are answered. **If we never do:** residence stays hard-coded and fresh's sample rules keep drifting from link's.

Batch 11 of `planning/backlog.md`: #75, #86, #129, #189, #212, #316, #327. Gate from the backlog: #212 to GR only or dropped; #316 and #327 adopt or decline on measurement; #86 cut to row counts or closed. One rules regeneration and diff; a `default` re-model if #316 or #327 is adopted.

## Decided at the gate

- 2026-11-22: there was no plan gate in this pane. `/coordinator` dispatched this `park review` (claim `dispatch:link_476`, `GATE=coordinator`), so the plan gate is the coordinator's, on the pushed review. The owner has decided nothing below. The forks are under `## Open decisions`, each with a recommendation.
- The launch carried no context block.
- A Plan review ran before the baseline (`planning/active/review-plan.md`). Its corrections are folded in below, and each phase says what the review changed.
- Mechanism (mine): link's top-level sample (`inst/extdata/parameters_habitat_rules.yaml`) is built from `default`'s dimensions and thresholds. `inst/extdata/parameters_habitat_dimensions.csv` stays a shipped file, but `build_rules.R` writes it as a copy of `default/dimensions.csv`, and a test holds the two identical. No file is removed, so no shim is needed.
- Mechanism (mine): `data-raw/build_rules.R` runs `pkgload::load_all()` on the source tree, as `regen_provenance.R` does, not the installed `link::` (review G1).
- Mechanism (mine): each phase that edits a tracked bundle file updates its provenance checksums in the same commit (review G4, O2). A regenerated `rules.yaml` is committed only where its body changed, since the `# Generated:` date moves on every run (review G10).

## Open decisions

Ask decisions 1 to 7 at the resume, before Phase 1, in one question set. Decision 8 waits for Phase 1's numbers. The recommended option is listed first in each.

1. **#212: close it, or add GR to the `bcfishpass` bundle?**
   - **Close (recommended).** KO and RB are paused, so only GR is left. bcfishpass upstream models no grayling (no `load_habitat_linear_gr.sql` at `smnorris/bcfishpass` main, 2026-11-22), so a GR row would be written by link, and the bundle exists to check against bcfishpass. GR's 0.15 access gradient would add cuts. Of the 83 groups where GR is present, 70 hold no salmon to supply 0.15 cuts already (`presence_groups.csv` promotes CH, CM, CO, PK and SK together). In the other 13, GR's lifts are its own (`R/lnk_pipeline_prepare.R:767-772`). So segmentation would move away from bcfishpass's, which #326 matched, in at least 70 and possibly all 83 groups. Comparison B also needs a link-vs-link compare that does not exist.
   - **GR rows in `bcfishpass`.** Add a dimensions row and a `parameters_fresh` row, add `acc-bcfp-6` to `vocabulary.csv` at the release version and retire `acc-bcfp-5`, bump the version in the PR, and re-model `fresh`.
   - **A thin bundle `bcfishpass_gr` (`extends: bcfishpass`).** Comparison B would get GR, and parity would stay where it is. It is a new bundle, token and schema, with no compare built yet.
2. **#316: decline and close it on the 2026-10-22 measurement, or adopt?**
   - **Decline (recommended).** 15,484 km of 1200 / 1400 lines lie in wetlands (`fresh_default`, by `waterbody_key`), and 97 % of them have no width. Through the stream door, at most 156 km would become BT rearing province-wide. That figure is BT only: the door would apply to every species with `rear_wetland_flow = stream`. Admitting the lines with `thresholds: false`, as lakes are, would rear about 15,000 km on lines with no width or gradient evidence.
   - **Stream-door form.** Add 1200 / 1400 to the wetland-flow rule, and re-model `default`.
   - **Free form.** `thresholds: false` on the W polygon rule.
3. **#86: close it, or build row-count checks?**
   - **Close (recommended).** `lnk_config_verify()` checks every provenance file's sha256. Since #429 the weekly sync compares the `bcfishpass` and `default` copies byte for byte with bcfishpass's published CSVs at the rebuild SHA, so their row counts match those files. What it does not cover:
     - the April copies in `default_extrabreaks` and `default_rearbreaks`, which are never synced and resolve no token, so they cannot run;
     - a reference database whose load filters rows.
     The closing comment says both.
   - **Row counts.** Implement `lnk_config_audit()` (crate `crt_schema_audit()` first) as the issue scopes it.
4. **#129: where does the copy to fresh run, and what does fresh's fallback become?**
   - **A weekly workflow in fresh pulls link's sample (recommended).** It needs one setting changed by the owner: fresh's Actions permissions read `default_workflow_permissions: read, can_approve_pull_request_reviews: false` (2026-11-22). "Allow GitHub Actions to create and approve pull requests" must be ticked there, or `gh pr create` with `GITHUB_TOKEN` fails. It needs no secret, since link is public. It keeps one PR open on a fixed branch, which it force-pushes, and it never auto-merges.
   - **link pushes a `repository_dispatch` on change.** This is what the issue proposes. The owner would create a fine-grained token with write access to fresh and store it as a link secret. Neither repo holds a secret today.
   - **Either way, fresh's fallback changes.** Today's sample and `default/rules.yaml` differ:
     - the 1050 / 1150 lines for BT, CH, ST, WCT and RB move from a free W rule to the stream test;
     - CO loses `thresholds: false`;
     - SK gains `lake_adjacent: false`.
     fresh runs the sample on its own thresholds, which have no CH `rear_river_*` pair and differ in MAD ranges. So fresh's fallback becomes "`default`'s rules on fresh's thresholds", not `default`. The owner accepts that, or keeps the sample as it is.
   - A PR opened with `GITHUB_TOKEN` starts no fresh CI, so its body says to run R-CMD-check by hand.
5. **#189: is `spawn_only` its own column, or read from `rear_no_fw`?**
   - **Derive it from `rear_no_fw` (recommended).** In both `default` and `bcfishpass`, `rear_no_fw = yes` holds exactly for CM and PK, the spawn-only species. A second column would be a second statement of one fact.
   - **A `spawn_only` column, as #189 asks,** with a test that it agrees with `rear_no_fw`.
6. **#189: wire residence into the exported functions too, or file the rest?**
   - **File the rest as its own issue, naming move 8 (recommended).** This PR reads residence from the bundle where persisted mapping codes are built (`.lnk_mapping_code_persist()`). Under the backlog rule, the other half of #189's acceptance goes to a new issue: `lnk_mapping_code()` and `lnk_pipeline_mapping_code()` deriving their sets from a bundle, and the custom-species smoke test. That issue's home is move 9 (#477), which touches the same files.
   - **Do all of #189 here.** That changes the exported functions' signatures in this PR.
7. **#327: what decides adoption, fixed before scoring?** Under #364's floor of record (`--floor=expected`), a band expecting fewer than 10 locations decides nothing. PARS has 552 measured order-1 widths, so the BT band may be underpowered.
   - **An underpowered band declines (recommended).** `default` keeps declining the exception, now with a recorded reason.
   - **An underpowered band adopts for bcfishpass parity.** The exception mirrors what the `bcfishpass` config already does.
8. **#327, asked after Phase 1's numbers: adopt the exception in `default`, or decline?** If it is adopted, every `default` group re-models at the next provincial run (move 17). It reaches no output token: the species set does not change (see Phase 1).

## Phase 1: measure the order-1 exception in `default` (#327), first

Review B1, A4 and AC5 changed this phase: the arms, the groups, its place first, and a fixed environment.

- [ ] Run the build from a separate `git worktree` at the baseline commit. The harness needs a clean tree that nothing edits while it runs (`habitat_variants_build.R:96-97, 156`). Install fresh at the `DESCRIPTION` pin (v0.52.0) in a scratch library, or stamp the installed version, which is 0.53.0 here.
- [ ] Find and cite why fwapg models no order-1 width (Thorley & Irvine 2021b; the channel width memo, attachment 2 of `fish_passage_parsnip_2021_reporting`) through the Zotero skills, or record that it was not found.
- [ ] Write `data-raw/habitat_score/variants_327.csv` and `wsg_roles_327.csv`. A `dims` variant edits one species' row, so each arm is one row per species:
  - BT's bypass on PARS, PCEA and FINA (the Peace closure). #324 found the exception moves BT there, and these groups hold no CH, CO or ST. PARS has been in-sample for BT in every earlier roles file, so the roles file states its roles and why.
  - CH's and ST's bypass, and CH's near-river pair at `both`, on #364's groups (ADMS, BULK, CHWK, CLWR, SQAM). This is the side-by-side #327 asks for.
  - CO's rearing bands are skipped (BULK holds a CO rearing `user_habitat_classification` reach). WCT is dropped, since no scored group holds it; say so.
- [ ] Build with `--prefix=score327_` and `--jobs=4` on m1, and score with `--floor=expected` under Open decision 7's rule. Report capture against km added per species and arm, with the run stamped: link SHA, fresh version, fwapg.
- [ ] Record beside the numbers: a rules change that leaves the species set alone reaches no output token. `cfg$species` (the rules' top-level keys) is in the `acc` payload, but this bypass adds no species.
- [ ] Write the result into `research/habitat_thresholds.md` (revised in place). Evidence goes to `data-raw/logs/order1_327/`.
- [ ] Ask Open decision 8 with the numbers. If adopted, set `default`'s cells in Phase 5.

## Phase 2: the column dictionary documents and validates (#75)

Review B4, G1, G2 and S3 changed this phase: the renderer lives in `R/`, no fallback, and a pretest map row.

- [ ] An internal renderer in `R/` (`.lnk_dictionary_readme()`) renders every `inst/extdata/configs/dictionary_*.csv` into markdown: one section and table per dictionary, from that file's own columns, under a "generated, do not edit" header. `data-raw/dictionary_readme_build.R` is a thin wrapper that writes `inst/extdata/configs/README.md`.
- [ ] A test renders through the `R/` function and compares the result with the installed `README.md`, so R CMD check in CI fails on a stale README.
- [ ] `lnk_rules_build(strict = FALSE)` reads the dictionary through the existing `.lnk_dictionary_columns("dimensions")` (`R/lnk_log.R:478`). It warns on a column the dictionary does not list, and `strict = TRUE` stops on one.
- [ ] Tests cover known columns (silent), an unknown column (warning) and `strict = TRUE` (error). Existing fixtures pass unchanged, with no new warnings in `devtools::test()`.
- [ ] Add `link,^inst/extdata/configs/README\.md$,none,documentation` to `data-raw/pretest_inputs.csv`, plus a row for any new `R/` file. `test-pretest.R` must stay green.
- [ ] Switch `data-raw/build_rules.R` to `pkgload::load_all()` on the source tree.
- [ ] Link the README from `lnk_rules_build()`'s roxygen and from RUNBOOK §7.

## Phase 3: residence from `dimensions.csv` (#189)

Review G3, G4 and G6 changed this phase: the bundles touched, the `cfg = NULL` default, and the proof.

- [ ] Add a `residence` column (`resident` / `anadromous`) to `default/dimensions.csv` and `bcfishpass/dimensions.csv` only. `default_extrabreaks` and `default_rearbreaks` resolve no token and cannot run, so the helper's fallback covers them. Fill it with today's sets: BT, WCT, KO, CT, DV, RB and GR are resident; CH, CM, CO, PK, SK and ST are anadromous. Spawn-only follows Open decision 5, from `rear_no_fw` or a `spawn_only` column plus an agreement test. Update both bundles' provenance in the same commit.
- [ ] Add dictionary rows for the new columns, and regenerate the README.
- [ ] A helper, `.lnk_species_residence(cfg, species)`, reads them. It stops on a modelled species with no residence value. Where a bundle lacks the column, it falls back to today's sets.
- [ ] `.lnk_mapping_code_persist(..., cfg = NULL)`, where `NULL` means today's sets. That keeps the mock in `test-lnk_pipeline_run.R:350` and the old `rerun.R` scripts working. Pass `cfg` from `lnk_pipeline_run()` and `data-raw/wsg_recompute_one.R`, and update the mock's formals.
- [ ] Tests:
  - the helper reproduces today's sets for `default` and `bcfishpass`;
  - a bundle copy with CT set to anadromous gives CT the anadromous barrier token;
  - a missing value stops.
- [ ] Prove no mapping code moves. On `fresh_default`'s persisted tables, run `lnk_mapping_code()` for ADMS and PARS (PARS holds GR, the one non-bcfishpass species `default` classifies) into scratch tables, once with the old sets and once with the helper's, and compare digests. Record the result in `data-raw/logs/residence_189/`.
- [ ] `log_dimensions` gains the new columns by `ALTER TABLE` at the next init (`R/lnk_log.R:505-555`). Check that a test covers it.
- [ ] Act on Open decision 6. Record the fresh-side outcome on #189: fresh builds no mapping code, so `parameters_fresh.csv` needs no residence column.

## Phase 4: fresh's copy of the rules stays current (#129)

Review B2, G7 and G8 changed this phase: the workflow's permissions, idempotency, header lines and proof, plus the docs that flip.

- [ ] `data-raw/build_rules.R` builds the top-level sample from `default/dimensions.csv` with `default`'s thresholds. It writes `inst/extdata/parameters_habitat_dimensions.csv` as a byte copy of `default/dimensions.csv`, which today lacks seven columns from #326 and #364. Regenerate the sample here, since the next test needs it.
- [ ] A test holds the top-level sample equal to `default/rules.yaml` below the header, and the top-level dimensions CSV equal to `default`'s.
- [ ] Do the sync as Open decision 4 answers. Under the recommended option, a fresh branch and PR add `.github/workflows/sync-link-rules.yml`. It:
  - runs weekly and on dispatch, with `permissions: contents: write, pull-requests: write`;
  - compares link main's sample with fresh's, ignoring every `^# Generated` line;
  - on drift, force-pushes a fixed branch and opens or updates one PR, labelled `rules-sync`, never auto-merged.
  Its body says fresh CI must be run by hand, and what changes in fresh's fallback. The branch carries no planning files.
- [ ] Prove the workflow on the fresh branch with a temporary `push` trigger with no `paths:` filter, removed before merge, or with `act`. `workflow_dispatch` cannot run a workflow that is not yet on fresh's default branch. The current drift is 338 lines against fresh's 2026-04-28 copy.
- [ ] Fix the docs that call the top-level CSV the source of truth or describe a hand copy:
  - `inst/extdata/configs/default/README.md:28`;
  - `inst/extdata/configs/default_rearbreaks/README.md:24`;
  - CLAUDE.md's config-change workflow, step 4;
  - `data-raw/audit_configs.R:413-415`;
  - RUNBOOK §7, including its residence row.

## Phase 5: the final rules regeneration and diff

Review G10 changed this phase: "every bundle" means the three that `build_rules.R` builds, and the regeneration is the last one, not the only one.

- [ ] If Phase 1 adopts the exception, set `default`'s cells. If Open decision 1 chooses GR rows, add them, with `acc-bcfp-6` and the version picked before the row is written (review B3, O5).
- [ ] Run `Rscript data-raw/build_rules.R`. Diff `default`'s, `bcfishpass`'s and the top-level `rules.yaml`. Expected: no rule moves from Phases 2 to 4. Commit a file only where its body moved.
- [ ] `lnk_config_verify()` is clean on every bundle, and every changed file has a row in the pretest map.

## Phase 6: the gate's closures and issue bodies

- [ ] #212, #316 and #86: act on Open decisions 1 to 3. Close each with the reason, or carry its work, and edit its body to say which.
- [ ] Edit the #75, #129, #189 and #327 bodies where the work changed their scope: #75's path and README covering every dictionary, and #189's split under decision 6.

## Phase 7: release

- [ ] NEWS entry and a minor version bump (new `lnk_rules_build(strict =)` argument, new dimensions column), as the final commit unless a vocabulary row already fixed the version.
- [ ] CLAUDE.md status block for move 8, and RUNBOOK §7 (residence, dictionary, sample sync).
- [ ] `devtools::document()`, `devtools::test()` (no new warnings), `lintr::lint_package()` per file against main, `devtools::check()`, `pkgdown::check_pkgdown()`.

## Owed at the end (reported, done after merge)

- [ ] The pre-run gate runs again before the next provincial run (`R/` and `inst/extdata/` changed).
- [ ] If Phase 1 adopts the exception, every `default` group re-models at the next provincial run (move 17).
- [ ] `config_hash` moves for `default`, `bcfishpass`, and the three bundles that extend `default`. The cost is near nil, since an `R/` change already refuses readers.
- [ ] Under Open decision 4's recommended option, the owner ticks fresh's Actions setting, the fresh PR merges, and fresh releases its refreshed sample.
- [ ] Under Open decision 6's recommended option, the issue for #189's remainder is filed, naming move 8.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved:

- #327: the variants score on held-out capture, read under decision 7's rule.
- Dictionary: the README test, which runs in R CMD check, and the unknown-column tests.
- Residence: helper tests, the CT-anadromous test, and identical mapping-code digests for ADMS and PARS.
- Sample: the equality test in link, and one workflow run on the fresh branch.
- Regeneration: a `rules.yaml` diff that matches intent, and `lnk_config_verify()` clean.
