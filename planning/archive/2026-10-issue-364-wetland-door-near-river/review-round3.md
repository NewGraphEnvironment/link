# Code-check round 3 (#364)

## Checklist read

Every FULL TEXT file is over 40,000 bytes, so none was read in full.

- `code-check.md` (329 KB): the prose of all 14 H3s under `## Mechanisms`, table rows skipped. Not read: the 31 headings under Rules that stand alone, Security, and Spreadsheets/PDFs. None of them names a tool or pattern this diff uses.
- `code-check-r.md` (175 KB): 11 headings read in full:
  - Postgres row order
  - `sprintf("%g")` and Inf/NA into SQL
  - the literal-name `information_schema` lookup
  - the `function(...)` mock
  - `data-raw/` must load the source tree
  - `::text` spelling
  - DBI driver values
  - `sort()` / `order()` and `LC_COLLATE`
  - `paste()` with a zero-length argument
  - `R CMD check` runs against the installed package
  - yaml's mixed int/float sequences

  About 115 headings were not read.
- `code-check-shell.md` (121 KB): none read. The diff changes no shell, psql or git script.
- `code-check-spatial.md` (154 KB): 1 heading read ("FWA main flow is not edge type 1000 alone"), about 95 not read. The diff uses no terra, sf, GDAL or bcdata.

Ran in a copy (`scratchpad/linkcopy3`, `git archive HEAD`, NOT_CRAN=true): test-lnk_pipeline_persist, _discharge, _habitat_validate, _rules_build, _pipeline_classify, _log and _persist_init. All gave 0 failed and 0 error. The scratch schemas `zzcr3_p` and `zzcr3_v` were created for the probes below and dropped.

## The mechanism, one axis over

Round 2 moved persist's delete set off the walk's output and onto fresh's resolver. That fixed the stand-in it named, but the set is still **re-derived in persist rather than taken from the step that walked**:
- persist resolves from `cfg`'s thresholds CSV and method table, and from the `species` it is passed;
- classify walked with its own `thresholds_csv`, `method_csv` and `species`, filtered to species with a `parameters_fresh` row;
- fresh wrote each pair's numbers with its own formatter.

Each of those is "one fact derived twice" (code-check.md). The two derivations agree on today's shipped paths, because `lnk_pipeline_run()` and the harness pass classify nothing that differs from cfg. That agreement is coincidence, not construction, and one axis of it fails now (finding 1).

The validator has the same shape on its WSG axis (finding 2). The set of groups whose near-river provenance gets checked is "groups with a log row", which stands in for the aoi.

## Findings

- **[fragile]** `R/lnk_pipeline_persist.R:238-243`: the pair-scoped DELETE writes its VALUES with `format(x, digits = 15)`, but fresh stores `threshold` / `distance_max` through `.frs_sql_num()`, which is `sprintf("%.10g")` (fresh `R/frs_near_river.R:345-350`, `R/utils.R:82`).
  - Any pair number with more than 10 significant digits fails to match its own stored rows. So the zero-hit case that round 2's fix exists for (a pair that found no river, so it is absent from the working table's UNION arm) leaves the earlier build's rows in place again.
  - Reproduced in `zzcr3_p`: one row was stored with fresh's literal for 15 and one for 0.0412345678912, then link's DELETE was run with the resolver VALUES. It deleted 1 of 2; the 0.04123457 row survived.
  - `SELECT 0.04123456789::float8 = 0.0412345678912::float8` is FALSE. So is 1/3 formatted both ways. 15, 3 and 1000 match, which is why the mocked test (`'channel_width', 15::double precision, 1000::double precision`) cannot see it.
  - When it bites: a `*_river_*` cell with that many digits. It could be typed into a thresholds CSV, or come from a harness `set` on a `*_river_*` cell, which the harness now allows.
  - Fix: format the VALUES with fresh's own formatter, `utils::getFromNamespace(".frs_sql_num", "fresh")`, the way `.lnk_near_river_pairs()` already borrows `.frs_near_river_specs()`. Then the literal and the stored value are the same text.
  - On the wider mechanism: the robust form records the walked pairs in classify (link's wrapper has the exact `params`, `params_method`, `species` and `parameters_fresh` fresh used) as a small working table, and persist reads that instead of re-resolving from cfg. Today the re-resolution diverges from the walk in three places, none of them reached by a shipped path:
    - `lnk_pipeline_classify(thresholds_csv =, method_csv =)` overrides (the `data-raw/logs/*/reclassify.R` style). Zero-hit pairs under the override are not cleared, and cfg's pairs are cleared though not re-walked.
    - A persisted species with no `parameters_fresh` row. Its pair is deleted though fresh never walked it, which on a species-subset build removes distances another, unbuilt species still reads.
    - The formatter.

- **[fragile]** `R/lnk_habitat_validate.R:460-517` (`.lnk_hv_check_log()`) together with `:405-415` (`.lnk_hv_check_schema()`): the near-river check runs only over WSGs that have a log row (`lg$watershed_group_code`), not over `aoi`.
  - An unlogged WSG was necessarily built before the log existed, so before 0.67.0, and walked no pair. That is exactly the case the new check stops for when the log value is NULL ("a missing log value is from a build before link 0.67.0, which walked none"). With no row at all, it passes.
  - The schema-level guard does not catch it either. `has_near` is "the table exists", and `lnk_persist_init()` creates `streams_near_river` in every schema on any 0.67 build. Existence therefore says nothing about which groups persisted distances.
  - So, under a cfg that reads a pair (default, default_tuned: CH `channel_width:15:1000`), an unlogged group in a schema touched by any 0.67 build is scored with an empty near-river table. Its CH near_river predicates read FALSE, which gives false "persisted TRUE, predicate FALSE" disagreements or masked misses. The only sign is `run_logged = FALSE` in the summary.
  - Reproduced in `zzcr3_v` (empty `log`, empty `streams_near_river`, cfg `default`, aoi ADMS): `.lnk_hv_check_log()` returned `character(0)` with no error. After one `near_river = NULL` row was inserted, it stopped as designed.
  - Not live in any schema I know of: `fresh_default`'s 241 groups are all logged (#246). But a pair-reading cfg over a schema with pre-#127 groups would hit it.
  - Fix: in the near-river block, treat an aoi WSG absent from `lg` like a NULL row, i.e. compare `want_nr` over `aoi` with `""` for missing groups. Alternatively, stop in `.lnk_hv_check_schema()` when the schema has no `streams_near_river` row for a group that cfg reads a pair in and that has no log row.

## The enumeration (findings.md, "Round 2 found two defects")

Rows checked against the code:
- **Rows 1, 3, 4, 6, 7, 8, 9 and 10:** the stated sources match the code.
- **Row 2:** matches as stated ("resolver: persisted species × the group's model ∪ the walk's rows"). But the table does not record that this is a reconstruction of row 1 from different inputs: cfg's thresholds and method table instead of classify's arguments, no `parameters_fresh` filter, and link's number formatter instead of fresh's. That difference is finding 1.
- **Row 5 (`.lnk_discharge_read_rules()`):** the pair half resolves over `cfg$species`, but the rule-level `mad:` half scans every species in `params` (`names(params)`). The row reads as if both were one set. This is harmless as it stands, because over-inclusion means only a needless fill.

Missing rows, which are places the branch derives a set or a presence from a stand-in:
- **11.** `.lnk_hv_check_log()` near-river block: which WSGs are checked. Source: groups with a log row, standing in for `aoi` (finding 2).
- **12.** `.lnk_hv_check_schema()`: whether the schema holds the distances. Source: whether `streams_near_river` exists, a table `lnk_persist_init()` creates in every schema. It stands in for "these groups persisted their walked pairs".
- **13.** `lnk_pipeline_persist()` VALUES: the numbers that identify a pair. Source: link's `format(digits = 15)`, standing in for fresh's stored `%.10g` text (finding 1).

## The rest of the diff

Nothing else fails:
- the rules builder's door, scope and stop combinations;
- the `near_river: false` stamping;
- the log column and its `lnk_log_read()` projection;
- the persist DDL and index;
- classify's DROP before the walk;
- the preflight formals and internals;
- the validator passing the persisted table into both the strict and the relaxed predicates (fresh's EXISTS keys on `id_segment` and `watershed_group_code`, so #203's fan-out does not apply);
- the harness `own_rules` / `record_built` / sha / dims / structure-variant checks;
- `audit_configs.R`'s unstamp (it removes only `near_river: FALSE`, never a mapping);
- `query_mad_width_equivalent.R`.

Consolidate copies `streams_near_river`, because it enumerates the tables carrying `watershed_group_code`, so cloud-built groups do not lose their distances.
