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

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `$TMPDIR` unset in the Bash tool: `/p1.sql: Read-only file system` | write probes to the session scratchpad directory |
| `column o.wscode_ltree does not exist` | `bcfishobs.observations` names them `wscode` / `localcode` |
