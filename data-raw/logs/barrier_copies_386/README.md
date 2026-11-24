# Copies of one barrier held by several groups (link#386)

**Measured:** 2026-11-24 on m1's `fresh_default` (241 groups at link 0.78.2, `4dfbfa49`; fresh 0.56.0) and local FWA. **Produced by:** `bash measure.sh <schema> <out dir> [bundle]` (`measure.sql`, then `report.sql`), with the `PG*` variables naming the database.

The **owner** of a position is the group of the FWA segment it sits on, picked as the pipeline picks it: lowest downstream measure, then lowest `linear_feature_id`, for the ~1 mm overlap of two segments; the line's nearest segment for a measure in the gap between two. A group **scans** a line when it holds a segment of it with edge type other than 6010.

## Before the change (`before_fresh_default/`)

| measure | value |
|---|---|
| lines touching more than one group | 259 |
| gradient rows on those lines / positions | 3,087 / 1,224 |
| positions held by more than one group | 1,224 (every one; up to 13 holders) |
| rows held by a group that does not own the position | 1,864 |
| copies differing in subtype or `blocks_species` | 0 |
| positions a built scanner does not hold within 1 m | 1 |
| positions whose owner holds no row | 1 (owner built, and scans the line) |
| positions on no persisted segment | 0 |
| override positions on those lines / held by more than one group | 141 / 101 |
| override copies whose species sets differ | 0 |
| override positions whose owner holds none | 1 |
| control rows filed under a group that does not own the position | 7 of 238 |
| user-definite rows / falls filed under a non-owner | 0 of 227 / 0 of 3,294 |

The one disagreement is the case #386 describes. LSAL's control row on the Salmon River (`356364485`, 67492, `GRADIENT`, `barrier_ind` false, "an odd point on Salmon River that looks like a data error") prunes LSAL's copy. SALR and TABR scan the same line, hold their copies, and lift them for eight species. So the position blocks in the access view whatever LSAL's control says. That is the "position whose owner holds no row", the "missing scanner" and the "override whose owner holds none" above.

The 7 control rows filed under a non-owner are all `FALLS` with `barrier_ind` false, and none has a natural barrier row within 1 m in any group (`control_non_owner.csv`). fresh's `falls.csv` already leaves those falls out. So today they do nothing, and applying controls by position changes nothing for them.

Every control row on a line several groups scan, with what each group holds beside it, is `control_multi_group_lines.csv`.

bcfishpass applies its control table by position, with no group filter, and files each gradient barrier under the group of the segment it sits on (`model/01_access/sql/barriers_gradient.sql` at `smnorris/bcfishpass@3bd2824`: `LEFT OUTER JOIN bcfishpass.user_barriers_definite_control p ON b.blue_line_key = p.blue_line_key AND abs(b.downstream_route_measure - p.downstream_route_measure) < 1`, `s.watershed_group_code` from the joined segment).
