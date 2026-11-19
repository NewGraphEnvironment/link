# Code-check round 3 (link#472, backlog move 4)

Reviewed at 85839dcd (worktree wt_cc) plus the uncommitted NEWS.md / DESCRIPTION 0.86.0 entry.
Diff: `git diff db4a7710...HEAD` minus the bulky presence_check output, model_diff.csv and the stall TSV.

## Checklist read

- code-check.index, code-check-r.index, code-check-shell.index, code-check-spatial.index: read in full.
- code-check.md: the prose of all 14 H3s under `## Mechanisms` (table rows skipped): A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice. The 24 standalone/security/spreadsheet H3s: not read in full (index only).
- code-check-r.md, full sections read: "`$` on a list partial-matches, so a longer sibling key answers for a missing one"; "CSV whitespace: `trim_ws` and `strip.white` do not do what the name suggests"; "Read-back shape must match write-back shape"; "`match()` treats NA as a matchable VALUE, so two unknowns join to each other"; "`identical()` on two reader results tests the reader, not the file"; "`read.delim()` quotes by default, so a `"` in a field silently swallows rows"; "`nzchar(NA)` is TRUE — non-empty checks silently pass NA". The other ~115 headings: index only (no tool or shape they name is used here beyond the ones read).
- code-check-shell.md: 0 sections read in full (72 not read); the diff carries no shell changes beyond a CSV row map.
- code-check-spatial.md: 0 sections read in full (94 not read); no spatial code in the diff.

## The mechanism behind round 1

One role (the exclusion list; the presence table) is now split across two bundle files: bcfishpass's copy plus link's own rows (`observation_exclusions_link`) or link's cells (the overlay). Every reader and guard written when the copy was the only file carried an assumption that held only for that single file:

- typing: read.csv's per-file column typing was safe on the copy's large hex-key population and not on a 3-row link table (finding 1);
- lookup: `$observation_exclusions` was unambiguous until a sibling key with that prefix existed (finding 2);
- meaning: "the data_error rows" meant "bcfishpass's known errors" until link's rows joined them (finding 3).

So the places to check are every reader of either role, and every second list that must agree with the first (a header, a recall set, a map layer, a pretest row, a dictionary, a provenance entry).

Walked: every `observation_exclusions` / `release_include` / `data_error` reader in R/ and data-raw/ (pipeline prep, validator, presence check, presence measures, query_habitat_thresholds_obs, habitat_variants_score, the presence check and map drivers, the sync); every `lnk_presence()` caller (prep_minimal, pipeline_run, presence_check, habitat_variants_build, wsg_recompute_one) and the acc spec; every by-path reader of the presence CSV (none left outside access_disagree_349.R, accepted); `$` lookups on `loaded`/`files` for prefix siblings of the new keys (none on the new keys; `loaded$user_barriers_definite` vs `_control` is pre-existing and outside the diff); provenance checksums of the five new or converted files (all match their bytes); `read_as: text` with an overlay or canonical_schema; pretest map rows for the new files. Token resolution re-run on the branch for default, default_tuned, default_minimal, default_parent and bcfishpass: all resolve (acc-v6 / acc-bcfp-5). Test files lnk_presence, lnk_csv_sync, dictionaries, lnk_presence_check, lnk_load_overrides, lnk_vocabulary, lnk_overlay: 0 failed, 0 errors (NOT_CRAN=true). The overlay counts NEWS quotes (110 added, 10 removed, 2 kept absent, 4 ko; 126 rows) check against the file.

## Findings

- **[severity: fragile]** data-raw/wsg_species_presence_map.R:70 and :166 — the map's "known errors" ring layer is now `.lnk_observation_exclusion_rows(loaded)`'s data_error rows, i.e. bcfishpass's copy **plus link's three #436 rows**. Its own header (lines 28-33) still says the rings are "the data_error rows of observation_exclusions.csv" and that "recall.csv scores the rules against them", and round 1 deliberately narrowed recall.csv in wsg_species_presence_check.R:305-307 to the copy alone (link's rows were found with these measures, so scoring them is circular). The two scripts now name different sets with the same words: a reviewer reading the map sees three rings (GUIC CH, MESI SK, KOTL ST) as known errors the rules "miss" or "catch" that recall.csv does not score. This is round 1's finding 3 in the sibling script that shares the measures. Fix: take `known_err` from `loaded[["observation_exclusions"]]` as the check does (keep `excl_keys`/`incl_keys` on the union, which is right for counting records), or show link's rows as their own layer and reword the header.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness" ; code-check.md "One fact derived twice"

No other instance of the mechanism found. Not flagged: the pre-existing `suppressWarnings(lnk_load_overrides(...))` pattern in the evidence scripts (no warning is raised on today's bundle; the pattern predates the branch); the pretest map leaving `observation_exclusions` and the presence table off `obs_upstream` (pre-existing for the copy, the new link file only inherits its row).

## Triage (session, 2026-11-18)

**Fixed:** `data-raw/wsg_species_presence_map.R` rings now read `loaded[["observation_exclusions"]]` only, as `recall.csv` does; counting still excludes both. Treated as a defect inside round 1's fix (it reached one of two sibling scripts), so the loop ends on an enumeration, not a quiet round.

**Enumeration** (`grep -rn -E 'observation_exclusion|exclusion_keys|exclusion_rows|release_include_keys|data_error'` over `R/`, `data-raw/*.R`, `data-raw/logs/presence_overlay_431/*.R`, comments and roxygen aside): 15 reader sites, each classed by role against the set it reads.

| role | sites | reads | ok |
|---|---|---|---|
| count records | `R/lnk_pipeline_prepare.R:332`, `R/lnk_presence_check.R:123-124`, `R/lnk_habitat_validate.R:794`, `data-raw/query_habitat_thresholds_obs.R:67`, `data-raw/wsg_species_presence_check.R:121-122,143-147`, `data-raw/wsg_species_presence_map.R:95-96` | union, through `.lnk_observation_exclusion_keys()` / `.lnk_observation_release_include_keys()` | yes |
| known errors to score | `data-raw/wsg_species_presence_check.R:307`, `data-raw/wsg_species_presence_map.R:72,168` | copy only | yes (after this fix) |
| retire report | `data-raw/sync_bcfishpass_csvs.R:274-276` | link rows against the copy, `[[ ]]` | yes |
| turn both off | `data-raw/habitat_variants_score.R:554-555` | both set NULL | yes |
| accepted one-off | `data-raw/access_disagree_349.R:110-112` | copy | accepted |

The helpers themselves (`R/lnk_pipeline_prepare.R:362-414`) read both tables with `[[ ]]` and refuse a non-text link key. Nothing reads a set other than its role's, so the loop ends here.
