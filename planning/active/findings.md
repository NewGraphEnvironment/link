# Findings — streams_habitat_<sp>.accessible disagrees with streams_access.access_<sp> (#349)

## Issue context

**If we settle it:** a consumer knows which column says a segment is accessible to a species, and rearing and spawning agree with it. **If we never do:** every consumer picks one of two columns that disagree on up to 17 % of RB's accessible network and 90 % of KO's, and results depend on which.

## Problem

In a `default` build, `streams_habitat_<sp>.accessible` and `streams_access.access_<sp>` disagree. Counts are segments, joined on `id_segment` and `watershed_group_code`:

| species | `accessible` TRUE, `access_<sp>` = 0: `fresh_default` (province-wide run `20261017_004619-3f4c713b`, 241 groups) | the same in `score284_default` (link 0.53.0, 2026-09-30, 23 groups) |
|---|---|---|
| BT | 48,728 (1.8 % of `accessible`), 8,867 of them `rearing`, 4,697 `spawning` | 2,948 (0.7 %), 40 `rearing` |
| CH | 14,242 (1.6 %), 330 `rearing` | 1,923 (1.7 %), 43 `rearing` |
| CO | 12,717 (2.0 %), 531 `rearing` | not checked |
| GR | 30,996 (3.5 %), 7,170 `rearing` | not checked |
| RB | 481,275 (17 %), 147,445 `rearing`, 66,983 `spawning` | 99,992 (27 %), 27,056 `rearing` |
| KO | 55,989 (90 %), 983 `rearing` | not built |

The other species (CM, PK, SK, ST, WCT) are at 1.3–2.3 %. The reverse (`accessible` FALSE, `access_<sp>` > 0) is at most about 1,000 segments per species. A few segments have `spawning` while `accessible` is FALSE (CH 178, CO 760, CM 280), probably the user-habitat overlay.

It is in the older build too, so it is not only the cross-group recompute of `streams_access`. Its cause is not established. It could be rearing and spawning gated before access was settled, or the two columns built from different inputs (observation overrides, a different rule for resident species).

## Question

Which column is authoritative for "accessible to <sp>"? And should the habitat flags be re-gated on it after `streams_access` is settled? knowledge#57 gates on `streams_access` for now and records this table on every build.

Query (per species):

```sql
SELECT h.accessible, (a.access_bt > 0) AS access_gt0, count(*)
FROM fresh_default.streams_habitat_bt h
LEFT JOIN fresh_default.streams_access a USING (id_segment, watershed_group_code)
GROUP BY 1, 2;
```

## First known component: #336

#336 is the same disagreement on DUNC BT, characterised: all 228 segments it traces start within 5 mm of a BT-blocking **gradient** barrier in `<schema>.barriers` that fresh's breaks table does not hold as blocking BT. fresh's own access predicate blocks a segment at a break (`<=`), so the two columns are built from **different barrier sets**, not one set read two ways. Plan this issue with #336 as its first phase:

1. Per species, split the disagreeing segments into those starting within 1 m of a barrier that blocks the species in `<schema>.barriers` (#336's class) and the rest.
2. Fix #336's mechanism, so both columns read one barrier set, and re-measure the table above.
3. What remains (RB's 17 %, KO's 90 %, if they are not #336's class) decides the rest of the plan. #351 also writes `access_<sp>` and is to be ruled in or out there.

Why accessible-km parity with bcfishpass did not show this: `lnk_rollup_wsg()`'s `accessible_km` reads `streams_access`, the side that agrees with bcfishpass; fresh's `accessible`, which gates spawning and rearing, was never scored for access.


## Measured in plan mode (2026-10-19, read-only SQL on `fresh_default`, run `20261017_004619-3f4c713b`, link `849d1f3e`, fresh 0.39.0)

Probe SQL is in the session scratchpad only; Phase 1's script reproduces every number below.

### DUNC BT, #336's 229 segments

Nearest BT-blocking natural barrier on the same line within 1 m of each disagreeing segment:

| barrier_source | n | `round(barrier) > segment start` | `round(barrier) <= start` | offset (m) |
|---|---|---|---|---|
| GRADIENT | 228 | 225 | 3 | −0.0050 … +0.0049 |
| (none within 1 m) | 1 | | | |

DUNC segment starts: 50,398 of 63,067 are integer metres (break positions, `frs_break_apply(measure_precision = 0)`); the rest are FWA feature starts. Reverse direction in DUNC BT: 3 segments.

### Whole-group disagreement (`accessible` TRUE, `access_<sp>` = 0, share of accessible)

KO: NATR 22,352 / 22,352 (100 %), PARS 19,401 / 19,401, CARP 14,033 / 14,033, KOTL 203 / 6,627 (3.1 %).
RB: PARS, NATR, TOOD, FINL, PCEA, UNRS, FINA, CRKD, INGR, UEUT, LOMI, CARP, PARA, FIRE, FOXR, UOMI, TURN, OSPK, MESI, CLRH, LEUT, CANO at 100 % (KHOR 99.9, COLR 100), ELKR 29.5 %.
GR: ELKR 10,480 / 10,480, TURN 5,150 / 5,150, BULL 4,927 / 4,927; then TOAD 598 / 13,780 and smaller.

### What blocks RB downstream of PARS

Every RB-blocking natural barrier downstream of the lowest disagreeing PARS segment: two GRADIENT rows on `blue_line_key` 359572348 at 1,684,183.0 m and 1,706,109.9 m, `blocks_species` = all 13, each persisted under FINA, LPCE, PCEA and UPCE. `barrier_overrides` lifts both for BT, neither for RB or KO. FWA places both in UPCE. The reviewer found a third row at 1,706,197.2 m blocking the 15 % species (KO, GR, salmon).

`fresh_default.barrier_overrides` by species: BT 6,074, WCT 5,302, ST 1,939, CH/CM/CO/PK/SK 1,755 each, KO 53, GR 13, RB none (no rule).

### Observations upstream of the two Peace barriers (bcfishobs, by species)

| barrier | sp | all | ≥ 1990 | in PCEA | in UPCE | groups |
|---|---|---|---|---|---|---|
| 1,684,183 | BT | 1,270 | 1,232 | 188 | 32 | 17 |
| 1,684,183 | KO | 252 | 244 | 63 | 72 | 12 |
| 1,684,183 | RB | 3,269 | 2,660 | 158 | 290 | 17 |
| 1,706,110 | BT | 1,238 | 1,202 | 188 | 0 | 16 |
| 1,706,110 | KO | 180 | 172 | 63 | 0 | 11 |
| 1,706,110 | RB | 2,979 | 2,420 | 158 | 0 | 16 |

The override rows at 1,706,110 are `watershed_group_code` FINA and PCEA (UPCE wrote none: no observations inside it above that point). KO is present in PARS, NATR, CARP, not in FINA / LPCE / PCEA / UPCE, so the groups that hold the barrier filter every KO observation out before counting. Mechanism C.

### Code facts the plan rests on

- `.lnk_pipeline_classify_build_breaks()` rounds every break to the metre; `.lnk_pipeline_prep_natural()` rounds `natural_barriers` the same way; fresh's override anti-join is exact `=` (`frs_habitat_classify.R:459, 473`). Rounded matches rounded today; drop one side and every lift ends.
- fresh's `accessible` CTE: same line `b.drm <= s.drm`, other lines `fwa_upstream()` on ltrees; breaks AOI-filtered. link: `frs_network_features()` → `fwa_downstream(…, include_equivalents, 1)`.
- `lnk_pipeline_run()`: mapping_code (L303) runs before the second persist (L315) and reads the working long `streams_habitat`; the recompute builds it from persist `streams_habitat_long_vw` (`wsg_recompute_one.R:168-180`).
- `habitat_variants_build.R:544-556, 681-688` digests `working_<wsg>.streams_habitat` after `lnk_pipeline_run` and asserts classify + connect reproduce it: a working-side settle breaks that.
- `lnk_access(merge = TRUE)` CASE (`R/lnk_access.R:226`) returns 1 where a prior 0 is lifted: a settle is lossy.
- `frs_habitat_overlay()` never reads `accessible`.
- `.lnk_log_align_columns` adds columns `IF NOT EXISTS` on every `_create_tables`; `_finish`'s single UPDATE fails softly on an older schema.
- `inst/extdata/schemas/habitat_fwa_v1_segment.yaml:123-132` still carries #336's retracted boundary-convention story.
- Reviewer's alternative for the dam faces, not taken: a `user_barriers_definite_control` row with `barrier_ind = f` prunes the row from `gradient_barriers_raw` (prepare `:360-368`) and so from `<persist>.barriers`.

## Phase 1: province-wide, by mechanism (2026-10-20)

`data-raw/access_disagree_349.R` on `fresh_default` (241 groups, run `20261017_004619-3f4c713b`);
output `data-raw/logs/access_disagree_349/`. Every species' forward classes sum to the issue's
totals (the script asserts it): BT 48,728, CH 14,242, CO 12,717, GR 30,996, KO 55,989, RB 481,275.

| species | A (rounding) | A′ (ltree) | B (cross-group) | residual | reverse |
|---|---|---|---|---|---|
| BT | 6,999 | 7,636 | 33,739 | 269 (+85 A_other) | 1,035 |
| CH | 6,695 | 7,339 | 0 | 138 (+70) | 710 |
| GR | 4,999 | 5,423 | 20,319 | 201 (+54) | 752 |
| KO | 213 | 270 | 55,498 | 6 (+2) | 0 |
| RB | 7,840 | 8,608 | 457,912 | 6,817 (+98) | 759 |

- **A and A′ are near-equal halves everywhere** (≈ 0.25–1 % of accessible per species). They are
  the classify-time half the fresh `tolerance_m` follow-up would fix; the gate fixes them in
  persist.
- **B is every whole-group case.** RB: 25 groups behind the two Peace rows (UPCE), the
  Columbia rows (REVL, LNRS), the Clearwater / Mahood rows (CLWR, MAHD). KO: NATR, PARS, CARP
  behind the three Peace rows. GR: ELKR, TURN, BULL behind KOTL rows (1–3 GR records upstream,
  threshold 5: GR is genuinely blocked there, so the gate's blanking is the intended outcome).
  **BT TURN** (6,491 km) is mechanism C for BT too: a UKEC barrier with 69 BT records upstream
  province-wide and 0 inside UKEC.
- **The residual is small and mostly one case:** RB's 6,817 are 6,623 in ELKR, the Flathead, a
  second drainage out of the group: an ELKR Flathead segment's blocking barrier is a GRADIENT
  row on blue_line_key 356570104 at 723 m in LARL (on the Columbia), which the single-outlet
  B test does not see. A per-segment cross-group test took over 10 min on ELKR alone and was
  dropped; `residual_groups.csv` lists the residual by group instead.
- **Reverse direction** (fresh blocks, link does not) is at most 1,035 segments per species.
  `R_override_scope` (a barrier lifted only by another group's override row) is BT 169, GR 299,
  WCT 2; the rest are `R_other`.
- **Overlay exemption:** of the `access_<sp> = 0` rows with spawning, the user habitat
  classification sets CH 189, CM 300, CO 788, PK 263, SK 153, ST 110 (of 284 / 455 / 976 / 395 /
  197 / 181). These keep spawning under the gate. BT, GR, KO, RB, WCT: none.
- **Lake rearing left without spawning:** 0 polygons for every species (`lake_polygons_lose_spawning`;
  98 BT and 3,470 CO polygons sit within 10 km of blanked spawning, all keep other spawning).
- **#351 ruled out:** no `-9` in any `access_<sp>`, and no disagreeing row in a group where the
  species is absent.

### Correction to "Measured in plan mode": where KO's records are

The plan said KO's 172–244 records upstream of the Peace rows are "all in PARS / NATR / CARP
where KO is present". They are not: post-1990, PCEA 63, FINA 27, FINL 22, PARS 12, FIRE 11,
PARA 10, LOMI 8, TOOD 7, INGR 6, NATR 5, OSPK 1 above 1,706,110 m. `wsg_species_presence`
marks KO present only in CARP, NATR and PARS, so counting each record against its own group's
presence (bcfishpass's rule) admits 17 (PARS 12 + NATR 5). That still clears KO's threshold of 5,
so the province-wide count lifts KO; the records in groups that list KO absent are a presence-table
question, not this issue's.

### bcfishpass's observation scope (Phase 1, pinned)

`smnorris/bcfishpass@620dbe4` (main, 2026-10-19), `model/01_access/sql/load_observations.sql`:
`bcfishpass.observations` holds every group's bcfishobs records, each kept when
`array[o.species_code] && wsg_spp.species_codes` for **its own** `watershed_group_code`, minus
`observation_exclusions`. `model_access_bt.sql` filters the barriers to `:'wsg'` and joins them to
**all** of `bcfishpass.observations` with `fwa_upstream(..., false, 20)`. So bcfishpass counts lifts
province-wide; link counted only the AOI's records. (bcfishpass matches the raw code, so a CCT record
is not admitted by a CT presence; link admits CCT / ACT / CT/RB when CT is present, both tables.)

## Phase 3: what counting over province-wide observations costs (2026-10-20)

`data-raw/overrides_scope_time_349.R` → `data-raw/logs/access_disagree_349/overrides_scope_time.csv`
(m1, docker fwapg). Prep of both observation tables 3.9 s per group (the province table is built
once per group, 376 k source rows, two GiST indexes). `lnk_barrier_overrides()` over the AOI table
vs the province table: DUNC 27.6 s vs 18.6 s, CARP 18.0 s vs 17.5 s (the habitat-confirmation pass
dominates; the GiST-indexed province table is no slower). Lift counts are identical in both groups
(DUNC BT 96, RB 25, WCT 98; CARP RB 4): neither group's own barriers have records upstream in
another group. The scope matters where a group holds a barrier on a line others drain through
(UPCE, the Peace rows), which is why the Phase 4 build adds UPCE.

`audit_configs.R` flagged the edited `parameters_fresh.csv` as byte drift against its recorded
checksum; the manifest's `checksum` (sha256 of the bytes, CRLF kept) and `synced` date were updated,
after which the audit reports no findings. The audit's own `print()` errors with
`invalid 'na.print' specification` when it has drift to print (pre-existing; seen only then).

## Phase 4: verification build (2026-10-20, scratch `fresh_349`)

`data-raw/logs/access_disagree_349/verify_build_349.sh`, link `ca4a58ef` (clean on every log row),
fresh 0.39.0. UPCE added to the plan's DUNC + CARP: the Peace rows that block CARP are held by
FINA, LPCE, PCEA and UPCE (FWA places them in UPCE), so the province-wide lift reaches CARP only
through one of those groups' runs. Builds UPCE 3.6, CARP 1.9, DUNC 3.3 min; recomputes 1.3, 0.8,
1.6 min.

- **UPCE now lifts all three Peace rows for KO and RB** (`barrier_overrides`, UPCE rows); before,
  none of the four holding groups did.
- **Classify time (`before/`, gate off):** B is gone for CARP KO and RB (fresh_default `baseline/`:
  13,982 and 17,578 segments). What remains is A / A′ only: BT 353, GR 172, KO 51, RB 355, WCT 236.
  GR's 299 reverse rows in UPCE (`R_override_scope`, 60.5 km) are gone too: UPCE counts the records
  that lifted those barriers in other groups' runs.
- **After the recompute (`after/`): forward disagreement 0 for every species.** Reverse: BT 7,
  GR 2, KO 1, RB 7, WCT 2 (`R_other`).
- **Gate counts** (`log_recompute`): UPCE 396 segments / 51.6 km, CARP 77 / 9.7 km, DUNC 694 /
  249.9 km of `accessible` set FALSE; `habitat_gate_lifted` 0. Model-time log rows NULL (gate off).
- **No lift lost** (`access_transitions.csv`, joined on blue_line_key + measure, segmentation
  identical): open → closed 0 for every group × species. Closed → open: CARP KO 13,982 segments /
  3,694.8 km, CARP RB 17,584 / 4,419.7 km, UPCE RB 4,483 / 843.4 km, DUNC RB 27 / 4.6 km.
- **Rollups** (`rollup.csv`): `accessible_km` moves by exactly those km (UPCE RB +843.37, DUNC RB
  +4.56; CARP KO and RB from none to 3,695.04 and 4,421.15). Habitat km: UPCE RB +197.7 spawning,
  +345.9 rearing (the Peace rows are in UPCE, so fresh blocked RB above them until they lifted); UPCE
  GR +1.1 spawning, +22.9 rearing, +28.5 lake connection (the closed reverse rows); DUNC BT −0.01
  spawning, −0.14 rearing; CARP KO and RB unchanged (fresh had classified them accessible already).
- **DUNC BT against bcfishpass** (`bcfp_dunc_bt.csv`, `fresh.streams_vw_bcfp` codes 1/2): spawning
  543.14 → 543.13 km (bcfishpass 538.41), rearing 1,017.24 → 1,017.09 (861.81). Toward bcfishpass,
  barely: #336's 85 km are accessible km, almost none of it habitat. The tunnel was down, so
  `lnk_compare_rollup()` was not run; the local view is the same reference parity uses.

## Code-check round 1 (2026-10-20)

Two real findings, both fixed in the commit after this one:
1. **The model-time gate makes losses permanent on a multi-host run.** A group gated at model time
   against another host's stale overrides loses habitat the post-consolidate recompute then lifts;
   the gate is one-way. `study_area_run.sh` now exports `LNK_HABITAT_GATE=0` on both legs (the
   recompute always follows there and settles on final access); a single-group `wsg_run_one.R`
   still gates, as decided.
2. **Every working schema kept its own province-wide observations copy** (~200 MB with indexes;
   `wsg_run_one.R` keeps working schemas, 241 per run). The table is dropped once the overrides are
   counted.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `$TMPDIR` unset in the Bash tool: `/p1.sql: Read-only file system` | write probes to the session scratchpad directory |
| `column o.wscode_ltree does not exist` | `bcfishobs.observations` names them `wscode` / `localcode` |
| Phase 1 lake query ran 5+ min on CH (`ST_DWithin` between a CTE and all streams) | temp tables with GiST indexes on each side: whole province in 4 min |
| `pg_cancel_backend` matched nothing: the query text starts with a newline | terminate by pid |
| `sprintf("%d", <integer64>)` from `count(*)` | `as.integer()` first |
| per-segment cross-group test for the residual: 10+ min on ELKR alone | dropped; `residual_groups.csv` plus one probe |
