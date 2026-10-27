# Where streams break: bcfishpass and link, step by step

**Verified:** 2026-10-27 · **Issues:** #324 (from #319), #326; history #29, #45, #96, #223, fresh#160 ·
**Produced by:** a read of `smnorris/bcfishpass@620dbe4` (`model/01_access/`,
`.github/workflows/ng-prod.yaml`), `data-raw/habitat_diff_segments.R`,
`data-raw/logs/rearing_diff_324/mechanism.R` and `breaks.R` → `data-raw/logs/rearing_diff_324/`,
`data-raw/breaks_diff.R` → `data-raw/logs/segmentation_326/`, and the planning archives cited
below · **Status:** the difference is explained; #326 breaks where bcfishpass does

## How bcfishpass breaks streams

`01_model_access_natural.sh`, run by `ng-prod.yaml` (the build our reference snapshot comes
from) with five models: `bt ch_cm_co_pk_sk ct_dv_rb st wct`. The CWF test workflow runs four,
without `ct_dv_rb`.

1. For each model, `model_access_<model>.sql` builds that model's barriers: its gradient
   classes, falls and subsurface flow, minus the barriers its own observation and habitat rules
   lift, in the groups its own rule allows.
2. It deletes every barrier with another barrier of the same model downstream, leaving the
   downstream-most per flow path. This runs **after** step 1's lifts.
3. `break_streams()` cuts the network at observations, then at each model's remaining barriers,
   then at `user_habitat_classification` endpoints, then at crossings.

The five scripts differ, and each difference changes where streams break:

| model | gradient classes | groups built in | observations that lift a barrier | lifts at | since | control table | habitat lifts |
|---|---|---|---|---|---|---|---|
| `bt` | 25, 30 % | BT present | BT, CH, CM, CO, PK, SK, ST | ≥ 1 | any date | no | BT + salmon + ST |
| `ch_cm_co_pk_sk` | 15, 20, 25, 30 % | any of CH, CM, CO, PK, SK present | CH, CM, CO, PK, SK | ≥ 5 | 1990 | yes | salmon |
| `st` | 20, 25, 30 % | ST present | salmon + ST | ≥ 5 | 1990 | yes | salmon + ST |
| `wct` | 20, 25, 30 % | WCT present | WCT | ≥ 1 | any date | no | none |
| `ct_dv_rb` | 25, 30 % | a fixed list of 14 groups (CCIRA, LDEN / UDEN, COWN), not presence | BT, DV, CT, RB | ≥ 1 | any date | no | any species |

## How link breaks them today

Since #326, `.lnk_pipeline_prep_minimal()` (`R/lnk_pipeline_prepare.R`), then `lnk_pipeline_break()`:

1. **Lifts match bcfishpass's per script.** The bcfishpass bundle's `parameters_fresh.csv`
   carries each row of the table above: `observation_threshold`, `observation_date_min`,
   `observation_species`, `observation_control_apply`. The five salmon rows are identical, so
   per-species sets equal bcfishpass's pooled model. Built in #25, #44, #48, #88 and #90.
2. **Groups: by presence.** A break set is built for each species in `cfg$species` that
   `lnk_presence()` finds present in the group, with the salmon and `ct_dv_rb` group
   expansion. bcfishpass builds `ct_dv_rb` only in a fixed list of 14 groups; link has no such
   model.
3. **Reduction after the lifts.** Each species' set is gradient at its classes, falls and
   (bcfishpass bundle) subsurface flow, minus that species' rows in the group's
   `barrier_overrides`, plus every user-definite barrier. `fresh::frs_barriers_minimal()`
   keeps the downstream-most position per flow path, per species, never on the union. Only
   those positions, and the independent `falls`, `barriers_definite` and `subsurfaceflow`
   sources, break the network.

Two residuals are named, not fixed. **Cross-group lifts:** the reduction lifts by the group's
own overrides, while the access view lifts by every group's persisted rows. So where another
group lifts its copy of a shared barrier and this group does not, that position still prunes
the frontier above it here. Reading the persisted table at prepare time made segmentation
depend on host and run order, so it was refused (#326 review round 2). **Classify's scope:**
classify's access gate reads the group's gradient barriers only, while the per-species sets
span whole lines, so a frontier pruned by an out-of-group barrier is classify-accessible above
it until `lnk_habitat_gate()` settles the persisted flags. Measured on m4 (2026-10-27): both
are 0. Classify scope was counted on PCEA BT and LFRA BT / CH / CO / ST; cross-group lifts over
the 11 cross-section groups, where 38 rows carry another group's override and each holder lifts
too. The province-wide cross-group count waits for the provincial run.

## Measured since #326

`bcfishpass` config into m4's `fresh` on the 11 cross-section groups, and `default` on PCEA,
FINA, PARS and LKEL, at link `21e0fea2` on fresh 0.43.0 (2026-10-27, round 2). Evidence is
`data-raw/logs/segmentation_326/` (its README).

| Group | link segments | bcfishpass segments | link-only breaks | bcfishpass-only breaks |
|---|---|---|---|---|
| BULK | 42,989 | 42,965 | 28 | 7 |
| ELKR | 38,245 | 38,214 | 33 | 4 |
| FINA | 28,650 | 28,650 | 0 | 0 |
| KISP | 30,873 | 30,852 | 22 | 1 |
| KOTR | 37,674 | 37,610 | 61 | 3 |
| LFRA | 27,612 | 27,442 | 158 | 2 |
| LKEL | 3,374 | 3,360 | 14 | 0 |
| MORR | 29,100 | 29,093 | 8 | 2 |
| PARS | 43,776 | 43,655 | 114 | 6 |
| PCEA | 37,972 | 37,957 | 15 | 0 |
| USKE | 27,255 | 27,268 | 1 | 15 |

- **The 454 link-only breaks have named sources:** falls 129, observations, crossings and habitat
  endpoints 320, gradient 4, user-definite 1. Before #326, PCEA alone had 68,118.
- **`default` segments drop 2.1 to 2.7-fold:** PCEA 106,079 → 39,566, FINA 70,329 → 30,136,
  PARS 97,537 → 46,341, LKEL 7,448 → 3,378.
- **Parity:** 120 of 122 pairs within tolerance, with accessible km 44 of 44 within 0.11 %. The
  two pairs over are BULK SK (parked). #223's FINA frontier at 3,834.78 m holds.
- **BT habitat, segment by segment:**

  | Group | Rearing link-only / bcfishpass-only (km) | Spawning link-only (km) |
  |---|---|---|
  | FINA | 0 / 0.06 | 4.6 |
  | PCEA | 0.1 / 1.2 | 1.8 |
  | PARS | 0 / 8.1 | 5.5 |
  | LKEL | 0 / 0 | 0 |

  The segmentation movement of 71–85 km per BT-only group is gone. PARS's 8.1 km are order-1
  lines the direct-child test in `frs_order_child()` leaves out (fresh#158; 10.7 km fail it).
  Before the exception it was −24.8 km. Link-only spawning is the deferred strict `>`.
- **Accessible segments that still hold a barrier more than 1 m inside them:** 27
  segment-species on 13 positions, BT 9. Each barrier is 1.07 to 1.43 m from its nearest break.
  This is #349's metre-rounded family (fresh#258). A first run also found barrier rows
  `lnk_barriers_unify()` dropped when `FWA_LocateAlong()` returned no point for a measure in
  FWA's millimetre segment gap. That was 11 of 18 BT cases, and it is fixed.
- **The CH / CO / ST / WCT waterbody and edge filter** on the order-1 exception, which
  `frs_order_child()` does not apply, would turn away at most 2.7 km per species per group
  (BULK CH). In LFRA and KOTR it would turn away 0 km.

## Where they differ, and since when

| date | change | what it did to the breaks |
|---|---|---|
| 2026-04 (bcfishpass comparison, fresh#160) | per-model downstream-most reduction adopted (ADMS 27,443 → 677 barriers) | close to bcfishpass, but the reduction ran **before** lifts |
| 2026-05-01 (#96) | falls added to `break_order` | fixed a fall that bcfishpass breaks at (HORS blk 356357296). That case is consistent with step 2: the fall below it is lifted by the observations between them |
| 2026-05-03 (#45) | per-species derivation; presence filter deliberately **not** applied, to stay bit-identical with link's own previous build | the pre-#45 hardcoded models were already unfiltered, so link never filtered by presence |
| 2026-07-03 (#223) | reduction dropped: every position breaks | fixed access (a reduction before lifts let a lifted mainstem barrier prune real tributary frontiers), but doubled segments: FINA 26k → 70k, PARS 48k → 97k, PCEA 34k → 106k, LKEL 3.4k → 7.4k |
| 2026-10-11 (#324) | first direct comparison of break positions | link holds all but 1 of bcfishpass's 24,393 PCEA breaks, plus 68,118 extra |
| 2026-10-27 (#326) | per present species, reduce the **post-lift** set | FINA: 28,650 segments against bcfishpass's 28,650, every one of 20,394 breaks held both ways (`data-raw/logs/segmentation_326/`) |

Before #223, LKEL had 3,376 link segments against bcfishpass's 3,360 today. That is the
segmentation match the earlier work achieved. #223 called its break set "matching bcfishpass,
which segments at every gradient barrier" (`R/lnk_pipeline_prepare.R` comment, NEWS 0.44.0).
Neither half was measured, and step 2 above contradicts the second.

## Why the parity numbers never showed it

- **Mapping-code parity is an exact-key inner join** (`R/lnk_compare_mapping_code.R`, merge on
  `blue_line_key` + `downstream_route_measure`). Each bcfishpass segment joins only the link piece
  starting at the same measure, and link's extra pieces drop out. PARS BT 98.91 % after #223 is
  43,600 joined rows of link's 97,538 segments.
- **`accessible_km` sums each side whole**, and agrees within 0.05 % (44 / 44). Extra breaks do not
  move access.
- **#223's habitat check ran on LKEL only**, where salmon are present and the extra breaks move
  1.4 km. In PCEA, FINA and PARS they move 71–85 km of BT rearing both ways (below).

Only an overlap join, which reconciles both networks, sees segment-level disagreement.

---

The rest of this document is #324's measurement of what the difference does to BT habitat.

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
  `model_access_bt.sql:148-152` filters BT the same way, while `model_access_ct_dv_rb.sql` builds
  only in a fixed list of 14 groups, none of them these), and it deletes non-minimal barriers before
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
    is would also rear the NULL-width lines bcfishpass leaves out. *Since #326* the bundle takes
    it (`yes` for BT, CH, CO, ST and WCT), with fresh 0.43.0's width and gradient tests, and
    the taxonomy entry is retired. PCEA's connection lines now differ by 0 km and PARS's by
    8.1 km ("Measured since #326").
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

## Decided (2026-10-11, operator; implemented in #326 except where noted)

Changed at #326's gate (2026-10-26): `default` breaks for its own present species (GR and KO
at 15 %, RB), so the two configs no longer share one segmentation and the PARS vignette's
`id_segment` join is owed a fix; the strict `>` spawning minimum is deferred to its own issue;
the order-1 exception takes bcfishpass's width and gradient tests, but not yet its waterbody and
edge-type filter for CH, CO, ST and WCT (an open decision on #326).

The `bcfishpass` config is there to match bcfishpass step by step wherever link can.

- **Both configs break where bcfishpass does:** in the groups each model's own rule allows (the
  "groups built in" column above), the access barrier set after observation and habitat lifts,
  reduced to the downstream-most position per flow path
  (`01_model_access_natural.sh`: build per model, delete non-minimal, then `break_streams()`).
  A break above a species' first barrier changes nothing for that species, so there is no reason
  for `default` to differ, and keeping both on one segmentation keeps the PARS vignette join on
  `id_segment` valid (`data-raw/wsg_vignette_data.R`). #223's failure was reducing the
  pre-override set (below), not reducing as such.
- **The `bcfishpass` config takes bcfishpass's order-1 width exception.** fwapg models no width
  on order 1 (`stream_order > 1` in its channel width SQL; PARS order 1: 552 field-measured,
  4 river-polygon, 19,184 NULL, 0 modelled), so in practice the exception admits order-1 lines
  only on a measured width. Whether `default` takes it, on measured widths only, is a separate
  decision.
- **Spawning size minimum: the `bcfishpass` config takes bcfishpass's strict `>`; `default`
  keeps `>=`** (a segment at exactly the minimum spawns). Recorded as an intentional departure in
  `research/default_vs_bcfishpass.md`, §6.

## What #223 matched, and what it asserted

#223 (`planning/archive/2026-07-issue-221-223-accessible-km-parity/`) went through segmentation
in depth, but its question was the opposite one: link had **too few** breaks. fresh's
`frs_barriers_minimal()` had reduced PCEA's gradient break positions to 32 and FINA's to 11, so
a segment straddled BT's barrier and its whole reach read accessible (FINA BT `accessible_km`
+23.6 %). The reduction ran on the gradient + falls set before observation overrides, so mainstem
barriers that the overrides remove still pruned the tributary frontiers upstream of them (FINA blk
359209845); bcfishpass reduces after. The fix fed every per-model position in (PCEA 32 → 82,931 positions).

- **Measured:** `accessible_km` within 0.05 % on 11 WSGs × 8 species. Spawning and rearing km were
  byte-identical before and after on **LKEL only**, a group with salmon present, where the extra
  breaks move 1.4 km.
- **Asserted, not measured:** that the new break set "matches bcfishpass" (the archive README, the
  `R/lnk_pipeline_prepare.R` comment, and the #223 status in `CLAUDE.md`, "bcfp-matching"). Nobody
  compared break positions until #324. The new set is a superset of bcfishpass's breaks (24,392
  of 24,393 in PCEA), with 68,118 extra in PCEA, and in BT-only groups the extra 15 / 20 %
  breaks move BT habitat 71–85 km both ways.
