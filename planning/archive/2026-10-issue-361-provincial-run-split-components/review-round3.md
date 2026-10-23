# Code-check round 3 — branch `361-provincial-run-can-a-drainage-component`

Reviewer: fresh agent, read-only against `/tmp/codecheck.vz9pBy/` (diff, round-2 fix patch, full
changed files) and the committed evidence under `data-raw/logs/provincial_361/` and
`data-raw/logs/study_area_run/20261023_074321_*`. Nothing was run against the database or the
cloud; `split_test.csv` and the driver's logs were parsed with Python/awk from the checkout.
`review-round1.md` and `review-round2.md` were read after the view below was formed.

## Checklist read

- `code-check.index.md`: in full.
- `code-check-shell.index.md`: in full.
- `code-check-r.index.md`: in full.
- `code-check-spatial.index.md`: in full.
- `code-check.md` (full text): the prose of all 14 H3s under `## Mechanisms` (table rows
  skipped). Not read: the 20 stand-alone rules, Security, Spreadsheets/PDFs (the diff carries
  no YAML, URL, credential, bucket policy, spreadsheet or PDF handling).
- `code-check-shell.md` (full text): read in full "psql does not interpolate `:'var'`",
  "Heredoc precedence in pipelines", "A heredoc whose body contains its own delimiter", "Empty
  arrays under `set -u` on bash 3.2", "Quoting", "`grep -c` prints the count AND exits 1",
  "`for x in $(cmd | grep …)` hides a failing `cmd`", "awk `==` compares version strings", "A
  `local` statement cannot read a variable it is assigning", "`if ! cmd; then rc=$?`", "Reading
  a file line-by-line drops the last line", "A sed/awk range can run to EOF". Not read: 52
  sections (git/gh/ssh/S3/docker/curl/conda/Perl/Python/sips/Qt/worktrees/Tailscale), none of
  which the diff touches.
- `code-check-r.md` (full text): read in full "Postgres row order is never fixed", "A database
  driver's value is not a base R type", "A `data-raw/` script must load the source tree",
  "`nzchar(NA)` is TRUE", "`paste()` with a zero-length argument", "`read.delim()` quotes by
  default", "`strsplit()` drops a trailing empty field", "`[[` on a named ATOMIC vector",
  "`c(name = x)` keeps `x`'s own name", "Rscript reads a script as it runs", "Base name
  shadowing in formal args", "`match()` treats NA as a matchable VALUE". Not read: the other
  ~105 sections (xml2, glue, readr, arrow/duckdb, ggplot2, terra, pak, roxygen, knitr, cli,
  climr, earthdatalogin, …), none of which the diff uses.
- `code-check-spatial.md` (full text): 0 sections read; the diff has no terra, sf, bcdata or
  GDAL code.

## The mechanism, named

Round 2's "241 rows" is one instance of: **a quantity stated in prose from a neighbouring
sentence, an earlier run's paragraph, or a tool's incidental output, rather than derived from
the artifact the sentence cites.** The tell is a number that no committed file reproduces
when the file beside it is parsed. This diff carries two families of restated numbers: the
run's timings (mostly from the driver's logs, which exist and are committed) and the split
test's digest classes (from `split_test.csv` / `split_verdict.md`). Every quantity in
CLAUDE.md, NEWS.md, RUNBOOK.md, `research/study_area_run.md` and the three script headers was
re-derived below; the enumeration at the end lists each with its source and verdict. Three
restatements fail, one of them load-bearing.

## Findings

- **[bug]** `data-raw/logs/provincial_361/split_verdict.md` (the committed evidence) and every
  restatement of it in the diff — CLAUDE.md:14, NEWS.md:37 and :40, RUNBOOK.md:60-62,
  `research/study_area_run.md`:822-828 and :834, `data-raw/study_area_buckets.R`:97-99, :326
  and :352, `data-raw/study_area_run.sh`:497-500 and :1197-1203, `data-raw/study_area_wsgs.R`:
  12-16 — claim that all 55 differing digests are traced to "cross-host arithmetic or the
  test's 26-group scope (two NATR segments)". **The committed `split_test.csv` does not support
  that enumeration.** Parsed (442 rows, `identical == FALSE`): `streams` 26, `barriers` 18,
  NATR `streams_access` + `streams_habitat_{bt,gr,ko,rb}` + `streams_mapping_code` 6, and
  **TOOD `streams_access`, `streams_habitat_{bt,gr,rb}`, `streams_mapping_code` 5**. The
  verdict's class 1 is "49 digests: `streams` in 20 groups, `barriers` in 29" — 20 + 29 = 49
  was obtained as 55 − 6, not from the file (26 + 18 = 44, and `barriers` cannot differ in 29
  of 26 groups) — and its class 2 names NATR only. TOOD's five access / habitat / mapping-code
  digests appear in no table of the verdict, no CSV, and no sentence of any doc. The mechanism:
  `split_compare.R` writes a column diff for **the first** differing `id_segment`-keyed table
  only (`first <- diff_rows[keyed, ][1, ]`, by design), that was NATR, and the verdict's
  class-2 enumeration was built from that one output while the class-1 counts were stated from
  memory. Why it matters: `streams_access` is the table the modelling order *can* reach, the
  verdict is the sole basis for `--atom=group` / `--buckets-exact`, and five of its eleven
  access-class differences are untraced. TOOD may well be another "lines coded to another
  basin" case (the verdict's own caution 2), but nothing in the record says so. Remedy before
  merge: run `split_compare.R`'s per-column join for TOOD `streams_access` and the
  `fwa_downstream` probe on its differing segments against `fresh_361a` / `fresh_default`
  (the scratch schemas are kept until the PR merges, per the README), add the result and the
  corrected class counts (26 / 18 / 6 / 5) to `split_verdict.md`, and either keep the docs'
  claim or narrow it to what was traced. I could not run the probe (no database access in this
  review).

- **[fragile]** `research/study_area_run.md`:793 — "recompute, 240 groups, `-j8` | 110 min
  (median 1.8 min per group; LFRA 22.7, FRCN 17.9, SETN 16.5)". The run's own
  `20261023_074321_recompute.log` gives 240 `recomputed in` lines with **median 2.66 min**
  (sum 839 min, which at `-j8` is the ~110 min wall; LFRA 22.76 / FRCN 17.94 / SETN 16.52 are
  right). The 1.8 is `run.log`'s "ordering 241 known WSG time(s) longest-first (median 1.79 min
  for the rest)" — the median of the *prior* known times the driver sorts by, not this
  recompute's. Same mechanism as round 2, from an incidental driver line.

- **[fragile]** CLAUDE.md:14 and `research/study_area_run.md`:826-827 — "MILL and LPCE
  rebuilt on m1 alone are byte-identical to the split build in every model-time table". The
  verdict says *digest*-identical in `streams`, `barriers`, `barrier_overrides`,
  `streams_near_river` and every `streams_habitat_<sp>` **except the rows the recompute's
  habitat gate blanked in `fresh_361a`** (MILL GR 5 rows; LPCE BT 69, GR 100, RB 69). The
  restatement drops the exception and upgrades "digest" to "byte" (the digests are md5 of row
  text at `extra_float_digits = 3`). A compression that drops its condition
  (`code-check.md`, "A guard's scope, escape hatches, and remedies": "Compression runs both
  ways"). Low: it does not change the verdict, but it is the sentence someone will quote.

- **[fragile]** NEWS.md:40 and RUNBOOK.md:62, :74 — "differs at 1e-10 m across
  architectures". The artifact's barrier positions differ by up to 3.7e-9 m (verdict table;
  CLAUDE.md:14 and research:825 say "at most 3.7e-9 m" correctly). An order of magnitude
  understated in two of the four restatements. Low.

- **[fragile]** RUNBOOK.md:64-65 and `data-raw/study_area_buckets.R`:101 — "the Fraser: 205 of
  873 host-minutes" is on the 2026-10-17 minutes (`buckets_default.md`: largest component 205,
  total 873); on this run's minutes the same component is 231 of 1,077 (CLAUDE.md:15,
  research:831, `buckets_group{4,5}.md`). Both are right for their base, neither sentence
  names it, and the diff now carries two "largest component" figures. Low; a time qualifier
  fixes it.

## The round-2 fix, reviewed

`/tmp/codecheck.vz9pBy/round2_fix.patch`:

- `research/study_area_run.md`:221 — "242 rows: 241 groups, OKAN twice" matches
  `run_verify.log` section 1 (57 + 68 + 42 + 75 = 242; m1's 75 holds OKAN's failed and
  finished rows) and section 1c (one open row, `superseded = t`). Correct.
- `data-raw/study_area_run.sh`:1242 — "a group listed twice, on two hosts or within one". The
  "within one" clause is executable: `lnk_wsg_resolve(expand = FALSE)` returns
  `focal[focal %in% modelable]`, which keeps duplicates and order, and `study_area_wsgs.R`
  does not `unique()` its input, so a within-list repeat survives to `sort | uniq -d`. Correct,
  and round 1 reached the same reading.

## Code, re-walked (no findings)

- `study_area_verify_negative.sh` 6g: with ZYMO's only row set `date_end = NULL`, `n_model`
  (DISTINCT groups) and `n_gap` (log EXCEPT finished log_recompute) are unchanged, so the
  new `n_open` raise is the **first** assertion that can fire; 6g isolates the new guard
  rather than failing on a neighbour. 6f's inserted row carries every provenance column, so
  it passes the per-row arms, as OKAN's real row did. Restore is by `DELETE` + re-copy from
  `SRC_SCHEMA` scoped to `run_uid`, and case 7 re-runs the healthy case last.
- `study_area_verify.sql`: `'',''` inside the `format()` literal is a correct `','`; `bad` is
  declared `text`; the EXCEPTION precedes the NOTICE, so the NOTICE prints only when every
  open row is superseded; `f.run_uid = o.run_uid` makes a hand re-model under another
  `run_uid` still raise, which matches the message's remedy.
- `study_area_buckets.R`: the minutes query ends `ORDER BY watershed_group_code, date_start
  DESC` on a `timestamptz` that cannot tie within a group in practice; `as.numeric(w$n)`
  absorbs numeric/integer64; `weight_of()` substitutes the median before `pack()`;
  `global_order` is disjoint by the existing `dup` assertion on `flat`; group-mode
  `host_focal <- host_wsgs` is what `--exact` expects.
- `study_area_run.sh`: `BUCKET_MODE` is assigned at 1207/1210 before both `run_wsgs_write`
  calls (1254, 1467) in the same shell that sourced `study_area_finish.sh` (438); the
  `--recompute-only` gate refuses `--buckets-exact` before anything runs.
- `study_area_finish.sh`: the two-header `case` matches quoted `$(printf …)` literally; the
  awk reader keys on `$1 $3 $4`, which both shapes share. The test writes and reads both.

## Enumeration

Every quantity in the diff's prose and script headers, its source artifact, and the verdict.
"underivable" means no committed file reproduces it (the figure may still be right).

| quantity (where) | source artifact | verdict |
|---|---|---|
| run_uid `20261023_074321-24d85e8c`, link `1d00c04c` (0.68.0), fresh `e9793047` (0.42.0) (CLAUDE:11, NEWS:36, research:220-223) | `run_verify.log` §2; `split_stamp.txt` | match |
| 241 groups, `expected_n=241`, both verifiers pass (CLAUDE:11, NEWS:36, research:224) | `run_verify.log`:569, `run_verify_extra.log`:8 | match |
| `log` 242 rows: 241 groups, OKAN twice (research:221, round-2 fix) | `run_verify.log` §1 (57+68+42+75), §1c | match |
| `log_recompute` 241 (research:221) | `run.log` recompute 240 + `okan_recompute.log` 1 | match |
| `--refresh-primitives`, `--recompute-jobs=8`, 2026-10-17 build kept as `fresh_default_20261017` (CLAUDE:11, NEWS:36) | `run.log` banner; `split_test_summary.txt` control line | match |
| 442 digests, 387 identical, 55 differing (CLAUDE:14, RUNBOOK:61, research:822) | `split_test.csv` parsed | match |
| 55 = cross-host arithmetic + NATR scope, "nothing the order can reach differs" (CLAUDE:14, NEWS:37/40, RUNBOOK:60-62, research:822-828/834, buckets.R:97-99/326/352, run.sh:497-500/1197-1203, wsgs.R:12-16) | `split_test.csv` parsed: streams 26, barriers 18, NATR 6, **TOOD 5** | **mismatch** (finding 1) |
| verdict class 1 "49: streams in 20 groups, barriers in 29"; class 2 "6: NATR" (`split_verdict.md`) | `split_test.csv` | **mismatch** (26 / 18 / NATR 6 / TOOD 5) |
| 62 barrier positions, ≤ 3.7e-9 m; 104,047 / 1,265 rows; 2.0e-10 / 2.3e-10 m; 1,476,338 / 1,000,112 rows joined (CLAUDE:14, research:825) | psql probes 21:35–21:45 UTC, not committed | underivable |
| "1e-10 m across architectures" (NEWS:40, RUNBOOK:62/74) | `split_verdict.md` table (barriers 3.7e-9) | mismatch (finding 4) |
| two NATR segments, Fraser-coded line, downstream barriers TAKL's (CLAUDE:14, RUNBOOK:77, research:826) | `split_verdict.md` §2, `split_test_diff_streams_access_NATR.csv` (2 per column) | match |
| MILL, LPCE rebuilt on m1 "byte-identical in every model-time table" (CLAUDE:14, research:827) | `split_verdict.md` §1 (digest identical except gated habitat rows) | mismatch (finding 3) |
| reference Peace built on amd64 cloud host, split on arm64 m1 (CLAUDE:14, research:824) | `split_verdict.md`; `run.log` job1 held the Peace | match |
| 26 Peace groups, two hosts, worst order; 18 of 26 guard warnings; recompute all 26 in error mode (CLAUDE:11, RUNBOOK:59, research:819-821) | `split_stamp.txt`, `split_status.txt`, `split_guard_warnings.tsv` (18 rows) | match |
| 1,077 host-minutes, KTSU's 65 included; largest component 231 (CLAUDE:15, research:831) | `buckets_group4.md`:86 | match |
| four hosts 270 under either atom; five hosts 216 vs 231 (CLAUDE:15, NEWS:37, RUNBOOK:72-73, research:831-833) | `buckets_group4.md`:85, `buckets_group5.md`:86 | match |
| "the Fraser: 205 of 873 host-minutes" (RUNBOOK:64-65, buckets.R:101) | `buckets_default.md`:83 (2026-10-17 minutes); 2026-10-17 research section names the Fraser, 68 groups | match on its base; base unnamed (finding 5) |
| Phase 1 packing ~218 per host (CLAUDE:16, research:229) | `buckets_default.md`:77-80 (218 / 219 / 217 / 219) | match |
| cloud hosts 247 / 260 / 257 min of modelling; m1 306 (CLAUDE:16, research:229) | `run_job{1,2,3}.log`, `run_local.log` `done in` sums: 247.2 / 261.3 / 257.2 / 307.2 | within 1 min; producer of 260 / 306 not named |
| 249 / 264 / 259 wall; m1 560 wall (research:229) | no committed timestamps per leg | underivable |
| "13 to 19 % over" (research:237) | 247/218, 260/219, 257/219 | match |
| m1 "about 10 % over" net of KTSU and the stall (research:237) | (306 − 64) / 218 = 1.11 | match |
| KTSU 65.4 min (1.3 on 2026-10-17); 64 min excess (CLAUDE:16-17, research:239) | `run_local.log` "KTSU done in 65.4 min"; 1.3 from `fresh_default_20261017.log`, not committed | 65.4 match; 1.3 underivable |
| OKAN from 09:19 UTC, cancelled 13:30, ~4 h 10 m (CLAUDE:17, research:240-241, :233) | `run_verify.log` §1c date_start 09:19:57; 13:30 not in a committed file | 09:19 match; 13:30 underivable (4 h 11 m arithmetic consistent) |
| 54 m1 groups after 13:30 at the 2026-10-17 pace (CLAUDE:17) | `run_local.log` has no per-group timestamps | underivable |
| OKAN re-model 7.6 min; `--recompute-only --wsgs=OKAN` 3 min (CLAUDE:17, research:232) | `okan_remodel.log` "done in 7.6 min"; `okan_recompute.started` 20:23:11Z → log mtime 20:26Z | match |
| OKAN walk re-run 59 s (3.2 M pairs), KTSU 3 s, same plan (CLAUDE:17, NEWS:40, research:243-244) | not committed | underivable |
| consolidate 42 min, 3 hosts, 167 groups (CLAUDE:16, research:230) | 167 = 57 + 68 + 42 (`run_verify.log` §1); 42 min not in a committed timestamp | 167 match; 42 underivable |
| recompute 110 min, 240 groups, `-j8` (CLAUDE:16, research:231) | `run.log` "240/240"; `recompute.log` sum 839 min ÷ 8 ≈ 105 | match |
| recompute median 1.8 min; LFRA 22.7, FRCN 17.9, SETN 16.5 (research:231) | `recompute.log`: median **2.66**, LFRA 22.76, FRCN 17.94, SETN 16.52 | **mismatch** on the median (finding 2) |
| wall clock 12 h 21 m, 07:43 → 20:04 UTC (research:233) | `run.started` 07:43:21; exit 20:04 not committed (`run.log` mtime 20:06 after redaction) | start match; end ≈ |
| cloud 3 × ~10.4 h, spin 07:45 → burn 18:06, ≈ $7.80 at $0.25/h (research:234) | arithmetic 10 h 21 m × 3 × 0.25 = 7.76; timestamps not committed | arithmetic consistent; underivable |
| ~17 host-hours idle; legs finished 12:12–12:27 UTC; m1 17:23 (CLAUDE:19, research:234/245) | `run_verify.log` §1 last_done 12:12 / 12:27 / 12:21; (18:06 − 12:12/12:21/12:27) = 17.3 h | 12:12–12:27 match; 17 consistent; 17:23 underivable |
| `fresh_default` 29 GB (14 + 15), 11.39 M segments; database 386 GB (research:235) | database state, not committed | underivable |
| 2026-10-17 spread 165 to 272; 165 / 205 / 272 / 231 against 218 (research:238, buckets.R:191-192) | sum 873 matches the 2026-10-17 section's total; per-host figures not committed | consistent; underivable |
| R² 0.64 over 104 WSGs (buckets.R:190) | `study_area_run.sh`:533 recompute_order note | match (restated from code comment) |
| 0.45× cloud speed (2026-08-31), equal at 2026-10-17 (buckets.R:159-164, NEWS:38) | research "Equal packing was right" (pre-existing) | match |
| negative cases 6f, 6g pass; ZYMO (CLAUDE:18, NEWS:39, research:248) | `verify_negative.log` | match |
| "17 of 17 cases" (`provincial_361/README.md`, outside the diff) | `verify_negative.log`: 15 ticks (1, 2, 3, 4a-c, 5, 6, 6b-g, 7) | mismatch (evidence index, not the diff) |
| `habitat_validate.R` writes to `habitat_validate_283/` unless `--out=` (CLAUDE:20) | `data-raw/habitat_validate.R`:89 | match |
| parity re-score 16 of 17 rows `link_dirty` (CLAUDE:21) | not committed | underivable |
| "Only `job1`–`job3` tofu workspaces exist" (CLAUDE:15) | infrastructure, out of scope | not checked |
| `--recompute-only --wsgs=<one group>` right only when nothing drains through it (CLAUDE:22, research:242) | `run.log` INCOMPLETE remedy text; OKAN's drainage not in a committed file | behaviour match; OKAN claim underivable |
