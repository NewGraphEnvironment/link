# Pausing a species: what it does to segmentation and to tuning

**Verified:** 2026-11-02 · **Issues:** #432 (the switch), #433 (keep or drop a paused species' breaks) · **Produced by:** `data-raw/logs/species_paused_432/compare.R` (its README)

A species a bundle pauses (`species_modelled.csv`, `f`) adds no gradient breaks.
That was chosen on what it does to tuning (operator, 2026-11-01): segmentation
matters where it moves the gradient a habitat rule reads at the records a tuning
scores.

## What moves

Pausing KO and RB in `default` removes gradient breaks wherever a paused species
was the only one at its access class: RB at 25 % without BT, KO at 15 % without
CH, CM, CO, PK, SK or GR. With the presence groups expanded (RB is present
wherever CT or DV is), that is 73 groups. Even where the class stays, a paused
species' own downstream-most positions go (each species' set is reduced after
its own lifts), so BULK, with BT present, still loses 98 breaks.

On six groups built both ways:

- Segments fall by 0.2 % (BULK) to 6.0 % (KETL); MURT, where only RB is present, 5.4 %.
- Accessible km does not move for any modelled species: access reads barrier positions, not segment ends.
- Habitat moves only in KOTL (BT rearing 20.9 km flips, +5.4 km net on 2,161; WCT rearing 9.8 km, −4.8 km net) and KETL (WCT rearing 0.4 km). It moves because a segment's gradient is averaged over its length, and longer segments average across what were separate steep and gentle pieces.
- 33 of KOTL's 1,473 fish records of modelled species sit on a segment that changed, with a median gradient shift of 0.012 (largest 0.083); 4 of KETL's 47 (0.030). No record moved in BULK, NBNK or SALR.

So a pause moves what tuning reads only where steep ground was cut finer by the
paused species, and there by about one percentage point of gradient at a few
percent of the records. A tuning that compares builds across a pause should
compare them on one side of it.

## What does not move

- Barrier and override rows: identical in all six groups. `lnk_barriers_unify()` and `lnk_barrier_overrides()` read every `parameters_fresh` row, so a group's barriers, which other groups' access reads, do not depend on what it models.
- Observation tops and habitat endpoints: they follow presence and the habitat overlay, not the modelled list, so a paused species' records and known-habitat rows still cut streams.
