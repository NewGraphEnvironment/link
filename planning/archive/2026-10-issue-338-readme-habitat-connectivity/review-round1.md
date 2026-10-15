# Code-check round 1: branch 338-readme-lead-with-intrinsic-habitat-poten vs main

Reviewer: subagent, 2026-10-14. Scope: README.md, DESCRIPTION, NOTICE.md, CITATION.cff,
.Rbuildignore, .github/workflows/update-citation-cff.yaml, data-raw/readme_figure.R,
man/figures/readme-pars.png.

## Findings

- **[claim] README.md:44: "`default_tuned` also fills discharge gaps on the main stems of large rivers from the nearest valued reach on the same river."**
  As shipped, the fill never runs. `.lnk_discharge_fill_applied()` (R/lnk_discharge.R:203-208)
  returns TRUE only when the rules read `mad` or a group is on `mad` in
  `parameters_habitat_method.csv`. `default_tuned` declares no method CSV, so it inherits
  `default`'s, which has 188 rows and every one is `cw`. `default/rules.yaml` has no `mad:`.
  `default_tuned/config.yaml:26-32` says the same: "Applied only to groups
  parameters_habitat_method puts on `mad`". So the sentence describes behaviour that is
  configured but switched off.
  "From the nearest valued reach on the same river" is also too narrow. The third fallback
  is "the largest value on any line upstream" (config.yaml:29), and that line can be on
  another river.
  Suggested wording: the fill is configured in `default_tuned` for groups put on discharge.

- **[claim] README.md:44: "Rearing is reported separately for streams, lakes and wetlands, and in `default` lake and wetland rearing counts only where it connects to the same species' spawning (sockeye and kokanee excepted)."**
  The connection test filters only the `lake_rearing` / `wetland_rearing` **bucket** flags,
  which are reported in hectares. It does not filter the `rearing` flag, and the
  stream / lake / wetland km split is built from that flag. fresh says so itself:
  `fresh/R/frs_habitat.R:33-35`, "Only the bucket flag is filtered: if the L / W rule also
  feeds the main `rearing` predicate (no `area_only: true`), `rearing` is unchanged." In
  `default/rules.yaml` the L and W rules carry `requires_connected` with no `area_only`.
  So lake-line km count in `rearing` whether or not they connect (CLAUDE.md #310:
  "lake centrelines count in `rearing`").
  For RB, `cluster_rearing` is FALSE (`default/parameters_fresh.csv`), so RB lake and
  wetland rearing km carry no spawning connection at all.
  As written, the sentence ties the km split to a connection rule that governs only the
  hectare buckets.

- **[claim/fragile] README.md:21 (Setup) and README.md:23-40 (Example): the example will not run on the database the Setup section describes.**
  - **Missing tables.** `lnk_pipeline_run()` reads `cabd.dams`,
    `whse_fish.pscis_assessment_svw` (and the other `pscis_*` views),
    `fresh.modelled_stream_crossings` and `bcfishobs.observations` (grep over R/). Neither
    fwapg nor fresh's `docker/load.sh` loads them. load.sh has no cabd, PSCIS or
    modelled-crossings stage, and loads bcfishobs only with an optional flag. They are
    loaded by link's own `data-raw/snapshot_bcfp.sh` (lines 10-13). `data-raw` is in
    `.Rbuildignore`, so a user who installs link with `pak` does not get that script.
    Setup says the database is "the same setup fresh uses (see fresh's `docker/` for a
    local one)", so a reader who follows it gets a pipeline failure.
  - **Lesser (fragile).** The example is a single-WSG run. `lnk_pipeline_run()` does not
    call `lnk_wsg_downstream_check()` (that happens in `data-raw/wsg_run_one.R:74`). On an
    empty `fresh_default`, PARS's downstream dams (Bennett, Peace Canyon, Site C) are not
    yet persisted. Its `mapping_code` would then silently lack the `DAM` token that the
    figure directly above shows on most reaches. The rollup numbers the example prints are
    not affected.

- **[convention / public text] .github/workflows/update-citation-cff.yaml:28: the comment cites `soul#365`.**
  `NewGraphEnvironment/soul` is PRIVATE (`gh repo view`) and link is PUBLIC. The
  feature-workflow convention says "No links to private repos, and no
  `owner/private-repo#N`, not even as provenance." The comment explains itself without
  the reference. Drop it, or point to a link issue.

- **[fragile] man/link-package.Rd is regenerated but not committed (working tree `M`).**
  The committed Rd still carries the old title, description, email
  (`airvine@`) and wrong ORCID (`0009-0003-7697-6064`). It also lacks the company author.
  If the branch merges without it, the help page and pkgdown's package page contradict
  DESCRIPTION and CITATION.cff. Commit the regenerated file. The `pkgdown/` directory is
  also untracked; it is ignored by `.Rbuildignore`, so decide whether it belongs in the PR.

- **[minor / broken link] README.md:81: `[CITATION.cff](CITATION.cff)` 404s on the pkgdown site.**
  Verified with `pkgdown::build_home()` in a temp copy. `docs/index.html` gets
  `href="CITATION.cff"` and no `docs/CITATION.cff` is produced. The link works on GitHub.
  The pre-existing `LICENSE` and `LICENSE-bcfishpass` links on line 85 behave the same way
  (not new). An absolute GitHub URL fixes the new one.

## Checked and found clean

- **Figure script.** `data-raw/readme_figure.R` runs from a copy of the repo root (gpkg
  copied, run in the scratchpad). Its output PNG is **byte-identical** to the committed
  `man/figures/readme-pars.png`.
- **Caption against the data.**
  - DAM is 2,717.7 of 4,368 km of classified GR reaches, so "most" holds.
  - The gq colours match the caption: MODELLED `#ff9f85` (orange), ASSESSED `#ef4545`
    (red), DAM `#ae7dd6` (purple).
  - The resident precedence in `R/lnk_pipeline_mapping_code.R:196-203` (REMEDIATED > DAM
    via sequence-aware `dam_dnstr_ind` > ASSESSED > MODELLED) explains why the reaches
    above crossings are not purple.
  - `mapping_code_gr` comes from the default config, as the caption says.
- **CITATION.cff.** Regenerating it with cffr 1.4.2 and the workflow's exact expression
  reproduces the committed file byte for byte. The workflow matches the gq / flooded /
  drift copies except for the intended `authors_roles` / `doi` / `repository` changes.
- **README functions.** Every function named in README is exported
  (`lnk_rollup_wsg`, `lnk_pipeline_run`, `lnk_log_read`, `lnk_artifact_record`,
  `lnk_scenario_export`, `lnk_catalog`, `lnk_db_load`, `lnk_habitat_validate`,
  `lnk_habitat_validate_band`, `lnk_species_pooling`, `lnk_barrier_overrides`,
  `lnk_match`, `lnk_aggregate`, `lnk_mapping_code`, `lnk_config`,
  `lnk_load_overrides`, `lnk_db_conn`). The example's argument names match the
  signatures, and `cfg$pipeline$schema` is honoured (R/utils.R:163).
- **Species, gradients and connection settings.**
  - Both `default` and `default_tuned` model BT, CH, CM, CO, PK, SK, ST, WCT, KO, RB and GR.
  - Access gradients: salmon 0.15, BT 0.25.
- **Sync, links, credits, env vars.**
  - The bcfishpass sync is weekly.
  - #331 is the wet discharge issue.
  - The ORCID and email match the sibling NGE packages.
  - `lnk_db_conn()` reads `PG_*_SHARE` first, then `PG*`, as the README says.
- **Vignette link.** The vignette filename matches the README link, and the vignette
  carries both a BT and a GR map.
