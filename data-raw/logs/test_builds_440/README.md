# test_builds_440 — `default` at the minimal run's code (#440)

**2026-11-02, m4, link 0.78.0 (the code PR #443 pins), fresh 0.52.0.** KETL built at `4069fdfc`; KOTL, BULK and MURT and all four recomputes logged `7c36b882`, because `expected.txt` for the parity re-score was committed into this checkout while `run.sh` modelled from it (it checks the tree only at start). `R/` is identical between the two, and every row is clean. KETL, KOTL, BULK and MURT built under
`default` into scratch `zz440_default` and recomputed (`run.sh`, `status.tsv`). MURT is the group where only paused
species are present. KOTL's recompute exited 1 on the downstream-dam post-condition (`BLOCKED (link#227)`): its dam
lies in a group this schema does not hold, and the check runs after the recompute's work has committed, as in
`../minimal_breaks_415/run.sh`'s pass rule.

## Against the same groups' last builds (`zz432_post`)

`compare.R` (copied from `../species_paused_432/`; output path changed, and both schemas are required arguments): **identical.** BULK, KETL and KOTL there are link `a6942b5d` at fresh 0.52.0; MURT's newest row is a later rebuild, link `2774f5b2`, logged at fresh 0.48.0. Segments, break positions,
barrier and override rows, accessible, spawning and rearing km per species, and the segment under each fish record
are the same in all four groups (`summary.csv`, `km.csv`, `obs.csv`, `compare.log`). The code since those builds moves nothing in `default`'s output on these groups: `identical.sql` finds no row in
one schema and not the other, either way, in `streams`, `streams_access`, `streams_mapping_code`, `barriers`,
`barrier_overrides` and all 11 `streams_habitat_<sp>` tables (`identical.csv`).

## Against the last provincial build (m1 `fresh_default`, run `20261023_074321-24d85e8c`, link 0.68.0, fresh 0.42.0; `provenance_m1_fresh_default.csv`)

`summary.R`, run on each host against its own schema (`summary_m1_fresh_default.csv`, `summary_zz440_default.csv`;
`summary_zz432_post.csv` beside them):

| group | segments, provincial | now | barrier rows, provincial | now |
|---|---|---|---|---|
| BULK | 87,640 | 42,458 | 60,990 | 61,005 |
| KETL | 102,101 | 41,394 | 81,149 | 81,174 |
| KOTL | 109,951 | 38,287 | 92,588 | 92,628 |
| MURT | 37,569 | 14,403 | 25,742 | 25,765 |

- **Segments fall 2.1- to 2.9-fold.** The changes since 0.68.0 that remove breaks are #326 (only where a modelled
  species' access changes), #396 (each species' top record per line) and #432 (KO and RB add no gradient breaks; #433
  measured 0.2 to 6.0 % fewer segments for it alone). Not decomposed here.
- **KO and RB have no habitat or access** (paused, #432). In MURT, where only RB was present, the group is still
  built, with no habitat.
- **BULK gains chum** (5,164 km accessible, 1,862 km spawning), from #402's presence review.
- **Barrier rows rise 15 to 40 per group,** of the order of #326's change to `lnk_barriers_unify()` (rows
  `FWA_LocateAlong()` could not place, 4 to 31 per group lost before); KOTL's 40 is above that range. Not checked row
  by row.
- **Accessible km move by 0.0 to 0.3 %, spawning and rearing by under 1 %** for every species modelled in both
  (KOTL BT rearing 2,179 to 2,167 km, KETL WCT spawning 1,387 to 1,377 km).

The `bcfishpass` parity re-score at the same code is `../parity_0.78.0/` and `research/bcfishpass_parity.md`.
