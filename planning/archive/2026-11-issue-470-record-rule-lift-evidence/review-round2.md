# Code-check round 2 — #470 (branch vs 2da2db35, head d6d1ba06)

## Checklist read

- code-check.md: the prose of all 14 H3s under `## Mechanisms` (A guard that fails toward pass;
  A fixture that cannot reach the failure mode; A proxy is not the property; Verification that
  reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two
  callers that share a harness; Restore the bug and prove the guard fires; A shared working tree,
  and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset
  are three different things; The probe is broken before the world is; Written data outlives the
  fix; Serialization loses meaning silently; One fact derived twice), table rows skipped. Not read:
  the 27 standalone / security / spreadsheet headings.
- code-check-r.md: "Postgres row order is never fixed unless the query fixes it, …"; "An
  `information_schema` lookup by the literal table name misses what Postgres resolves"; "`match()`
  treats NA as a matchable VALUE, …"; "`ifelse()` with an all-NA test returns a logical vector, …";
  "`$` on a list partial-matches, …"; "Cross-function consistency for label/string normalization"
  (index line). Not read: the rest (about 150).
- code-check-shell.md: none read in full beyond the index (the shell changes are a list literal, a
  heredoc-driven negative test and harness scripts); about 100 not read.
- code-check-spatial.md: none read; no spatial tool in the diff.

## Round-1 fixes

- (1) `lnk_barrier_overrides()` now reads `species_code_recorded` from `SELECT * FROM <obs> LIMIT 0`,
  so a temp table, a search_path name or case resolve as Postgres resolves them; the DB test runs it
  on a `pg_temp` table. Correct.
- (2) `study_area_verify_negative.sh` 6j–6l: a run with no log row at 0.84.0 or later is skipped and
  not counted; a newer run is judged as it stands, with the evidence and overrides copied for the
  scratch log's groups. Correct.

## Findings

- **[severity: bug]** R/lnk_presence_check.R:89-103 with :139-158 — the presence check resolves an
  alias code to its target (line 101) *before* it applies the pooled rows (merge at line 153). So a
  record whose alias target is itself pooled into another species is counted twice over: an `ADV`
  record becomes `DV` and then pools into `BT` through the `BT <- DV` row wherever DV pools into BT.
  The record rule the pipeline reads (`lnk_species_pooling()` → `.lnk_observation_species_map()`)
  resolves each tracker row on its own, with no transitive step. Under that rule ADV counts as DV
  only. `species_pooling.csv` row 13 says so too ("in a region where DV pools into BT it does not
  count as BT through DV"), and the function's doc promises the codes are read "as the pipeline
  reads them". Measured: 2 ADV records sit in pooled groups (LIAR 1, SHUL 1). Each adds 1 to
  `n_kept_pooled` for BT there. Neither changes a flag today, because BT has 42 and 13 records of
  its own in those groups. But the review tracker's numbers for those cells disagree with the rule
  the model applies. The same error will reach any later alias whose target pools into another
  species. Fix: run the pooled merge on the records' recorded codes (before the alias fold), or
  drop pooled rows whose source record was an alias.
  - **Rule:** code-check-r.md "Cross-function consistency for label/string normalization"

Nothing else found. Checked and clean:
- the pairs temp table and its lift / evidence inserts (column order, DISTINCT, threshold, date,
  control filter);
- the persisted evidence PK against what the working table can hold (vocabulary refuses a duplicate
  `parameters_fresh` species);
- persist, consolidate and drop-partials lists;
- the verify block's version gate;
- the observation table build and its VALUES typing;
- the floor-mix refusal;
- the vocabulary specs (all of `default`, `default_tuned`, `default_minimal`, `default_parent` and
  `bcfishpass` resolve at HEAD);
- `pretest_inputs.csv` rows (`obs_upstream.sql` exists);
- the measurement scripts: `pre_post_diff.R`'s AFTER rule is unchanged between the 09e8339d build
  and HEAD apart from renames, and `lifts_426_427.R`'s floor swap is checked by its own
  `stopifnot`.
