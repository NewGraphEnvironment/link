# Code-check round 2 — #403 branch (39e9c2c5...f9473c8c)

## Checklist read

- `/tmp/codecheck.shdbGA/index.md`: read.
- `code-check.md` (335 KB): the prose of all 14 H3s under `## Mechanisms`, `|` table rows skipped. The 22 headings under `## Rules that stand alone`, Security and Spreadsheets and PDFs not read.
- `code-check-r.md` (191 KB): 12 sections read in full: "A `data-raw/` script must load the source tree, not the installed package"; "`tolerance` in testthat is RELATIVE, so it pins a published figure far more loosely than it looks"; "Postgres row order is never fixed unless the query fixes it, …"; "An `information_schema` lookup by the literal table name misses what Postgres resolves"; "`system2(stdout = TRUE)` warns on a non-zero exit instead of raising, …"; "A database driver's value is not a base R type — and it fails twice"; "Tests that silently do not run"; "A `skip_if_not()` skips only its own `test_that()` block"; "`sprintf("%g", x)` writes `Inf` and `NA` into SQL as bare words, …"; "Rscript reads a script as it runs, …"; "A value compared as `::text` in SQL has PostgreSQL's spelling, not R's"; "A range total taken as the difference of two large running totals loses the small ranges". 103 headings not read.
- `code-check-shell.md` (132 KB): "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0" read; 69 not read.
- `code-check-spatial.md` (156 KB): nothing in the diff uses its tools; 0 read, 93 not read.

## What was checked

- **The round-1 fix (README.md:46-60).** The printed frame equals `rollup.csv`'s `zz396_default_post` PARS rows in all six metric columns for BT (6882.15 / 842.81 / 6039.34 / 1682.72 / 2624.20 / 40.16) and GR (4441.86 / 596.01 / 3845.86 / 983.83 / 1398.15 / 30.09), not the `_pre` rows (spawning 1683.08 / 983.86 differ). BT's parts sum exactly; GR's to 0.01. It differs from the old 0.68.0 block, as round 1 asked.
- **Default SQL:** both new metrics carry `accessible_km`'s exact `FILTER (WHERE access IN (1, 2))`, so all three are NULL together and a missing code sums to 0; the `CASE … ELSE 0` keeps `double precision`. The rounding bound (each part off by at most 0.005, result a multiple of 0.01) makes the 0.0101 tolerances in the test and `rollup.R` correct. No `fresh_default` group has BT or CO built with nothing accessible (0 each, queried), so the "NA means not built" reading has no live counterexample there.
- **Consumers of the widened frames:** `lnk_habitat_validate()` rbinds per-group rollups and merges by key; `data-raw/habitat_validate.R` sums `cols_km` with `na.rm` (all-NA stays NA) and compares `cols_cmp` by name; `lnk_compare_rollup()` passes its own metrics; no reader selects km columns by position or pattern (grepped `R/`, `data-raw/`).
- **Tests:** the offline test's `part()` reproduces the default strings exactly; the live test's direct sum keeps the rollup's habitat inner join on the full PK; `tolerance = 1e-9` is on unrounded sums of one population.
- **`rollup.R`:** loads the worktree with `load_all()`, stamps HEAD, refuses a dirty `R/`; `LIKE 'access\_%'` escapes the underscore under `standard_conforming_strings`; the `information_schema` lookups use lower-case literal names the persist writes; `DISTINCT ON … ORDER BY date_start DESC` matches the build table in the log README (date ranges, SHAs, hash prefixes).
- **`parity_pieces.sql`:** `access_:sp` interpolates outside any dollar quote; the committed CSV has only `link_only`/`at_start = t` rows, matching the research's "every piece" and "never the reverse"; piece totals equal `observed_diff_km` to 0.01 (PK 4.15 / 4.14).
- **Research numbers:** every "change from #396" cell equals post minus pre in `rollup.csv`; shares, "0.3 % to 42 %", "at most 2.29 km", "within 1.3 km", "1.9 to 29.7 km" all reproduce.
- **`man/lnk_rollup_wsg.Rd`:** the usage section gained a whitespace-only line before `rearing_lake_connection_km =` (roxygen's wrapping); `tools::checkRd()` reports nothing and usage parsing ignores whitespace, so it is cosmetic.
- `.Rbuildignore` covers `data-raw`, `research` and `planning`, so none of the new files ship.

## Clean

No issues found.
