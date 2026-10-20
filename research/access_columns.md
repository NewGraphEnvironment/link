# Which column says a segment is accessible

**Verified:** 2026-10-20 · **Issues:** #349 (and #336, its DUNC BT instance) · **Produced by:**
`data-raw/access_disagree_349.R`, `data-raw/overrides_scope_time_349.R`, log prefix
`data-raw/logs/access_disagree_349/` · **Archive:** `planning/archive/2026-10-issue-349-accessible-vs-access/`

A link build carries two answers to "is this segment accessible to <sp>":

- `streams_habitat_<sp>.accessible`, fresh's, computed in `frs_habitat_classify()` from the
  group's own breaks table. It gates `spawning`, `rearing`, `lake_rearing` and
  `wetland_rearing` at classify time.
- `streams_access.access_<sp>` (with `has_barriers_<sp>_dnstr`), link's, computed by
  `lnk_pipeline_access()` from every group's persisted barriers and overrides and re-settled
  after a multi-host run (`lnk_access(merge = TRUE)`). It is what `accessible_km`,
  `mapping_code` and the export's `has_barriers_dnstr` read, and what is scored against
  bcfishpass.

**`access_<sp>` is authoritative, and since link#349 the build makes the habitat flags follow
it** (`lnk_habitat_gate()`, RUNBOOK §3). A build from before that, or one whose recompute has
not re-run since, still disagrees as measured below.

## How much they disagreed, and why

`fresh_default`, 241 groups, run `20261017_004619-3f4c713b` (`classes.csv`, `summary.md`).
Forward = `accessible` TRUE where `access_<sp>` = 0; segments.

| species | forward | of accessible | A rounding | A′ ltree | B cross-group | residual | reverse |
|---|---|---|---|---|---|---|---|
| BT | 48,728 | 1.8 % | 6,999 | 7,636 | 33,739 | 354 | 1,035 |
| CH | 14,242 | 1.6 % | 6,695 | 7,339 | 0 | 208 | 710 |
| CO | 12,717 | 2.0 % | 5,804 | 6,475 | 0 | 438 | 676 |
| GR | 30,996 | 3.5 % | 4,999 | 5,423 | 20,319 | 255 | 752 |
| KO | 55,989 | 90 % | 213 | 270 | 55,498 | 8 | 0 |
| RB | 481,275 | 17 % | 7,840 | 8,608 | 457,912 | 6,915 | 759 |

(residual includes `A_other`, a barrier within 1 m that is neither case; CM, PK, SK, ST, WCT
are in `classes.csv`, all A / A′ and residual.)

- **A, metre rounding.** link writes every break at `round(drm)`
  (`.lnk_pipeline_classify_build_breaks()`); a gradient barrier a few mm *below* a segment start
  lands above it, and fresh's same-line test `b.drm <= s.drm` misses it.
- **A′, the near-equal case.** A barrier 0–5 mm *above* the start: link's
  `fwa_downstream(…, tolerance = 1)` treats it as downstream through the barrier's ltree (the lower
  FWA feature's), fresh's exact `<=` never. Dropping the rounding alone would fix A, not A′, and
  would end every observation lift, because fresh matches overrides to breaks by exact `=` and
  `natural_barriers` is rounded too. A fresh-side tolerance is NewGraphEnvironment/fresh#258.
- **B, cross-group barriers.** fresh's breaks are filtered to the group; link's view reads every
  group's persisted barriers. A blocking barrier downstream in another group is invisible to fresh.
  Whole groups: RB in 27 (16 behind two Peace rows in UPCE, 4 behind REVL rows, 3 behind LNRS
  rows, 3 behind CLWR falls, and TURN behind a UKEC falls), KO in NATR, PARS and CARP, GR in ELKR
  and BULL (KOTL rows) and TURN (the UKEC falls), each with 1–3 GR records upstream against a
  threshold of 5, so genuinely blocked, and BT in TURN (the UKEC falls).
  `groups_blocked.csv` lists each barrier.
- **Residual.** Small everywhere; RB's 6,817 (A_other aside) are 6,623 in ELKR, the Flathead: a second drainage
  out of the group to a Columbia barrier in LARL, which the single-outlet test does not see.
- **Reverse** (fresh blocks, link does not): at most ~1,000 segments per species. 169 BT, 299 GR
  and 2 WCT are a barrier lifted only by *another* group's override row, which link's view reads
  and the group's own fresh run did not.

**Why accessible-km parity never showed it:** `accessible_km` reads `streams_access`, the side
that agrees with bcfishpass; fresh's `accessible` was never scored for access.

## Why a barrier stayed un-lifted: observations counted inside one group

bcfishpass lifts a natural barrier when enough observations lie upstream of it, counted over
**every** group's records, each kept by its own group's species presence
(`smnorris/bcfishpass@620dbe4`, `load_observations.sql`, `model_access_bt.sql`). link counted only
the records inside the group running. A barrier on a line several groups share is persisted
under each (the two Peace rows at 1,684,183 m and 1,706,110 m on blue_line_key 359572348 sit under
FINA, LPCE, PCEA and UPCE; FWA places them in UPCE), so it was lifted only where one of those
groups held enough records inside itself.

- **BT TURN:** a UKEC barrier with 69 BT records upstream province-wide, 0 inside UKEC.
- **KO:** above 1,706,110 m, post-1990, PCEA 63, FINA 27, FINL 22, PARS 12, FIRE 11 and six more
  groups; presence marks KO only in CARP, NATR and PARS, so by bcfishpass's rule 17 count
  (threshold 5). Most KO records upstream sit in groups the presence table lists without KO.
- **RB** had no observation rule in `default` at all, so nothing lifted for it. It now has a rule shaped like BT.s:
  one RB record (only RB records count for RB), no date floor, no control veto.

Since #349 the lift counts over `<schema>.observations_province`. Building it costs ~4 s per
group and the override step is no slower (DUNC 27.6 → 18.6 s, CARP 18.0 → 17.5 s;
`overrides_scope_time.csv`).

## What the settle keeps and loses

- **Known habitat:** rows `user_habitat_classification` marks keep `spawning` / `rearing` where
  `access_<sp>` is 0 (fresh's overlay forces them the same way). Province-wide that is CH 189, CM
  300, CO 788, PK 263, SK 153, ST 110 spawning rows (`side_effects.csv`).
- **Lake rearing without spawning:** no lake polygon keeps `lake_rearing` while losing every
  spawning segment within 10 km to the settle (0 for every species).
- **One-way.** A later recompute that lifts a segment cannot give its habitat back; only a
  re-model of the group does. The recompute counts these (`habitat_gate_lifted`).

## Verification build

UPCE, CARP and DUNC rebuilt at this change under `default` into a scratch schema seeded with
`fresh_default`'s barriers and overrides, downstream first, with the gate off, then recomputed
(`verify_build_349.sh`; `baseline/`, `before/`, `after/`). UPCE is in the set because it holds
the Peace rows that block CARP.

- UPCE now writes KO and RB override rows at all three Peace rows (no holding group did before),
  so at classify time CARP's KO and RB are no longer blocked by link (B gone: 13,982 and 17,578
  segments in `fresh_default`). UPCE's 299 GR reverse rows go too.
- After the recompute, **forward disagreement is 0 for every species**; the reverse is 1–7
  segments per species.
- The gate set `accessible` FALSE on UPCE 396 segments (51.6 km), CARP 77 (9.7 km), DUNC 694
  (249.9 km); no recompute lifted a settled segment.
- No lift was lost: no segment open in `fresh_default` is closed now. Opened: CARP KO 3,694.8 km,
  CARP RB 4,419.7 km, UPCE RB 843.4 km, DUNC RB 4.6 km, and `accessible_km` moves by exactly that.
- Habitat: UPCE RB +197.7 km spawning, +345.9 km rearing (above the Peace rows, which fresh saw
  and could not lift for RB before); UPCE GR +22.9 km rearing; DUNC BT −0.01 km spawning, −0.14 km
  rearing, toward bcfishpass (538.4 / 861.8 km) by very little: #336's 85 km are accessible km,
  almost none of it habitat.

## What it should do to bcfishpass parity

**Measured 2026-10-20 (#362): as predicted.** Re-built at v0.66.6 into `fresh_parity362` and
scored against the same reference, the four groups stay at 48/50, accessible km does not move,
and BT rearing falls by the 0.3 / 0.3 / 0.6 km below (0.269 / 0.325 / 0.633 km). The "0 km of
spawning" below is 0 at 0.1 km: the gate removes 0.002–0.043 km of spawning or rearing from ten
other pairs. TURN cannot be scored: bcfishpass does not model TURN or UKEC. Record:
`bcfishpass_parity.md`.

The prediction, as written before that build: on `fresh_parity246` (the `bcfishpass`-config parity
build of 2026-10-17, before #349) the segments the gate would settle (`accessible` and
`access_<sp>` = 0) carry 0 km of spawning in every scored pair and at most 0.6 km of rearing
(BT: BULK 0.3, BABL 0.3, ELKR 0.6 km), against 300-3,000 km per pair; accessible km reads
`streams_access` and already sits within 0.07 %. So parity on ADMS, BULK, BABL and ELKR checks
for regression; it cannot show a gain. Province-wide lift counting matters only behind a barrier
held in another group, which none of those groups has: TURN BT, behind a UKEC barrier with 69 BT
records upstream and none inside UKEC, is the candidate that would show it under `bcfishpass`.

## Which schemas are settled

- A build whose last write since #349 was a gate: a model run with the gate on (a single-group
  `wsg_run_one.R`), or a recompute. A dispatch's model leg runs with the gate off, so a group of a
  run that was never recomputed (failed, not consolidated, or the recompute never ran) is not settled.
- **Not** `fresh_default`, `fresh`, `score284_*` or any variant schema built before it.
  `bash data-raw/study_area_run.sh --recompute-only --run-uid=<uid> --config=<config>
  --schema=<schema>` settles a provenanced run without a re-model (decision 4 of #349, the
  operator's call). **Re-model first, then gate:** the RB / KO / BT lifts behind shared barriers
  arrive only with a re-model of the groups that hold those barriers, and a re-gate run before it
  blanks habitat those lifts later open, which then needs a re-model of every group upstream.
