# Code-check round 2: #444 (branch 444-parent-attributes-on-the-full-network)

## Checklist read

- **code-check.md**: the prose of every H3 under `## Mechanisms` was read, with its `|` rows skipped. In full: "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output", "A guard's scope, escape hatches, and remedies", "A shared working tree, and what generators leave in it", "Zero-length, empty, and unset are three different things" and "Written data outlives the fix". The other Mechanisms H3s were read only to their first lines. "## Rules that stand alone", "## Security" and "## Spreadsheets and PDFs" were read at index level only. Of 37 headings, 8 were read in full and 29 were not.
- **code-check-r.md**: read in full: "Postgres row order is never fixed unless the query fixes it…", "`sprintf("%g", x)` writes `Inf` and `NA` into SQL as bare words…", "A database driver's value is not a base R type…", "A `data-raw/` script must load the source tree, not the installed package" and "An `information_schema` lookup by the literal table name misses what Postgres resolves". The other headings were checked against the diff at index level. Of 116 headings, 5 were read in full and 111 were not.
- **code-check-shell.md**: index only. The diff has no shell. git is called only through `pretest_git()`, which applies `shQuote()` to each argument. Of 70 headings, 0 were read in full.
- **code-check-spatial.md**: index only. The diff has no spatial code; the join is on measures. Of 94 headings, 0 were read in full.

Verified against the repo and the local fwapg (read-only):
- `fresh_default.streams_parent` holds 5,546,370 rows. That equals `fresh_default.streams`, and the minimal schema holds 4,987,761 rows, which matches the README.
- The sums over `build.tsv` (3.909 min, TESR the longest at 0.05, 96 straddling segments over 0.096 km, max 1 m, 241 ok) match the README and research.
- `verify.tsv` has no `why`.
- The only file that differs between `193cb8aa` and `4dfbfa49` under `PRETEST_LINK_PATHS` is `DESCRIPTION`.
- No log row in either schema has a NULL `date_start` (the column is NOT NULL), so `ORDER BY date_start DESC` cannot pick a NULLS-FIRST row.
- `run_id` is `text`, so `.lnk_quote_literal(bm$run_id)` holds.

Both round-1 fixes hold:
- `--wsgs=` gives `character(0)` and refuses; `--wsgs=,` fails the code regex.
- A pair with zero groups refuses in `verify_groups()`.
- The pathspec form `:(top,exclude)data-raw/logs` reaches git quoted.

## Findings

- **[severity: fragile]** data-raw/streams_parent_build.R:57 (`out <- opt("out", file.path("data-raw", "logs", "streams_parent_444"))`) and RUNBOOK.md (§8d, the new "A run under `default` or `default_minimal` also owes `streams_parent`" paragraph). The default `--out` is #444's committed evidence directory. RUNBOOK §8d tells the operator to run `streams_parent_build.R … --verify` after every `default` / `default_minimal` run, and then "the same command without `--verify`", with no `--out` in either.
  - Every such run therefore rewrites the committed `verify.tsv`, and a rebuild rewrites `pair.tsv` and also deletes and rewrites `build.tsv`. A `--wsgs=BULK` rebuild leaves a one-row `build.tsv`.
  - After that, `data-raw/logs/streams_parent_444/README.md` describes files that no longer hold what it says ("verify.tsv | --verify right after the build … empty for all 241", "build.tsv | one row per group").
  - Nothing stops the overwrite. The round-1 fix excludes `data-raw/logs` from the clean-tree check, so the driver also no longer notices that its own evidence was modified.
  - This is the recurrence CLAUDE.md already records for `habitat_validate.R` ("writes to `data-raw/logs/habitat_validate_283/` unless given `--out=`: a one-off check rewrote the #283 record").
  - Fix: require `--out`, or default it to a timestamped directory or a tempdir, and give RUNBOOK's command an `--out`.
  - **Rule:** none

- **[severity: fragile]** data-raw/streams_parent_build.R:79-86 (`status --porcelain --untracked-files=no -- :(top,exclude)data-raw/logs`). The comment above it says "The code a build loads must be committed".
  - `pkgload::load_all(repo)` at line 64 sources every `R/*.R`, untracked ones included, because DESCRIPTION has no `Collate:`. `--untracked-files=no` hides exactly those files.
  - An untracked file in `R/` can therefore redefine `lnk_streams_parent()` or any helper, or change `pretest_reach()`'s answer, which the pair verdict depends on. The build still passes the check, and `pair.tsv` records `judged_at_link_sha = HEAD` for code HEAD does not hold.
  - `data-raw/pretest_check.R:31`, which the comment cites, does not pass `--untracked-files=no`. This guard is narrower than the one it says it follows.
  - Fix: either drop `--untracked-files=no`, or keep it for the rest of the tree but also refuse untracked files under what `load_all` and the guard read (`R/`, `inst/`, `DESCRIPTION`, `data-raw/pretest*.R`, `data-raw/streams_parent*.R`). An example is a second `status --porcelain --untracked-files=all -- R inst DESCRIPTION …`.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" ; code-check.md "A proxy is not the property"

- **[severity: fragile]** research/minimal_network.md, the new "Parent attributes" section, opening bold sentence: "**Every full segment of the province lies in one minimal segment**". This is false, and the table and bullet three lines below contradict it: 96 full segments straddle a minimal cut, by up to 1.000 m.
  - CLAUDE.md's #415 facts say the opposite outright ("A full segment is not always inside one minimal segment"). The column `straddle_m` exists because of it.
  - A downstream reader such as knowledge's join who takes the research verdict at its lead sentence would assume containment, for example that `straddle_m` is always 0 or that the parent is unique without a largest-overlap rule.
  - Fix: reword to "each full segment takes the minimal segment it overlaps most; all but 96 lie wholly inside it".
  - **Rule:** none
