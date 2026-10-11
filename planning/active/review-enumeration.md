# Claim ledger after code-check round 2 (#324)

Mechanism behind rounds 1-2's claim findings: numbers restated in prose from an earlier run or from
memory instead of copied from the current artifact (1.35 / 1.54 km bounds, 8.38 km, 22.12 net, the
"to 1 m" guarantee). Fix: the net table is now written by `mechanism.R` (`<wsg>_bt_mechanism_net.csv`)
and every quantitative claim below was re-checked against the regenerated artifacts on 2026-10-11.

| claim | where | source | verdict |
|---|---|---|---|
| net / gross table (4 WSGs × 6 cols) | research doc, issue body, findings, log README | `*_bt_mechanism_net.csv` | updated to match |
| connectivity-other ≤ 3.96 km gross | research doc, log README | `connectivity_other_gross` column | matches (PCEA 3.96, PARS 2.02, FINA 0.06, LKEL 0) |
| coverage gap 0.0 m, flag gap 0.0 m | research doc | script stdout | matches |
| 106,079 / 37,957 segments | research doc, CLAUDE.md | tol 106 m; plan-mode count | matches |
| break census (24,392/24,393 …, 68,118 = 29,959+19,888+18,254+15+2, 35,022) | research doc, draft issue | `*_breaks.csv` | matches; 35,022 reworded to "at 25 / 30 % positions" |
| spawning 925.7 / 918.5, 7.3 of 9.3, 2.05 | research doc | `pcea_bt_spawning_{summary,mechanism}.csv` | matches |
| 8.37 km on two 1450 lines, +1.2 km stream, 9.59 total | research doc, taxonomy, issue body, findings | pieces (5,818.5 + 2,555.9 m) | corrected from 8.38 |
| PARS −24.78 km on 54 blks | research doc, taxonomy (−24.8), CLAUDE.md, draft issue | `pars_bt_mechanism.csv` | matches |
| access 1.8 / 0.23 / 0.94 / 0.24 km | research doc, CLAUDE.md, draft issue | `*_bt_mechanism.csv` | matches |
| 2.75 km / 2.47 km downstream (blk 359497146) | research doc, findings | round-2 reviewer's DB check | matches |
| 5.4 km / 0.39 km (blk 359421737) | research doc, findings | row-level query, Phase 3 | matches |
| 0.5–1.9 % WSG-level | research doc, draft issue | `lake_connection_319/parity_crosssection_after.txt` | matches |
| 74–113 km gross per BT-only group | research doc, taxonomy, CLAUDE.md, draft issue | gross column 73.72–112.59 | matches (rounded) |
| 715 of 1,258 slivers | script comment, log README | `ec7b838` pieces CSV | matches |
| PCEA rearing_lake_connection −2.18 % | taxonomy entry | 367.69 / 375.89 | matches |
