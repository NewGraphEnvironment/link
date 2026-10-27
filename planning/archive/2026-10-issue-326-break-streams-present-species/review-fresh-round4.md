# Review: fresh `269-frs-order-child-width-gradient`, round 4 (`18b94fe..HEAD`)

Commits reviewed: `7462772` (`channel_width_lt` -> `channel_width_max`, `<` -> `<=`) and
`43ca870` (NEWS "Closes #269").

## Checklist read

- `code-check-infra.md` (38,115 bytes): in full.
- `code-check.md`: the prose of all 14 `## Mechanisms` H3s (table rows skipped), plus
  "Documentation Staleness" and "An assertion that matches an interpolated value cannot see
  the claim around it". Not read: the remaining 16 standalone rules, Security, Spreadsheets/PDF
  (the diff touches no shell, YAML, secrets, URLs, PDFs or dispatch chains).
- `code-check-r.md`: "Tests that silently do not run", "`expect_gt()` and friends take no
  `info`", "Inserting a helper between a roxygen block and its function rebinds `@export`",
  "Under `R CMD check`, tests run from a temp dir against the INSTALLED package", "`\<` and
  `\>` are word boundaries", "`sprintf("%g", x)` writes `Inf` and `NA` into SQL",
  "A `pkg::` call in a test ... undeclared", "A `function(...)` mock hides arguments the real
  callee no longer accepts". Not read: the other ~100 headings (no file I/O, dates, dplyr,
  arrow/duckdb, ggplot, yaml, Rmd, or network in the diff).
- `code-check-shell.md`: 0 headings (no shell in the diff).
- `code-check-spatial.md`: 0 headings (no sf/terra/GDAL/bcdata in the diff).

## Invariants checked (all measured, fresh checkout read-only)

| invariant | result |
|---|---|
| Old name gone | `git grep channel_width_lt` over the whole tracked tree: 0 hits. The caller (link `R/lnk_pipeline_classify.R:232`, `lnk_preflight_fresh.R:135`) already passes `channel_width_max`. |
| "below" / strict wording | Only two remain: `R/frs_order_child.R:13` (biology paragraph about FWA width being below the species threshold, unchanged and not about this test) and `:39` ("bcfishpass tests below the minimum (`<`)", the deliberate statement about bcfishpass). `width_known_below_min` kept by operator decision. No "strictly" or "sub-minimum" anywhere. |
| Tests pin `<=` | Mock test matches `s\.channel_width IS NOT NULL AND s\.channel_width <= 1\.5\b` and `<= 2\b`; a `<` emission produces `< 1.5`, which contains no `<= `, so it would fail. Live test adds segment 6 at exactly the bound and expects `n == 2L` and ids `c(3L, 6L)`; under `<` it would be 1 and `3L`. `.frs_sql_num()` renders `1.5`, `2`, `0.1049` exactly as the regexes expect (run under `load_all`). |
| Rd matches roxygen | Deleted `man/frs_order_child.Rd` in a temp copy of the package, ran `roxygen2::roxygenise(roclets = "rd")`, saw `Writing 'frs_order_child.Rd'`, and the regenerated file is byte-identical to the committed one. |
| Validation loop covers both formals | `for (nm in c("channel_width_max", "gradient_max"))` with `get(nm)`; the refusal test loops five bad values over both names and matches each name's message. |
| NEWS | "Closes #269" added; the bullet says "at most the value" for `channel_width_max`. Consistent with the Rd. |
| `frs_params.R` comment | Reads "at most the rule's width minimum ... `channel_width_max` and `gradient_max`"; the key name `width_known_below_min` is unchanged by design. |
| Doc claim about where `<=` and `<` differ | "the two differ only on a line the ordinary rule does not cover" is right: a line at exactly the minimum passes the ordinary rule's `>=`, so the exception changes its outcome only where it failed the ordinary rule for another reason (and the function only writes where `rearing IS NOT TRUE`). |

Accepted tradeoffs from earlier rounds not re-raised.

## Clean
No issues found.
