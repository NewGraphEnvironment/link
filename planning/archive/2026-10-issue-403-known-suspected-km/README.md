## Outcome

`lnk_rollup_wsg()`'s default frame now splits `accessible_km` into `accessible_observed_km` (`access_<sp> = 2`, the species recorded upstream) and `accessible_unobserved_km` (`access_<sp> = 1`). Both sum over the rows `accessible_km` sums, so the pair adds to it within 0.01 km and all three are NA together. `lnk_habitat_validate()`'s `summary` and `data-raw/habitat_validate.R` carry the two columns. The README's printed output now comes from running the README's own code at the branch head; the old block came from a 0.68.0 build that the shown code no longer reproduces (code-check round 1). The gate kept the habitat split and the export out. bcfishpass's habitat "observed" split is codes 2 and 3 of its user habitat classification, a different axis, and the export waits for #399 and #401. The write-up is `research/known_suspected_km.md`. The code check ran four rounds and ended on an enumeration of 55 prose claims against their sources. Its three real findings were all prose written from a stand-in rather than read off the artifact: an older build, a plan's paraphrase, a count.

## Measurement

- **The identity holds** on all 50 group-species rows of #396's five groups, in both of its `default` builds on m4. The largest gap is 0.010 km, the two-column rounding bound.
- **How much of the accessible network has a record upstream:** 0.3 % (ELKR grayling) to 42 % (LKEL coho). Under `top_per_species` observed km only rose, by at most 2.29 km, and accessible km did not move.
- **Against bcfishpass** (BULK, PARS, `bcfishpass` config): accessible km agree within 1.3 km. link's observed km run 1.9 to 29.7 km higher per species. Every disagreeing piece is on a segment that starts within 1 m of a record of the species with no other record upstream, which link counts as observed and bcfishpass does not (#399).
- **The reference view's steelhead code 2 reads sockeye records.** That is a bcfishpass defect, fixed upstream on 2026-10-23 (`smnorris/bcfishpass@3bd2824c`) after the reference build. Steelhead is left out of the comparison.
- **The README's code at the branch head** models PARS in 3.71 min and reproduces #396's after-build of PARS exactly, on another host and fresh 0.47.0 against 0.43.0.

## Evidence

`data-raw/logs/known_suspected_403/` (its README indexes it); `research/known_suspected_km.md`.

Closed by: PR for #403 (branch `403-known-and-suspected-km-per-species-in-th`)
