# Code-check round 2 — #399 (branch head f3100331)

## Checklist read

- **code-check.md**: read every Mechanisms H3 in full (14 of 14: guard fails toward pass,
  fixture cannot reach, proxy, verification reads own output, guard's scope/escape
  hatches/remedies, fix lands in one of two callers, restore the bug, shared working tree,
  wrapper's exit, zero-length/empty/unset, probe is broken, written data outlives the fix,
  serialization, one fact derived twice). Standalone rules, Security and Spreadsheets/PDFs
  read from the index only (~20 headings not read in full; none names a tool or shape this
  diff uses).
- **code-check-r.md**: index read in full; full sections read for "An `information_schema`
  lookup by the literal table name misses what Postgres resolves" (incl. its correlated
  subquery paragraph), "Postgres row order is never fixed unless the query fixes it",
  "Rscript reads a script as it runs", "`paste()` with a zero-length argument returns
  length ONE", "A value compared as `::text` in SQL has PostgreSQL's spelling". About 145
  headings not read in full.
- **code-check-shell.md**: index read in full; full sections read for "A failed `cd` lets
  every later command run in the directory you were already in" and "`wait` with no
  argument waits for every background job". About 85 not read in full.
- **code-check-spatial.md**: index read in full; full section read for "FWA
  `upstream_route_measure` misses the next segment's start". About 95 not read in full.

## What was verified and holds

- fwapg `fwa_upstream(..., include_equivalents, tolerance)` (local DB): FALSE gives
  same-line `m >= start + tol`; TRUE gives `m > start OR |start - m| <= tol`
  (`m >= start - 1`). The tributary and side-channel arms are identical under both values,
  so "only the same-line test changed" is true. fresh 0.47.0's walk passes tolerance 1.
- bcfishpass `model/01_access/sql/load_streams_upstr_observations.sql` (local checkout)
  calls `FWA_Upstream(..., False, 1)` in both blocks.
- The two new tests pass on a worktree of HEAD (2 and 4 expectations), and the DB test's
  fixture discriminates (both segments read 2 under TRUE). `test-lnk_vocabulary.R` passes
  48/48, including the append-only check against origin/main; `.lnk_vocabulary_match()`
  returns the live row of a shared spec.
- Headline numbers re-derived from `pre_post_diff.csv`: 346.584 / 93.620 km, 25 / 7
  group-species, default 0.023 to 73.529 km, share max 5.40 % (LKEL RB), medians 1.85 % and
  1.94 %; largest losses BULK RB, ELKR WCT, PARS RB, then BULK CO (default). `parity_bcfp.csv`
  identity (200.85 = 187.109 + 14.778 − 1.036) holds.
- `build_obs.R`'s sets equal `working_<wsg>.observations` row for row (EXCEPT ALL both ways)
  for default LKEL, UPCE, ELKR and bcfishpass BULK, PARS.
- The tributary carve-out: every top-of-line segment still reading 2 in
  `zz399_default_post` BULK (RB 34, BT 7, CO 8, ST 7, CH 5) is explained by a record of the
  species upstream on another line (fwa_upstream false, 1), or by the top's own record
  lying ≥ 1 m above its segment's start (below).
- "The one ending there reads 2": 0 counter-cases over all 2,878 species-line tops in the
  seven post builds.
- pretest map covers `R/lnk_pipeline_access.R`, `configs/{config}/config.yaml` and
  `vocabulary.csv`.

## Findings

- **[severity: fragile]** RUNBOOK.md:254-258, CLAUDE.md:139, research/observation_breaks.md:35 and :133-139 (also research/README.md:22, not in the diff) — present-tense claims that #399 made false, left beside the diff's own new statement of the rule.
  - RUNBOOK:254 says the near-exact set (per species, the lowest record of any species more than 1 m above its raw top) "would keep nearly every turn to 1 where `all` puts it". After #399, `all` turns each species at its own top (RUNBOOK:203-206 in this same diff, "whichever bundle"), and that set puts no cut at the top, so it no longer reproduces `all`'s turns.
  - CLAUDE.md:139 (#396 block, not marked "until #399"): "it only reproduces where `all` turns, which is not at the fish either". After #399, `all` does turn at the fish.
  - research/observation_breaks.md:35: "`all` does not put it at the highest fish either: the walk counts a record at a segment's start as upstream of it". This describes the walk in the present tense and contradicts the file's own "The rule" section.
  - research/observation_breaks.md:133-139 (question 5): "That premise does not hold: a species' own top never changes its own code ... the real redundancy in the tops is every top that is not the first cut more than 1 m above some other species' top". After #399 the issue's premise holds: a top is redundant exactly where a tributary record of the species enters above it. That is the carve-out this diff writes everywhere else, and it is measured above: 61 of the BULK `default` tops of five species still read 2 for that reason.
  - research/README.md:22's index row still says the file explains "why link's observed km run above bcfishpass's".
  - The file's trailing marker ("The measurements above this section were made under the earlier reading") covers measurements. These are statements about how the walk behaves now, and a reader landing on question 5 or the "Dropped" note gets the opposite of the rule.
  - Fix: mark each "before #399", or restate it.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (a present-tense justification must track; only a time qualifier excuses a restatement)

- **[severity: fragile]** RUNBOOK.md:206-208 — "A top within 1 m of another observation's break does not cut itself …, and the boundary lands on that break instead, within 1 m of the record."
  - This is false when the uncut top lies 1 to 1.5 m above the existing end. The record then counts as upstream of the segment starting at that end (`m >= start + 1`), and the species turns at the next cut above, wherever it is.
  - Measured in `zz399_default_post`, ELKR: on `blue_line_key` 356549331, BT's only record is at 1 m. Its rounded position (1) is within 1 m of the FWA line start (0), so it did not cut. The segment 0–112 reads `access_bt` 2 and the segment at 112 reads 1, so the boundary is 111 m above the record.
  - The existing end there is an FWA end, not "another observation's break": `frs_break_apply()`'s 1 m rule is about any existing end.
  - The same edge is a missing carve-out in the universal "on each line a species turns from 2 to 1 at its own top / highest record, unless a tributary…" wording. That wording appears in:
    - vocabulary.csv:9 (the `acc-v2` definition);
    - R/lnk_pipeline_access.R:70-75 and the comment at :284-290;
    - R/lnk_pipeline_break.R:113 and :153-156;
    - the `default` config.yaml comment;
    - CLAUDE.md:11;
    - research/observation_breaks.md "The rule" and "Since #399".
  - It is 1 of 2,878 species-line tops across the seven post builds, so the magnitude is small. But the RUNBOOK sentence states a bound ("within 1 m of the record") that the data breaks, and `acc-v2`'s definition is the durable one.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (a universal quantifier restatement executed against its population)

No code defect found: the one-line change, its tests, the vocabulary retire/re-add and the evidence harness check out. Round 1's seven fixes were checked and hold, except that fix (1)'s correction did not reach the four places named in the first finding.
