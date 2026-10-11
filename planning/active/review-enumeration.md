# Claim ledger after code-check round 2 (#324)

Mechanism behind rounds 1-2's claim findings: numbers restated in prose from an earlier run or from
memory instead of copied from the current artifact (1.35 / 1.54 km bounds, 8.38 km, 22.12 net, the
"to 1 m" guarantee). Fix: the net table is now written by `mechanism.R` (`<wsg>_bt_mechanism_net.csv`)
and every quantitative claim below was re-checked against the regenerated artifacts on 2026-10-11.

| claim | where | source | verdict |
|---|---|---|---|
| net / gross table (4 WSGs × 6 cols) | research doc, issue body, findings, log README | `*_bt_mechanism_net.csv` | updated to match |
| connectivity-other ≤ 4.01 km gross | research doc, log README | `connectivity_other_gross` column | matches after round 4 (PCEA 4.01, PARS 2.02, FINA 0.06, LKEL 0) |
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
| segmentation moves 74–87 km per BT-only group, nets +29.91 / −13.10 / +10.01; LKEL 1.4 | research doc, taxonomy, CLAUDE.md, issue body, draft issue | `segmentation_gross` 74.85 / 73.50 / 86.87 / 1.44, `segmentation_net` | replaces the all-mechanism gross (round 4) |
| 715 of 1,258 slivers | script comment, log README | `ec7b838` pieces CSV | matches |
| PCEA rearing_lake_connection −2.18 % | taxonomy entry | 367.69 / 375.89 | matches |

## Causal and factual claims (after round 3)

Round 3 widened the mechanism: causal and qualitative statements taken from a reviewer's narrative, an
older document or a generalisation from PCEA, with no probe. Each one in the changed docs, probed:

| claim | probe | verdict |
|---|---|---|
| slivers come from measures differing at a shared break | segment overlap within each side (8,806 link / 8,805 bcfp, ≤ 3.93 mm); 24,350 / 24,393 shared breaks identical | **wrong**, corrected in script, research, CLAUDE.md, log README |
| mapping-code parity ⇒ access agrees | the table predates #223; accessible km 5,003.0 / 5,003.4 | **wrong reasoning**, now cites accessible km (research, issue body) |
| spawning disagreement is segmentation | `*_bt_spawning_mechanism.csv`: width = 2.0 exactly (bcfp `>`, fresh `>=`) is 1.78 / 4.54 / 5.27 km | **incomplete**, width rule added everywhere spawning is claimed |
| link's breaks are a superset of bcfp's | `*_breaks.csv`: 1 / 14 / 34 / 5 bcfp breaks unmatched | **overstated**, reworded "all but a handful" with counts |
| −9.59 km is "the whole" connection gap | 8.37 connection + 1.22 stream | **overstated** in log README; research says "accounts for" |
| link breaks at 3,050.8 m | segment boundary 3,051; barrier 3,050.8 | corrected |
| 5.4 km above the cut | 5,451.6 m | corrected to 5.5 |
| bundle models all 8 species | `lnk_config("bcfishpass")$species` | holds |
| prep loop is presence-unfiltered, raw positions | `R/lnk_pipeline_prepare.R` comments + code | holds |
| bcfp builds models only where species present; deletes non-minimal before breaking | `@620dbe4` SQL / shell, read | holds |
| PCEA / FINA / PARS BT-only; LKEL has CH / CO / ST | `wsg_species_presence` | holds |
| 25 / 30 % extras do not touch BT habitat | PCEA: 1 BT-accessible segment (10 m) starts at one, no habitat | holds |
| rearing width test is `>=` on both sides | bcfp `cw.channel_width >= t.rear_channel_width_min`; fresh `size_sql()` | holds |
| width exception covers BT / CH / CO / ST / WCT; SK has none | `git grep` @620dbe4 | holds |
| fresh#158 closed; `lnk_rules_build()` supports the bypass | `gh issue view`; `R/lnk_rules_build.R:89` | holds |
| access residual sits at a subsurface-flow / falls barrier | `fresh.barriers` at the segments' DRM | holds; cause not established (stated) |
| `default` shares the break set | `lnk_config("default")`: CH / ST modelled, `gradient_classes` NULL → default classes | holds |

## Round 4: generalisations, NULL branches, categorical fields

| claim | probe | verdict |
|---|---|---|
| FINA and PARS show the cutting side winning | `segmentation_net`: PARS +10.01 | **wrong for PARS**; its whole-group sign is the width exception. Taxonomy now tags PARS rearing `pars-bt-rearing-width-exception` (class B) |
| 74–113 km is segmentation's gross | gross includes width exception and access | **wrong**; segmentation_gross quoted instead |
| bcfp's exception admits "whatever" width | SQL `:90-97` nests it in `channel_width <= max`; PCEA 3,236 NULL-width order-1 segments, 0 rear | **wrong**; reworded everywhere; `mechanism.R` bypass now NA-safe; `frs_order_child()` read: no width test |
| `split_blk` counts spawning flips of any kind | uses `s$blk[s_grad]` now | fixed; PCEA connectivity_other 3.96 → 4.01 |
| "1.2 km of stream" | pieces: 0.99 edge 1000, 0.21 edge 1050 in wetland, 0.02 1450 outside a lake | corrected |
| leftover "where both sides" half-sentence; "reconciliation allows for" slivers | read | removed / reworded (gap closes to 0.0 m) |

### Categorical fields (taxonomy)

| entry | class / status | why |
|---|---|---|
| `bt-gradient-segmentation-over` (PCEA rearing) | SEGMENTATION / INTENTIONAL | segmentation +29.91 is #223's deliberate break set; mechanism text names the −9.6 width exception and the 1.8 km unexplained access residual |
| `bt-gradient-segmentation-under` (FINA rearing) | SEGMENTATION / INTENTIONAL | segmentation −13.10 is the whole net (access +0.23) |
| `pars-bt-rearing-width-exception` (PARS rearing) | B / INTENTIONAL | width exception −24.78 drives the sign; the bundle sets the bypass to `no` |
| `bt-spawning-segmentation-and-width` (PCEA / FINA / PARS spawning) | SEGMENTATION / NEEDS_INVESTIGATION | the width rule (25–39 % of the spawning net) is an open decision |
| `pcea-bt-connection-width-exception` (PCEA connection row) | B / INTENTIONAL | bundle setting |
