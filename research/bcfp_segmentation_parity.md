# Segmentation parity with bcfishpass, and what it does to BT habitat

**Verified:** 2026-10-11 · **Issues:** #324 (from #319) · **Produced by:**
`data-raw/habitat_diff_segments.R`, `data-raw/logs/rearing_diff_324/mechanism.R` and
`breaks.R` → `data-raw/logs/rearing_diff_324/` · **Status:** explained and annotated
(`research/bcfp_divergence_taxonomy.yml`, class `SEGMENTATION`); no code change

Reference: local `fresh.streams_vw_bcfp`, against the `fresh` schema (bcfishpass config),
which PCEA last modelled at link 0.50.0 / fresh 0.33.0 (2026-09-02). Upstream SQL read at
`smnorris/bcfishpass@620dbe4` (model run 142, `v0.7.15-50-g620dbe43`); the access and BT
habitat files it cites last changed on or before 2026-04-16 (`50688d5`;
`01_model_access_natural.sh` on 2026-01-05, `9fdcbc7`), before the snapshot.

## The question

After #319, PCEA BT rearing read +1.87 % against bcfishpass, with lake connection lines
−8.2 km and everything else +30.3 km. Accessible km agree (PCEA BT 5,003.0 / 5,003.4,
−0.01 %, `data-raw/logs/lake_connection_319/parity_crosssection_after.txt`), so the difference
is in the `rearing` flag.

## Method

The two sides are segmented differently (PCEA: 106,079 link segments against 37,957, the
same 14,315.7 km), so an exact `(blue_line_key, downstream_route_measure)` join is wrong.
`habitat_diff_segments.R` cuts both networks into their measure-interval overlaps per
`blue_line_key` and carries each side's segment attributes onto every piece. It stops unless
the pieces cover both networks and link-only minus bcfp-only equals the flag-total difference
(PCEA: coverage gap 0.0 m, flag gap 0.0 m). Pieces under 1 cm are dropped as slivers. Within
each side a segment's upstream measure can overshoot the next segment's start, by up to
3.93 mm (PCEA: 8,806 times in link, 8,805 in bcfishpass, inherited from FWA), and each overshoot
makes a sliver that pairs the reach above that break on one side with the reach below it on the
other. No segment on either side is under 1 cm. `mechanism.R` then gives each disagreeing piece
one mechanism, first match wins.

## Result

BT `rearing` km, link − bcfp, by mechanism (bcfishpass config). This is the rollup's `rearing`
row, which leaves lake connection lines out (#319); each total reconciles to the parity
cross-section (PCEA 1,655.8 − 1,625.5 = +30.3 km):

| WSG | rear gradient | connectivity, split stream | connectivity, other | width exception | access | net | segmentation net | segmentation gross |
|---|---|---|---|---|---|---|---|---|
| PCEA | +21.72 | +4.51 | +3.52 | −1.22 | +1.80 | +30.33 | +26.22 | 70.8 |
| FINA | +12.21 | −25.25 | −0.06 | 0 | +0.23 | −12.88 | −13.04 | 73.4 |
| PARS | +19.28 | −9.48 | +0.21 | −24.78 | +0.94 | −13.83 | +9.81 | 84.9 |
| LKEL | +0.07 | +1.34 | 0 | 0 | +0.24 | +1.65 | +1.41 | 1.4 |

From `<wsg>_bt_mechanism_net.csv`, scope `rearing`; the same file has the `flag` scope (connection
lines in) and the `rearing_stream` slice. Segmentation is rear gradient plus connectivity on a
stream that carries its own gradient split. Rear gradient and connectivity move km both ways; the
table nets them.

**Connectivity, other** (≤ 3.91 km gross per group, PCEA) is rearing where both segments pass the
thresholds and the stream carries no gradient split of its own. A split on a neighbouring stream of
the same cluster would explain it, but that is not shown, so it is not counted as segmentation.

### Segmentation is the cause

- **link's breaks hold almost all of bcfishpass's.** Of bcfishpass's breaks, 24,392 / 24,393
  (PCEA), 20,378 / 20,392 (FINA), 30,699 / 30,733 (PARS) and 2,549 / 2,554 (LKEL) have a link
  break within 1 m. PCEA's 68,118 extra link breaks are gradient positions: 29,959 at
  25 / 30 %, 19,888 at 20 % and 18,254 at 15 %, plus 15 falls and 2 crossings.
- **Why link has them.** `.lnk_pipeline_prep_minimal()` builds a break set for every species
  the config models, deliberately not filtered by WSG presence, and feeds the raw positions
  into the network (#223): every 15 / 20 / 25 / 30 % gradient position breaks it.
- **Why bcfishpass does not.** Its 15 % (CH / CM / CO / PK / SK) and 20 % (ST, WCT) models build
  barriers only in groups where their species are present (`model_access_ch_cm_co_pk_sk.sql:146-150`;
  `model_access_bt.sql:148-152` filters BT the same way, while `model_access_ct_dv_rb.sql` has no
  presence filter but is a 25 / 30 % model), and it deletes non-minimal barriers before
  `break_streams()` (`01_model_access_natural.sh`). None of those 15 / 20 % species is present in
  PCEA, FINA or PARS (they hold BT, DV, GR and RB, and PARS KO), so bcfishpass never breaks at a 15
  or 20 % position there. This document calls such groups **BT-only**. In LKEL, where CH, CO and ST
  are present, it breaks at their minimal positions.
- The 25 / 30 % extras lie above BT's own frontier, so they do not touch BT habitat. (The
  comment at `R/lnk_pipeline_prepare.R` that bcfishpass "segments at every gradient barrier"
  does not hold for these: 29,959 of PCEA's 35,022 link breaks at 25 / 30 % positions have no bcfishpass
  break.)

### How finer segments move habitat

- **Rear gradient.** A threshold is tested on a segment's average gradient. Where link splits
  one bcfishpass segment, its pieces sit either side of the average, so some pass
  `rear_gradient_max` (0.1049) where the parent failed, and some fail where it passed.
- **Spawning** moves the same way, plus one rule difference (`<wsg>_bt_spawning_mechanism.csv`).
  In PCEA (link 925.7 / bcfp 918.5 km), 7.30 of the 9.29 link-only km and all 2.05 bcfp-only km
  are spawn-gradient flips at 0.0549. Another 1.78 km lie on segments whose width is exactly
  2.0 m: bcfishpass spawns on width > `spawn_channel_width_min` (`load_habitat_linear_bt.sql:27`),
  fresh on width ≥ it (`channel_width BETWEEN`, `.frs_rules_to_sql()` in fresh `R/utils.R`, the
  same at v0.33.0, which built these groups). The width rule is 4.54 km in
  FINA and 5.27 km in PARS. The last 0.21 km in PCEA is the access residual below. Rearing's width
  test is `>=` on both sides.
- **Connectivity.** Both sides keep rearing only in clusters connected to spawning, so a flip
  carries along the stream:
  - **Joining** (PCEA blk 359497146): link breaks at 3,051 m, at a 15 % position (3,050.8 m). Its
    2,771–3,051 m piece is 4.3 % and spawns; bcfishpass's 2,771–3,329 m segment is 7.2 % and
    does not. link then rears 2.75 km on the stream, 2.47 km of it downstream of that piece
    through the cluster rule, and bcfishpass rears nothing on that stream.
  - **Cutting** (FINA blk 359421737): link carves 1,036–1,267 m (13.6 %) out of bcfishpass's
    393–1,267 m segment (10.2 %, rears). That splits the cluster, and 5.5 km of rearing above
    it loses its connection to the 0.39 km of spawning at the mouth.
- The parts carry different signs. Rear-gradient flips are positive in all three BT-only groups
  (+21.72, +12.21, +19.28). Connectivity on split streams is positive in PCEA (+4.51) and negative
  in FINA (−25.25) and PARS (−9.48). In FINA connectivity outweighs the gradient flips, so its
  segmentation net is negative; PARS's whole-group net is negative only because of the width
  exception below.

### Two smaller mechanisms

- **bcfishpass's width exception.** Its BT, CH, CO, ST and WCT rearing admits an order-1 line
  with parent order ≥ 5 whose channel width is below the minimum (`load_habitat_linear_bt.sql:90-97`).
  The exception sits inside `channel_width <= max`, so a NULL width is never admitted: of PCEA's
  3,306 such bcfishpass segments, 3,236 have no width and none of them rears. The bcfishpass
  bundle sets `rear_stream_order_bypass = no` (`dimensions.csv`).
  - In PCEA it is −8.37 km on the connection lines (the `rearing_lake_connection` row), offset by
    +0.17 km of link-only rearing there, which nets the row's −8.21 km: two 1450 lines (blks 359386479, 359555604) in a lake on an order-9 stem. In the `rearing`
    row it is the other 1.22 km (0.99 km of edge 1000, 0.21 km of edge 1050 in a wetland,
    0.02 km of a 1450 line outside a lake).
  - In PARS it is 24.78 km on 54 lines, none of them connection lines (22.77 km of it in the
    stream slice; the rest is on lake and wetland lines).
  - The taxonomy's `hors-class-stream-order-bypass` entry still calls this fresh-deferred.
    fresh#158 is closed and `lnk_rules_build()` supports the bypass; the bundle declines it.
    Whether it should is open. fresh's `frs_order_child()` has no width test, so taking it as
    is would also rear the NULL-width lines bcfishpass leaves out.
- **Access.** Three PCEA segments (1.8 km) whose downstream end is a subsurface-flow (1410) or
  falls barrier rear in link: its classify-time `accessible` is TRUE there, while
  `streams_access` and bcfishpass read 0. FINA, PARS and LKEL have under 1 km each. Cause not
  established.

## What this means

- At WSG level, link on the bcfishpass config reproduces BT rearing to within 0.5–1.9 % in these
  four groups. Under that, segmentation alone moves 71–85 km of the `rearing` row per BT-only
  group in both directions (LKEL, with salmon present: 1.4 km); the width exception, the access
  residual and unattributed connectivity add the rest.
- **For segment-level parity in BT-only groups,** link would have to break where bcfishpass
  does: presence-filtered models and minimal positions. That re-segments every group, touches
  #223's access fix, and gives up the presence-independent break set. It is not done here.
- **The `default` config shares the break set,** so its BT habitat is computed on the finer
  segments too. That reads truer to the reach, but it is a choice, and it moves numbers against
  bcfishpass both ways.

## Decided (2026-10-11, operator; not yet implemented)

- **Both configs filter the break set by species presence.** A 15 or 20 % position breaks a
  stream only where a species with that access threshold is present. With no such fish, the break
  gates nothing; it is a side effect of the config listing all eight species. Filtering both
  configs keeps `fresh` and `fresh_default` on one segmentation, which the PARS vignette join on
  `id_segment` relies on (`data-raw/wsg_vignette_data.R`, segmentation-parity guard).
- **Spawning size minimum: the `bcfishpass` config takes bcfishpass's strict `>`; `default`
  keeps `>=`** (a segment at exactly the minimum spawns). Recorded as an intentional departure in
  `research/default_vs_bcfishpass.md`, §6.
- Still open: every position versus the downstream-most per model (below), which matters only
  where salmon are present (LKEL 1.4 km).

## What #223 matched, and what it asserted

#223 (`planning/archive/2026-07-issue-221-223-accessible-km-parity/`) went through segmentation
in depth, but its question was the opposite one: link had **too few** breaks. fresh's
`frs_barriers_minimal()` had reduced PCEA's gradient break positions to 32 and FINA's to 11, so
a segment straddled BT's barrier and its whole reach read accessible (FINA BT `accessible_km`
+23.6 %). The fix fed every per-model position in (PCEA 32 → 82,931 positions).

- **Measured:** `accessible_km` within 0.05 % on 11 WSGs × 8 species. Spawning and rearing km were
  byte-identical before and after on **LKEL only**, a group with salmon present, where the extra
  breaks move 1.4 km.
- **Asserted, not measured:** that the new break set "matches bcfishpass" (the archive README, the
  `R/lnk_pipeline_prepare.R` comment, and the #223 status in `CLAUDE.md`, "bcfp-matching"). Nobody
  compared break positions until #324. The new set is a superset of bcfishpass's breaks (24,392
  of 24,393 in PCEA), with 68,118 extra in PCEA, and in BT-only groups the extra 15 / 20 %
  breaks move BT habitat 71–85 km both ways.
