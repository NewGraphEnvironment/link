## Outcome

`whse_basemapping.fwa_stream_networks_discharge` has no value on part of the edge 1250 main
flow through double-line river polygons. #300 found that this, not a MAD threshold, was
`mad`'s most-used loss. link now fills it along the network, set in `default_tuned` only
(`pipeline: discharge_fill`). An edge 1250 line with no value takes:
1. the nearest valued line upstream on its `blue_line_key`;
2. else the nearest downstream;
3. else the largest value on any upstream line.

The fill runs only in groups the table covers, and only where something reads discharge.
One rule, `.lnk_discharge_fill_applied()`, decides it for prepare, the run log, the
validator and the variants harness. The fill state is recorded (`<schema>.log`,
`built.csv`) rather than re-derived.

**Wrong turns kept:**
- The plan's third tier was "the downstream line". Measurement showed it would hand the
  Beatton the Peace's value, so it became the upstream tributary max.
- The plan put the knob in `default`. Review moved it to `default_tuned` so `default`'s
  config_hash would not move.
- `/code-check` took 4 rounds: R2's and R3's findings sat inside earlier fixes (the
  same "each consumer decides the fill itself" mechanism), and an enumeration of 22 places
  ended the loop (`review-round{1..4}.md`).

The plan review (`review-plan.md`) caught that `frs_col_join()` types a subquery's columns
`text`, which would have failed the first `mad` classify.

## Measurement

- **Gap** (123 covered WSGs): edge 1250 is 6,243 of 28,122 km NULL (22 %, not "most").
  4,152 km of it is absent rows and 2,091 km NULL-value rows, almost all order 4+.
- **Reach:**
  - The fill reaches all but 4.8 km of the absent rows: 3,407 km same-line upstream and
    740 km via tributaries.
  - It reaches only 229 km of the NULL-value rows. The other 1,862 km, in 12 northern
    groups, has NULL tributaries.
- **Accuracy:**
  - Single-line masking is uninformative: neighbours share a watershed, so the error is
    0.01 % (median).
  - At a ≥ 10 km gap the upstream fill is −26 % (median), a lower bound in 93 % of
    lines. At every MAD minimum it gains 0 km (never admits a line the true value would
    refuse) and loses 7.7 of 399 km for BT and 40 of 375 km for GR.
- **Regression:** #300 re-scored with this code reproduces its outputs, byte-identical or
  within 7.4e-15 relative.
- **Re-score with the fill, on #300's segmentation** (31.5 min, every base digest matched):
  - BT rearing's `cw`-only band goes from 0.71 to **0.19** of the size-matched core
    (52 found, 269 expected).
  - BT spawning goes from 0.69 to 0.13, GR from 0.49 / 0.72 to 0.25 / 0.35, RB spawning
    from 2.33 to 0.39, and RB rearing from 1.49 to 0.64 (still both ways).
  - #300's `cw`-favouring verdicts were the discharge gap. `mad` still keeps −32 % BT and
    −76 % GR stream rearing, but what it drops is now used at a fifth to a third of the
    size-matched rate.

Durable verdict: `research/habitat_thresholds.md`, "Filling discharge on river-polygon main
stems (#305)".

## Evidence

- `data-raw/logs/discharge_fill_305/` (Phase 1 at `312e195`; `rescore300/` is the
  fill-off regression)
- `data-raw/logs/habitat_score_305/` (variants build and score)

Closed by: PR for branch `305-main-stems-with-no-discharge-drop-out-of`
