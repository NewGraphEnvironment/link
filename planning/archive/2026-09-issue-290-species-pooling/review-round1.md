# Code-check review, round 1: `lnk_species_pooling()` (#290, commit 2 staged diff)

Reviewer: subagent, 2026-09-26. The tree was not modified; probes ran in R through `pkgload::load_all()` with scripts in the session scratchpad.

## Findings

- **[fragile]** R/lnk_species_pooling.R:71 and the `lapply(aoi, ...)` at :90. `aoi` is normalised but never de-duplicated, so a repeated or case-variant WSG gives a repeated block of rows. Measured: `aoi = c("MORR", "MORR", "morr"), species = "BT"` returned 6 rows, BT<-BT three times and BT<-DV three times, where 2 were expected. The output is meant to be joined against observations by the validator and drivers in the next commit. A duplicated pooling row fans that join out and double-counts evidence without raising anything. `species` does not have this problem because `intersect()` de-duplicates it. Fix: either `aoi <- unique(norm(aoi))` or stop on `anyDuplicated(norm(aoi))`.

- **[fragile]** R/lnk_species_pooling.R:94 (`present <- intersect(species, ...)`). A model species that is not a known species code, such as a typo like `"BTT"` or a code missing from the presence columns, is silently dropped. Measured: `species = "BTT"` returns a 0-row frame, which looks exactly like "absent from this WSG". `known_species` is already computed at :83, and the tracker side already fails loud on unknown codes (`expand()`, :231). Fix: `stop()` on `setdiff(species, known_species)`, which makes the two sides consistent.

- **[fragile]** R/lnk_species_pooling.R:96 (`regions[regions$watershed_group_code == w, ][1, ]`) and :92 (`presence[... == w, ]` then `prow[1, ]`). Logical indexing with an NA key produces an all-NA row in position order. With a `regions` frame that has an NA `watershed_group_code` row ahead of the real one, `[1, ]` picks the NA row, `reg$region` becomes NA, and region rules silently stop applying. Measured: `regions = data.frame(watershed_group_code = c(NA, "W1"), region = c("South", "North"))` with a `North` pooling row gave W1 only its self row. The shipped `wsg_regions.csv` has no NA or duplicate codes (verified), so this bites only on a caller-supplied `regions` or a future edit to the lookup. The code also never checks that `regions` has the `region` / `subregion` columns or a unique code column. Fix: `which()` instead of the logical index, plus a uniqueness/NA check on `regions$watershed_group_code`.

## Checked and fine

- read.csv coercion: `pool = TRUE` is caught ("pool must be yes or no"). A scope of `NA` read as NA is caught ("empty scope"). All-empty subregion columns and `na.strings = ""` on the lookup behave. Empty or whitespace cells are caught per column.
- Zero-row tracker and groups, a one-row tracker (`mapply` path), and no pooled rows surviving: all give correctly typed empty or self-only frames.
- Group expansion that gives the same pair from two rows: it resolves deterministically to the lowest rule number, and a tie that disagrees on pool errors. Overlapping groups, and group codes that clash with species codes or with nested groups, are rejected.
- Output order and rownames are deterministic. The keys are upper-case ASCII codes, so locale collation does not change the order.
- Provenance: `lnk_config_verify()` is clean for `default` and for `default_tuned`, which inherits via `extends:`. The config, config_verify, stamp, load, log, load_overrides, dictionaries and species_pooling test files all pass, and `data-raw/audit_configs.R` exits 0. Adding a `files:` entry changes `default`'s config_hash. That is expected for a changed bundle and breaks no pinned test.
- Dictionary `consumed_by` line refs (205/211/217/238/239) point at the lines that read those columns.

## Note, not a defect

`default_extrabreaks` and `default_rearbreaks` are standalone (`extends: ~`) copies of `default` and do not declare the tracker, so under those bundles nothing is pooled. That matches the documented no-tracker fallback. It does mean a validator run on them will score BT without DV evidence while `default` / `default_tuned` pool it. Worth deciding on purpose before the consumers land.
