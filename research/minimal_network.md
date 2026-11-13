# The minimal network

**Verified:** 2026-11-13 (classifying on the parent's gradient; 2026-11-03 parent attributes; 2026-11-02 the proof) · **Issues:** #415 (and #441); #444 (parent attributes); #463, #462 (classifying on it) · **Produced by:** `data-raw/logs/minimal_breaks_415/` (`run.sh`, `proof.R`, `lifts.R`) builds at link `6bf9ca06` (0.78.0), fresh 0.52.0, on m4's local fwapg; `lifts.csv` written by `lifts.R` as of `ac52e150`, with `R/` unchanged since the builds · parent attributes by `data-raw/streams_parent_build.R`, evidence `data-raw/logs/streams_parent_444/` · classifying on it by `data-raw/logs/grad_parent_463/` (`run.sh`, `proof.R`) at link `6f0eea81` (0.81.0) · **Status:** proof run on four groups; both networks built province-wide (#441, #454) and joined (#444); `default_parent` classifies on the join, proved on four groups (#463).

`default_minimal` cuts streams only at gradient barriers where a modelled species' access changes, falls and user-definite barriers. `default` also cuts at each species' highest fish record per line, at known-habitat end points and at crossings (modelled and PSCIS crossings, and dams). Read this beside `species_paused.md`, which measures the same kind of change for pausing a species.

## What the proof answers

**The minimal network is the full network with fewer cuts, and access does not move.** Four groups were built under both bundles from one clean commit: BULK, as #415 asked, and SETN, MORK and COTR, the top three of `pick_groups.sql` (most chinook sites plus most modelled crossings). All four are on `cw`. Every check in `proof.R` passed:

| group | segments, full | segments, minimal | km (both) | minimal cuts with a full cut within 1 m |
|---|---|---|---|---|
| BULK | 42,458 | 36,272 | 14,642 | 26,131 of 26,131 |
| SETN | 80,538 | 72,354 | 26,020 | 44,073 of 44,073 |
| MORK | 51,930 | 45,845 | 17,888 | 30,399 of 30,399 |
| COTR | 28,473 | 21,812 | 8,268 | 16,417 of 16,417 |

- **The minimal network keeps 77 to 90 % of the segments.** Most of its cuts are FWA's own segment ends (`breaks_census.csv`: 19,656 of BULK's 26,131), which every build keeps. The cuts it drops are the records, crossings and habitat end points.
- **Accessible km are the same on both networks** for every species. No piece of 1.01 m or more reads a different access (`access_differences.csv` holds 10 pieces of 1 m, the slivers the 1 m skip rule can leave; RUNBOOK §2).
- **The minimal segments' gradient is the length-weighted gradient of the full pieces they hold:** median difference 0, largest 0.022 (one SETN segment), and at least 99.99 % of km within 0.01 (`gradient.csv`).
- **Each build took about as long:** 2.8 to 6.6 min per group under `default`, 3.0 to 6.5 under `default_minimal` (`status.tsv`).

## What moves

**Code 2 grows by a segment's length above each record.** `access_<sp>` 2 means the species is recorded upstream, and a segment reads 2 when a record sits above its start. With no cut at the top record, the segment holding it reads 2 up to its next cut, so more of the stream above the record reads 2: 0 to 8.5 % per group and species, the most BULK coho (628 to 681 km) and COTR bull trout (663 to 698 km). Accessible km, codes 1 and 2 together, do not move.

**Rearing rises, because coarser segments disconnect less.** The rearing predicate passes about the same km on both networks. The connectivity pass keeps a rearing cluster with spawning anywhere upstream, or with spawning downstream within 10 km along segments no steeper than 0.05, and it drops less on the minimal network. A longer segment's averaged gradient passing that bridge more often is the likely reason, not measured here:

| group | species | rearing km, full | minimal | dropped by connectivity, full | minimal |
|---|---|---|---|---|---|
| BULK | CH | 2,101 | 2,205 | 309 | 203 |
| BULK | ST | 2,634 | 2,756 | 355 | 253 |
| COTR | CH | 1,322 | 1,419 | 260 | 180 |
| MORK | CH | 2,468 | 2,528 | 200 | 143 |
| SETN | CH | 1,012 | 1,018 | 43 | 38 |

So **a rearing threshold tuned on the minimal network is not tuned on the full network's rearing.** It is tuned on the same gradient a full segment would read from its parent, which is what the parent-attribute table is for. Spawning moves by under 1 %, except MORK sockeye, 28.2 to 28.6 km (`connectivity.csv`).

**The user habitat overlay applies to fewer km.** It keeps a flag only where a segment lies wholly inside a range, and no cut falls at a range's end. Under-applied km, of the km the ranges cover: BULK 53 of 291 (11 under `default`), MORK 22 of 454 (0), SETN 19 of 333 (0), COTR 8 of 198 (0) (`overlay.csv`).

**Crossing fields read below the segment's start.** No cut falls at a crossing, so a segment holding one reads as below it:

- `has_barriers_anthropogenic_dnstr` loses 370 to 861 km per group.
- `has_barriers_pscis_dnstr` loses 0 to 287 km.
- `dam_dnstr_ind` gains as well as loses, because the next feature downstream can become a dam: SETN gains 659 km.

These fields should be flagged or dropped on the minimal network (`crossing_fields.csv`; the proof README says what each means).

**A record sits on a longer segment.** Under knowledge's placement rule, records whose segment starts at the record fall from 2,160 to 426 in BULK (from about half of each group's records to a sixth or less). Within each branch of the rule, the median segment is 1.1 to 1.7 times as long (`placement.csv`).

## How far fish records reach the minimal cuts

The minimal network is not independent of the fish records, because barriers are reduced after observation lifts. `lifts.R` rebuilds each group's barrier overrides with no fish records, keeping the known-habitat and control lifts. It then re-runs the pipeline's own minimal prep and break on a copy of the working tables. Two controls passed in every group: the build's own overrides reproduce the build exactly, and every segment start that moves sits within 1 m of a position that moved. The second fires when told no position moved (29 starts in COTR).

A lift moves the minimal barrier positions, and a moved position is a cut only where no cut is already there: an FWA segment's start, or another cut within 1 m, which the break step skips. So the table gives both:

| group | observation lifts | positions removed | positions added | segment starts removed | segment starts added | km of segment changed | of km | records on a changed segment | median gradient shift there |
|---|---|---|---|---|---|---|---|---|---|
| BULK | 200 | 7 | 79 | 6 | 71 | 79.3 | 14,642 | 11 of 1,478 | 0.021 |
| SETN | 151 | 6 | 601 | 5 | 340 | 310.5 | 26,020 | 3 of 1,764 | 0.073 |
| MORK | 18 | 1 | 3 | 0 | 2 | 0.7 | 17,888 | 0 of 315 | |
| COTR | 13 | 1 | 30 | 1 | 29 | 38.1 | 8,268 | 2 of 222 | 0.007 |

- **Only bull trout's observation lifts move positions here.** `default` lifts a natural barrier for BT on one record and for salmon and steelhead on five since 1990. The salmon and steelhead overrides these groups hold are known-habitat and control lifts, which the counterfactual keeps; RB's belong to a paused species, which cuts nothing.
- **A lift adds more cuts than it removes.** With the lowest barrier on a path lifted, the barriers above it become that species' downstream-most positions. In SETN, 6 positions removed gave 601 new ones, 592 of them on lines with no position before. They added 340 segment starts and removed 5, a net 335; the other added positions fall on an existing cut, an FWA segment's start or another cut within 1 m. That is why the changed km is far larger than the count of removed positions.
- **Few records sit on a changed segment** (0 to 0.9 %), the scale #433 found for pausing a species (`research/species_paused.md`: 33 of KOTL's 1,473). The issue's framing of segments that know nothing about where fish were caught holds to that degree, with lifts held fixed. Where a tuning holds records out, as knowledge#131's leave-one-out does, a held-out BT record can still move a cut below it.

Raw numbers: `lifts.csv` (per species and per group), `lifts_obs.csv`.

## Parent attributes: each full segment reads its minimal parent

**Every full segment of the province takes the minimal segment it overlaps most, and all but 96 lie wholly inside it; `fresh_default.streams_parent` names it** (#444). The two provincial builds, `fresh_default` (`cut-full-top`, link `4dfbfa49`) and `fresh_default_minimal` (`cut-min`, link `193cb8aa`), differ on the modelling paths only in `DESCRIPTION`, so they pass the pair guard, and `lnk_streams_parent()` joined all 241 groups on m4 in 3.9 min summed (RUNBOOK §6b, "Parent attributes: `streams_parent`").

| measure | value |
|---|---|
| full segments, each with one row | 5,546,370 |
| minimal segments | 4,987,761 |
| km | 1,887,603 |
| full segments straddling a minimal cut by 1 cm or more | 96 (0.096 km) |
| largest straddle | 1.000 m |

- **The superset holds province-wide:** every minimal cut has a full cut within 1.01 m in every group, as the proof found in four. The 96 straddling segments are cuts the full build skipped because they lay within 1 m of an existing end.
- **The table is the proof's prototype.** On BULK, SETN, MORK and COTR it gives every full segment the parent `parent_<wsg>.csv.gz` gave it, with identical gradients and lengths within 5.5e-12 m (`prototype_check.csv`). The proof's segment ids still name the same segments, because both networks were cut the same way since.
- **Only gradient is carried.** Discharge is per FWA segment and neither network crosses an FWA segment boundary, so a full segment and its parent read the same value.

## Classifying on the parent's gradient

**A `default_parent` build cuts `default`'s segments and classifies each on its parent's gradient; on four groups only habitat moves, and rearing rises much as it does on the minimal network itself** (#463). BULK, SETN, MORK and COTR were built under `default` (a control) and `default_parent` at one commit on m4 (`data-raw/logs/grad_parent_463/README.md`).

- **Segments and access are identical,** and the parent build's `gradient` equals `streams_parent.gradient_minimal` on every segment. The gradient changes on 3,316 to 3,777 km per group.
- **Every habitat difference sits on a segment whose gradient changed, or in a connected cluster holding one** (none unexplained). Over the four groups rearing rises (CH +3.9 %, ST +3.3 %, CO +1.5 %, BT +1.1 %) and spawning moves within ±0.33 %, both ways. BULK CH rearing goes from 2,101 to 2,208 km, against 2,205 on the minimal network (above), so on BULK the minimal network's rise does not need its longer segments: the parent's gradient on the full network's segments gives nearly the same km.
- **The near-river distance costs nothing here** (#462). CH's near-river pair applies only to 1050/1150 lines under `default`, and on those lines it reads the segment's own distance, not the parent's. Accessible CH segments failing the rear width whose parent is within 1,000 m of a 15 m river and whose own distance is not: 0 in each group (0 km). The two distances differ on 94 segments, by up to 542 m, and none crosses 1,000 m. This is not comparable to knowledge#120's 1,042 km, which applied the pair to every line.

## What is not measured

- No group in the proof has a dam below it in the scratch schema, so the recompute's downstream-dam branch did not run on real data.
- The proof groups are all on `cw`; a `mad` group reads discharge, which the proof does not compare.
- One run of each build, on one host.
- `default_parent` is proved on four groups only; whether to build it province-wide is an operator decision (it runs only on the dispatcher, where `fresh_default` and `streams_parent` live).
