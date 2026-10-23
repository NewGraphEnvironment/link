# Code-check round 4b (#361): the round-3 fix against its artifacts

Scope: `/tmp/codecheck.vz9pBy/round3_fix.patch` (commit 20480b5a) checked quantity by quantity
against `data-raw/logs/provincial_361/` and `data-raw/logs/study_area_run/20261023_074321_*`,
then round 3's enumeration re-run, then the rest of `diff.patch` read for anything real.
Nothing was run against a database or the cloud; all derivations are awk over committed files.

## Checklist read

- `code-check.index.md`: in full. `code-check.md` (full text): the prose of every H3 under
  `## Mechanisms` (all 14, table rows skipped); of the stand-alone rules, "Documentation
  Staleness" by index line only. Rules-that-stand-alone, Security and Spreadsheets sections
  not read in full text (22 headings): nothing in this diff touches them.
- `code-check-shell.index.md`: in full. Full text read: "psql does not interpolate `:'var'`
  inside a dollar-quoted string, and `\quit N` exits 0", "Empty arrays under `set -u` on bash
  3.2", "A heredoc whose body contains its own delimiter ends early". The other ~85 headings
  not read in full: their tools or shapes are not in this diff.
- `code-check-r.index.md`: in full. Full text read: "Postgres row order is never fixed unless
  the query fixes it" (the `DISTINCT ON` minutes query), "An `information_schema` lookup by the
  literal table name misses what Postgres resolves". The other ~110 headings not read in full.
- `code-check-spatial.index.md`: in full. No full-text section read: the diff uses no
  spatial tool (the FWA measure rule was checked by index line only).

## Findings

- **[severity: fragile]** `data-raw/logs/provincial_361/README.md:40` — the row for
  `split_test_diff_streams_access_NATR.csv` still reads "the one access difference: 2
  segments". Round 3 added TOOD as a second scope case, and `split_test.csv` /
  `split_test_summary.txt` show `TOOD streams_access` differing too (2 `streams_access`
  digests: NATR and TOOD). The evidence index now contradicts the verdict it indexes; it
  should say the NATR file is NATR's column diff and that TOOD's has no committed file
  (next finding). Same mechanism as round 3: a count restated from the pre-TOOD state.

- **[severity: fragile]** `data-raw/logs/provincial_361/split_verdict.md`, the new TOOD
  paragraph and the closing provenance line — the TOOD figures (`id_segment` 77049 / 77050,
  `blue_line_key` 359529171, 45 m, "six FROG rows in `fresh_default.barriers`, none in the
  26-group schema", reference `access_<sp> = 0` / split `1`) are in no committed file, unlike
  NATR's (`split_test_diff_streams_access_NATR.csv`). And the file's last line still says
  "the numbers above are their outputs (2026-10-23 21:35–21:45 UTC)", but the TOOD probe ran
  after round 3 found the case (`review-round3.md` mtime 22:38 UTC; fix commit 22:40 UTC), so
  that window no longer covers every number above it. Either widen the stamp to name the
  TOOD probe's time, or commit TOOD's column diff beside NATR's (`split_compare.R`'s
  per-column join wrote one only for the first differing `streams_access`).

- **[severity: fragile]** `research/study_area_run.md:231` (round-3 hunk) — "LFRA 22.7":
  the driver's log has `LFRA recomputed in 22.76 min`, which rounds to 22.8; the row's other
  two figures are rounded (FRCN 17.94 → 17.9, SETN 16.52 → 16.5), so LFRA is truncated. Tiny,
  but it is a restated figure in the very row round 3 re-derived (median 2.655 → 2.7 and
  sum 839.2 → 839 both match).

Everything else in the round-3 fix matches its artifact (enumeration below). No new code
defect found in `study_area_buckets.R`, `study_area_wsgs.R`, `study_area_run.sh`,
`study_area_finish.sh`, `study_area_verify.sql`, `study_area_verify_negative.sh` or the test.

## Enumeration

Round-3 fix hunks first, then round 3's table rows re-checked. "underivable" = no committed
file reproduces it.

| quantity (where) | source artifact | verdict |
|---|---|---|
| 442 digests = 26 groups × 17 tables; 387 identical, 55 differing (CLAUDE:19, verdict, research:261) | `split_test.csv`: 442 rows, 26 wsg, 17 tables, TRUE 387, FALSE 55 | match |
| class 1 "44 digests: `streams` in 26 groups, `barriers` in 18" (verdict) | `split_test.csv` FALSE by table: streams 26, barriers 18 | match |
| class 2 "11 digests": NATR access + habitat {bt,gr,ko,rb} + mapping code (6); TOOD access + habitat {bt,gr,rb} + mapping code (5) (verdict, CLAUDE:19, research:265) | `split_test.csv` / `split_test_summary.txt`: NATR 6, TOOD 5 | match |
| "26 + 18 + 6 + 5 = 55" and the `awk -F, '$5=="FALSE"'` command (verdict) | the command run over `split_test.csv` (FALSE is unquoted) | match |
| rows joined 1,476,338 (`streams`) and 1,000,112 (`barriers`) (verdict table) | sum of `n_a` (= `n_ref`) over 26 groups in `split_test.csv` | match (round 3 called these underivable; they are derivable) |
| NATR "other 47,300 segments" (verdict) | `split_test.csv` NATR streams `n_a` 47,302 − 2 | match |
| NATR 2 segments, every `access_<sp>` / `has_barriers_<sp>_dnstr` column (verdict, README:40) | `split_test_summary.txt` column diff, 2 per column | match |
| "the one access difference" (README:40) | `split_test.csv`: `streams_access` differs in NATR and TOOD | **mismatch** (finding 1) |
| TOOD `id_segment` 77049/77050, blk 359529171, 45 m, six FROG rows (verdict) | not committed; probe after the stated 21:35–21:45 window | underivable; provenance stamp stale (finding 2) |
| lengths 104,047 rows / 2.0e-10 m; geom 1,265 / 2.3e-10 m; barriers 62 / 3.7e-9 m (verdict, CLAUDE:19, research:262-263) | psql probes 21:35–21:45 UTC, not committed | underivable (internally consistent) |
| "differs by up to 3.7e-9 m" (NEWS:9, RUNBOOK:1593/1605, verdict caution) | verdict table maximum 3.7e-9 (barriers) | match |
| MILL / LPCE on m1 "digest identical … in every model-time table, except the habitat rows the recompute's gate blanked" (CLAUDE:19, research:265-267) | verdict §1 (streams, barriers, barrier_overrides, near_river, habitat; gated rows excepted); the 17 tables in `split_test.csv` less `streams_access`, `streams_mapping_code` | match |
| gated rows MILL GR 5, LPCE BT 69, GR 100, RB 69 (verdict) | not in `split_test_run.log` (no gate line for MILL/LPCE) | underivable (unchanged by round 3) |
| "the Fraser: 205 of 873 host-minutes on the 2026-10-17 minutes" (RUNBOOK:1595, buckets.R:38) | `buckets_default.md`:83 (largest 205, total 873; weights from pre-run `fresh_default.log`) | match |
| "231 of 1,077 on 2026-10-23's" and that 231 is the Fraser (RUNBOOK:1596, buckets.R:39) | `buckets_group4.md`:87 (largest 231, total 1,077); `done in` sums over component 1's 68 groups from `run_{local,job1,job2,job3}.log` = 231.7 (component 2 107.1, component 3 108.2) | match |
| four hosts 270 either atom; five 216 vs 231 (CLAUDE:20) | `buckets_group4.md`:85-86, `buckets_group5.md`:85-86 | match |
| recompute median 2.7 min, 839 min summed, 240 groups (research:231) | `recompute.log`: 240 "recomputed in" lines, median 2.655, sum 839.2 | match |
| LFRA 22.7, FRCN 17.9, SETN 16.5 (research:231) | `recompute.log`: 22.76, 17.94, 16.52 | LFRA **mismatch** by rounding (finding 3); others match |
| recompute 110 min, `-j8` (CLAUDE:21, research:231) | `run.log` "240/240"; 839.2 / 8 = 105 | consistent |
| old "median 1.8" origin | `run.log`:76 "median 1.79 min for the rest" (the ordering hint from earlier runs, not this run) | explains the round-3 error; now fixed |
| "15 of 15 cases, including 6f / 6g" (README:23) | `verify_negative.log`: 1, 2, 3, 4a-c, 5, 6, 6b-g, 7 = 15 ticks, PASSED | match |
| 26 Peace groups, worst order, 18 guard warnings (CLAUDE:16) | `buckets_group4.md` component 3 (26 groups); `split_guard_warnings.tsv` 18 rows | match |
| 1,077 host-minutes with KTSU's 65 (CLAUDE:20) | `buckets_group4.md`:87; `run_local.log` "KTSU done in 65.4 min"; log `done in` total 1,080.5 (log rounding) | match |
| stale strings anywhere in the tree (`1e-10`, `17 of 17`, `49 digests`, `6 digests`, `median 1.8`, "byte-identical to the split") | `grep -rn` over CLAUDE.md, NEWS, RUNBOOK, research, data-raw (planning/archive excluded) | none left; `205 of 873` remains only in dated 2026-10-20 status and planning drafts, which describe that date |
| remaining round-3 rows (run_uid, SHAs, 241 / 242 / 167 / OKAN times, cloud cost, wall clock, consolidate 42 min, OKAN walk 59 s, 29 GB) | as round 3's enumeration | unchanged by the fix; round 3's verdicts stand |
