# Task: README: lead with intrinsic habitat potential and cover validation, species extensions and exports (#338)

## Problem

The README still describes link at roughly its v0.4x shape: an interpretation layer plus bcfishpass reproduction. The package is at v0.65.0, and its core idea, intrinsic habitat potential per species, is not named anywhere a reader lands.

## Context

link's README describes the package at ~v0.4x (interpretation layer + bcfishpass reproduction). At v0.65.0 its core idea — intrinsic habitat potential per species, whether fish can reach it, and the barrier in the way — appears nowhere a reader lands. The README and DESCRIPTION are the source of the New Graph website copy (newgraphenvironment.github.io#53), and 12 sibling README issues were filed today (fresh#255, wet#75, flooded#81, drift#105, gq#95, fly#104, cd#142, cred#34, fpr#131, floodplains#128, stac_floodplains_bc#85, stac_uav_bc#40).

Operator direction (2026-10-14): learn from the best READMEs and our best packages, and **grow the convention by updating all of them**. Descriptions matter most, because they are what people see. The voice is technical, honest and ethical, with no bragging: **show** why (a figure, a working call, a measured result the reader can check) rather than say it.

## Decisions taken at the gate
- **pkgdown index: keep it auto-generated.** The prefix families already sort the reference into groups (`lnk_pipeline_*`, `lnk_compare_*`, `lnk_preflight_*`, `lnk_artifact_*`, `lnk_habitat_validate*`). The grouping by purpose (validation, export, provenance) goes in the README's "What it does" section. That task comes out of the issue, and the CLAUDE.md rule stands.
- **Convention home: a new soul `conventions/readme.md`**, written for any language because the wave includes the Python/STAC repos. A soul issue carries draft v0 now. Each sibling README PR amends the draft, and the convention lands once it has settled.
- **fresh pin v0.39.0 → v0.40.0: separate issue.** The v0.40.0 breaking change (`frs_point_snap()`) touches nothing link calls (checked by grep).

## Research inputs (both reports in hand; folded into findings.md in Phase 1)
- **Exemplars:** dplyr, dbplyr, httr2, sf, terra, targets, osmdata, duckdb, RPostgres, polars, ruff and ripgrep, plus the rOpenSci devguide, r-pkgs and Art of README.
  - Shared order: name/logo → 1–3 sentence pitch (what it is, what problem it solves, what it builds on) → install → setup → one example whose output shows the payoff → a documentation list with one line per vignette → related packages / non-goals → citation.
  - None of them carries a function table, a roadmap or a changelog.
  - For packages that need a database: show the code unrun with its assumptions stated, use a cached result, or lead with a figure.
- **Our packages:**
  - Strongest READMEs: flooded (has a "decision it serves" section), wet (honest about scope today), crate (states its scope today).
  - Weakest: fpr, xciter/rake, spacehakr.
  - Recurring defects: roadmaps that list shipped work (link, gq); "by design / agnostic" claims ahead of the code (fresh, link); function tables or lists; version strings in prose; vignette lists out of step with the vignettes; no license section in 8 packages.
  - The ecosystem tables disagree across packages, in both membership and roles. The proposal: one canonical table in soul.

## Figures and identity (operator question, answered; goes into draft v0)

**Show, every time; the form follows the output.**
- A package whose output is spatial or visual leads with one figure.
- A package whose output is data or plumbing shows a short example with its real printed output. No decorative image.

**Identity has two layers:**
- **The hex sticker** is the consistent mark: every README, same size and place.
- **gq-styled maps of real output** are the house cartographic language.

**A README figure:**
- is produced by the package, from a committed `data-raw/readme_*.R`;
- sits at `man/figures/readme-*.png`, which website#53 reuses;
- passes cartography.md checks 1–12 at its published width;
- carries a one- or two-sentence caption saying what it shows.

## Phase 1: Findings + convention draft v0
- [x] Fold both research reports, with their cited sources, into `planning/active/findings.md`
- [x] Write "README convention draft v0" in findings.md. It merges the exemplar checklist, soul `writing.md`, #53's copy rules (plain language, present tense, no published counts, say what the models are) and the operator's voice (descriptions first; technical and honest; show, don't tell; no comparative boasting)

## Framing (operator, 2026-10-14)

link is three things, and the descriptions carry all three:
1. **Intrinsic habitat potential** per species.
2. **Connectivity modelling:**
   - per-species access past crossings, dams, falls and gradient barriers, with fish observations and habitat confirmations as evidence of passage;
   - per-crossing upstream habitat;
   - map-ready access codes.

   The operator is moving the provincial reporting and mapping work onto link.
3. **Flexible, trackable rules.** Every threshold and rule is a dated row in a config bundle, and runs record their inputs.

How this is said (operator, revised):
- **bcfishpass gets a real acknowledgement, in its own short body section: "Data and methods it builds on".** It states the dependency link actually has (verified in `config.yaml` and `NOTICE.md`):
  - link's connectivity model follows bcfishpass's method;
  - **every** config, `default` included, reads seven of its community-maintained override CSVs (crossing fixes, PSCIS barrier status, xref, definite barriers + control, habitat confirmations, misc crossings), synced weekly from upstream (corrected 2026-10-14: the workflow's cron is Wednesdays; "daily" was wrong) with the SHA and checksums recorded, so corrections stay centralised;
  - the comparison bundle carries 10 more (CABD edits, observation exclusions, species presence, and others);
  - observations come from bcfishobs, and the network from fwapg;
  - the `bcfishpass` bundle reproduces its classification so link can be checked against it. This is mentioned once, here.
- **The rest of the body describes capability without comparison.** No superseding language; this is the CLAUDE.md rule "How to talk about bcfishpass".
- **Nothing about Simon's future plans or migration.** link is made easy to take from: rules, thresholds and pooling are plain CSVs with dictionaries.
- **Correct NOTICE's software row.** "Reference for habitat-classification parity" becomes: the method link's connectivity model follows, reproduced by the `bcfishpass` bundle for comparison.
- **Open, for the operator's word:** a line saying corrections to the synced files belong upstream in bcfishpass.

Starting draft, to be refined in Phase 2. Every clause must check against code:

> **Title:** Intrinsic Habitat Potential and Fish Passage Connectivity for Stream Networks
>
> **Description:** Models where fish habitat could be on a stream network and whether fish can reach it. For each species it classifies stream, lake and wetland reaches as spawning or rearing habitat from gradient and channel width or discharge. It then resolves access past road crossings, dams, falls and steep gradients, using fish observations and habitat confirmations as evidence of passage. Every rule and threshold is a row in a config bundle, and every run records its inputs, so a result traces back to the rule that produced it. Runs on the BC Freshwater Atlas through 'fresh'. Experimental: APIs and outputs change without notice.
>
> **README opening, in addition:** what it informs. Which crossings to fix, how much spawning and rearing habitat each would open (`lnk_aggregate()`), and maps of access and habitat per species (`lnk_mapping_code()`).

## Phase 2: Descriptions first: DESCRIPTION Title + Description, README opening
- [ ] Draft the Title, the Description and the README opening paragraph together, so all three say one thing
- [x] Restore intrinsic habitat potential, and state plainly that the package is experimental
- [ ] Name the decision it informs: which crossings to fix, and what fixing them opens up
- [ ] Check each claim against code (an export, a config bundle, a vignette) before writing it. No adjectives that cannot be checked

## Phase 3: README body
- [ ] **Show:** one figure, `man/figures/readme-pars.png`, made by `data-raw/readme_figure.R` from the cached `inst/vignette-data/pars.gpkg`, reusing the vignette's mapping_code styling (gq registry). It shows habitat potential, access and the barriers in the way for one species in the Parsnip. Self-review it against the cartography checks at the published width
- [ ] **"What it does", grouped by purpose, not a function table.** Each group names its entry function:
  - config bundles: `default` and `default_tuned` (biological defaults and calibrated values), plus a comparison bundle, which Acknowledgements names;
  - species added by config, such as Arctic grayling;
  - habitat checked against fish observations (`lnk_habitat_validate()`) and species pooling;
  - discharge fill, and rearing split into stream, lake and wetland;
  - run provenance;
  - Parquet export with a manifest (`lnk_scenario_export()` → `lnk_catalog()` → `lnk_db_load()`);
  - rollups and mapping code
- [ ] Setup: the fwapg / fresh prerequisite and `lnk_db_conn()`. The example code is shown unrun, with its assumptions stated (the RPostgres pattern)
- [ ] Documentation: link the vignette with one line on what it shows, and link the pkgdown reference
- [ ] Remove "network-agnostic by design" and the Roadmap section. Say what runs today: the Freshwater Atlas, through fresh
- [ ] Ecosystem table:
  - add wet;
  - state the current discharge wiring (fwapg's table, read through link; reading it from wet is #331);
  - word the roles to match the sibling READMEs
- [ ] "Connectivity" section:
  - per-species access, where each barrier type blocks only the species it should (`lnk_barrier_overrides()`, the pipeline);
  - per-crossing upstream habitat (`lnk_aggregate()`);
  - access codes for maps (`lnk_mapping_code()`);
  - crossings matched across inventories (`lnk_match()`).

  No product names in the body
- [ ] "Data and methods it builds on" section, as framed above. Correct NOTICE.md's bcfishpass software row. Keep License / NOTICE

## Phase 3b: Citation with company credit (operator, for Zenodo; soul#40, soul#39)

Verified 2026-10-14:
- link's DESCRIPTION does not name New Graph Environment Ltd., although LICENSE does.
- Its ORCID `0009-0003-7697-6064` fails R's checksum ("Invalid ORCID iD"). fresh, flooded, drift and gq all carry `0000-0002-3495-2128`, which is also the ORCID soul#40's Zenodo setup uses. Its email `airvine@` differs from the `al@` the others use.
- link has no CITATION.cff and no `update-citation-cff.yaml`.
- Across the fleet the company is `cph`, but cffr's default `authors_roles = c("aut", "cre")` drops it. Only crate and ngr carry it in their CFF.
- Tested in memory: `cff_create(authors_roles = c("aut", "cre", "cph"))` writes the company as a CFF entity author (`- name: New Graph Environment Ltd.`). Zenodo maps CFF authors to its creators.

Tasks:
- [x] DESCRIPTION Authors@R:
  - fix the ORCID to `0000-0002-3495-2128` and the email to `al@newgraphenvironment.com`;
  - add `person("New Graph Environment Ltd.", role = c("cph", "fnd"))`
- [ ] Add CITATION.cff and `update-citation-cff.yaml` through the `/citation-cff` skill, with `authors_roles = c("aut", "cre", "cph")` so the company is a credited author. References are stripped, as the skill already does
- [ ] Zenodo switch-on for link is an operator step: Zenodo login → GitHub → enable the repo. It is noted in the final report, not done here

## Phase 4: Issues
- [ ] soul: edit #40's body. Company credit in Zenodo needs `cph` in cffr's `authors_roles` in the `/citation-cff` skill and its workflow template, plus a fleet sweep: company in Authors@R, ORCID consistency, regenerate CFFs. Link #39
- [ ] File the soul issue: convention draft v0, link#338 as the worked example, the 12 sibling issues as the next applications, and an open question on a canonical ecosystem table
- [ ] File the link issue for the fresh v0.40.0 pin bump
- [ ] Edit link#338's body: the pkgdown task is dropped (prefix families already group), the pin bump moves to its own issue, and the convention issue is linked

## Validation
- [ ] Build the site locally (`pkgdown::build_site()`, or `build_home()`). Read the rendered home page; the figure and all links resolve
- [ ] `devtools::check()` clean on DESCRIPTION
- [ ] Grep the README and DESCRIPTION: every function named is exported, there is no version string in prose, and there is no "will / by design / designed to"
- [ ] `/code-check` clean (once over the branch)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

## Validation (skill frame)

- [ ] Tests pass
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
