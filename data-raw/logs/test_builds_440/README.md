# test_builds_440 — `default` at the minimal run's code (#440)

**2026-11-02, m4, link `4069fdfc` (0.78.0, the code PR #443 pins), fresh 0.52.0.** KETL, KOTL, BULK and MURT built under
`default` into scratch `zz440_default` and recomputed (`run.sh`, `status.tsv`). MURT is the group where only paused
species are present. KOTL's recompute exited 1 on the downstream-dam post-condition (`BLOCKED (link#227)`): its dam
lies in a group this schema does not hold, and the check runs after the recompute's work has committed, as in
`../minimal_breaks_415/run.sh`'s pass rule.

## Against the same groups at fresh 0.52.0 (`zz432_post`, link `a6942b5d`)

`compare.R` (copied from `../species_paused_432/`, output path changed): **identical.** Segments, break positions,
barrier and override rows, accessible, spawning and rearing km per species, and the segment under each fish record
are the same in all four groups (`summary.csv`, `km.csv`, `obs.csv`, `compare.log`). The code between `a6942b5d` and
0.78.0 moves nothing in `default`'s output.

## Against the last provincial build (m1 `fresh_default`, 2026-10-23, link 0.68.0, fresh 0.42.0)

`summary.R`, run on each host against its own schema (`summary_m1_fresh_default.csv`, `summary_zz440_default.csv`;
`summary_zz432_post.csv` beside them):

| group | segments, provincial | now | barrier rows, provincial | now |
|---|---|---|---|---|
| BULK | 87,640 | 42,458 | 60,990 | 61,005 |
| KETL | 102,101 | 41,394 | 81,149 | 81,174 |
| KOTL | 109,951 | 38,287 | 92,588 | 92,628 |
| MURT | 37,569 | 14,403 | 25,742 | 25,765 |

- **Segments fall 2.1- to 2.9-fold:** streams break only where a modelled species' access changes (#326) and at each
  species' top record per line (#396).
- **KO and RB have no habitat or access** (paused, #432). In MURT, where only RB was present, the group is still
  built, with no habitat.
- **BULK gains chum** (5,164 km accessible, 1,862 km spawning), from #402's presence review.
- **Barrier rows rise 15 to 40 per group.** That is the scale #326's change to `lnk_barriers_unify()` restored (rows
  `FWA_LocateAlong()` could not place, 4 to 31 per group lost before); not checked row by row.
- **Accessible km move by 0.0 to 0.3 %, spawning and rearing by under 1 %** for every species modelled in both
  (KOTL BT rearing 2,179 to 2,167 km, KETL WCT spawning 1,387 to 1,377 km).

The `bcfishpass` parity re-score at the same code is `../parity_0.78.0/` and `research/bcfishpass_parity.md`.
