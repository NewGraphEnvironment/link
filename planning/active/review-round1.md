# Code-check round 1 — #260 (loadall_260 evidence + write-ups)

## Checklist read

- `index_code-check.md`: read in full. Full text: read the prose (table rows skipped) of all 14 H3s under `## Mechanisms`, the first ~30 KB closely and the rest skimmed for its bold rules. Not read: the 23 H3s outside Mechanisms (Security, Spreadsheets/PDFs, standalone rules); none bears on this diff.
- `index_code-check-r.md`: read in full. Full sections read: "Rscript reads a script as it runs", "`read.delim()` quotes by default", "Postgres row order is never fixed". 108 of 111 not read.
- `index_code-check-shell.md`: read in full. Full sections read: "Empty arrays under `set -u` on bash 3.2", "Parallel writers sharing one output file", "`wait` with no argument", "A second `trap … EXIT` replaces the first", "On this Mac `stat` and `date` are GNU", "Put cleanup on the EXIT trap, not RETURN". 61 of 67 not read.
- `index_code-check-spatial.md`: read in full. 0 of 93 sections read; the diff uses no spatial tool.

## What I verified and found right

- `prologue.R` mirrors `wsg_recompute_one.R:21-62` line by line: the same load branch (`:26-30`), DBI/RPostgres, the same `lnk_db_conn()` args, both `SET`s, `lnk_config()` plus the schema override, `lnk_load_overrides()`, `lnk_pipeline_species()` and `lnk_presence()`. `t0` is at `:62`.
- `log_recompute.date_start` is `now()` at the INSERT in `.lnk_log_recompute_start()`, after `t0` (it also follows `lnk_stamp()`, which I timed at about 0.1 s, so that does not matter).
- Every median in `shares.txt` and the README table matches `timings.tsv` (I recomputed them). `total` equals the sum of the stages to within 2 ms.
- `span.sql` gives exactly `span.tsv` against the live DB. 241 rows sit under the run_uid; the one excluded is OKAN's (20:23). `recompute.log` has 240 "recomputed in" lines with no SKIP.
- The share arithmetic is right: 3.6 / 1.0 / 0.2 / 12.9 / 0.7 %, 0.81 min (0.74 %), 0.35 min (0.32 %), and 11.3 s per job.
- "12 `data-raw/` scripts" is right: 12 top-level `data-raw/*.R` files read `LNK_LOAD`.
- #260's old line reference was `:24-28` at v0.48.0 and is now `:26-30`.
- The pool really is `Rscript wsg_recompute_one.R` under `LNK_LOAD=loadall`, with a 1 s `sleep` poll.
- #374, #261 and #377's next item all match.
- No host identity in the files the diff adds.

## Findings

- **[severity: bug — wrong claim]** `data-raw/logs/loadall_260/README.md`, Verdict ("the pool runs groups in parallel, longest first, so short groups never sit on its critical path"). This is false, and it contradicts the README's own pool model.
  - The 2026-10-23 span (110.3 min) is set by the summed work over 8 slots (104.6 min), not by the longest job (22.75 min).
  - So every job's prologue, short ones included, is on the critical path at a weight of 1/8. That is exactly the `240 × 1.63 s / 8` estimate the README uses.
  - Longest-first puts the short groups at the **tail**. In `log_recompute`, MUSK (14 s), KAKC (23 s), LNRS (18 s) and LEUT (16 s) all started at 19:55, in the last 90 s of the span.
  - The conclusion still stands: a 13 % share on one short group does not become 13 % of the span. The fix is to replace the reason with that one (the span is aggregate work / 8, so a group's own share does not carry over), not with "never on the critical path".

- **[severity: bug — wrong number and wrong mechanism]** `data-raw/logs/loadall_260/README.md`, Notes, last bullet ("`lnk_load_overrides()` reads 0.24 s under `library(link)` against 0.11 s under `load_all()`, in every condition. That is the installed 0.68.0 against the source tree").
  - **The numbers.** 0.24 / 0.11 holds only in `seq`. The medians from `timings.tsv` are conc 0.30 / 0.15 and busy 0.33 / 0.15.
  - **The mechanism is not version drift.** `git diff --stat v0.68.0 c7e23509 -- R/ inst/extdata/configs/` touches only `lnk_log.R`, `lnk_persist_init.R`, `lnk_stamp.R` and `utils.R`. Nothing that `lnk_config()` or `lnk_load_overrides()` reads changed.
  - **The measured cause.** Under `library(link)`, the first `lnk_load_overrides()` call lazily loads 18 namespaces (crate, dplyr, readr, tibble, tidyr, vroom, purrr, …): 0.237 s on the first call, 0.054 s on the second. Under `load_all()` those Imports are already loaded inside its `load` stage, so its first call is 0.099 s.
  - **What follows.** The "load_all stage alone" column (1.08 vs 0.28 s busy) charges `load_all()` with namespace loading that `library(link)` pays later, in `overrides`. The totals and the 0.71 s saving are unaffected, but the stated explanation is wrong.

- **[severity: bug — unsupported claim, low]** `data-raw/logs/loadall_260/README.md:3-4` ("macOS indexing about 1.3 cores throughout"). No evidence file records this, and `env.txt` shows a 1-minute load average of 4.03 **before** the run, with 0 active PG backends. So the background load during the timings is not what the README says, or at least nothing in the record supports the figure. Either record what was running (for example a `ps`/`top` snapshot in `env.txt`) or drop the figure.

- **[severity: bug — wrong number, minor]** `data-raw/logs/loadall_260/README.md`, Verdict ("13 % of SALR's 11 s"). `shares.R` computes the share as `p / (w + p)`, so 12.9 % is 1.63 s as a share of 12.63 s. As a share of SALR's 11 s, 1.63 s is 14.8 %. The table's "prologue share" column is fine, because it is a share of the whole job. Only the prose phrasing "of SALR's 11 s" mismatches the number. The same phrasing appears in the #260 issue body ("SALR 12.9 % of #260's 11 s").

Nothing else found: no defect in `measure.sh`, `prologue.R`, `shares.R` or `span.sql` that changes a number, and no host identity added.
