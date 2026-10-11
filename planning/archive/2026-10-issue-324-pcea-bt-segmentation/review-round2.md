# Code-check round 2 — branch 324-pcea-link-bcfishpass-config-flags-differ

Reviewer: subagent, 2026-10-11. Diff `main...HEAD` (ec7b838), with attention on the round-1 fixes.
Verified against the committed CSVs in `data-raw/logs/rearing_diff_324/`, the local fwapg (read-only
SELECTs) and `smnorris/bcfishpass@620dbe4`.

Verified, no action: the new `pcea-bt-connection-width-exception` entry matches PCEA BT
`rearing_lake_connection` (link_lt, |diff| 2.18 in [0, 5]); no earlier entry shadows it, and the
SEGMENTATION entries shadow no later entry. The `ORDER BY ... id_segment, segmented_stream_id` tiebreak
is unique per piece (`segmented_stream_id` is varchar `blk.measure`, written as a string). `load_all()`
plus `link:::` resolves; stamps read link 0.63.0 = DESCRIPTION. Header tolerance wording now matches
`tol_m`. Break census sums (68,118 = 29,959 + 19,888 + 18,254 + 15 + 2; 35,022 = 29,959 + 5,063;
bcfp-missing 1 / 14 / 34 / 5) match the regenerated `*_breaks.csv`; `fresh.barriers` is one row per
position with a `blocks_species` array, so the GRADIENT class CASE is sound. PCEA blk 359497146:
link rears 2,470.4 m wholly downstream of the 2,771–3,051 m spawning piece (279.7 m), bcfp rears 0 on
the blk, and the 15 % barrier sits at 3,050.77. PARS width exception: 54 blks, all > 1 m, none
lake-connection. Upstream file dates (`50688d5` 2026-04-16 x3, `9fdcbc7` 2026-01-05) confirmed.
Species presence: PCEA / FINA / PARS carry no CH/CM/CO/PK/SK/ST/WCT; LKEL carries CH, CM, CO, CT, PK, ST.

## Findings

- **[severity: claim]** `research/bcfp_segmentation_parity.md:42` and
  `data-raw/logs/rearing_diff_324/README.md:34-35` (root cause `data-raw/logs/rearing_diff_324/mechanism.R:45`)
  — "Connectivity on a `blue_line_key` with no gradient split of its own is at most 1.54 km per WSG
  (gross)" is an artifact of sub-centimetre sliver pieces. The overlap join emits a piece wherever the two
  sides' boundaries at the *same* break differ by fractions of a millimetre (FWA measure float noise), and
  such a piece pairs the reach above the break on one side with the reach below it on the other. Its
  `grad` and its spawning class therefore compare two different reaches, and `split_blk`
  (`p$blk %in% unique(c(s$blk, p$blk[grad & !bypass]))`) counts it as a gradient split on that blk.
  715 of PCEA's 1,258 disagreeing rearing pieces are < 1 cm (FINA 592 / 928, PARS 975 / 1,646, LKEL
  91 / 111). Example: PCEA blk 359544279 carries 2.42 km of link-only connectivity rearing labelled
  `connectivity_split_on_blk`, but every spawning and `grad` piece on that blk is 0.2–1.2 mm long
  (e.g. 7,485.450–7,485.451: link 93383 [7,485.45, 7,494.73] against bcfp [7,401.44, 7,485.45]); both
  sides segment that stream identically. Re-running the attribution with pieces < 1 cm excluded from
  `split_blk` (results identical at a 1 m cutoff): PCEA connectivity_other 1.54 → **3.96 km** gross
  (link-only 1.35 → 3.77), PARS 0.90 → **2.02 km** (bcfp-only 0 → 0.91, link-only 0.90 → 1.11), FINA
  0 → 0.06, LKEL unchanged. The table's net connectivity column (+8.20 / −25.32 / −9.27 / +1.34) is
  unaffected (split + other is the same total), but the stated bound on connectivity *not* explained by a
  split on its own stream is understated by about 2.5x, and the findings table rows
  (`planning/active/findings.md:30-31`, 15.11 / 8.07 and 1.35 / 0.19) carry the same misclassification.
  The same slivers inflate `n_piece` / `n_blk` in every `*_summary.csv` and `n_blk` in
  `*_mechanism.csv` (e.g. PCEA `other` 52 blks at 0 km; FINA `bcfp_only other` 115 blks at 0 km).
  Fix: drop pieces below a length floor (e.g. 0.01 m) in `split_blk`, regenerate, and restate the bound;
  or say the bound counts sub-mm slivers as splits.

- **[severity: claim, minor]** `research/bcfp_divergence_taxonomy.yml:177` (new in ec7b838), also
  `research/bcfp_segmentation_parity.md:88` and `planning/active/findings.md:53` — "8.38 km on two 1450
  lines". From `pcea_bt_pieces.csv`, the bcfp-only lake-connection pieces sum to 8,374.4 m (blk
  359386479 5,818.5 m + blk 359555604 2,555.9 m) = **8.37 km**, which is also what the committed
  `pcea_bt_summary.csv` gives (32.06 − 23.69) and what round 1 reported. The "plus 1.2 km of stream" is
  1,216 m, so the 9.59 total holds either way; only the 8.38 figure is off.
