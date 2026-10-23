# Code-check round 4 (#367), branch 367-before-the-next-provincial-default-run-a vs 67a410e2

## Checklist read

- code-check.md: the prose of all fourteen H3s under `## Mechanisms`, with `|` rows and evidence blocks skipped. The first six were read in full; the last eight were read through their bolded rules. The 25 headings under Standalone / Security / Spreadsheets were not read beyond their index lines, because the diff has none of those shapes.
- code-check-r.md: "Postgres row order is never fixed unless the query fixes it" and "`sprintf("%g", x)` writes `Inf` and `NA` into SQL" read in full. The other 109 were not read beyond their index lines.
- code-check-spatial.md: "FWA `upstream_route_measure` misses the next segment's start" read in full. The other 91 were not read beyond their index lines.
- code-check-shell.md: 0 of 67 read. The round-3 fix contains no shell.

## Findings

- **[severity: fragile]** R/lnk_wsg_downstream_check.R:139 (`.lnk_dams_usa_sql()`, new on this branch). `row_number() OVER (ORDER BY a.csv_row)` numbers rows after a range join with `ROUND(...) >= ROUND(s.drm) AND ROUND(...) < ROUND(s.urm)`, and that join can repeat a placeholder. This is round 2's falls shape: an ordering that names the position but not the joined segment. Round 3's verdict, "the half-open rounded join cannot match a placeholder twice", does not hold for the join in general.
  - **Repeats:** on the provincial `fwa_stream_networks_sp` there are 617 boundaries where `round(urm)` of one segment is greater than `round(drm)` of the next on the same `blue_line_key`. An integer measure there matches both segments.
  - **Drops:** there are 632 boundaries where `round(urm)` is less than `round(drm)` of the next segment. An integer measure there matches neither, so the dam is silently dropped. The join copies bcfishpass's `load_dams.sql`, so that half is parity.
  - **Today:** all 5 rows of `default`'s `cabd_additions.csv` match exactly once (measured), so nothing moves now.
  - **Why it matters:** the CSV comes from bcfp (`source: bcfp`). Under `default`, the knob now makes these rows barriers whose ids are persisted, and the guard looks those ids up. A future row on one of the 617 boundaries would get two rows tied on `csv_row`, numbered in scan order.
  - **Fix that moves nothing today:** `ORDER BY a.csv_row, s.linear_feature_id`. The enumeration row should read "csv_row, `linear_feature_id`".
- **[severity: fragile, pre-existing, not on this branch]** R/lnk_pipeline_prepare.R:485-505 with R/lnk_barrier_overrides.R:192-211.
  - **The double count:** `natural_barriers` re-joins `gradient_barriers_raw` and `falls` to `fwa_stream_networks_sp` on the range and keeps every match. A point in a segment overlap therefore becomes two rows. Positions are also rounded, so a falls and a gradient point, or two gradient classes, can share one `(blk, measure)`. `lnk_barrier_overrides()` then does `GROUP BY b.blue_line_key, b.downstream_route_measure HAVING count(o.observation_key) >= threshold`, which counts each observation once per copy.
  - **Effect:** a position with 3 distinct observations upstream counts 6, which clears the threshold of 5 for salmon, GR and KO. bcfishpass counts per `barrier_id` (`model_access_ch_cm_co_pk_sk.sql` `obs_upstr_n`) over a `gradient_barriers` table that is one row per position, so it does not double.
  - **Measured:** I took the 3,223 positions duplicated in `natural_barriers` across the 158 local `working_*` schemas (6,455 rows, 799 of them `blocked`) and counted `bcfishobs.observations` upstream of them province-wide, from 1990, with the 20 m tolerance. Doubling occurs at 9 position × group rows, and none crosses a threshold: at most 2 distinct observations become 4. So no lift changes today.
  - **Why the verdict misses it:** round 3 called this join "range joins that keep every match: set semantics, no pick". That is right about picking and misses the aggregate that reads the copies. `count(DISTINCT o.observation_key)` would close it. It is a different property from the one this round enumerates, so treat it as a follow-up, not a blocker.

## The round-3 fix itself (`.lnk_pipeline_prep_gradient`, R/lnk_pipeline_prepare.R:428-447)

Correct. Measured on a copy of `working_setn.gradient_barriers_raw` (139,933 rows, the largest local one) in a scratch schema, now dropped:

- **Same codes:** the new statement gives the same `wscode_ltree` / `localcode_ltree` as the old `UPDATE ... FROM` on every row (0 differ). This was compared as a multiset on the full row, since no `(blk, measure)` position repeats in the raw table.
- **Unmatched rows:** the 74 rows with no matching segment stay NULL under both statements, because the inner join leaves them out of `m`. That is the old behaviour.
- **Self-reference:** `DISTINCT ON (g2.ctid)` over the target table inside its own UPDATE is sound. The subquery reads the statement snapshot, the ctids are stable within the statement, and `frs_break_find()` creates the table with `CREATE TABLE AS`, so it is a plain heap. The earlier `DELETE` and `ADD COLUMN` (no default) do not rewrite it.
- **Performance:** about 1.2 s against 2.3 s for the old statement on PostgreSQL 17. The plan is an index scan on `fwa_streamnetworks_blkey_measure_idx` per row, a quicksort of 139,939 rows in 21 MB, and a hash join on `tid`. On PostgreSQL 13 or earlier, `tid` has no hash support, so the planner falls back to a merge join; the result is still correct.
- **Test:** the test goes red when the fix is reverted. Under the parent commit's statement, two expectations fail in ".lnk_pipeline_prep_gradient quotes aoi safely in the streams_blk query"; at HEAD the file passes 204 of 204. Both runs were in a `git archive` copy with `NOT_CRAN=true`.
- **Not a defect, for the record:** in SETN, every double-matched point (80 of 80) lies 0.003 to 0.9 mm above the upper segment's `downstream_route_measure`. By the FWA convention (take a segment's top from the next segment's start), it sits on the upper segment, and a junction point where FWA has no overshoot gets the upper segment's codes. "Lower" is therefore deterministic and preserves every earlier build, but which side of the junction a point lands on still depends on FWA float noise. bcfishpass is no reference here: `gradient_barriers_load.sql` joins with `< urm + .01` and keeps whichever row `ON CONFLICT DO NOTHING` meets first. The comment's wording ("what every build so far happened to take") is accurate.

## The enumeration: completeness

Re-derived from source rather than read off the findings:

- **Syntax hits:** `grep -nE "row_number\(\)|DISTINCT ON|LIMIT [0-9%]" R/*.R` gives 68 hits at HEAD (the findings say 58). The rest are existence probes or `LIMIT 0`.
- **`UPDATE ... FROM`:** extracted from every SQL string in `R/` by script, it gives exactly the sites round 3 lists, plus `lnk_artifact.R:292` (`ON CONFLICT ... DO UPDATE`, keyed on a unique constraint).
  - **Uniqueness, measured:** the joined sources are unique on their keys. `fwa_stream_networks_discharge` has 2,716,652 rows and as many ids. wet's annual pick has 4,532,843 and 4,532,843. `pscis_fixes` (from `user_pscis_barrier_status.csv`) has 1,387 rows and 1,387 ids in both shipped bundles. `pscis_assessment_svw` has 19,905 rows and 19,905 `stream_crossing_id`s. `fresh.modelled_stream_crossings` has 524,578 rows and 524,578 ids.
  - **Conclusion:** Step 5's `branch_rank` holds, and the other `UPDATE ... FROM` sites either set constants or join on a key.
- **Window functions** (`OVER (`): every site is in the table or orders on a unique key. `RANK()` in `lnk_score.R` gives tied rows the same rank, so it involves no pick.
- **R-side picks** (`match()`, `duplicated()`, `[1]`): `lnk_pipeline_mapping_code.R:160` and `lnk_pipeline_access.R:280-311` match on segment ids that are unique within a group. `anth[1]` is fresh's array order, which is out of scope.
- **`ON CONFLICT DO NOTHING`:** `lnk_barrier_overrides.R:210` and `:251` insert only key columns, so the order of inserts cannot change the result.

**Verdict:** the candidate set is complete for "keeps one of several joined rows without naming which", with one row to add, `.lnk_dams_usa_sql()` (first finding). Every other verdict I re-checked holds. The `natural_barriers` double count is the nearest neighbouring property (fan-out into an aggregate), and the enumeration does not cover it.

Side effect to note: running `test-lnk_pipeline_prepare.R` against the local DB creates and drops `working_usa_dams`, as the test itself does. No other schema was written; `zz_cc_r4_a` was created and dropped.
