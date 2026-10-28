# Code-check round 3 (#404): fresh-eyes review of the branch diff

## Checklist read

- `code-check.md` (330,698 bytes): every H3 under `## Mechanisms` read in full (14 of 14, prose only, table rows skipped). The standalone rules, Security and Spreadsheets sections read from the index only (none names a shape this diff uses beyond what the mechanisms cover).
- `code-check-r.md` (178,405 bytes): 25 sections read in full, chosen by what the diff uses (base `read.csv`/`write.csv` round trip, `Sys.time`/`difftime`, `system("uptime")`, DBI queries, `data.frame`/`rbind`, `regmatches`, `list.files`, base graphics, `tryCatch`, NA handling, `paste`, `strsplit`, `match`, `[[` on atomic, `sort`/`order`, `sprintf`, `system2`, Rscript-in-flight, Postgres row order, `aggregate`, `ifelse`, `vapply`, `unlist`, `c(name=)`, `read.delim`, `as.POSIXct`); 86 of 111 H3s not read (terra/arrow/duckdb/testthat/pak/roxygen/yaml/etc., none used here).
- `code-check-shell.md` (125,440 bytes): index only. The diff holds no shell; `launch_state.txt` was read as data, not as a script.
- `code-check-spatial.md` (155,517 bytes): index only. Nothing spatial in the diff.

## What was verified against the files (all reproduce)

Recomputed from `variant_timing.csv` (not from `steps.csv`/`split.csv`, which are analyze.R's own output): variant pooled classify 36.46 %, connect 30.89 %, digest_working 0.09 %, persist 30.28 %, copy_access_analyze 1.62 %, gate 0.34 %, digest_persist 0.32 %, total 5.583 min; split 0.677 / 0.004 / 0.319; per-group pass 0.310 (UBTN) to 1.038 (PARS); median shares 0.348 / 0.304 / 0.286; the two digests 1.355 s over nine; `default` pass 6.82 min, 0.288 to 1.455 per group, classify 48.5 % / connect 51.0 % / digests 0.47 %; base_model 67.10 min over 17 (1.74 LPCE to 7.03 KOTR; focal nine 2.95 to 7.03, sum 42.35); base_recompute 2.37; pass/base 8.3 %; classify+connect 3.76 min = 8.9 % of 42.35; discharge join 0.61 (variant) / 0.80 (`default`); `persist_init` 0.123 and 0.174 s; longest-first greedy over four jobs 5.58 to 1.56 (longest 1.04) and 6.82 to 1.80 (longest 1.45); 12 × 4.0 + 5.0 = 53 and 12 × 6.2 + 7.6 = 82.0; 12 rungs in `variants_331.csv`; segments 25,044 to 46,004; pass-start loads 2.07 to 6.33, LHAF 6.33 and UBTN 6.32; end-of-run load 3.67. UBTN connect 0.173 against REVL 0.057 and UARL 0.071, and UBTN is the largest positive residual on the variant connect fit (+0.083).

Logs: the builds table (19:09:47 / 20:19:23 / 69.6; 20:20:36 / 20:21:24 / 0.8; 20:22:17 / 20:36:09 / 13.8; loads 2.42, 2.21 with the 42 s gap, 2.07) matches `launch_state.txt` and the logs' last lines. REVL digests `778f7c72` and `15073c87` appear in both the pre-flight and the full log; `variant_timing.csv`'s REVL rows carry the full pass's stamps (13:22:37, 13:30:17). The 2026-10-15 comparison (`habitat_score_331/build_20261015_full.log`): variant 9.8 (REVL 0.5, PARS 2.4), `default` 12.0, base 42.7 over 17.

`write_thresholds()`'s rule (run standalone on the three committed CSVs, not through the build script): reproduces `default`, `bcfishpass` and `default_tuned` md5 for md5; the old name-list rule fails on `default` (its `rear_river_measure` holds `"model"`) and would pass on `bcfishpass` (all NA there), so "every `--step`, with `--base=default`" is the right qualifier, and the self-check sits in a top-level `local()` ahead of the step dispatch at the script's end.

`record_timing()` round trip, simulated on a tempfile with the diff's code: an NA `n_segments` and NA `load_1min` write as bare `NA` and read back NA; the empty `watershed_group_code` of a `persist_init` row writes `""` and reads back `""` (not NA), so its replace key works; a re-run of a (variant, group) replaces exactly its own step rows and leaves another variant's `persist_init` row alone; after the second write every column is quoted text, and analyze.R's default-typed `read.csv` still gets numeric `seconds`, logical `in_total`, integer `n_segments`. Column order is by name (`old[names(row)]`, `rbind` by name). `load_1min()`'s regex reads both the macOS and the Linux `uptime` line.

Instrumentation side effects: `load_1min()` is `uptime`; `n_segments_of()` is one `SELECT count(*)` on the base schema; `record_timing()` writes only `<out>/variant_timing.csv`. Nothing touched reaches a schema, `built.csv`, the digests or the bundles, and `total` is taken before `record_built()`/`record_timing()` so the "done in" line excludes the bookkeeping, as it did before.

## Findings

- **[fragile]** `data-raw/logs/variant_cost_404/README.md` (the "Steps scale with the group" paragraph: "The point furthest above the connect fit (UBTN, 0.17 min where REVL and UARL, of about its size, take 0.06 and 0.07) is a pass that started at a load of 6.3 from another process") and `CLAUDE.md` (the "Another process loaded m4 through the variant builds" fact: "... and the connect point furthest above the fit (UBTN ...) is a pass that started at 6.3"). The data does not support the load as the explanation. UBTN's connect excess is a property of the group, present in both passes: in the `default` pass, at a load of 4.41, UBTN connect is 0.341 min against REVL 0.120 and UARL 0.144 (2.4 to 2.8×, the same ratio as the variant pass's 2.4 to 3.0×), and it is again the largest residual above that pass's connect fit (+0.178). The other pass that started at 6.33 (LHAF) sits 0.048 above the variant connect fit, in line with its size. So the 6.3 load does not separate UBTN from its peers, and the sentence, literally true, is placed as the cause and will be read as one from a "facts not worth re-deriving" list. Mechanism: a proxy (load at pass start) standing for the property (what made this connect slow), with a control the data already holds (the same group at a lower load, and another group at the same load) that was not consulted. Remedy: say UBTN's connect runs 2.4 to 3× its size peers in both passes (at 4.4 and 6.3) so the load does not account for it; or drop the load clause from that sentence.

- **[fragile, low]** `data-raw/logs/variant_cost_404/analyze.R:500-502`. The log-to-pass key is time of day without the date (the log line carries only `HH:MM:SS`), compared as `abs(done$secs - passes$secs) <= 2`. A pass whose `built_at` and "done in" line straddle local midnight differs by 86,399 s, gets no hit, and the script stops with "a pass has no done-in line at its built_at". It fails loud, not silent, but it refuses a valid overnight campaign (an 82-min ladder launched late evening). One-line remedy: `d <- abs(done$secs - passes$secs[i]); d <- pmin(d, 86400 - d)`.

- **[fragile, low]** `data-raw/logs/variant_cost_404/analyze.R:496-500`. `stamp <- tm$built_at[tm$in_total]` is a vector derived from `tm` and aligned to `steps` by row position (both are the same filter of `tm`, built two lines apart, and `steps` is not reordered before line 500, so it is correct today). It is the one join in analyze.R that rests on order rather than on a column, and a reorder of `steps` inserted above it would misalign every pass's stamp silently (`code-check.md`, "One fact derived twice": a vector derived from a frame is a second copy of its row order; make it a column). Remedy: `secs_of_day(sub(..., steps$built_at))`, and drop `stamp`.

Not a finding, recorded so it is not re-derived: `launch_state.txt`'s first `pg_stat_activity (other backends):` entry (the base launch) has no `(end of list)` terminator, while the three later snapshots do. The README's "no other backend on the database at any boundary" is supported by three of the four boundaries; at the first, the file cannot tell an empty list from a cut-off one.

## Mechanism and enumeration

**The mechanism behind rounds 1 and 2.** A value joined across artifacts by an incidental property of where they sit (file-name order, then mtime) rather than by a key the producer wrote into both artifacts at the moment the fact was made. Under `code-check.md` that is "A proxy is not the property": file order and mtime were correlated with "the run that produced these rows" and the join needed equivalence; a clone or a copy changes the proxy and not the fact. The fix moved the join onto (variant, group, built_at), which the build stamps into the CSV in the same call sequence that prints the log line, and made the no-match and multi-match cases stop.

**Every place in the diff where a value is joined, matched or ordered across files or rows, and what it sits on:**

analyze.R

1. Log "done in" lines to passes (lines 486-504): key (variant, group) from the log line and from the CSV rows, plus time of day from the log's own stamp and from `built_at`, within 2 s. Both sides carry the key; the time is written by the same process in the same call (`record_timing()` stamps `built_at` at row construction, then reads and rewrites a small CSV, then `say()` prints). Fails loud on 0 or 2+ hits (proved in round 2 on a shifted copy). Sits on a key the data carries, with the midnight edge above.
2. A pass present in two logs (REVL in the pre-flight and the full run): resolved by the same key; the CSV holds the later run's rows (replace key below), so the earlier log's line is 8 min away and is not a hit. Sits on the key.
3. Timing rows to step kinds (`kind[steps$step]`, line 470-475): by step name, guarded by `stopifnot(all(steps$step %in% names(kind)))`. Key.
4. Pass totals (`ave(minutes, key)`, line 477; `split(steps, key)`, line 536): by (variant, group). Key.
5. `stamp` to `steps` (line 496-500): by row position within one frame. Not a key; correct today; the third finding.
6. `unique(data.frame(key, variant, wsg, minutes, secs))` to one row per pass (line 497): relies on every row of a pass sharing `built_at`, which holds because one `record_timing()` call writes all of a pass's `in_total` rows. Key, by construction of the writer.
7. Groups to segment counts: `n_segments` is a column of every row, written by the build from the base schema at write time. Key.
8. The figure's per-variant fits (lines 581-593): `d[d$variant == v, ]` by the variant column; `pch[d$variant]` by name; `lty = match(v, vars)` in the loop and `lty = seq_along(vars)` in the legend both derive from the one `vars` vector in one order. Key.
9. Parallel bound (lines 566-572): `passes$minutes[passes$variant == v]`. Key.
10. `base` and `outside` tables (lines 553-562): by step name. Key.

habitat_variants_build.R

11. `record_timing()` replace key (lines 134-136): (variant, watershed_group_code, step %in% names(seconds)), compared on the columns read back as character. `species`, `in_total`, `n_segments`, `load_1min`, `built_at` are not in the key and need not be: a (variant, group) has one species set and one `in_total` per step. The empty group of a `persist_init` row round-trips as `""`. Key the data carries.
12. Old rows' columns against the new row (line 133, `old[names(row)]`; line 138, `rbind`): by column name, not position. A column missing from an older file errors loudly; an extra column in an older file is dropped silently (no older shape exists; the file is new on this branch). Key.
13. `n_segments_of(w)` (lines 109-115): the base schema's `streams` filtered by `watershed_group_code`. Key.
14. The base digest and `built.csv` writes around the new calls are unchanged and were not re-reviewed beyond confirming the timing calls do not reorder them.

README numbers citing file contents

15. The Measurement table, the medians, the digests' 1.4 s, the base figures, the 8 % and 9 %, the join and `persist_init` figures, the parallel bound, the segment range, the loads: each re-derived above from `variant_timing.csv` and the logs by (variant, group, step), never by row order. Key.
16. The builds table: launch times and loads from `launch_state.txt`'s labelled lines; last-line times and "done in" from each log's own last line, converted PDT to UTC. Each cited to the file that holds it.
17. The 2026-10-15 comparison: summed from `habitat_score_331/build_20261015_full.log`'s "done in" lines by (variant, group). Key.
18. The UBTN sentence: the numbers are right and keyed; the causal reading is the first finding.

Nothing in the enumeration sits above its source except item 5 (order, correct today) and the causal clause in item 18; items 1 and 2 are the fixed class and sit on a carried key.

## Verdict

No bug or security issue. Three fragile items: one recorded reading the data contradicts (UBTN's connect excess attributed to the 6.3 load; the same excess is there at 4.4), and two low-severity shapes in analyze.R (a time-of-day key that false-stops across midnight; one positional vector that should be a column).
