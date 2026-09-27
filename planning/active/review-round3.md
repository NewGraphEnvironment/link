# Review round 3 — #290 staged diff (lnk_species_pooling + hash + dictionaries)

Scope: staged diff only. Ran the three affected test files (all green), `lnk_config_verify("default")`
(new checksums match), and probes/mutations on a copy under the scratchpad. No repo file was edited
other than this one.

## The mechanism

All five earlier findings share one assumption: **two independently maintained lists agree on a
key, and a disagreement between them narrows the result silently instead of failing.** The key
was a WSG code (aoi vs presence rows vs the regions frame), a species code (the `species` argument
vs presence columns), or a line number (dictionary `consumed_by` vs the code). Each time, the
disagreement went through a filter-shaped operation — `intersect()`, `==` inside `[`, `[1, ]`, a
filtered subset — whose "no match" output (zero rows, an NA row, a duplicate row, a stale line)
looks the same as a legitimate "nothing applies". The fixes all turn one disagreement into an
error or an assertion. R2's line-ref drift is the same thing with a slower fuse: the two lists
matched when they were written, and nothing re-checked them once the code moved.

## Findings

- **[severity: fragile]** tests/testthat/test-dictionaries.R:236 (the new
  "consumed_by refs land on their column" test): `grepl(d$column[i], line, fixed = TRUE)` is a
  **substring** match. Short column names are substrings of other identifiers on nearby lines:
  `scope` is inside `scope_level`, `pool` is inside `species_pooling`, and `group_code` and
  `species_code` both appear in roxygen and error-message text. So a stale ref that lands on the
  wrong column's line still passes. Proven on a copy: I pointed the `scope` ref at line 231
  (`level <- tolower(trimws(p$scope_level))`) and the test **passed**. A separate mutation on
  `species_code` did fail, so the guard is partial rather than dead.
  Stale shifts within ±15 lines that it still accepts:
  - `scope`: 4 shifts, 2 of them onto `scope_level` lines.
  - `pool`: 5 shifts, 3 of them onto `species_pooling ...` error strings.
  - `group_code`: 3 shifts, one onto a roxygen comment.
  - `species_code` (groups): 2 shifts.
  - `scope_level`: 1 shift.

  This is the same mechanism again: the guard for "two lists agree" compares them loosely enough
  that a disagreement still reads as agreement. A token match fixes it, e.g.
  `grepl(sprintf("(\\$|\")%s(\\b|\")", col), line)`, or `(?<![A-Za-z_])col(?![A-Za-z_])` with
  `perl = TRUE`. Re-run the ±N shift sweep afterwards; the probe is in the scratchpad history
  of this review.

- **[severity: fragile]** R/lnk_species_pooling.R:76 — `utils::read.csv(.lnk_wsg_regions_path(), ...)`.
  When the file is missing from the installed package, `system.file()` returns `""`, and
  `read.table(file = "")` reads **stdin** rather than erroring. The hash side
  (R/lnk_log.R:108) handles `""` explicitly as `MISSING`, so the two consumers of the one path
  disagree on what "missing" means. Today this is latent: the file is tracked and not
  `.Rbuildignore`d. A `if (!nzchar(p)) stop(...)` inside `.lnk_wsg_regions_path()` would close it
  for the resolver. The hash would then need its own `nzchar` test kept, or a `must = FALSE` arg.

## Where the mechanism reaches in this diff, and whether each is guarded

| Place | The two lists | Status |
|---|---|---|
| aoi vs regions (L91) | caller aoi / regions frame | guarded (stop) |
| aoi repeats / case (L72) | aoi vs itself | guarded (unique(norm())) |
| aoi vs presence rows (L110-115) | aoi / presence | duplicates guarded; absence yields no rows (accepted tradeoff) |
| species vs presence columns (L99) | `species` / presence header | guarded (stop) |
| regions rows per WSG (L86, L118) | regions frame vs itself | guarded (unique + not NA; `which()`) |
| region NA for a WSG (L123) | `reg$region` NA gives an NA in the logical index, so an all-NA row enters `hit` | **guarded only incidentally**: the NA row has `target = NA` and is dropped by L125 `hit$target %in% present`. Probed with a caller frame whose region is NA: correct output. Reordering or removing L125 would expose it. Not a current bug. |
| tracker scope vs regions (L243-254) | tracker `scope` / regions | guarded (stop) |
| tracker codes vs species/groups (L255-261) | tracker / groups / presence header | guarded (stop) |
| group members vs species; group vs species name clash; nesting (L188-202) | groups / presence header | guarded (stop) |
| known_species exclusion list (L97-98) vs `.lnk_wsg_species_present()` (R/utils.R:136) | two copies of `c("watershed_group_code", "notes")` that happen to agree | **unguarded, currently benign**. If one list changes without the other, a non-species column either becomes a "known species" or stops being one. No wrong output today. |
| hash gate vs resolver (R/lnk_log.R:104) | `cfg$files$species_pooling` / what the resolver reads | fine for bundles; default and default_tuned both declare the tracker and are hashed. A caller-supplied `regions=` is not what the hash records, but that only affects out-of-scope data-raw callers. |
| missing regions file | resolver (stdin) vs hash (`MISSING`) | **finding 2 above** |
| dictionary columns vs bundle CSVs | dictionary / CSV header | guarded (`expect_setequal`, `expect_gt(length(bundles), 0)`) |
| dictionary line refs vs code | dictionary / R source | guarded, **but loosely: finding 1** |
| ref-landing test under R CMD check | `test_path("..","..","R")` | skips its own block only (the `R/` dir is absent under `.Rcheck`); `expect_gt(n_refs, 0)` prevents a vacuous pass when it does run. Correct. |
| default-bundle test (test-lnk_species_pooling.R:211) | filtered subset | guarded (`expect_gt(nrow(pooled), 0)`) |
| provenance checksums vs new CSVs | config.yaml / files | verified by `lnk_config_verify` (no drift) |

Nothing else found: the precedence logic, the tie/conflict error, group expansion, the
case/whitespace normalisation, and the hash change (a fixed name, radix order, and non-tracker
bundles left unchanged, as the test proves in both directions) all check out.
