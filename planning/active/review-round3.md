# Code-check round 3 — branch 324-pcea-link-bcfishpass-config-flags-differ

Reviewer: subagent, 2026-10-11. Diff `main...HEAD` (3d606dd). Checked against the committed
artifacts in `data-raw/logs/rearing_diff_324/`, a re-run of
`habitat_diff_segments.R PCEA bt fresh rearing` into the scratchpad (`LNK_OUT`), read-only SELECTs on
local fwapg, and `smnorris/bcfishpass@620dbe4`.

## (a) Mechanism

The author's mechanism is right for the numbers but incomplete. The ledger lists **quantities**.
This round's defects are **causal and quantified statements** ("because measures differ",
"so access agrees", "superset", "the whole gap", "spawn ... flips" applied to all spawning). They were
taken from a reviewer's narrative, an older document, or a generalisation from PCEA, and no
discriminating probe checked them. A number ledger cannot catch that kind of claim. Where it reaches:
the sliver explanation (5 places), the access inference (research doc, issue body), the spawning
attribution (taxonomy `-over`, CLAUDE.md status, research doc), "superset" (CLAUDE.md Facts, issue
body, research doc), and "the whole connection-line gap" (log README).

## (b) Verified, no action

- Every cell of the net/gross table recomputes from `*_mechanism.csv` / `*_summary.csv` and the stamps'
  flag totals: 2023.48−2001.37, 2845.63−2858.51, 2575.08−2588.91, 222.78−221.13.
- The re-run reproduces `pcea_bt_summary.csv` byte for byte in content, with coverage gap 0.0 m and
  flag gap 0.0 m.
- DB: 106,079 / 37,957 segments.
- Break-census sums.
- The 0.52–1.87 % WSG level, from `lake_connection_319/parity_crosssection_after.txt`.
- The width exception, from the pieces: PCEA 8.374 km on two lake-connection 1450 lines with parent
  order 9, plus 1.216 km; PARS 24.78 km on 54 blks, none of them lake-connection lines.
- blk 359497146: 2,750.1 m in total and 2,470.4 m downstream.
- FINA blk 359421737: segments and gradients as stated.
- Upstream: line refs `model_access_bt.sql:148-152` and `model_access_ch_cm_co_pk_sk.sql:146-150`; the
  non-minimal delete before `break_streams()`; the order-1 exception in BT / CH / CO / ST / WCT; the
  file dates; `git describe` = `v0.7.15-50-g620dbe4`.
- The taxonomy matches on `abs(diff_pct)`, so the `link_lt_bcfp` `[0, 3]` range is sound.

## (c) Sliver fix

The 1 cm floor hides nothing real:
- Neither side has a segment shorter than 1 cm in the four WSGs.
- No disagreeing piece remains between 1 cm and 1 m. The shortest is 1.0 m, and no piece shorter
  than 1 m straddles a break.
- The reconciliation still means what it says: coverage closes to 0.0 m.

The cause the fix states is wrong, though (first finding).

## Findings

- **[severity: claim]** The sliver explanation is wrong in four places: `data-raw/habitat_diff_segments.R:90-92`,
  `research/bcfp_segmentation_parity.md:27-29`, `CLAUDE.md:28` (under "Facts not worth re-deriving"),
  and `data-raw/logs/rearing_diff_324/README.md:36-37`. All four say "where both sides break at one
  position their measures differ by a fraction of a millimetre".
  - **The two sides do not differ there.** Of PCEA's 24,393 bcfp breaks, 24,350 have a link segment
    starting at the *identical* `downstream_route_measure`. None differs by between 0 and 1 cm.
  - **The sliver comes from within each side.** Consecutive segments overlap: a segment's
    `upstream_route_measure` overshoots the next segment's `downstream_route_measure`. PCEA has 8,806
    overlaps in link and 8,805 in bcfp, the same FWA-inherited set. There are also about 8,890 gaps,
    up to 3.18 mm.
  - **The overshoot is up to 3.93 mm**, not "a fraction of a millimetre".
  - **Example: PCEA blk 359544279, the round-2 example.** Both sides read
    `[7401.4355, 7485.45076]` then `[7485.44998, …]`. The 0.78 mm sliver pairs link's upper segment
    with bcfp's lower one, although the two sides segment that stream identically.
  - **Why it matters.** This sits in "Facts not worth re-deriving". A reader who trusts "fraction of a
    millimetre" could lower the floor below the real 3.9 mm overshoot, which would bring the
    split-counting artifact back. The fix, 1 cm, is correct; only the stated cause is wrong.

- **[severity: claim]** The access evidence is stale: `research/bcfp_segmentation_parity.md:17`
  ("Mapping-code parity there is ~100 %, so access agrees"). The issue body's "Prior work checked"
  makes the same inference from `research/bcfp_compare_mapping_code.md`.
  - **That table is dated 2026-05-11**, before #223. At that time PCEA BT `accessible_km` was **+40 %**
    off bcfishpass (`research/accessible_km_divergence.md:26`), while the same table read 99.93 % BT
    mapping-code parity. So mapping-code parity did not imply agreement on access.
  - **The conclusion holds today on different evidence:** PCEA BT accessible is 5003.0 / 5003.4,
    −0.01 % (`data-raw/logs/lake_connection_319/parity_crosssection_after.txt:10`). Cite that instead.
  - This is the author's own mechanism (a figure restated from an earlier run), and the ledger has no
    row for it.

- **[severity: claim]** Spawning is attributed to segmentation, but part of it is a width-boundary
  rule difference. The claim sites are `research/bcfp_divergence_taxonomy.yml:147-153`
  (`bt-gradient-segmentation-over`, metric `spawning` for PCEA / FINA / PARS), `CLAUDE.md:18`
  ("finer segments flip BT spawn and rear gradient tests") and `research/bcfp_segmentation_parity.md:71-72`.
  - **What the pieces show.** The link-only spawning that is *not* a spawn-gradient flip is:

    | WSG | not a gradient flip | link-only total |
    |---|---|---|
    | PCEA | 1.99 km | 9.29 km |
    | FINA | 4.54 km | 12.38 km |
    | PARS | 5.27 km | 16.68 km |

    Source: `*_bt_spawning_mechanism.csv`, `spawn_gradient_split = FALSE`.
  - **Almost all of it sits on segments with `channel_width` exactly 2.0.** Gradient and access are the
    same on both sides there. bcfishpass spawns on `cw.channel_width > t.spawn_channel_width_min`, a
    strict comparison (`load_habitat_linear_bt.sql:27` @620dbe4). fresh's size predicate is `>=`
    (`fresh/R/frs_habitat_predicates.R:118`).
  - **So this is a rule difference, independent of segmentation.** It accounts for FINA 4.54 km,
    PARS 5.27 km and PCEA 1.78 km; PCEA's other 0.21 km is the access residual (cw 12.9, `access` 0).
  - **Effect on the claims.** The research doc's "7.3 of the 9.3" is arithmetically right but leaves
    the other 2.0 km unexplained without saying so. The taxonomy tags FINA / PARS spawning, about a
    third of whose link excess is this boundary, as SEGMENTATION.
  - **Effect on rearing:** negligible. Only 0.05 km of PCEA `connectivity_split_on_blk` sits on blks
    whose only "split" is such a piece.

- **[severity: claim, minor]** "Superset" is stated without qualification in two places: `CLAUDE.md:28`
  ("its breaks are a superset of bcfishpass's", under "Facts") and the issue body's Answer bullet.
  - **The census says otherwise:** 34 PARS, 14 FINA, 5 LKEL and 1 PCEA bcfp breaks have no link break
    within 1 m.
  - **The PARS ones are real.** Their nearest link break is 2–85 m away, not rounding.
  - The research doc gives the counts beside the word, but the CLAUDE.md fact does not.

- **[severity: claim, minor]** `data-raw/logs/rearing_diff_324/README.md:19` reads "bcfishpass's
  order-1 width exception (PCEA −9.59, the whole connection-line gap of #319; …)".
  - **That equates −9.59 km with the connection-line gap, which is −8.2 km.** Of the 9.59 km,
    8.37 km is on connection lines and 1.22 km is on stream.
  - The research doc (`:90`) and the taxonomy word it correctly.

- **[severity: claim, nit]** `research/bcfp_segmentation_parity.md:80` says "5.4 km of rearing above
  it". The DB has 5,451.6 m of bcfp rearing at or above 1,267 m on FINA blk 359421737, which is
  5.45 km (5.5 km at one decimal).
  - Also at `:75`, "link breaks at 3,050.8 m": that is the barrier position. link's segment boundary
    is 3,051.0, because the breaks are whole metres.

- **[severity: fragile]** `data-raw/logs/rearing_diff_324/breaks.R:49`: `ORDER BY 1, 3 DESC` does not
  give a unique order when two positions share a count.
  - **This already happens:** LKEL `in_other = TRUE` has CABD 1 and PSCIS 1.
  - **Effect:** a re-run can swap those rows and churn the committed `lkel_breaks.csv`. This is the
    same class as round 1's `pieces` ORDER BY finding, in the sibling script. Add `2` as a tiebreak.
