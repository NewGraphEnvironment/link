# Backlog move 10: crossings snapping, and habitat upstream of each crossing (#478)

## Outcome

Two batches in one release, 0.89.0. **Snapping (#313, #314, #383):** `lnk_points_snap()` wraps `fresh::frs_point_snap()`, so a crossing never snaps to a placeholder (`999.*`) stream, and the PSCIS pick and the CABD dam snap give an exact tie at a shared vertex to the segment that starts there. The operator chose fwapg's rule; measuring it on the dams showed that across two streams fwapg's "higher measure" put a lower Fraser barrier dam at the top end of a Fraser side channel, so the rule became `[ds, us)` (the operator's second answer, decision 5). The cut tokens move to `-3`. The #383 sweep measured link's `FWA_LocateAlong` calls before and after fwapg's rework in a rolled-back trial, and live tests gate on that rework. **Habitat upstream of each crossing (#321, #232, #356):** `lnk_aggregate()` was rebuilt on `fresh::frs_aggregate()` with bcfishpass's measure-aware `fwa_upstream`, per species, with below-barrier totals, and checked against bcfishpass's crossings and `crossings_upstream_habitat`; the threshold scripts sum exactly. What is known now is in [`research/crossing_snap.md`](../../../research/crossing_snap.md) and the 2026-11-23 section of [`research/bcfishpass_parity.md`](../../../research/bcfishpass_parity.md).

`/code-check branch` ran four rounds and ended on an enumeration of the 62 numbers the branch publishes (`review-verdict.md`). Code defects it found: two barriers within 1 m were each upstream of the other under `fwa_upstream`'s tolerance; FWA segments overlap, so a point resolved by `[ds, us)` matched two and doubled its upstream sums; `to` and `table_out` guards that let the function drop a table it reads. The rest were prose that did not match its CSV, and measurement stamps that named the wrong code. The mechanism round 3 named: values written from a picture of the system rather than read from the artifact.

## Measurement

- **Snap, province-wide** (19,905 PSCIS, 2,554 dams): placeholder picks 11 → 0; 14 picks change (8 dropped, each with only its placeholder candidate; 3 to a real stream; 3 moved 1 m); 17 dams move to the segment starting at their vertex, under 1 mm. fwapg's rule alone would have put the Crescent Slough dam where 17,657 segments (7,892 km) count as upstream instead of 16 (7.7 km).
- **Re-model under `bcfishpass`**, seven groups at main and the branch: every difference sits at a moved pick or dam, plus one modelled crossing in LILL freed when PSCIS 63445's fifth candidate changed streams in a cross-stream tie.
- **`FWA_LocateAlong`** before and after the rework: PSCIS 0 and 0 misses; sampled barriers 22 → 14 (10 of the 14 in FWA's gaps); the threshold script's capped upper locate 581 → 21.
- **Crossings against bcfishpass** (ADMS, BULK): barrier status agrees on all 9,173 both hold; 27 on one side only. **Per-crossing habitat:** 98 to 100 % of main-stem crossings within 0.1 km in every species and metric; sockeye spawning and the below-barrier totals in BULK are the departures.
- **The defect fixed:** main's `lnk_aggregate()` gave ADMS chinook spawning 774.5 km summed over crossings against 1,349.5 over the network (BULK 4,201 against 22,996).
- **Cost:** the first rebuild took 91.5 min on BULK (immediate barriers per species, `NOT EXISTS`); building them once with `EXCEPT`, then resolving each point's segment once, 0.3 min.
- **Wrong turns kept:** I first told the operator 13,200 crossings (it is 9,173) and 96 to 100 % (98; 96 was the 1 % column), and quoted 15 and 17,656 segments from an ad-hoc query that left equivalents out; the committed producer gives 16 and 17,657. NASR's `default` build stalled twice in the near-river walk beside another session's walk (#487), so the `default` re-model is owed.

## Evidence

`data-raw/logs/snap_tie_478/`, `data-raw/logs/crossings_upstream_478/`, `data-raw/logs/crossings_parity_232/`, `data-raw/logs/habitat_thresholds_284/reruns_356.txt`

## Owed

- The `default` config's scratch re-model of the groups holding a moved crossing (NASR, JERV, LILL, GUIC) against `main`: blocked here by the near-river walk stalling beside another session's (#487).
- #356's two reruns of `query_habitat_thresholds_mad.R`, once a host's `fresh_default` has #481's near-river column.
- Every persisted group in `fresh_default` and `fresh` re-models at the next provincial run if the cut token moved; the pre-run gate runs again (`R/` changed).
- The live tests that need fwapg#41 run for real once the shared database is migrated (fwapg#41's upstream review).
- #341 (barrier rule scenarios) reads the per-crossing table.

Closed by: PR (to be opened from branch `478-backlog-move-10-crossings-snapping-and-h`)
