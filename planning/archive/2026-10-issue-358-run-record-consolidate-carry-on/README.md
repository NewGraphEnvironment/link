## Outcome

`study_area_run.sh` now records which groups a run was running, and a consolidate that refuses one
source no longer ends the run (#358). The driver writes `<TS>_run_wsgs.tsv` when the buckets resolve,
before any spend, and rewrites it after the per-host accounting with each host's SKIPs. A bare
`--recompute-only` reads it together with the dispatcher's log rows, so a group that failed on a cloud
host, or before its first log row, is named. After `schema_consolidate`, the driver writes one outcome
per source. When every source has one, it carries on: a failed source's bucket becomes a
`not_consolidated` coverage class, kept out of the recompute; its host is kept while finished groups
remain there; and the run exits non-zero. `<TS>_consolidate_state.tsv` is written `in_flight` before
the copy and rewritten after the outcomes, so a crash mid-copy still tells a later `--recompute-only`
which groups to keep out.

What was learned: code-check took three rounds, and rounds 2 and 3 found defects in the previous
round's fixes. The shared mechanism was one fact, "which groups may not be safely on the dispatcher",
derived separately at each consumer from records that cover different populations or were written at
different times. The case that kept exposing it is a group a failed host finished outside its bucket.
Round 3's enumeration of every set combination ended the loop (`findings.md`, "Code-check mechanism").
The driver's full-run carry-on path needs cloud hosts and is executed by no test. Its wiring is pinned
structurally, and every lib function it calls is mutation-checked (`findings.md`, mutation table).

## Measurement

- Each defect, restored in a scratch copy of a lib, turned the test for it red: 14 mutants across
  the build and three review rounds, 14 red.
- Finish tests rose from 14 to 28 (`devtools::test` on the local docker fwapg, `NOT_CRAN=true`,
  0 skipped); host tests rose from 37 to 38.
- Full suite: 3293 pass, 3 fail, 0 skip. All three failures predate the branch and are in files it
  does not touch: two `lnk_wsg_resolve` tests need the `:63333` tunnel, which was down, and the
  golden ADMS dams pin expects 8 dams where `cabd.dams` now gives 7.

Closed by: PR for branch `358-study-area-run-sh-a-run-that-stops-befor`
