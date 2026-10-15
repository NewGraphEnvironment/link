# Findings — README: lead with intrinsic habitat potential (#338)

## Issue context

## Problem

The README still describes link at roughly its v0.4x shape: an interpretation layer plus bcfishpass reproduction. The package is at v0.65.0, and its core idea, intrinsic habitat potential per species, is not named anywhere a reader lands.

## Findings

**Missing core framing**
- "Intrinsic habitat potential" is not in the README, the DESCRIPTION or the vignette. It was in DESCRIPTION from NEWS 0.18.1 ("three habitat axes (intrinsic potential, accessibility under connectivity, per-feature rollups)") and came out in 05a18135 (2026-04-29). fresh's vignette `habitat-pipeline.Rmd` uses the phrase in its title.

**Shipped but not in the README (underselling)**
- Habitat scored against fish observations: `lnk_habitat_validate()`, `lnk_habitat_validate_band()` (v0.51.0; #283, #284)
- `lnk_species_pooling()` (#290)
- More than one config bundle (`default`, `default_tuned`), and species bcfishpass does not model, such as Arctic grayling (`pars-habitat-connectivity` vignette)
- Discharge gap-fill (v0.58.0); rearing split into stream, lake and wetland (v0.61.0 to v0.63.0)
- Run provenance, `lnk_artifact_*` (v0.64.0); parquet export with a manifest, `lnk_scenario_export()`, `lnk_catalog()`, `lnk_db_load()` (v0.65.0)
- `lnk_rollup_wsg()`, `lnk_mapping_code()`, `lnk_wsg_resolve()`
- The vignette is not linked from the README

**Ahead of the code (overselling)**
- README line 5, "network-agnostic by design": everything runs on the Freshwater Atlas through fresh today. Describe what runs today.

**Cross-package**
- The ecosystem table (README.md:57-63) omits wet. Discharge comes from fwapg's table through the internal `lnk_discharge()` today; reading it from wet is #331. State the current wiring.
- DESCRIPTION `Remotes:` pins `fresh@v0.39.0`; fresh is at v0.40.0.

## Tasks

- [ ] Open with intrinsic habitat potential per species, access, and the barrier in the way
- [ ] Restore intrinsic potential in DESCRIPTION
- [ ] Add a "what it does" section covering the capabilities above, and link the vignette
- [ ] Replace the network-agnostic claim with what runs today
- [ ] Update the ecosystem table: wet, and the current discharge wiring
- [ ] Group the `_pkgdown.yml` reference index by purpose. It has no `reference:` sections today, so the docs site shows a flat alphabetical list.

## Context

Audited 2026-10-14 against `origin/main` @ `1e84df2`, from README, DESCRIPTION, NEWS, NAMESPACE and vignettes. Verify each item against the code before acting. Versions cited are where a capability landed.

The New Graph website will describe this package from its README (NewGraphEnvironment/newgraphenvironment.github.io#53), so the README is the source of truth for the public one-liner. Plain language in the opening paragraph: what it does today, and what restoration planning, implementation or monitoring decision it informs.


## Errors Encountered

| Error | Resolution |
|-------|------------|

## Research: exemplar READMEs and guides (2026-10-14)

Read raw: dplyr, dbplyr, httr2, sf, terra, targets, osmdata, duckdb (R), RPostgres, polars, ruff, ripgrep; guides r-pkgs.org (https://r-pkgs.org/other-markdown.html), rOpenSci devguide (https://devguide.ropensci.org/pkg_building.html#readme), Art of README (fork https://github.com/bradparks/art-of-readme; hackergrrl original 404s), makeareadme.com.

- **Order:** name + logo → badges → 1–3 sentence pitch → install → usage with output → docs links → help / citation. R exemplars run 92–249 lines.
- **Opening:** what it is, what problem it solves, what it builds on. dbplyr: "dbplyr is the database backend for dplyr. It allows you to use remote database tables as if they are in-memory data frames by automatically converting dplyr code into SQL." targets opens on the problem class first. rOpenSci: answer "what does it do? why should a potential user care?"; name the external source in a clause ("…, an online repository of Goober sightings in South America").
- **Example:** one example whose output is the payoff (dbplyr `show_query()`, httr2 `req_dry_run()`). makeareadme: "Use examples liberally, and show the expected output if you can."
- **Docs:** one line per vignette saying what it is for (targets; rOpenSci "descriptive links to all vignettes").
- **Related packages and non-goals:** osmdata "Other approaches"; duckdb "Goals and non-goals"; ripgrep "Why shouldn't I use ripgrep?".
- **Left out by every R exemplar:** function tables, roadmaps, changelogs. Art of README: "The ideal README is as short as it can be without being any shorter."
- **Heavy setup:** run against a stand-in (dbplyr's in-memory SQLite), show code unrun with assumptions stated (RPostgres), or lead with a figure / screenshot (ripgrep, ruff). rOpenSci: list "Any additional setup required".

## Research: NGE package READMEs (21 surveyed, 2026-10-14)

- **Strongest:** flooded (plain opening; a section on the restoration decision it serves), wet (scope accurate to today; admits what is not built), crate (problem stated plainly; real output; "What crate handles today"). cred's opening is a model.
- **Weakest:** fpr (no structure, dated text), xciter / rake (no stated purpose), spacehakr (stale function table, WKT wall, no "why").
- **Recurring defects:** roadmaps listing shipped work (link lists `lnk_score()`; gq lists `gq_tmap_legend()`); "by design / designed to / agnostic" ahead of the code (fresh, link); function tables or lists (spacehakr, roli, ngr, cd, rfp, fresh); version strings in prose (fly, fpr, crate, trap); vignette lists out of step (wet says "both", has 3); no license section (drift, cd, crate, fly, trap, fpr, breaks, diggs); inconsistent badges.
- **Ecosystem tables disagree:** fresh is "modelling engine" in three READMEs and "data layer" / "FWA queries" in four; membership differs per package; pipelines conflict on whether breaks sits in the land-cover chain. Proposal: one canonical table, generated into each README.

## README convention draft v0

Sources: the two surveys above; soul `writing.md`; `r-packages.md` §README; website#53 copy rules; operator direction 2026-10-14.

**Voice.** Technical, honest, plain. Present tense: what it does today. Show, don't tell — every claim is something a reader can check (a figure of real output, a function, a vignette, a measured result). No adjectives that cannot be checked, no comparative boasting, no claims ahead of the code ("will", "by design", "designed to").

**Descriptions come first.** DESCRIPTION `Title` / `Description` (or pyproject `description`) and the README's opening paragraph are what people see — GitHub cards, pkgdown, the website. Write them together so they say one thing, and check each clause against code.

**Order.**
1. Name, hex sticker (same size and place in every repo), one-line tagline.
2. Opening, 1–3 sentences: what it does, on what data, and what restoration planning, implementation or monitoring decision it informs.
3. Show: a figure (spatial / visual outputs) or a short example with its real printed output (data / plumbing packages). Never a decorative image.
4. Install, then Setup (database, env vars, credentials) stated as a step.
5. What it does, grouped by purpose, naming an entry function per group. Not a function table.
6. Documentation: pkgdown link plus one line per vignette on what it shows. Keep the list in step with `vignettes/`, or link the articles index only.
7. Ecosystem / related packages: roles worded the same in every repo.
8. Data and methods it builds on: name what the package actually reads or follows, and from whom.
9. Citation (from CITATION.cff, company as an author), License, NOTICE where data is redistributed.

**Figures.** Produced by the package from a committed `data-raw/readme_*.R`; saved at `man/figures/readme-*.png` (the website reuses it); styled through gq; passes `cartography.md` checks 1–12 at its published width; a one- or two-sentence caption saying what it shows.

**Leave out.** Roadmaps (link the issues instead), changelogs (NEWS), function tables (pkgdown), version strings in prose, counts of published things, internal hosts or private repos.

**Open.** A canonical ecosystem table in soul generated into each README; README.Rmd vs README.md where examples cannot run without a database.

## Corrections made while writing

| Claim drafted | Code says | Resolution |
|---|---|---|
| bcfishpass CSVs synced daily | `sync-bcfishpass-csvs.yml` cron `0 11 * * WED`: weekly | README says weekly; CLAUDE.md's "daily csv-sync" (#76 note) is historical |
| discharge gaps filled (all configs) | `discharge_fill: true` only in `default_tuned` | README scopes it to `default_tuned` |
| connected lake/wetland rearing (all configs) | `default` dimensions, SK/KO excepted | README scopes it to `default` |
| `bcfishpass` config "reproduces" the classification | parity is close, not exact (segmentation, #324) | README: "applies bcfishpass's own rules and thresholds" |
| link ORCID `0009-0003-7697-6064` | fails R's checksum | DESCRIPTION uses `0000-0002-3495-2128`, as fresh/flooded/drift/gq |
| cffr output for link | `doi: 10.32614/CRAN.package.link` and `repository: https://CRAN.R-project.org/package=link`, an unrelated CRAN package (soul#365) | One-off and workflow drop both (`x$doi <- NULL; x$repository <- NULL`); company enters via `authors_roles = c("aut", "cre", "cph")` |
| README: access resolved past crossings and dams | access set is natural barriers only; crossings and dams annotate token2 (`lnk_pipeline_run.R:252-264`, `lnk_barriers_views.R:20-33`) | Descriptions say access is resolved past falls and gradients, and crossings and dams are recorded below each reach |
| README: `lnk_aggregate()` sums habitat upstream of each crossing | same `blue_line_key`, higher measure; no network walk; not per species; persisted habitat tables lack its key columns; no caller in the repo | Dropped from README. Gap: per-crossing upstream habitat, network-walked and per species, is not in link today |
| Figure: grey = "not classified for grayling" | grey = empty grayling code = above a grayling natural barrier (all 78,305 PARS segments, `has_barriers_gr_dnstr`) | Relabelled |
| README "and which barrier it is" | per-reach output keeps barrier-source flags only; id arrays not persisted (`lnk_persist_init.R:50-54`) | "what kind of barrier it is" |
| "Every link config reads ... synced weekly" | sync covers `bcfishpass` and `default` only; `default_extrabreaks` / `default_rearbreaks` hold older own copies (`extends: ~`) | scoped. Possible follow-up: put the two variants on `extends: default` |
| `user_crossings_misc` listed as read | loaded, then `.lnk_crossings_union()` drops and rebuilds `crossings` without it | dropped from README |
