# Code-check round 3 (link#476)

Reviewed: branch diff against `origin/main` at 15ca442e (diff_r3.patch), round 2's fix first
(diff_r2fix.patch), in the worktree `rev3` at a3787a76. rev3 left clean (`git status` empty
after every probe).

## Checklist read

- **code-check.md**: all 14 sections under `## Mechanisms`, prose read in full (tables skipped).
  Not read in full: the 24 standalone, Security and Spreadsheets/PDFs headings (index lines
  only; none names a tool or shape this diff uses beyond "Documentation Staleness", which the
  index covers).
- **code-check-r.md**: read 9: "Read-back shape must match write-back shape"; "`file(open = "wb",
  encoding = )` does not re-encode on write"; "`strsplit()` drops a trailing empty field, so a
  trailing separator vanishes"; "A `data-raw/` script must load the source tree, not the
  installed package"; "`vapply(..., USE.NAMES = FALSE)` strips ALL dimnames, row names
  included"; "`sort()` and `order()` collate by `LC_COLLATE`, so a canonical form is
  locale-dependent"; "`$` on a list partial-matches, so a longer sibling key answers for a
  missing one"; "`match()` treats NA as a matchable VALUE, so two unknowns join to each other";
  "Regenerated binaries churn git even when nothing changed". Not read: 121.
- **code-check-shell.md**: read 0 (the diff has no shell). Not read: 73.
- **code-check-spatial.md**: read 0 (no spatial code). Not read: 96.

## The mechanism behind rounds 1 and 2

Two lists that happen to agree, checked only against the renderer's own output:

1. **Escaping**: `cell()` escapes an enumerated set of markdown-significant characters (round 1:
   `|` and newline; round 2: `<` and `>`), and the set is "the characters a reviewer has seen
   break". It agrees with the dictionaries only for the characters they happened to contain
   when each round looked. The guard that should catch the next one cannot: the README test
   compares the shipped file with `.lnk_dictionary_readme()` (the renderer checked against
   itself), and the escaping test asserts the markdown *source* string, never what a markdown
   parser displays. So each round finds one more character class.
2. **Encoding**: the renderer's reader and the test's reader were made to agree on UTF-8 in
   round 2, but the third party to that agreement, the writer in
   `data-raw/dictionary_readme_build.R`, still uses the native encoding.

Where the mechanism reaches in this diff, each checked:

| place | checked how | result |
|---|---|---|
| `cell()` prose escaping, all nine shipped dictionaries | rendered the README with `commonmark::markdown_html(extensions = "table")` (cmark-gfm, as GitHub) and compared every `td` text with its CSV cell, backticks removed (script `scratchpad/mdcheck.R`) | **1 cell loses text** (finding 1) |
| `cell()` code-span splitting: empty cell, leading backtick, trailing backtick (strsplit's dropped field), `|` inside a code span | probed through commonmark (`scratchpad/celltest.R`) | all render correctly |
| `cell()` odd number of backticks, a doubled-backtick span, an escaped `` \` `` | same probe | parity inverts: an unmatched backtick leaves the text after it unescaped, so `a `b<c>` drops `<c>`; ``` ``a`b`` <d>``` drops `<d>`. **No shipped dictionary cell has an odd count, a doubled span or a backslash** (counted: 0), so not reachable today |
| renderer read encoding (round 2's fix) | `LC_ALL=C` run of test-dictionaries.R | README tests pass (4 + 3 expectations) |
| README writer, `data-raw/dictionary_readme_build.R` | wrote the README under `LC_ALL=C` and compared bytes with the shipped file | **differs** (finding 2) |
| `.lnk_dictionary_columns()`, `.lnk_species_residence()`, `lnk_rules_build()` reads | no `encoding =`; values read are ASCII (species codes, `resident`/`anadromous`, column names); no BOM on any shipped `dimensions.csv` | not reachable |
| column headers and section titles in the README (not passed through `cell()`) | all ASCII words | not reachable |
| dictionary file pattern `^dictionary_[a-z_]+\.csv$` | renderer and test share it by copy; every shipped dictionary matches | agrees today; a name with a digit would be invisible to both |

## Findings

- **[bug]** R/lnk_dictionary_readme.R:27-33 (`cell()`), shipped in inst/extdata/configs/README.md:27 —
  the `rear_near_river` description contains `(<stage>_river_*, fresh#263)`. After round 2 it is
  written `(&lt;stage&gt;_river_*, …)`; the `_` after `&gt;` is left-flanking (preceded by
  punctuation) and the second `_` right-flanking (followed by `*`), so cmark-gfm renders
  `(&lt;stage&gt;<em>river</em>*, …)`: GitHub shows "(<stage>river*", the parameter name's
  underscores gone and "river" italic. Same class as round 2's `<stage>` drop, one character
  over; round 2's fixture `(<stage>_x, …)` has no closing `_`, so it cannot reach emphasis.
  `*`, `[…](…)`, `&lt;`-as-text and `\` are open the same way (probe: `a*b*c` → `abc`,
  `[x](y)` → `x`, `&lt;` → `<`). A fix that ends the class rather than this instance:
  backslash-escape markdown punctuation in the prose parts, e.g.
  `parts[prose] <- gsub("([][\\*_<>&~])", "\\\\\\1", parts[prose])` in place of the `&lt;`/`&gt;`
  line, done before the `|` → `\|` escape so the backslash pass does not double it. Probed in
  rev3 (then restored): 0 mismatches across all nine shipped dictionaries through commonmark,
  and the `*`, `_`, `[`, `&`, `\` probes render as typed. The guard that would hold it: the
  commonmark cell comparison above as a test (`commonmark` is not in DESCRIPTION; it would need
  Suggests and `skip_if_not_installed()`), since the two existing tests read the renderer's
  own output.
  - **Rule:** code-check.md "Verification that reads its own output"

- **[fragile]** data-raw/dictionary_readme_build.R:12-13 — `writeLines(.lnk_dictionary_readme(dir), …, sep = "")`
  re-encodes UTF-8-marked strings to the native encoding (`useBytes = FALSE`). Under
  `LC_ALL=C` the documented rebuild command writes `<U+2014>` for each em dash (three cells of
  `dictionary_dimensions.csv`, e.g. `rear_stream_order_child_max`); measured: that README's md5
  differs from the shipped file. The README test then fails, so it is loud rather than silent,
  but the remedy the test prints ("rebuild with data-raw/dictionary_readme_build.R") does not
  repair it in such a session. This is the writer half of round 2's encoding fix, which aligned
  only the two readers. `writeLines(..., sep = "", useBytes = TRUE)` writes the shipped bytes
  under `LC_ALL=C` (measured: md5 identical).
  - **Rule:** code-check-r.md "`file(open = "wb", encoding = )` does not re-encode on write"

## Round 2's fix, reviewed

- Backtick splitting: correct for an empty cell (`strsplit("")` is `character(0)`, returned as
  is), a leading backtick (leading empty field kept, so parity holds), and a trailing backtick
  (strsplit drops exactly one trailing empty field; `endsWith()` puts one back; `` a`` `` round
  trips). `|` escaped before the split renders correctly inside a code span.
- Odd, doubled or escaped backticks invert the prose/code parity (table above); not present in
  any shipped dictionary.
- `encoding = "UTF-8"` on the renderer's read: correct; tests pass under `LC_ALL=C`.

## Elsewhere in the diff (checked, no finding)

- `.lnk_species_residence()`: default's and bcfishpass's `residence` / `rear_no_fw` reproduce
  the coded sets (CM, PK spawn-only); every bundle's `cfg$species` has a `dimensions.csv` row,
  so the "no row" stop cannot fire on a shipped bundle; extrabreaks / rearbreaks lack the column
  and fall back.
- `wsg_recompute_one.R`: `cfg` is defined (line 73 uses it) before `.mc_persist(..., cfg = cfg)`.
- `log_variant_pass()`: variant cfg's `pipeline$schema` is the variant's own schema (written by
  `write_bundle()`), so the `DELETE` cannot reach `fresh`/`fresh_default`; every inserted column
  exists in the log DDL, only `run_id`/`watershed_group_code`/`date_start` are NOT NULL and all
  are supplied; `.lnk_near_river_text()` returns `""`, never length 0.
- Tokens: `default`, `default_tuned`, `default_minimal`, `default_parent` and `bcfishpass`
  still resolve (`acc-v7`, `acc-bcfp-5`, …) with the new `residence` column.
- `lnk_rules_build(check.names = FALSE)`: no shipped `dimensions.csv` has a BOM or a header
  that `make.names()` would change.
