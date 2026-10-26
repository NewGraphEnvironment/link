# Code-check round 2 — #260 load_all measurement (branch 377-…)

## Checklist read

- index_code-check.md: all 37 index lines read. In code-check.md, read the full prose of "Verification that reads its own output" and "One fact derived twice" (the two mechanisms this diff's evidence chain uses). The other 12 Mechanisms H3s were not read in full (12 not read); I relied on their index lines.
- index_code-check-r.md: all 111 index lines read (same text as CLAUDE.md's index). Full sections read: "`read.delim()` quotes by default" (shares.R reads timings.tsv / span.tsv with read.delim). 110 not read in full.
- index_code-check-shell.md: all 67 index lines read. Full section read: "`wait` with no argument" (measure.sh's conc waves, run_recompute_pool). 66 not read in full; measure.sh's `trap cleanup EXIT`, `set -euo pipefail` and per-pid waits were checked against their index lines.
- index_code-check-spatial.md: all 93 index lines read; nothing in the diff is spatial, 93 sections not read.

## What I re-checked from round 1's fixes

- Verdict "every job's prologue is on the pool's critical path, at a weight of one slot in eight": right. span.tsv gives 110.3 min span against 837.0 / 8 = 104.6 min, with the longest job at 22.75 min, so the pool is throughput-bound and each prologue adds about p/8.
- "removing it buys 21 s": 240 × 0.71 s / 8 = 21.3 s = 0.355 min. Right.
- "1.63 s on SALR's 11 s of work is 12.9 % of the job": 1.63 / (11 + 1.63) = 12.9 %. This matches shares.R's p/(w+p) and the issue's "prologue over prologue plus work". The 2026-09 11 s is from the `recomputed in` line (from t0), so "work" is right: recompute_parity logs show SALR at 0.17–0.18 min.
- Overrides note figures: re-derived from timings.tsv. The medians are 0.237 / 0.296 / 0.328 (library) against 0.108 / 0.147 / 0.150 (load_all) for seq / conc / busy, which matches 0.24 / 0.30 / 0.33 and 0.11 / 0.15 / 0.15. Re-run here: the first call takes 0.238 s and the second 0.059 s, which matches "0.24 s, its second 0.05 s". The namespace count does not match (finding 1).
- The unrecorded "macOS indexing" claim is gone. env.txt supports the load-average and pg_active statements.
- 12 `data-raw/` R scripts read `LNK_LOAD`: confirmed (git grep, 12).
- 11.3 s bound: (110.3 × 8 − 837.0) × 60 / 240 = 11.35 s, which prints as 11.3. Right. CLAUDE.md's copy agrees.

## Findings

- **[severity: fragile — wrong number]** data-raw/logs/loadall_260/README.md, Notes, third bullet ("its first `lnk_load_overrides()` call loads 19 namespaces"). In the order prologue.R and wsg_recompute_one.R run things (library(link), then DBI/RPostgres, the connection, then `lnk_config()`), the first `lnk_load_overrides()` call loads **17** namespaces. Measured here: crayon purrr glue crate tibble tzdb chk dplyr fs tidyr R6 readr tidyselect parallel vroom pillar magrittr. The 19 is what `lnk_config()` plus `lnk_load_overrides()` load together straight after `library(link)`: it adds `yaml`, which config loads, and `generics`, which the connection step loads first in the real prologue. Run straight after config without the connection, overrides alone loads 18. Nothing in the evidence directory records the count. The mechanism is right, and the totals and the 0.71 s saving are unaffected. The fix is to say 17, or "about 17–19 depending on what ran first", or drop the number.

- **[severity: fragile — claim contradicted by this work's own evidence]** data-raw/logs/loadall_260/README.md, Verdict, last sentence ("the next levers are #374 … and #261 (CHWK)"). The same class of claim also survives in issue #377's checklist line for #261 ("Cuts the recompute's slowest job, which bounds the pool"), which was edited 2026-10-26 in this work. It also survives in research/recompute_parallel_2026_09_01.md, candidate 2 ("the makespan floor *is* the slowest WSG"). That file's header now says "Revised 2026-10-26 (#260): … candidate 1, measured", so a reader takes the list as current.
  - This work's span.tsv shows the provincial `-j8` pool is **not** bounded by its slowest job. The span is 110.3 min against 104.6 min of summed work over 8 slots. The longest job is 22.75 min, and it is not CHWK, which took 15.56 min in `20261023_074321_recompute.log`.
  - So CHWK's time reaches the span only at one slot in eight, about 1.9 min of 110, the same arithmetic the round-1 fix applied to the prologue. The README's own corrected sentence ("the span is set by the summed work over the slots … not by the longest job") contradicts "the recompute's slowest job, which bounds the pool" two items later in #377.
  - The 2026-09 "makespan floor is the slowest WSG" held for a 4- to 8-group set at `-j4`, not at provincial scope.
  - Fix: name #261 as a lever only for the share CHWK contributes (or for a mechanism that generalises to other barrier-dense groups), and correct #377's #261 line. Also scope research candidate 2 to the 2026-09 small-set measurement, or note that the provincial pool is throughput-bound.
