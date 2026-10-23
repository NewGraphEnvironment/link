# Split test verdict (link#361, 2026-10-23)

Question: can a drainage component be modelled across hosts in any order, once the post-consolidate
recompute has settled it? Harness: `split_test.sh` + `split_compare.R` in this directory; run from a
worktree at link `1d00c04c` (the reference's SHA), `split_stamp.txt`, `split_status.txt`.

Reference: `fresh_default`'s 26 Peace groups, built on `cypher-job1` downstream-first in the provincial run
`20261023_074321-24d85e8c` and recomputed over all 241 groups. Split: odd positions of the DS-first order
reversed onto `fresh_361a`, even reversed onto `fresh_361b` (two lanes on m1), B consolidated into A, all 26
recomputed in A with the downstream guard in error mode (0 failures) and the habitat gate.

## Digests

`split_test.csv`: 442 = 26 groups × 17 tables; 387 identical, 55 differing (`split_test_summary.txt`).
Every differing digest is one of two classes; none is the order.

### 1. Cross-host arithmetic (44 digests: `streams` in 26 groups, `barriers` in 18)

Per-column join of the split build on the reference (same `id_segment` / `id_barrier`):

| table | rows joined | column | rows differing | largest difference |
|---|---|---|---|---|
| `streams` | 1,476,338 | `length_metre` | 104,047 | 2.0e-10 m |
| `streams` | 1,476,338 | `geom` (EWKB) | 1,265 | 2.3e-10 m (Hausdorff) |
| `barriers` | 1,000,112 | `downstream_route_measure`, `geom` | 62 | 3.7e-9 m |

No other column differs; barrier ids are the same set on both sides (0 in one side only). The reference was
built on an amd64 cloud host, the split on m1 (arm64); PostGIS length and interpolation differ in the last
bits between the two.

Same host, different order: MILL and LPCE rebuilt on m1 alone into `fresh_361c` (`hostcheck_build_*.log`,
single `wsg_run_one.R` runs, no recompute) digest identical to the split build (`fresh_361a`) in `streams`,
`barriers`, `barrier_overrides`, `streams_near_river` and every `streams_habitat_<sp>`, except the rows the
recompute's habitat gate blanked in `fresh_361a`: MILL GR 5 rows, LPCE BT 69, GR 100, RB 69, every one with
`access_<sp> = 0` in `fresh_361a.streams_access`.

### 2. The test's scope (11 digests: NATR `streams_access`, `streams_habitat_{bt,gr,ko,rb}`, `streams_mapping_code`; TOOD `streams_access`, `streams_habitat_{bt,gr,rb}`, `streams_mapping_code`)

Two NATR segments (`id_segment` 1 and 2, `blue_line_key` 356248829, 0.1 km, edge 1050) carry a Fraser code
(`100.567134.…`); NATR's other 47,300 segments are `200.*`. Their downstream barriers are TAKL's falls and
gradient barriers (`fwa_downstream` from segment 1 over each schema's `barriers`): present in `fresh_default`,
absent from the 26-group scratch schema. So the reference has `access_<sp> = 0` and
`has_barriers_<sp>_dnstr = TRUE` on them, the split `1` / `FALSE`, and the habitat gate and mapping code follow
(`split_test_diff_streams_access_NATR.csv`). A recompute over every group sees TAKL; the real run's does.

Two TOOD segments (`id_segment` 77049 and 77050, `blue_line_key` 359529171, 44.8 m) are the same case: their
downstream natural barriers are gradient barriers in FROG, LKEC, UKEC and ULRD (`fwa_downstream` from segment
77049: 140 rows in `fresh_default.barriers`, FROG 77 and 21 each in the other three; 0 in the 26-group schema;
`split_tood_probe.csv`). So the reference has `access_<sp> = 0` where the split has `1` (BT and RB on both
segments, GR on one; `split_test_diff_streams_access_TOOD.csv`), and the three habitat tables and the mapping
code follow. None of the four groups is in the Peace list the harness modelled.
Class counts: 26 + 18 + 6 + 5 = 55, from `split_test.csv` (`awk -F, '$5=="FALSE"'` by table).

## Verdict

Nothing attributable to the order of modelling differs: the recompute settles access, mapping code and the
gated habitat flags from every group's persisted barriers whatever host modelled which group, and the
model-time tables of a group do not depend on what was persisted when it ran. Phase 4a (group-level packing)
follows.

Two cautions for anyone reading digests across hosts:

- "Identical across hosts" holds after rounding, not byte for byte: `length_metre`, geometry and snapped
  barrier positions differ by up to 3.7e-9 m between an amd64 and an arm64 build of the same code and inputs.
  On one host the build is byte-identical (#367's reproducibility result, and `fresh_361c` here).
- A scratch recompute over a subset of groups differs from the full one wherever a group holds lines coded to
  another basin; the component closure does not include them either (NATR's two segments drain to the Fraser; TOOD's two have barriers below them in FROG, LKEC, UKEC and ULRD).

## Commands

```bash
# the harness, from a checkout at the reference's link SHA with a clean tree
/opt/homebrew/bin/bash data-raw/logs/provincial_361/split_test.sh
# the same-host control
LNK_LOAD=loadall LNK_SCHEMA=fresh_361c LNK_GUARD_DOWNSTREAM=warn LNK_HABITAT_GATE=0 \
  LNK_RUN_LABEL=split-test-361-hostcheck Rscript data-raw/wsg_run_one.R MILL default   # and LPCE
```

Per-column joins and the `fwa_downstream` probe were run with psql against the three schemas; the numbers
above are their outputs (the join counts, deltas and gate-blanked rows re-derived in one query at 22:50 UTC:
`split_column_joins.csv`) (2026-10-23 21:35–21:45 UTC; the TOOD probe 22:38 and 22:47 UTC, its outputs committed
as `split_test_diff_streams_access_TOOD.csv` and `split_tood_probe.csv`).
