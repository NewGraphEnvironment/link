# Code-check round 1: branch 399-read-a-fish-record-at-a-segment-s-start

Diff: `branch.diff` against the merge-base 804276e6. The `R/` change itself (one argument,
`include_equivalents = FALSE` on the upstream observation walk) is correct against fwapg's
`fwa_upstream()` and fresh's `frs_network_features()`. It changes only the same-line test,
from `m >= start - 1` to `m >= start + 1`, and both tests reach it. Every number in the
evidence README, RUNBOOK §2c and the two research files was re-derived from the committed
CSVs, except the ranking in finding 3. The PRE builds reproduce #403's 25 `default` rows
exactly. All findings below are about written claims.

## Checklist read

- **code-check.md:** I read the prose of all 14 H3s under `## Mechanisms`: A guard that
  fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the
  property; Verification that reads its own output; A guard's scope, escape hatches, and
  remedies; A fix lands in one of two callers that share a harness; Restore the bug and
  prove the guard fires; A shared working tree, and what generators leave in it; A
  wrapper's exit is not the work; Zero-length, empty, and unset are three different things;
  The probe is broken before the world is; Written data outlives the fix; Serialization
  loses meaning silently; One fact derived twice. I also read Documentation Staleness.
  That is 15 of 37 headings, and 22 were not read.
- **code-check-r.md:** I read 6: A `function(...)` mock hides arguments the real callee no
  longer accepts; An `information_schema` lookup by the literal table name misses what
  Postgres resolves; Postgres row order is never fixed unless the query fixes it, so a
  pick, a float sum and a presence check can each depend on it; `match()` treats NA as a
  matchable VALUE, so two unknowns join to each other; `$` on a list partial-matches, so
  a longer sibling key answers for a missing one; Tests that silently do not run. That
  leaves 109 of 115 not read.
- **code-check-shell.md:** I read 3: A failed `cd` lets every later command run in the
  directory you were already in; A `local` statement cannot read a variable it is
  assigning in the same statement; On this Mac `stat` and `date` are GNU, so the same flag
  letter means something else. That leaves 67 of 70 not read.
- **code-check-spatial.md:** I read 1: FWA `upstream_route_measure` misses the next
  segment's start. That leaves 92 of 93 not read.

## Findings

- **[bug] R/lnk_pipeline_break.R:28 and :153-156, inst/extdata/configs/default/config.yaml:121-124, man/lnk_pipeline_break.Rd:59.** The new text says that a kept top is also where species recorded only below it turn ("and at a kept top for species recorded only below it"; "the tops are also where species recorded only below them turn"; "which is also where species recorded only below it turn"). That was true only under the old reading. There, species Y with records on a line only below X's top read 2 on the segment starting at its own top and turned at the next cut above, often X's top. After #399, Y's own top break starts a segment that reads 1, so Y turns at its own top. It does not turn at X's top, unless a coincidence puts a Y record within 1 m of X's top or a recorded tributary at it. The evidence says so too: every 2-to-1 piece in `pre_post_diff.csv` has a record of its own species at its start (`n_2_to_1_no_record` is 0), and that is exactly the piece from Y's top up to the next cut. CLAUDE.md:126 keeps the same sentence under "Until #399", which is correct there. These three places present it as the current behaviour.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" ; code-check.md "Documentation Staleness"

- **[bug] Tributary records falsify the "turns at its highest record on each line" claim. Places: R/lnk_pipeline_access.R:31-35 (roxygen, and man/lnk_pipeline_access.Rd), R/lnk_pipeline_access.R:278-280 (comment), inst/extdata/vocabulary.csv:9 (the `acc-v2` definition), RUNBOOK.md:203-205, research/known_suspected_km.md:91-92.** Each says, with no carve-out, that "the segment starting at a species' top record reads 1", that a species "turns from 2 to 1 at its highest record on each line", or that "the segment above each species' highest record on a line reads 1". The walk's other-line test still counts a tributary record for every segment of the receiving line below the tributary's mouth (RUNBOOK §2c says this a few lines lower). So on any line with a recorded tributary entering above its top record, the segment starting at the top reads 2, and the turn is at the confluence. I measured this read-only on `zz399_default_post`, BULK RB:
  - Of 205 segments starting within 1 m of the line's top RB record, 34 read 2 (170 read 1, 1 reads 0).
  - 494 segments (159.6 km) read 2 above their own line's top RB record.

  The #403 text this branch deleted from `known_suspected_km.md` carried the carve-out ("A segment with a record on a tributary entering above it keeps code 2"), and so does the harness comment in `pre_post_diff.R:20` ("a tributary record above keeps 2"). The new prose dropped it. The `acc-v2` row is the durable definition consumers decode, so the overstatement lands in the place meant to stay true for years. The `definition` cell is still editable under `vocab_append_only()`.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[bug] research/known_suspected_km.md:107-108.** "The largest losses are rainbow trout and coho (BULK RB 73.5 km, 5.2 %; PARS RB 41.2 km; BULK CO 29.0 km)" is false against `pre_post_diff.csv`. The second-largest loss is ELKR WCT at 54.26 km, which is larger than PARS RB (41.18) and BULK CO (29.03). In order: BULK rb 73.53, ELKR wct 54.26, PARS rb 41.18, BULK co 29.03, PARS bt 27.50, ELKR bt 25.77.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (a rank or superlative restatement)

- **[fragile] The 1 m boundary is described two ways, and one is wrong. Places: "more than 1 m above" in R/lnk_pipeline_access.R:31-32 (and the Rd), R/lnk_pipeline_break.R:28 and :154, inst/extdata/configs/default/config.yaml:122, inst/extdata/vocabulary.csv:9 (`acc-v2`).** The code is `m >= start + 1`: fwapg's `downstream_route_measure_b >= upstream_route_measure_a + tolerance`. That is "at least 1 m", which is what RUNBOOK §2c, research/known_suspected_km.md and research/observation_breaks.md say. A read-only probe returned `whse_basemapping.fwa_upstream(10, 521, …, 10, 522, …, false, 1)` = TRUE, so a record exactly 1 m above a start is upstream, which "more than 1 m" denies. It matters only at exactly 1 m, but the `acc-v2` definition and the roxygen are the reference texts, and the branch's own documents disagree with each other.
  - **Rule:** none

- **[fragile] RUNBOOK.md:818-819.** The token rule still says "A new transcription of bcfishpass's rules is `acc-bcfp-2`". This branch gave that token to the #399 code change, and tokens are never reused (`anyDuplicated(v$token)` is refused in test-lnk_vocabulary.R). Someone following the RUNBOOK for the next transcription would add a duplicate row, which the suite refuses, or would be pointed at the wrong token name.
  - **Rule:** code-check.md "Documentation Staleness"

- **[fragile] data-raw/logs/record_at_start_399/build_obs.R:9-12.** The header says the script writes `zz399_obs.province` ("its `<schema>.observations_province` under `default`, for the upstream-group reading in parity_pieces.sql"). The code writes `province_<config>` for both configs (`province_default`, `province_bcfishpass`; confirmed in the database). `parity_pieces.sql` reads `zz399_obs.province_bcfishpass`, not the `default` set. The comment names a table that does not exist and the wrong config.
  - **Rule:** code-check.md "Documentation Staleness"

- **[fragile] CLAUDE.md:18 and :21 (the 2026-10-30 "later" #403 status) and :123 (the #396 Owed line).** Both still state the pre-#399 world as current:
  - "link's observed km run above bcfishpass's by exactly the segment above a record … That is #399."
  - "The numbers are a baseline before #399 and #401; their builds revise the research file."
  - #399 is listed as owed.

  After this branch, `parity_bcfp.csv` shows a gap of 0.00 km for every non-steelhead row. The branch edited CLAUDE.md:42 and :126-130 but not these lines. If a #399 status block is planned for `/planning-archive`, fold these lines into it there.
  - **Rule:** code-check.md "Documentation Staleness"
