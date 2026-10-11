# Code-check round 4 (#324): findings

Reviewer: subagent, 2026-10-11. Read-only probes against local fwapg :5432; scripts re-run only into the scratchpad (LNK_OUT / a copied mechanism.R). No repo file changed except this one.

## (a) Mechanism

The stated mechanism ("claims restated without a probe") holds, but it is incomplete in four ways. Each one produced a finding below:

1. **A probe on one group generalised to the others.** The ledger probed the net table's numbers but never the prose that interprets their signs. "In FINA and PARS the cutting side wins" was read off FINA and is false for PARS (finding 1).
2. **A predicate probed on its populated rows, never on its NULL branch.** The width exception was checked for species coverage, and its effect was checked on the 9 PCEA pieces, all of which have a width. Its behaviour on NULL width is the opposite of "whatever its width" (finding 3).
3. **Categorical fields are claims too.** The taxonomy's `status` and `class` values assert things ("someone decided this", "this row is segmentation"), and the ledger has no row for any of them (findings 1 and 4).
4. **A round-3 fix changed a shape that other text depended on, and that text was not swept.** The spawning classifier went from TRUE/FALSE to four mechanisms, but `split_blk` and its comment still treat every spawning disagreement as a gradient split (finding 7). The sliver rewrite left a half-sentence behind (finding 6).

## Findings

- **[claim] research/bcfp_segmentation_parity.md ("The net sign is incidental … in FINA and PARS the cutting side does"); issue #324 Answer ("The same mechanism runs in FINA and PARS with the opposite net sign"); research/bcfp_divergence_taxonomy.yml `bt-gradient-segmentation-under` ("here the bcfishpass side wins", wsg includes PARS)**: the claim is false for PARS.
  - PARS's segmentation net is rear gradient +19.28 plus connectivity −9.27 = **+10.01 km**. The gradient side wins in PARS, the same sign as PCEA (`pars_bt_mechanism_net.csv`).
  - The PARS row is negative (−13.83) only because of bcfishpass's width exception (−24.78). That is a bundle-rule difference, not segmentation.
  - Only FINA has the cutting side winning (+12.21 against −25.31).
  - So PARS BT rearing is tagged class `SEGMENTATION` with a mechanism sentence that is wrong for it. The issue body tells readers that segmentation flips the sign in PARS.
  - The same misreading is in `planning/active/findings.md` Controls ("FINA and PARS, where the connectivity side wins").

- **[claim] research/bcfp_segmentation_parity.md "What this means" ("74–113 km per BT-only group disagree in both directions, from where the network is broken"); also CLAUDE.md "Mechanism:" bullet and the taxonomy SEGMENTATION comment, which present the gross figure as the measure of segmentation**: the gross includes disagreement that is not segmentation.
  - It includes the width exception and the access residual: PCEA 9.59 + 1.80, PARS 24.78 + 0.94.
  - The rear-gradient plus connectivity gross is about 74.9 (PCEA), 73.5 (FINA) and 86.9 (PARS) km. The 113 km upper end is 23 % non-segmentation.

- **[claim] research/bcfp_segmentation_parity.md "Two smaller mechanisms" ("admits an order-1 line with parent order ≥ 5 whatever its channel width"); issue #324 bullet ("whatever their width"); taxonomy `pcea-bt-connection-width-exception` mechanism and comment ("whatever their width")**: the claim is wrong, and the predicate is the reason.
  - bcfishpass's predicate is `cw.channel_width <= rear_channel_width_max AND (cw.channel_width >= min OR (order_parent >= 5 AND order = 1))` (`load_habitat_linear_bt.sql:92-96`, 138-142 and 225-229 @620dbe4). With a NULL width the first conjunct is NULL, so the exception never admits a line that has no modelled width.
  - That is the common case. In PCEA, 3,236 of 3,306 order-1 / parent ≥ 5 segments in `fresh.streams_vw_bcfp` have NULL width (1,910.8 km). None of them has a row in `fwa_stream_networks_channel_width`, and bcfishpass rears 0 of them. FINA has 2,328 / 2,355, PARS 4,156 / 4,644 and LKEL 371 / 391.
  - **Why it matters:** the open follow-up asks whether the bundle should take the bypass. fresh's `frs_order_child()` has no width test (`fresh/R/frs_order_child.R:182-197`), so turning it on would admit those NULL-width lines, which bcfishpass does not rear. "Whatever their width" hides exactly that.
  - **Same defect, latent, in the code:** `mechanism.R`'s `bypass` uses `!pass_c(p$b_cw)`, which counts NA width as eligible. No current bypass piece has NA width (checked: 0), so the tables are unaffected.

- **[claim] research/bcfp_divergence_taxonomy.yml, `bt-gradient-segmentation-over` (and `-under`) `status: INTENTIONAL`**: the status claims that someone decided these divergences.
  - The rows these entries tag also carry two components that the same branch calls undecided:
    - **The spawning width rule.** CLAUDE.md lists "whether the bcfishpass config should spawn on width > min" as open.
    - **The access residual.** The research doc says "Cause not established".
  - On the spawning rows the entry tags, the width rule is 25–39 % of the net:
    - FINA: 4.54 of +11.52 km.
    - PARS: 5.27 of +15.43 km.
    - PCEA: 1.78 of +7.24 km.
  - The schema has `NEEDS_INVESTIGATION` for this. Alternatively, the width rule could get its own entry, ordered first.
  - `lnk_parity_annotate()` reports this status as the verdict.

- **[claim] research/bcfp_segmentation_parity.md ("8.37 km on two 1450 lines … plus 1.2 km of stream")**: 0.22 km of the "1.2 km of stream" is not stream.
  - The 1.22 km is: 0.99 km of edge 1000; **0.21 km of 1050 inside a wetland polygon** (blk 359544210, `b_wb = wetland`); and 0.02 km of a 1450 line outside a lake (blk 359124578).
  - In the rollup's own vocabulary, 0.21 km of it is `rearing_wetland`. The ledger row for 8.37 / 9.59 checked the totals, not this split.

- **[claim] research/bcfp_segmentation_parity.md:28**: a half-sentence was left over from the round-3 edit.
  - The text reads "Pieces under 1 cm are dropped: where both sides" and then starts a new sentence, "Within each side a segment's upstream measure…".
  - As written, the sentence asserts something about "both sides" that round 3 showed to be the wrong cause.

- **[fragile/claim] data-raw/logs/rearing_diff_324/mechanism.R `split_blk <- p$blk %in% unique(c(s$blk, …))` and its comment ("a gradient split (a rear_gradient piece, or a spawning disagreement of either kind below)")**: this was not updated when round 3 replaced the TRUE/FALSE spawning split with four mechanisms.
  - `s$blk` now includes `spawn_width_min` and `access` spawning pieces. A connectivity piece on a stream whose only spawning disagreement is the width rule is therefore labelled `connectivity_split_on_blk`, and the docs attribute that label to a gradient split from segmentation.
  - Measured with `s$blk[s_grad]` instead: PCEA moves 0.05 km (2 blks) from split to other, so `connectivity_other_gross` is **4.01**, not the 3.96 km quoted in the research doc, the log README and the ledger. FINA, PARS and LKEL do not move.

- **[claim, low] data-raw/habitat_diff_segments.R sliver comment ("they are dropped, and the reconciliation below allows for their length") against the tolerance comment ("allows that rounding and nothing else")**: the two comments contradict each other, and the first states the wrong mechanism.
  - A sliver double-counts its overshoot. With slivers kept, the pieces exceed each side's total by the overshoots. That was Phase 1's 14.8 m coverage gap (progress.md).
  - Dropping them makes coverage exact: a re-run gives 0.0 m. The tolerance does not absorb them, because there is nothing left to absorb.

## (c) Round 3's fixes, one axis over

- **Spawning width classifier:** sound for the current data.
  - Every `spawn_width_min` piece has `l_cw = b_cw = 2` exactly, on edge 1000 / stream, in all four WSGs. Widths are double precision with 2 decimals, so the `< 1e-9` test cannot be fooled by CSV rounding (the nearest values are 2.01, on gradient pieces).
  - **The order of the categories is right for link-only pieces.** Width-2.0 pieces that also flip on gradient (PCEA 0.02 km, PARS 0.13 km) fail bcfishpass's gradient anyway, so 1.78 / 4.54 / 5.27 km is the width-only km.
  - The width rule holds for PCEA, FINA, PARS and LKEL alike: all four are `cw` in the bundle's `parameters_habitat_method.csv`. fresh 0.33.0, which produced the data, spawns on `BETWEEN` (inclusive), so `>=` holds at that version too. The doc cites `size_sql()`, which is later code with the same behaviour.
- **The `split_blk` axis is not sound:** see finding 7.

## Checked and holding (not exhaustive)

- Every figure in the net, mechanism, summary and breaks CSVs quoted in the docs.
- The re-run of PCEA reproduces its summary.
- With the pre-filter script (ec7b838) through the current `mechanism.R`, the net table moves by at most 0.01 km, and 715 of 1,258 pieces are slivers (max 1.9 mm).
- FWA, link and bcfishpass overshoot counts: 8,920 / 8,806 / 8,805, max 3.93 mm.
- 24,350 exact shared breaks. The 42 others sit exactly 1 m off, so "within 1 m" depends on the inclusive `BETWEEN`.
- Both blk examples, including 2.75 / 2.47 km, 3,050.77 m, 5,451.6 m and 393 m.
- The 25 / 30 % extras touch no BT habitat in FINA or PARS either.
- The bcfishpass presence filters (BT, salmon, ST, WCT) and the minimal reduction before `break_streams()`.
- The upstream file dates against the snapshot (relation file written 2026-08-31).
- `.lnk_pipeline_prep_minimal()` is identical at link 0.50.0 (6891468).
- The bundle's species are the eight models.
- `rear_stream_order_bypass` was `no` at 0.50.0.
- fresh#158 is closed.
- The access residual pieces are 1410 / 1000 with `b_access = 0`.
- The 0.5–1.9 % WSG-level range.

/Users/airvine/Projects/repo/link/planning/active/review-round4.md
