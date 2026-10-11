# Segmentation parity with bcfishpass, and what it does to BT habitat

**Verified:** 2026-10-11 · **Issues:** #324 (from #319) · **Produced by:**
`data-raw/habitat_diff_segments.R`, `data-raw/logs/rearing_diff_324/mechanism.R` and
`breaks.R` → `data-raw/logs/rearing_diff_324/` · **Status:** explained and annotated
(`research/bcfp_divergence_taxonomy.yml`, class `SEGMENTATION`); no code change

Reference: local `fresh.streams_vw_bcfp`, against the `fresh` schema (bcfishpass config),
which PCEA last modelled at link 0.50.0 / fresh 0.33.0 (2026-09-02). Upstream SQL read at
`smnorris/bcfishpass@620dbe4` (model run 142, `v0.7.15-50-g620dbe43`); the access and BT
habitat files it cites last changed on 2026-04-16 (`50688d5`), before the snapshot.

## The question

After #319, PCEA BT rearing read +1.87 % against bcfishpass, with lake connection lines
−8.2 km and everything else +30.3 km. Mapping-code parity there is ~100 %, so access agrees
and the difference is in the `rearing` flag.

## Method

The two sides are segmented differently (PCEA: 106,079 link segments against 37,957, the
same 14,315.7 km), so an exact `(blue_line_key, downstream_route_measure)` join is wrong.
`habitat_diff_segments.R` cuts both networks into their measure-interval overlaps per
`blue_line_key` and carries each side's segment attributes onto every piece. It stops unless
the pieces cover both networks and link-only minus bcfp-only equals the flag-total difference
(PCEA: coverage gap 14.8 m, flag gap 0.0 m). `mechanism.R` then gives each disagreeing piece
one mechanism, first match wins.

## Result

BT rearing flag km, link − bcfp, by mechanism (bcfishpass config):

| WSG | rear gradient | connectivity | width exception | access | net | gross |
|---|---|---|---|---|---|---|
| PCEA | +21.72 | +8.20 | −9.59 | +1.80 | +22.12 | 86.2 |
| FINA | +12.21 | −25.32 | 0 | +0.23 | −12.88 | 73.7 |
| PARS | +19.28 | −9.27 | −24.78 | +0.94 | −13.83 | 112.6 |
| LKEL | +0.08 | +1.34 | 0 | +0.24 | +1.66 | 1.7 |

Gross is link-only plus bcfp-only km. Each mechanism moves km both ways; the table nets them.
Connectivity on a `blue_line_key` with no gradient split of its own is at most 1.35 km per WSG,
and nothing is left unattributed.

### Segmentation is the cause

- **link's breaks are a superset of bcfishpass's.** Of bcfishpass's breaks, 24,392 / 24,393
  (PCEA), 20,378 / 20,392 (FINA), 30,699 / 30,733 (PARS) and 2,549 / 2,554 (LKEL) have a link
  break within 1 m. PCEA's 68,118 extra link breaks are gradient positions: 29,959 at
  25 / 30 %, 19,888 at 20 % and 18,254 at 15 %, plus 15 falls and 2 crossings.
- **Why link has them.** `.lnk_pipeline_prep_minimal()` builds a break set for every species
  the config models, deliberately not filtered by WSG presence, and feeds the raw positions
  into the network (#223): every 15 / 20 / 25 / 30 % gradient position breaks it.
- **Why bcfishpass does not.** It builds a model's barriers only in groups where that model's
  species are present (`model_access_ch_cm_co_pk_sk.sql:146-150`, `model_access_bt.sql:148-152`),
  and it deletes non-minimal barriers before `break_streams()` (`01_model_access_natural.sh`).
  PCEA, FINA and PARS are BT-only, so it never breaks at a 15 or 20 % position there. In LKEL,
  where CH, CO and ST are present, it breaks at their minimal positions.
- The 25 / 30 % extras lie above BT's own frontier, so they do not touch BT habitat. (The
  comment at `R/lnk_pipeline_prepare.R` that bcfishpass "segments at every gradient barrier"
  does not hold for these: 29,959 of PCEA's 35,022 BT-blocking link breaks have no bcfishpass
  break.)

### How finer segments move habitat

- **Rear gradient.** A threshold is tested on a segment's average gradient. Where link splits
  one bcfishpass segment, its pieces sit either side of the average, so some pass
  `rear_gradient_max` (0.1049) where the parent failed, and some fail where it passed.
- **Spawning** moves the same way (PCEA link 925.7 / bcfp 918.5 km; 7.3 of the 9.3 link-only km
  and all 2.05 bcfp-only km are spawn-gradient flips at 0.0549).
- **Connectivity.** Both sides keep rearing only in clusters connected to spawning, so a flip
  carries along the stream:
  - **Joining** (PCEA blk 359497146): link breaks at 3,050.8 m, a 15 % position. Its
    2,771–3,051 m piece is 4.3 % and spawns; bcfishpass's 2,771–3,329 m segment is 7.2 % and
    does not. link then rears 2.75 km downstream through the cluster rule, and bcfishpass rears
    nothing on that stream.
  - **Cutting** (FINA blk 359421737): link carves 1,036–1,267 m (13.6 %) out of bcfishpass's
    393–1,267 m segment (10.2 %, rears). That splits the cluster, and 5.4 km of rearing above
    it loses its connection to the 0.39 km of spawning at the mouth.
- The net sign is incidental. In PCEA the gradient side wins; in FINA and PARS the cutting
  side does.

### Two smaller mechanisms

- **bcfishpass's width exception.** Its BT, CH, CO, ST and WCT rearing admits an order-1 line
  with parent order ≥ 5 whatever its channel width (`load_habitat_linear_bt.sql`). The
  bcfishpass bundle sets `rear_stream_order_bypass = no` (`dimensions.csv`).
  - In PCEA this is the whole connection-line gap: 8.38 km on two 1450 lines (blks 359386479,
    359555604) in a lake on an order-9 stem, plus 1.2 km of stream.
  - In PARS it is 24.78 km on 54 lines, none of them connection lines.
  - The taxonomy's `hors-class-stream-order-bypass` entry still calls this fresh-deferred.
    fresh#158 is closed and `lnk_rules_build()` supports the bypass; the bundle declines it.
    Whether it should is open.
- **Access.** Three PCEA segments (1.8 km) whose downstream end is a subsurface-flow (1410) or
  falls barrier rear in link: its classify-time `accessible` is TRUE there, while
  `streams_access` and bcfishpass read 0. FINA, PARS and LKEL have under 1 km each. Cause not
  established.

## What this means

- At WSG level, link on the bcfishpass config reproduces BT rearing to within 0.5–1.9 % in these
  four groups. Under that, 74–113 km per BT-only group disagree in both directions, from where
  the network is broken (LKEL, with salmon present: 1.7 km).
- **For segment-level parity in BT-only groups,** link would have to break where bcfishpass
  does: presence-filtered models and minimal positions. That re-segments every group, touches
  #223's access fix, and gives up the presence-independent break set. It is not done here.
- **The `default` config shares the break set,** so its BT habitat is computed on the finer
  segments too. That reads truer to the reach, but it is a choice, and it moves numbers against
  bcfishpass both ways.
