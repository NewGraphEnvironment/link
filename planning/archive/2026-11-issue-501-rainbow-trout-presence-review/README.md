# Backlog move 16: rainbow trout back in `default`, and the presence review's last rows (#501)

## Outcome

`default` models rainbow trout again, on a record rule that counts steelhead records (`ST`, `SST`, `WST`) as rainbow trout wherever RB is marked present and never the reverse (#497). The second presence review decided every row outside kokanee (#402): BT added in nine groups, DV back in VICT, RB removed in LPRO and UPET, four cells kept absent, six native-range cells sent to #515. Kokanee's 138 rows moved to a new issue, #516, because #432 is closed. Released as 0.91.0, with tokens `cut-full-top-3 acc-v7`; #507 released 0.90.0 while this branch was open.

What was learned: an alias code counting as two species turned the code-to-species map from a function into a relation. Review rounds 1 to 4 each found a reader that still assumed one row per record: three joins, a tie-break inside the shared helper written to fix them, and two counts. The loop ended on round 4's grep of the 38 places that read the map (`review-verdict.md`). The plan's decision 6 handed KO's rows to #432 without checking that #432 was open.

## Measurement

- **Records by place** (`data-raw/logs/rb_st_497/`). Of the RB records, 58 % (69,911) sit in steelhead-reachable water and 49,972 above a steelhead barrier. Only 348 ST records sit above an unlifted steelhead barrier.
- **Rules compared:**
  - Counting ST as RB adds 16,509 records, +204 RB lift positions (3 %), and moves RB's top record per line in 77 groups (78 with SST and WST).
  - Telling them apart by place would discard about 28,000 RB records. The owner chose the first.
  - A barrier-side SQL count agrees for BULK, LFRA and OKAN.
- **Three-state builds** (`data-raw/logs/rb_return_501/`):
  - No species' access or habitat differs on segments identical between states.
  - GRNL RB: 1,749.2 km accessible, both now and in the last build before the pause.
  - LKEL RB lifts: 9 → 14, 6 of them on steelhead records.
  - Province-wide, cuts move in at least 105 groups.
- **Presence check** (`data-raw/logs/presence_check_501/`): 235 → 223 flags after the decisions; none is an added or removed cell. Write-up: `research/species_presence.md`, "The second review".
- **A wrong turn:** a re-run of the Phase 1 script failed with `object 'is_rb' not found`, because the script was edited while Rscript was reading it. A later untouched re-run at the final fixes equals the committed records, except LPRO's and UPET's RB presence.
- **Checks:** full suite 6,431 passing / 0 failing / 7 skipped on the merged tree (fresh 0.56.0 from a scratch library). `R CMD check`: 0 errors, 0 warnings, 3 notes, all on files the branch does not touch.

## Evidence

`data-raw/logs/rb_st_497/`, `data-raw/logs/presence_check_501/`, `data-raw/logs/rb_return_501/`, and `review-round*.md` here.

## Owed

- Post the knowledge#148 note once the rule is on `main`.
- Run the pre-run gate again before the next provincial run (`inst/extdata/` and `R/` changed).
- Every `default` group re-models at the next provincial run (move 17, #502) to `acc-v7`. Rebuild `streams_parent` after (`streams_parent_build.R --verify`, RUNBOOK §8d), and update #490's steps to name the new tokens.
- Drop m1's scratch schemas `fresh_rb501_main`, `fresh_rb501_paused`, `fresh_rb501_ship` after the merge.

Closed by: PR (opened next) for #501
