## Outcome

PCEA's +1.87 % BT rearing against bcfishpass (bcfishpass config, after #319) is explained and annotated, with no package code changed. Most of it comes from where streams are broken. link breaks at every 15 / 20 % gradient position for every configured species, whatever is present (#223). bcfishpass builds its 15 / 20 % models only where those species live, and breaks at their minimal positions. So in groups with no CH, CM, CO, PK, SK, ST or WCT ("BT-only": PCEA, FINA, PARS), link's segments are finer. Their average gradients flip spawn and rear tests both ways, and the flips join or cut rearing clusters.

Two rule differences sit beside it:
- **Rearing width exception.** bcfishpass rears order-1 lines with parent order ≥ 5 whose known width is below the minimum. That is the whole of #319's −8.2 km on PCEA connection lines, and −24.8 km in PARS.
- **Spawning width test.** bcfishpass spawns on width > 2.0 m; fresh spawns on width ≥ 2.0 m.

A 1.8 km PCEA access residual stays unexplained. The write-up is `research/bcfp_segmentation_parity.md`. The annotations are taxonomy class `SEGMENTATION` plus two class-B entries. A follow-up issue (should the bcfishpass config break and test width where bcfishpass does?) is drafted but not filed.

What was learned about the method:
- Join the two segmentations on measure overlap per `blue_line_key`, and drop sub-centimetre slivers. The slivers come from FWA measure overshoot of up to 3.93 mm within each side.
- Quote every figure from an artifact and say which scope it covers: the rearing flag, the rollup's `rearing` row, or its stream slice.

## Measurement

On the rollup's `rearing` row (link − bcfp km), segmentation (rear gradient plus connectivity on split streams) nets:

| WSG | segmentation net | moved in both directions | row net |
|---|---|---|---|
| PCEA | +26.22 | 70.8 | +30.33 |
| FINA | −13.04 | 73.4 | −12.88 |
| PARS | +9.81 | 84.9 | −13.83 (the width exception is −24.78) |
| LKEL | +1.41 | 1.4 | — |

- LKEL is the control with CH, CO and ST present.
- Each row net reconciles to the parity cross-section.
- link's segment breaks hold all but 1 / 14 / 34 / 5 of bcfishpass's. PCEA has 68,118 extra link breaks: 29,959 at 25 / 30 %, 19,888 at 20 %, 18,254 at 15 %, plus 17 others.
- Spawning width rule (link-only BT spawning): PCEA 1.78 km, FINA 4.54 km, PARS 5.27 km.

Wrong turns, kept:
- The first diagnosis blamed fresh's orphan-class path. It is the CH / ST per-model loop.
- Connectivity attribution first read only "spawning differs on the same stream". It needed any gradient split.
- `/code-check branch` ran six rounds, and rounds 2–5 each found a defect inside the previous fix:
  - slivers;
  - their wrong cause;
  - one group's sign generalised to another;
  - flag-scope figures quoted on the `rearing` row.
- The loop ended by enumeration. Every claim is in `review-enumeration.md`, and round 6 recomputed both rollup scopes from the DB.

## Evidence

- `data-raw/logs/rearing_diff_324/*`: `habitat_diff_segments.R` pieces and summaries, `mechanism.R` attribution with `*_mechanism_net.csv` (scopes flag / `rearing` / `rearing_stream`), and the `breaks.R` census.
- The reviews are in this directory: `review-round*.md` and `review-enumeration.md`.

Closed by: PR for branch `324-pcea-link-bcfishpass-config-flags-differ` (#324)
