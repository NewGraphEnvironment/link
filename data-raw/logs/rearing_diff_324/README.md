# rearing_diff_324 — BT spawning and rearing, link (bcfishpass config) against bcfishpass, segment by segment (#324)

Stamp: 2026-10-11 · link 0.63.0 on branch `324-pcea-link-bcfishpass-config-flags-differ` · fresh 0.39.0 installed · local docker fwapg (localhost:5432), schema `fresh` (bcfishpass config; PCEA last modelled 2026-09-02 at link 0.50.0 / fresh 0.33.0, per `*_stamp.txt`) against `fresh.streams_vw_bcfp`

Write-up: `research/bcfp_segmentation_parity.md`. Taxonomy: `bt-gradient-segmentation-over` (PCEA rearing) / `-under` (FINA rearing), `pars-bt-rearing-width-exception`, `bt-spawning-segmentation-and-width`, and `pcea-bt-connection-width-exception` for #319's connection-line row.

| file | what |
|---|---|
| `<wsg>_bt[_spawning]_{summary,pieces,stamp}` | `data-raw/habitat_diff_segments.R <WSG> bt fresh <flag>`: agreement classes (km), every disagreeing measure-interval piece with both sides' attributes, and the environment |
| `mechanism.R` → `<wsg>_bt_mechanism.csv`, `<wsg>_bt_spawning_mechanism.csv` | each disagreeing rearing piece given one mechanism (first match wins); spawning disagreement split by the spawn-gradient threshold |
| `breaks.R` → `<wsg>_breaks.csv` | segment-break census: link breaks matched to bcfishpass within 1 m, labelled by the `fresh.barriers` position they sit on |

## Measurement

BT rearing flag km, link − bcfp: PCEA +22.11 (gross 86.2), FINA −12.88 (73.7), PARS −13.83 (112.6),
LKEL +1.65 (1.7) (`<wsg>_bt_mechanism_net.csv`). In every group the disagreement is attributed: rear-gradient flips and the
cluster connectivity they join or cut (both from link breaking at every 15 / 20 % gradient
position, which bcfishpass does not in BT-only groups), bcfishpass's order-1 width exception
(PCEA −9.59, of which 8.37 km is on the connection lines #319 measured; PARS −24.78), and an access
residual (≤ 1.8 km). Spawning adds a width rule: bcfishpass spawns on width > 2.0 m, fresh on ≥ 2.0 m
(PCEA 1.78, FINA 4.54, PARS 5.27 km).
Moved #324 from "unexplained" to an annotated divergence.

## Evidence

`data-raw/logs/rearing_diff_324/*` — re-run with
`for w in PCEA FINA PARS LKEL; do for f in rearing spawning; do Rscript data-raw/habitat_diff_segments.R $w bt fresh $f; done; Rscript data-raw/logs/rearing_diff_324/mechanism.R $w bt; done; Rscript data-raw/logs/rearing_diff_324/breaks.R PCEA FINA PARS LKEL`
(`habitat_diff_segments.R` loads the source tree itself).

## Wrong turns

- The first plan-mode probe read link's extra breaks as fresh's orphan-class path. They come from the
  per-model loop: the bcfishpass bundle models every species, not only those present.
- First attribution split connectivity by "the same stream carries a spawning disagreement" and left
  21.4 km of FINA unexplained. Row-level on blk 359421737 showed a rear-gradient flip cutting the
  cluster, so the split now counts any gradient flip on the stream; connectivity with no split on its stream fell to
  ≤ 1.54 km per group (gross).
- That bound was still wrong: 715 of PCEA's 1,258 disagreeing pieces were sub-centimetre slivers, each
  pairing the reach above a break with the reach below it. Round 2 put them down to the two sides'
  measures differing at a shared break; round 3 found the measures identical there (24,350 of 24,393
  PCEA bcfp breaks start a link segment at the same measure) and the cause within each side: a segment's
  upstream measure overshoots the next one's start by up to 3.93 mm, inherited from FWA. The slivers
  counted as gradient splits on their stream. The script now drops pieces under 1 cm, which moved the
  net table by at most 0.01 km.
- Connectivity with no gradient split on its own stream is ≤ 4.01 km of the flag per group (gross, PCEA;
  3.91 km of the `rearing` row), once round 4 counted only gradient spawning flips as splits. Round 5 took
  it out of the segmentation columns, since nothing ties it to a split.
- Round 5 also found the taxonomy quoting flag-scope figures on the `rearing` / `rearing_stream` rows;
  `mechanism.R` now writes all three scopes and the taxonomy text quotes none.
