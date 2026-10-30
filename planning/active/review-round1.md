# Code-check round 1 — #403 branch (39e9c2c5...c8f78f17)

## Checklist read

- `/tmp/codecheck.shdbGA/index.md`: headings and index lines read (it mirrors the CLAUDE.md index).
- `code-check.md` (334 KB): the prose of all 14 H3s under `## Mechanisms`, `|` table rows skipped. None of the `## Rules that stand alone` / Security / Spreadsheets sections read (about 23 headings).
- `code-check-r.md` (191 KB): read in full the sections "A `data-raw/` script must load the source tree, not the installed package", "`tolerance` in testthat is RELATIVE…", "Postgres row order is never fixed…", "An `information_schema` lookup by the literal table name misses what Postgres resolves", "`system2(stdout = TRUE)` warns on a non-zero exit…", "A database driver's value is not a base R type…", "Tests that silently do not run", "A `skip_if_not()` skips only its own `test_that()` block", "`sprintf("%g", x)` writes `Inf` and `NA` into SQL…", "Rscript reads a script as it runs…". The other ~105 headings not read.
- `code-check-shell.md` (132 KB): "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0" read; the other ~69 not read.
- `code-check-spatial.md` (156 KB): nothing in the diff uses its tools; 0 headings read (93 not read).

## What was checked

- Default SQL: the two CASE sums carry the same `FILTER (WHERE access IN (1, 2))` as `accessible_km`, so NULL together and 0 for an absent code; the rounding bound (each column a multiple of 0.01, error at most 0.015, so at most 0.01) makes 0.0101 correct.
- `tests/testthat/test-lnk_rollup_wsg.R` run with `NOT_CRAN=true` against local `fresh_default`: 16 blocks, 0 failed, 0 errors, 0 skipped (both live blocks ran). No `fresh_default` group has BT code 2 without code 1 (0 of 157), so the unordered `LIMIT 1` pick cannot trip `expect_gt(r$unobserved, 0)`.
- Every consumer of the default frame or the validator's `summary` reads columns by name (`habitat_validate.R`, `habitat_variants_score.R`, `parity_crosssection.R`, `wsg_vignette_data.R`, the log scripts); `lnk_compare_rollup()` passes its own metrics.
- README block re-run locally (`fresh_default`, width 80): byte-identical to the committed output.
- `rollup.csv`: 50 rows, max identity gap 0.01, no NA `accessible_km`, `share_observed` reproduces exactly. Every number in `research/known_suspected_km.md`'s two tables (accessible, observed, share, pre/post change; parity) matches the CSVs, as do "within 1.3 km", "0.3 % to 42 %", "at most 2.29 km", the 1.9 to 29.7 range, and the piece totals against the gaps (PK 4.15 against 4.14).
- `stamp.txt` against the log README's build table (SHAs, hash prefixes, UTC ranges): matches; `date_end` is `timestamptz` and RPostgres prints it in UTC.
- bcfishpass claims: `aw_linear_summary()` at `620dbe43` uses `access_bt = 2` / `= 1` for `_obsrvd_` / `_model_`; `3bd2824c` (2026-10-23) fixes `access_st`, PR 939 "Fixes #938"; `a7373af` is an ancestor of `3bd2824c`.

## Findings

- **[severity: fragile]** README.md:46-61 — The refreshed output is real output of `lnk_rollup_wsg()`, but from the 0.68.0 `fresh_default` build, while the code shown above it, `lnk_pipeline_run(conn, aoi = "PARS", …)` under `default` at this release, re-segments PARS (#326, then `top_per_species` from #396) and does not reproduce these numbers. #396's 0.69.1 build of PARS under `default` (`zz396_default_post`, `rollup.csv`) gives BT 6882.15 accessible, 842.81 observed (README: 6883.03 / 841.45) and BT rearing 2624.20 (README: 2632.99). A reader who runs the block gets different numbers from the ones printed under it. The previous block had the same shape (an older build), but this branch re-pasted it and the progress log calls it "real output". Either say which build the output comes from, or take it from a build at the current code.
  - **Rule:** none

No defects found in the R code, the SQL, the tests or the measurement scripts.
