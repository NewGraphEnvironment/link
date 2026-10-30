# Accessible km with and without the species recorded upstream

**Verified:** 2026-10-30 · **Issues:** #403 (from #396; blocked by #398, #400, #401; #399 done) · **Produced by:** `data-raw/logs/known_suspected_403/` (its README indexes it): `rollup.R`, `parity_pieces.sql`; after #399, `data-raw/logs/record_at_start_399/` · **Status:** the split ships in `lnk_rollup_wsg()`'s default; the first tables below are a baseline taken before #399, and "After #399" has the same groups since; #401 will move them again

## The rule

`lnk_rollup_wsg()` splits `accessible_km` (`access_<sp> IN (1, 2)`) in two:

- **`accessible_observed_km`:** `access_<sp> = 2`, accessible with a record of the species upstream.
- **`accessible_unobserved_km`:** `access_<sp> = 1`, accessible with no record upstream.

Both sum over the rows `accessible_km` sums, so the pair adds to it within 0.01 km, the
rounding of two columns. All three are NA together where a group has no access build.
`lnk_habitat_validate()`'s `summary` carries all three.

What the columns report is whatever the access walk wrote. Since #399 a record on the same
line counts as upstream of a segment only when it lies at least 1 m above the segment's
start, as in bcfishpass (`RUNBOOK.md` §2c). The tables up to "After #399" were taken before it, when
the walk also counted a record within 1 m of the start.

## How much of the accessible network has a record upstream

Five groups under `default`, after #396 (`top_per_species`). The change column is the
observed km against the same groups built with every observation as a break.

| group | species | accessible km | observed km | observed share | change from #396 (km) |
|---|---|---|---|---|---|
| BULK | BT | 7661.08 | 534.41 | 7.0 % | +0.04 |
| BULK | CH | 5164.47 | 458.90 | 8.9 % | +0.64 |
| BULK | CO | 5164.47 | 657.14 | 12.7 % | +1.15 |
| BULK | PK | 5164.47 | 292.63 | 5.7 % | +0.05 |
| BULK | RB | 8077.12 | 1415.63 | 17.5 % | +0.49 |
| BULK | SK | 5164.47 | 314.48 | 6.1 % | +0.04 |
| BULK | ST | 6553.47 | 523.85 | 8.0 % | +0.30 |
| ELKR | BT | 4320.75 | 835.08 | 19.3 % | +2.29 |
| ELKR | GR | 2421.17 | 8.45 | 0.3 % | 0 |
| ELKR | RB | 3980.17 | 385.40 | 9.7 % | 0 |
| ELKR | WCT | 3760.33 | 1531.48 | 40.7 % | 0 |
| LKEL | BT | 405.00 | 54.17 | 13.4 % | 0 |
| LKEL | CH | 332.03 | 64.18 | 19.3 % | 0 |
| LKEL | CM | 332.03 | 49.09 | 14.8 % | 0 |
| LKEL | CO | 332.03 | 138.36 | 41.7 % | +0.25 |
| LKEL | PK | 332.03 | 59.01 | 17.8 % | 0 |
| LKEL | RB | 407.36 | 104.48 | 25.6 % | 0 |
| LKEL | ST | 370.19 | 64.37 | 17.4 % | 0 |
| PARS | BT | 6882.15 | 842.81 | 12.2 % | 0 |
| PARS | GR | 4441.86 | 596.01 | 13.4 % | 0 |
| PARS | KO | 4441.86 | 197.78 | 4.5 % | 0 |
| PARS | RB | 6665.23 | 879.02 | 13.2 % | 0 |
| UPCE | BT | 5578.70 | 473.27 | 8.5 % | +0.53 |
| UPCE | GR | 3973.44 | 508.23 | 12.8 % | +0.34 |
| UPCE | RB | 5907.29 | 889.42 | 15.1 % | 0 |

Most accessible water has no record of the species upstream: 0.3 % (ELKR grayling) to
42 % (LKEL coho). Accessible km did not move with #396. Observed km only rose, by at most
2.29 km, which fits #396's finding that a segment's code can rise only where its start
moves down.

## Against bcfishpass

link's `bcfishpass` builds of BULK and PARS, against the reference view's own `access_<sp>`
codes (`parity_bcfp.csv`). Accessible km agree within 1.3 km. Observed km do not:

| group | species | link observed km | bcfishpass observed km | link minus bcfishpass |
|---|---|---|---|---|
| BULK | BT | 534.37 | 519.91 | 14.46 |
| BULK | CH | 458.26 | 452.80 | 5.46 |
| BULK | CO | 654.56 | 626.79 | 27.77 |
| BULK | PK | 292.58 | 288.44 | 4.14 |
| BULK | SK | 314.44 | 312.53 | 1.91 |
| PARS | BT | 845.01 | 815.31 | 29.70 |

**One mechanism accounts for all of it** (`parity_pieces.csv`). Every disagreeing piece is
code 2 in link and code 1 in bcfishpass, never the reverse. Every piece lies on a link
segment that starts within 1 m of a record of the species on the same line. That is the
segment above a record. Link's walk counted the record as upstream of it, and bcfishpass
does not. Each species' piece total equals its gap above, to rounding. #399 removed it:
link's walk now counts a same-line record only when it lies at least 1 m above a segment's
start, as bcfishpass's does.

**Steelhead is not comparable against this reference.** bcfishpass's view gives BULK
steelhead the same observed km as sockeye (312.53), against link's 523.55. At the
reference build, bcfishpass coded steelhead's code 2 from sockeye records
(`model/01_access/sql/load_streams_access.sql`, the `access_st` case tests `'SK'`, at
`smnorris/bcfishpass@620dbe43`). Upstream fixed it on 2026-10-23
(`smnorris/bcfishpass@3bd2824c`; their issue 938). The view on m4 predates the fix, so
steelhead needs a re-score against a newer reference (still so after #399, below).

## After #399

Since #399 a same-line record counts as upstream of a segment only at least 1 m above its
start, so the segment starting at each species' highest record on a line reads 1, unless a
tributary entering above it holds a record of the species. The same groups
were built before and after the change on one database, in both configs
(`data-raw/logs/record_at_start_399/`; its builds reproduce the tables above to the
hundredth of a km).

**Only that code moved.** Every segment and segment start is the same in both builds, and
the one change is code 2 to 1 on a segment with a record of the species within 1 m of its
start. Accessible km, barrier flags, mapping codes and habitat do not move
(`pre_post_diff.csv`).

| config | group-species | observed km lost | per group-species | share of observed km |
|---|---|---|---|---|
| `default` | 25 | 346.6 | 0.02 to 73.5 | 0 to 5.4 %, median 1.8 % |
| `bcfishpass` | 7 | 93.6 | 1.9 to 29.7 | 0.6 to 4.2 %, median 1.9 % |

The largest losses are BULK RB (73.5 km, 5.2 %), ELKR WCT (54.3 km), PARS RB (41.2 km) and
BULK CO (29.0 km). In BULK, where both configs were built, each species loses nearly the same
under both (BT 14.5 and 14.5 km, CO 29.0 and 27.8): #403's expectation that `default` would
move more did not hold there.

**Against bcfishpass the observed km now agree.** link minus bcfishpass is 0.00 km for BULK
BT, CH, CO, PK and SK and for PARS BT, from 1.91 to 29.70 km before (`parity_bcfp.csv`).
This reference is a newer bcfishpass build than the one above (`v0.7.15-50-g620dbe4`), and
it still predates the steelhead fix, so steelhead stays apart. No disagreeing piece needed a
record from another group, which is where #401 would show.

## What will move these numbers

- **#401** raises observed km on main stems below a group boundary. Today code 2 reads only
  the group's own records, so a main stem with the species recorded just upstream, in the
  next group, reads 1.
- **#400** decides which records count as "recorded", and can move every row.
- **#398** gives CT its aliases. None of these five groups models CT under `default`.

`fresh_default` needs a re-model at the next provincial run before its numbers carry
any of these.

## What bcfishpass tabulates

`aw_linear_summary()` (`db/schema.sql`, `smnorris/bcfishpass@620dbe43`) reports two splits
per assessment watershed:

- **`length_naturallyaccessible_obsrvd_<sp>` / `_model_<sp>`:** `access_<sp>` 2 and 1. This
  is the split link now reports.
- **`length_spawningrearing_obsrvd_<sp>` / `_model_<sp>`:** habitat codes 2 and 3 against 1.
  Code 2 is set where the model says habitat and the user habitat classification confirms it,
  and code 3 where only the classification does
  (`model/02_habitat_linear/sql/load_habitat_linear.sql`). That is habitat confirmed by the
  classification, modelled or not, against model-only habitat. Spawning and rearing are
  combined, except for CM and PK, which read spawning only. It is not about fish recorded
  upstream.

Both come with `_access_a` (no dam or PSCIS barrier downstream) and `_access_b` (no
anthropogenic barrier downstream) variants.

## Not done, and not filed

- **The split in `lnk_scenario_export()`.** Its Parquet carries habitat flags, not access
  codes. A column there is stored data, and these values still move under #401, so it waits
  for it.
- **A habitat split by the user habitat classification,** matching bcfishpass's
  `spawningrearing_obsrvd`. link matches the classification at gate time and persists no flag
  (`R/lnk_habitat_gate.R`), so this needs that flag first.
- **Spawning and rearing by access code** need no new code. `lnk_rollup_wsg()`'s examples show
  them through `metrics =`. bcfishpass has no such split.
