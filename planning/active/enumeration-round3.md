# Enumeration after round 3 (#399 code-check)

**Mechanism (round 3):** every round restated where code 2 ends from the cases its examples
showed (rounding, then a tributary, then an uncut top), never from the clauses of the two
predicates that decide it: fwapg `fwa_upstream()` (same line by measure; tributary by code;
same watershed code with a larger local code, "capture side channels", which ignores measure)
and fresh `frs_break_apply()` (a break is tested only against the ends that existed before the
call, so only an FWA line end can stop a top from cutting).

**Fix:** RUNBOOK §2c states the three clauses (read with `pg_get_functiondef` on the local
fwapg) and the uncut-top case (read in fresh `R/frs_break.R`, the `to_break` CTE). Every other
statement says "normally" and points there, and statements of the measure test name it as
the measure test. The vocabulary definitions describe only the change.

**Candidate set:** `git grep -n -i -E "code 2|reads 2|reads 1|upstream of (it|a segment|that
segment|the segment)|top record|highest record|own top|top break|turns? from|same-line|
include_equivalents|observed upstream|recorded upstream"` over the repo, excluding
`data-raw/logs/`, `planning/`, `NEWS.md` and generated `.Rd`: 112 hits in 25 files.

**Verdicts:**
- Unrelated uses of the words (recompute audit, phases test, `wsg_run_one.R`, discharge fill,
  barrier lifts, preflight test, "fish observed upstream of this segment" definitions): 14
  hits, no claim about where code 2 ends.
- Explicitly historical (marked "until #399", "before #399", "under the earlier reading", or
  inside #396's measured sections): RUNBOOK §2c's #396 paragraphs, observation_breaks.md
  lines 25, 35, 135 and "What a merged piece does to code 2", CLAUDE.md lines 138 to 141,
  known_suspected_km.md "Against bcfishpass".
- States the rule: RUNBOOK §2c "What reads 2" (derived from the clauses; checked against the
  ELKR and PARS examples in `zz399_default_post`).
- Says "normally" and points to RUNBOOK §2c: `R/lnk_pipeline_access.R` roxygen and comment,
  `R/lnk_pipeline_break.R` table row and `.lnk_pipeline_break_obs()` roxygen, `default`
  config.yaml, CLAUDE.md #399 status, observation_breaks.md "The rule" and "Since #399",
  known_suspected_km.md "The rule" and "After #399", research/README.md row, RUNBOOK §2c's
  #396-set sentence.
- Names the measure test as the measure test: every "same-line" sentence above, both
  vocabulary definitions.
- Evidence statements (`pre_post_diff.csv`'s pass rule, the README): describe what changed
  between builds (2 to 1 at a record), which the clauses confirm is the only possible change
  since only clause 1 moved.

Nothing in the set states where code 2 ends as exhaustive without deriving it from the
clauses.
