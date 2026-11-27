# Code-check round 3: link#477 (branch 477-backlog-move-9-mapping-codes-as-rules-an vs 82cf1d08, at 238504a9)

## Checklist read

- **code-check.md:** the prose of every H3 under `## Mechanisms`, table rows skipped. The two that apply here were read closely: "A guard's scope, escape hatches, and remedies" and "A fix lands in one of two callers that share a harness". Of the standalone rules, "Documentation Staleness" was read. About 30 other standalone headings were not read (security, spreadsheets, URLs, YAML): this diff uses none of them.
- **code-check-r.md:** these were read:
  - "`$` on a list partial-matches, so a longer sibling key answers for a missing one", against `cfg$files$parameters_mapping_code_rules$path`.
  - "Inserting a helper between a roxygen block and its function rebinds `@export`".
  - "Under `R CMD check`, tests run from a temp dir against the INSTALLED package".
  - "A `function(...)` mock hides arguments the real callee no longer accepts".

  About 165 were not read.
- **code-check-shell.md:** the index only; none read in full (about 105 headings). The diff's only shell change is a comment.
- **code-check-spatial.md:** the index only; none read (about 115 headings). There is no spatial code.

## The mechanism behind round 2's stale name

The renames were swept by **file**, not by **section**. The leftover-name sweep looked at callers (`R/`, `data-raw/` outside `logs/`, `tests/`). It treated the prose files as history and excluded them whole. But CLAUDE.md holds two kinds of text:
- dated status blocks (history), and
- a live "Exported Functions" reference (current).

The same split applies to NEWS (current version against older ones) and to RUNBOOK (all of it current). So a current CLAUDE.md line that was edited for one rename kept the other. The inverse error comes from the same blind spot: a mechanical rewrite reaches historical comments.

**Where it reaches, every occurrence of each removed name in tracked files** (`git grep` over the whole tree, then classified by section):

| Name | Where | Class |
|---|---|---|
| `lnk_pipeline_persist` | NEWS.md:1166, 1280, 1306, 1309, 1311 (0.3x releases) | (a) history |
| | CLAUDE.md:1345 (2026-08-31 status) | (a) history |
| | backlog.md:146, 382, 388 (batches 3 and 20, both done) | (a) history |
| | data-raw/logs/*/pretest.md | (a) history |
| | NEWS.md:5 (the 0.95.0 entry announcing the rename) | correct |
| | CLAUDE.md:1517, R/lnk_persist_write.R:4, man/lnk_persist_write.Rd:36 ("named … before 0.95.0") | correct |
| | default_rearbreaks/config.yaml:71 and default_extrabreaks/config.yaml:75 | (b) deliberately kept, hashed |
| `lnk_compare_wsg` | NEWS.md:619, 1049, 1051, 1114, 1119, 1140 | (a) history |
| | CLAUDE.md:845, 1415, 1423 (dated status) | (a) history |
| | research/post_compact_provincial_handoff.md:235 | (a) history |
| | NEWS.md:5; CLAUDE.md:1532; R/lnk_compare_run.R:4; man/lnk_compare_run.Rd:85 ("named … before 0.95.0") | correct |
| | CLAUDE.md:1521 | now `lnk_compare_run` (238504a9) |
| `.lnk_compare_wsg_*` | NEWS.md:1049 | (a) history |
| | data-raw/logs/lake_connected_310/, data-raw/logs/lake_connection_317/ | (a) history: evidence scripts, which the owner keeps |
| | none in `R/`, `tests/`, other `data-raw/` scripts or docs | — |
| `resident_species` / `anadromous_species` / `spawn_only_species` | NEWS.md:1053 (0.40.0) | (a) history |
| | tests/testthat/test-lnk_pipeline_mapping_code.R:114, which asserts the alias is now an "unused argument" | intended |
| `with_mapping_code` | NEWS.md:1051, 1114, 1119, 1140 | (a) history |
| | research/provincial_parity_2026_05_12.md:184 | (a) history |
| | none in `R/`, `tests/` or the docs | — |
| The old two-chain description of token 2 | NEWS.md:1255 (0.40.0) | (a) history |
| | RUNBOOK §4 | rewritten as the rules |

The rest of the two-chain wording describes the shipped rules, not the old code, and each piece matches `inst/extdata/parameters_mapping_code_rules.csv` (identical in `default` and `bcfishpass`, by `cmp`):
- `R/lnk_pipeline_mapping_code.R:32-37` and its Rd: the shipped rules' CASE order, framed as the package copy's order.
- RUNBOOK.md:645-646 and 668-670: `mcbi_r` / `mcbi_a`. Still true of the shipped rules: the resident DAM row reads `dam_dnstr_ind`, the anadromous one `has_barriers_dams_dnstr`.
- `R/lnk_pipeline_access.R:96, 390, 422`: "resident-flavor" as residence, which still exists.

**Old file paths** (`R/lnk_pipeline_persist.R`, `R/lnk_compare_wsg.R`, their tests and Rd files):
- They survive only in history: `data-raw/logs/*/pretest.md`, `research/post_compact_provincial_handoff.md`, and the done batches in backlog.md.
- `data-raw/pretest_inputs.csv` maps both new paths, and `tests/testthat/test-dictionaries.R` passes (360/360), so no `consumed_by` file:line ref went stale.

**No (c) is left.**

## Helper names after the lint-driven rename

Each `.lnk_compare_rollup_*` definition in `R/` is defined once. No two `.lnk_*` functions in `R/` share a name (`uniq -d` over every definition is empty).

| Function | Defined at | Called from |
|---|---|---|
| `_resolve_species(conn, cfg, aoi)` | lnk_compare_rollup.R:149 | R :105 (named args); tests :72, :89, :142 (mock) |
| `_link(conn, cfg, aoi, species)` | lnk_compare_rollup.R:194 | R :125 (named args); tests :143 (mock), :183 and :201 (positional, unchanged since base) |
| `_working(conn, aoi, schema, species)` | lnk_compare_run.R:225 | test-lnk_compare_run.R:294 (positional, in this order) |
| `_reference(reference, conn_ref, aoi, species, conn)` | lnk_compare_run.R:327 | lnk_compare_rollup.R:127 (named); test mock :144 |
| `_accessible_ref(conn, aoi, species)` | lnk_compare_run.R:353 | lnk_compare_run.R:332 (named); tests :530-566 |
| `_bcfishpass(conn_ref, aoi, species)` | lnk_compare_run.R:384 | lnk_compare_run.R:330 (named); test :325 |
| `_assemble(aoi, species, rollup_link, rollup_ref)` | lnk_compare_run.R:499 | lnk_compare_rollup.R:131 (named); tests :211-517 |

The base defined `.lnk_compare_wsg_rollup_link(conn, aoi, schema, species)` beside `.lnk_compare_rollup_link(conn, cfg, aoi, species)`. Both have four arguments and different meanings, so a collapse into one name would have been silent. They stay separate:
- `_working` takes the old helper's positional order.
- No call site of `_link` passes a schema.
- No `data-raw/` script outside `logs/` calls either.

`test-lnk_compare_run.R:444` is a comment naming `.lnk_compare_rollup_mapping_code`. At the base it named `.lnk_compare_wsg_mapping_code`, a pre-#187 helper, so the rewrite changed history into a name that never existed. It is only a comment and nothing calls it, so it is not a finding.

## Checks run

- A scratch worktree at HEAD (removed afterwards; no database writes) passed these files, with 0 failed and 0 errored in each:
  - test-lnk_compare_run, test-lnk_compare_rollup, test-lnk_persist_write
  - test-lnk_mapping_code, test-lnk_mapping_code_rules, test-lnk_pipeline_mapping_code
  - test-lnk_pipeline_run, test-lnk_persist_init, test-lnk_access
  - test-pretest, test-dictionaries
- `roxygen2::roxygenise()` there left `man/` and `NAMESPACE` unchanged.
- `cfg$files$parameters_mapping_code_rules$path` has no sibling key the `$` could partial-match.
- The sibling repos fresh, knowledge, floodplains and crate hold no live caller of a removed name. Their one hit is a floodplains comment.

## Outside this diff (not a finding against it)

The pre-run gate's map dropped the rows for files 0.93.0 deleted (a2f5aeb1). A gate range from `fresh_default`'s builds (4dfbfa49) to HEAD reports `R/lnk_score.R`, `R/lnk_source.R`, `R/lnk_thresholds.R` and `inst/extdata/thresholds_default.csv` as unmapped, so it refuses.

This branch's renames are mapped only because `git diff --name-only` detects renames. Detection is on by default, and set to `copies` on this host. With `--no-renames`, the old paths `R/lnk_compare_wsg.R` and `R/lnk_pipeline_persist.R` show too. Either way the gate refuses loudly; it never passes wrongly. The precedent for keeping a removed path mapped is the `inst/extdata/schemas/` row. Whether to restore rows for removed paths is a separate change to the gate map.

## Clean

No issues found.

Index, diff and changed files read from file.
