# Code-check round 1 — branch 324-pcea-link-bcfishpass-config-flags-differ

Reviewer: subagent, 2026-10-11. Diff `main...HEAD` (9f579fe). Verified against the local fwapg
(read-only SELECTs), `smnorris/bcfishpass@620dbe4`, and a re-run of
`habitat_diff_segments.R PCEA bt fresh rearing` into a scratch dir (`LNK_LOAD=loadall`).

Verified and correct (no action): the research table (every mechanism net, net and gross for all four
WSGs recomputes from `*_mechanism.csv` / `*_summary.csv`); the break census numbers (68,118 =
29,959 + 19,888 + 18,254 + 15 + 2; 24,392/24,393 etc.; 35,022 = 29,959 + 5,063); the
106,079 / 37,957 segment counts and 14,315.7 km; the 25/30 % extras are inaccessible (PCEA: 30,002 of
30,003 link segments starting at an extra BT-blocking gradient break have `access_bt = 0`); both
row-level examples (PCEA blk 359497146, FINA blk 359421737) match the DB; the width-exception split
(PCEA 8.37 km on blks 359386479 / 359555604, parent order 9, + 1.22 km; PARS 24.78 km on 54 blks, no
lake-connection lines); the access residual's three PCEA segments (two 1410 at SUBSURFACE_FLOW, one
starting at FALLS@2950.8); the upstream line refs (`model_access_bt.sql:148-152`,
`model_access_ch_cm_co_pk_sk.sql:146-150`, non-minimal delete before `break_streams()` in
`01_model_access_natural.sh`); the order-1 / parent >= 5 exception in BT, CH, CO, ST and WCT at
620dbe4 and not SK/CM/PK; fresh#158 CLOSED; bcfishpass bundle `rear_stream_order_bypass = no` for all
eight species; `cfg$species` = 8 species; BT thresholds 0.1049 / 0.0549 / 1.5; the 0.5–1.9 % WSG-level
range (on `rearing_km` excluding connection lines); "nothing left unattributed" (`other` sums to
0.02–0.16 m per WSG); no `rear_gradient` piece runs in the wrong direction. Re-run summary CSV is
byte-identical. Taxonomy rows for PCEA rearing (+1.87 %), rearing_stream (+2.10 %), spawning (+0.79 %)
and FINA / PARS rearing / rearing_stream (−0.5 to −0.7 %) do match the new entries.

## Findings

- **[severity: claim]** `research/bcfp_divergence_taxonomy.yml:146-172` (with
  `data-raw/logs/rearing_diff_324/README.md:19-20`, `research/bcfp_segmentation_parity.md:87`) — the
  gap #324 was opened about stays UNEXPLAINED under `lnk_parity_annotate()`. The rollups emit a
  `rearing_lake_connection` row (#317), and PCEA BT reads link 367.69 / bcfp 375.89 km = **−2.18 %**
  there (from this branch's own `pcea_bt_summary.csv`: both 1969.31 − 1601.79 = 367.52; link-only
  lc 0.17; bcfp-only lc 8.37). Neither new entry lists `rearing_lake_connection` in `metric`, and
  `hors-class-stream-order-bypass` is scoped to HORS/CLRH/COLR/KHOR. Probed with
  `lnk_parity_annotate()` on synthetic PCEA BT rows: rearing / rearing_stream / spawning → SEGMENTATION,
  `rearing_lake_connection` −2.18 → `UNEXPLAINED / NEEDS_INVESTIGATION` (|diff| >= tolerance 2). So
  "Moved #324 from unexplained to an annotated divergence" and "the whole connection-line gap of #319"
  being explained are not reflected in the annotation the taxonomy drives. Needs an entry (width
  exception, PCEA, BT, `rearing_lake_connection`, `link_lt_bcfp`) or the claim narrowed.

- **[severity: fragile]** `data-raw/habitat_diff_segments.R:26-30` and the re-run command at
  `data-raw/logs/rearing_diff_324/README.md:25` — the default path is `library(link)`, and the installed
  link on this machine is **0.50.0**, which has no `.lnk_sql_lake_connection()`
  (`exists(".lnk_sql_lake_connection", asNamespace("link"))` is FALSE). The documented re-run loop
  (no `LNK_LOAD`) therefore errors on its first call; every committed stamp was produced with
  `LNK_LOAD=loadall` (they read `link 0.63.0`). The README presents `LNK_LOAD=loadall` as optional.
  This is the "a `data-raw/` script must load the source tree, not the installed package" trap
  (code-check-r): default to `load_all()`, or put `LNK_LOAD=loadall` in the command.

- **[severity: fragile]** `data-raw/habitat_diff_segments.R:144` — `ORDER BY class, blk, dm` is not
  unique within a group, so `<wsg>_<sp>_pieces.csv` row order is not reproducible. Re-running
  `PCEA bt fresh rearing` at HEAD against the same DB gave identical content (sorted diff empty) but a
  different file (`cmp` differs at line 74; rows swap at 74/75, 133/136, 315). Any re-run will churn the
  committed evidence and read as a change. Add a unique tiebreak (e.g. `um, id_segment,
  segmented_stream_id`). Same shape as "A pick whose `ORDER BY` ends on a key that is not unique".

- **[severity: claim]** `data-raw/logs/rearing_diff_324/breaks.R:37` (and every `*_breaks.csv`) — link
  breaks with no `fresh.barriers` position are labelled `none (observation / crossing / endpoint)`, but
  they are overwhelmingly FWA base-segment boundaries (`fwa_stream_networks_sp` linear-feature joins):
  in PCEA **15,931 of the 16,265** sit within 1 m of an FWA segment's `downstream_route_measure`. The
  committed evidence attributes ~16k breaks to the wrong source. Relabel (e.g. "no barrier position
  (FWA segment boundary / observation / crossing / endpoint)") or split out the FWA boundaries.

- **[severity: claim]** `data-raw/habitat_diff_segments.R:14` — header says the coverage assertion
  holds "(to 1 m)", but line 124 sets `tol_m = max(1, n_link_segments / 1000)` (106 m for PCEA), and
  the same tolerance also gates the flag reconciliation, which is an identity given full coverage. The
  measured gaps (14.8 m, 0.0 m) are fine; the stated guarantee is not what the code checks.

- **[severity: claim, minor]** `research/bcfp_segmentation_parity.md` — three small statements the data
  do not support as written:
  - `:41` "Connectivity on a `blue_line_key` with no gradient split of its own is at most 1.35 km per
    WSG" (also README `:35` "≤ 1.35 km per group"): PCEA `connectivity_other` is 1.35 link-only +
    0.19 bcfp-only = 1.54 km gross (1.16 net). 1.35 is the largest single class, not the per-WSG figure.
  - `:74` "link then rears 2.75 km downstream through the cluster rule": link's rearing on blk
    359497146 is 2.75 km in total, of which 0.28 km is the 2,771–3,051 m spawning piece itself; the
    rearing *downstream* of it is 2.47 km.
  - `:11` "the access and BT habitat files it cites last changed on 2026-04-16 (`50688d5`)": true for
    the three SQL files, but `01_model_access_natural.sh` (also cited) last changed 2026-01-05
    (`9fdcbc7`). Still before the snapshot (the local `fresh.streams_vw_bcfp` file was last written
    2026-08-31), so the conclusion holds.
