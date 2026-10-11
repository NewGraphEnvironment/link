# Review round 6 (#324): terminating round

## (a) Round 5's fix: verified, no defect

- **`rearing` scope matches the rollup.** I recomputed it from the DB: link side with `lnk_rollup_wsg()`, bcfp side with `.lnk_sql_lake_connection()` on `fresh.streams_vw_bcfp`. Link − bcfp, against `*_mechanism_net.csv`:

  | | rollup | csv |
  |---|---|---|
  | PCEA | +30.32 | +30.33 |
  | PARS | −13.84 | −13.83 |
  | FINA | −12.88 | −12.88 |
  | LKEL | +1.65 | +1.65 |

  All agree to rounding. Lake connection is a property of the FWA line (`waterbody_key` and edge 1450), so both sides agree on every reach. That means a 'both' piece cannot differ in lake connection, and keeping link_only pieces by `l_lake_conn` and bcfp_only pieces by `b_lake_conn` is exact.
- **`rearing_stream` matches the rollup's stream slice** (`COALESCE(wb.waterbody,'stream')='stream'`). DB gives PCEA +30.25, PARS −12.68, FINA −13.04, LKEL +1.65, the same as the csv.
- **Every quoted reconciliation holds.** PCEA +30.33 = 1,655.8 − 1,625.5. The flag totals, link 2,023.48 / bcfp 2,001.37, give +22.11. The lake connection row, 367.68 / 375.89, gives −8.21. FINA, PARS and LKEL have 0 km of connection-line difference.
- **Categories are the same in every scope.** Each piece gets its mechanism once; a scope only filters pieces.
- **The pieces reproduce.** Re-running `habitat_diff_segments.R PCEA bt fresh rearing` with `LNK_OUT` set to a temp dir gives a `pcea_bt_pieces.csv` byte-identical to the committed one (cmp), with a coverage gap of 0.0 m and a flag gap of 0.0 m.

## (b) Every claim site walked

Each of these checks passed:
- **Mechanism tables:** every value in the net, mechanism and spawning-mechanism CSVs; the issue table's connectivity sums (8.19 / −25.31 / −9.27 / 1.34).
- **Break census and segment structure:**
  - break counts: 24,392 / 24,393, 20,378 / 20,392, 30,699 / 30,733 and 2,549 / 2,554;
  - 68,118 extra breaks = 29,959 + 19,888 + 18,254 + 15 + 2;
  - 35,022 breaks at 25 / 30 %;
  - 106,079 / 37,957 segments;
  - 8,806 / 8,805 overshoots of up to 3.93 mm;
  - shortest segment 0.20 m;
  - 715 of 1,258 pieces were slivers (543 left now).
- **The 25 / 30 % extras lie above BT's frontier.** 30,003 link-only breaks sit on a BT-blocking gradient position. 1 starts a BT-accessible segment, and none starts a rearing or spawning segment.
- **Width exception:**
  - 3,306 / 3,236 / 0 NULL-width segments rearing;
  - PCEA bypass pieces: 0.99 km of edge 1000, 0.21 km of 1050 in a wetland, 0.02 km of 1450 outside a lake, and 8.37 km on blks 359386479 and 359555604 with parent order 9;
  - PARS: 54 lines in both scopes, 22.77 km in the stream slice.
- **Worked examples and residuals:**
  - joining example blk 359497146: 15 % barrier at 3,050.77; 4.3 % / 7.2 %; 2.75 / 2.47 km;
  - cutting example blk 359421737: 13.6 % / 10.2 %; 5.45 km; 0.393 km;
  - the access residual's three segments, and the spawning access 0.21 km on one of them.
- **Upstream sources:**
  - cited bcfishpass lines at 620dbe4: `load_habitat_linear_bt.sql:27` and `:90-97`, `model_access_*.sql` presence filters, the minimal delete in `01_model_access_natural.sh`;
  - last-change dates and shas of those files;
  - the exception in BT / CH / CO / ST / WCT and not SK / CM / PK;
  - fresh BETWEEN at HEAD and v0.33.0;
  - `frs_order_child()` has no width test;
  - fresh#158 is closed.
- **Configuration:** `cfg$species` has 8 entries; BT thresholds are 0.0549 / 2 / 0.1049 / 1.5; `rear_stream_order_bypass = no`.
- **Taxonomy:** I checked every entry's `diff_range` against the DB diff_pct:
  - PCEA rearing 1.87, PCEA rearing_stream 2.10;
  - FINA −0.52 / −0.70, PARS −0.54 / −0.55;
  - spawning 0.79 / 0.91 / 0.93;
  - PCEA connection −2.18.

  No earlier first-match entry captures these rows.
- **Issue #324's "Prior work checked" correction** (mapping-code table 2026-05-11 is before #223; +40 % access) holds.

## Findings

- **[severity: claim]** The −8.2 km is stated to *be* the width exception, but the exception is −8.37 km and the row nets to −8.21 km.
  - **Where:**
    - `CLAUDE.md:21`
    - `gh issue view 324` (Answer, first bullet)
    - `research/bcfp_segmentation_parity.md:111`
    - `research/bcfp_divergence_taxonomy.yml:214`
  - **What is wrong:** the sites say "#319's −8.2 km on PCEA connection lines **is** bcfishpass's … width exception (8.37 km …)", or that the exception "accounts for the connection-line gap: 8.37 km". The `rearing_lake_connection` row nets to −8.21 km. That is the exception's −8.37 km (bcfp-only) plus +0.17 km of link-only rearing on connection lines, attributed to connectivity: flag − `rearing` scope = connectivity_split +0.06, connectivity_other +0.10. `pcea_bt_summary.csv` gives the same: link_only 54.18 − 54.01 = 0.17 km.
  - **Why it matters:** the exception more than accounts for the gap, and nothing says what offsets it. The README states it correctly ("−9.59, of which 8.37 km is on the connection lines").
  - **Fix:** wording only, for example "−8.2 km net: the width exception's −8.37 km, less 0.17 km of link-only connectivity on connection lines".

- **[severity: claim]** "It builds a model's barriers only in groups where that model's species are present", and the companion label "BT-only groups".
  - **Where:** `research/bcfp_segmentation_parity.md:66-69` and the taxonomy SEGMENTATION comment (`research/bcfp_divergence_taxonomy.yml:139-140`).
  - **What is wrong:**
    - At `@620dbe4`, `jobs/model_02_access_natural` runs `bt ch_cm_co_pk_sk ct_dv_rb st wct`. `model_access_ct_dv_rb.sql` ("CCIRA specific") has **no** `wsg_species_presence` filter; it builds GRADIENT_25 / 30, falls and subsurface barriers in every group. So the "only where present" generalisation is false for one of the five models.
    - Separately, `wsg_species_presence.csv` marks DV, GR and RB present in PCEA, FINA and PARS, and KO in PARS, so "BT-only" is literally false.
  - **What survives:** the conclusion that bcfishpass never breaks at a 15 or 20 % position there. ct_dv_rb is 25 / 30 % only, and none of CH / CM / CO / PK / SK / ST / WCT is present.
  - **Fix:** scope the sentence to the 15 % and 20 % models (CH / CM / CO / PK / SK, ST, WCT), and say what "BT-only" means: no species with a 15 / 20 % access model present. The same phrase recurs in `CLAUDE.md:18-19`, the issue Answer and the taxonomy `mechanism` strings (lines 156, 170).

No other claim at any site was found false.
