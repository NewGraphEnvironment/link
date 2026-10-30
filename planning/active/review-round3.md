# Code-check round 3 — #399 (branch diff against 804276e6)

## Checklist read

- `code-check.md.index` in full; the prose of all fourteen H3s under `## Mechanisms` in `code-check.md` (tables skipped). Most relevant here: "A guard's scope, escape hatches, and remedies" (compression, terminating by enumeration), "A proxy is not the property", "Written data outlives the fix", "Restore the bug and prove the guard fires".
- `code-check-r.md.index`, `code-check-shell.md.index`, `code-check-spatial.md.index` in full. Read in full text: "Postgres row order is never fixed…", "FWA `upstream_route_measure` misses the next segment's start", "A `function(...)` mock hides arguments…", "`expect_message`…" (not used), the testthat skip/NOT_CRAN rules.

## What I checked, and what held

- **(a) The core of the exact rule holds.** fwapg's 11-argument `fwa_upstream()` (read from the local DB) tests a same-line feature with `b >= start + tolerance` under `include_equivalents = FALSE` and `b > start OR |start - b| <= tolerance` under `TRUE`; fresh passes tolerance 1 (`R/frs_network_features.R`, `walk_from`). So `m >= start + 1` after, `m >= start - 1` before, as written.
- Records are whole metres (`zz399_obs.province_default`: 0 of 232,773 measures fractional), so a top's break sits exactly on the record; "within 0.5 m" is true but loose.
- The ELKR example checks out: `blue_line_key` 356549331 has one BT record at 1 m, segment 0–112 reads 2, and the segments above read 1.
- I found no third case of the boundary sitting below a top that did cut: 0 of the cut tops in all 32 group-species have the segment below them starting less than 1 m under the record. Province-wide, 0 of 38,939 species-tops could produce one through an FWA end.
- Tests: in a scratch worktree at HEAD, `test-lnk_pipeline_access.R` passed 67 and `test-lnk_vocabulary.R` passed 48, with no skips. I restored `include_equivalents = TRUE` on the observation walk and both new #399 tests went red (1 failure each), then put the line back.
- The pretest map covers every changed modelling file (`vocabulary.csv` row 145, `config.yaml` rows 83–86).
- The numbers in CLAUDE.md, the README and `known_suspected_km.md` match `pre_post_diff.csv`, `parity_bcfp.csv` and `status.tsv`: 5.4 % max is LKEL RB, BULK RB is 5.2 %, BT is 14.5 and 14.5, the builds ran 19:00–20:00.

## The mechanism

Each round restated **where code 2 ends** from the cases its examples showed: the rounding, the tributary, then the top that did not cut. Nobody derived it from the clauses of the two predicates that decide it:

- `fwa_upstream()` ORs **three** clauses in its `wscode != localcode` branch: the same line by measure, a tributary by code, and **a line with the same watershed code and a larger local code** ("capture side channels"). None of the three is restricted to other lines.
- `frs_break_apply()` tests a break only against the ends the table had **before the call**.

So "the exact rule" and its "two cases" are a sample, not an enumeration, and every sentence copied from them inherits the gap. The fix is one restatement from the predicates, then a sweep of the places below. That is the termination rule in `code-check.md`, "A guard's scope, escape hatches, and remedies": execute a compression against each of its sources, here fwapg's SQL and fresh's join, not against itself.

## Findings

- **[severity: bug]** RUNBOOK.md:205-210 ("The exact rule": "…or below the mouth of a tributary holding a record of X…, and 1 elsewhere, barriers aside") — the rule leaves out `fwa_upstream()`'s third clause.
  - A record on a line that shares the segment's watershed code and carries a larger local code counts as upstream whatever its measure. This covers side channels and braids, and it fires on the **same** line wherever FWA's local codes run out of order along it.
  - Measured on the post builds: a code-2 segment with no same-line record at `m >= start + 1` and no record on a line of another watershed code, so 2 only through this clause.
    - Five `default` groups: 371 segments, 50.4 km. PARS GR 147 / 22.35 km, PARS RB 56 / 6.25, PARS BT 45 / 6.05, BULK BT 34 / 4.17, UPCE GR 25 / 3.21, ELKR BT 20 / 2.31, BULK CH 13 / 1.38, and smaller rows.
    - BULK and PARS under `bcfishpass`: 103 segments, 13.0 km.
  - Example of the side-channel case: PARS BT `blue_line_key` 359002361 (code `200.948755.936902.074405`) reads 2 from main-stem records on 359568913 at 72766 and 76155, which share the code with larger local codes.
  - Example of the same-line case: PARS BT `blue_line_key` 359567332, the segments starting at 182476.7 and 183194.1, reads 2 from a BT record on the **same** line at 182461, 15 m *below* both. That record is the line's top BT record. Its local code `…936902.888699` exceeds theirs (`…885589`), because FWA's local codes on that line are not monotone in measure.
  - So "1 elsewhere" is false, and so is "the segment starting at the top is the first to read 1 / the boundary sits on the highest record" wherever this clause applies.
  - The same incomplete rule is restated as exact ("only") or as "two cases" in:
    - `R/lnk_pipeline_access.R:31-37`, the roxygen (`man/lnk_pipeline_access.Rd`): "So code 2 reads 2 only on a segment starting…".
    - `R/lnk_pipeline_access.R:280-285`, the comment.
    - `R/lnk_pipeline_break.R:28`, the table row (`man/lnk_pipeline_break.Rd`): "a segment reads 2 only on…".
    - `R/lnk_pipeline_break.R:152-155`: "the cases that move it: a tributary record entering above, a top that did not cut".
    - `inst/extdata/vocabulary.csv`, row `acc-v2`: "so a segment reads 2 only on a segment starting…".
    - CLAUDE.md:16: "a segment reads 2 only if…".
    - `research/known_suspected_km.md`, "After #399", first paragraph: "a segment reads 2 only if…".
    - `research/observation_breaks.md`, "The rule" ("a segment reads 2 only if…"; "the cases that move the boundary off the top (a tributary record entering above; a top that did not cut…)") and "Since #399" ("except where RUNBOOK §2c's two cases move it").
    - `research/README.md`'s row ("normally ends at…") is hedged and fine.
  - **The `vocabulary.csv` row is the one that cannot wait for a follow-up.** `test-lnk_vocabulary.R`'s append-only check treats a changed `definition` as an edit (`vocab_append_only()`, `for (col in c("definition", "spec", "introduced"))`). Once `acc-v2` is on main, correcting its definition needs a new token. Fix it before merge, for example by dropping the "so a segment reads 2 only…" clause or stating all three clauses.
  - Not a regression: this clause behaves the same under `TRUE` and `FALSE`, so `pre_post_diff.R`'s "other-line tests unchanged" holds. The defect is only the claim of exactness.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: bug]** RUNBOOK.md:210-211 ("a top that did not cut, because an earlier end (another record's break, an FWA line end) lies within 1 m of it") — "another record's break" cannot stop a top from cutting.
  - `observations` is the first entry of `break_order` in both shipped bundles, and the streams table is raw FWA before it (`.lnk_pipeline_prep_network()`).
  - `.lnk_pipeline_break_obs()` puts every record's (or every top's) position into one `observations_breaks` table, which goes to one `frs_break_apply()` call. That call joins each break against the segment's **pre-call** ends only (fresh `R/frs_break.R:625-626`) and pairs all the breaks inside a segment with `lead()`, so two records' breaks cut each other at any spacing of 1 m or more. Since records are whole metres, distinct breaks are at least 1 m apart.
  - Measured: every one of the 50 tops that made no cut in the five `default` post builds (LKEL 2, BULK 15, UPCE 9, PARS 7, ELKR 17, per species and line) has an FWA end within 1 m.
  - The parenthesis should name FWA line ends only.
  - The same sentence in `research/observation_breaks.md` ("a top that did not cut because another end lies within 1 m") is vaguer, but it inherits the same reading.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (a compression executed against its source: here fresh's join)

- **[severity: fragile]** `research/observation_breaks.md`, question 5 ("Since #399 it does, and a top is redundant exactly where a tributary with the species' records joins above it") — "exactly" is false.
  - A top is also redundant for code 2 where it made no cut at all (the 50 above).
  - It is also redundant where a record sharing the line's watershed code with a larger local code keeps 2 above it (finding 1).
  - It is also redundant where the species is blocked (code 0) there.
  - This is the same mechanism: an exhaustive word over a set taken from the cases met.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

/Users/airvine/Projects/repo/link/planning/active/review-round3.md
