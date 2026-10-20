# Code-check round 4 (#362): fix commit aa09b854, plus #277's "Measured 2026-10-20"

All checks were read-only (`default_transaction_read_only=on`) against `fresh_parity246` and `fresh_parity362`.

## Claims added or changed

| Claim | Source | Verdict |
|---|---|---|
| closure is 17 groups | `count(distinct watershed_group_code)` in both schemas | ✓ 17 / 17 |
| 349 segments on 75 lines in 12 groups exist in one build only (closure) | the query re-run independently over both schemas; `resegmented_closure.csv` sums | ✓ 349 rows, 75 distinct (wsg, blk), 75 distinct blk (no line counted in two groups), 12 groups |
| per-group rows of `resegmented_closure.csv` | same query | ✓ (sums 349 / 75) |
| 39 segments on 8 lines in the scored groups (ADMS, BULK, ELKR) | csv: ADMS 19/4, BULK 10/2, ELKR 10/2 | ✓ |
| "the 67 lines outside the scored groups were not examined" (findings, #277, research) | 75 − 8 | ✓ |
| "the tie above is confirmed on the 8 lines in the scored groups; the other 67 are not examined" | | ✓ as stated. Informational: all 8 KOTL lines have a `MODELLED_CROSSINGS` barrier present in one build only, with its counterpart on the same `linear_feature_id` (for example 356543322: 1024732431 at 256.2 m → 1009006894 at 336.3 m, lfid 707128851), which fits the same tie |
| 91a968ab reaches none of the 86 rows; every one has barriers | `streams_access.has_barriers_<sp>_dnstr` per (group, species) for the 86 rows of `mapping_code_moves.csv`: TRUE on at least one segment in **both** builds for all 86, and never all-NULL, so the `nrow(dnstr_per_sp[[sp]]) == 0` branch (`R/lnk_pipeline_access.R:244`) is never taken | ✓ |
| "it changes only a species with no barrier in a group" | `R/lnk_pipeline_access.R:244-250`: zero downstream-barrier rows, and the species present | ✓ |
| "Two things move it at once: the gate, and lines the two builds break in different places, which across the whole closure is 349 segments on 75 lines" (research; moves.R comment; findings) | mapping-code diff on shared segments, all 17 groups, 6 species | ✓ on the causes, ✗ on the extent; finding 2 |
| no third cause from lifts | `access_<sp>` identical on every shared segment in all 17 groups for bt/ch/co/sk/st/wct (LARL included) | ✓ (supports omitting the lifts) |
| README: `resegmented.csv` = "lines the two builds break in different places (#277)", scored groups | csv | ✓ |
| README: `resegmented_closure.csv` = "the same, counted per group over all 17 groups" | csv | ✓ |
| moves.log: "closure: 17 groups; segments in one build only: 349 on 75 lines in 12 groups" | query | ✓ |
| #277: the scored-group sentence and closure sentence | as above | ✓ |

## Findings

1. **[defect, text]** `planning/active/findings.md:66-67`. The fix deleted "Added to #277's" at the end of the old line and left the next line orphaned, so the bullet now reads "…the 67 lines outside the scored groups were not examined. / body as a measured instance; no new issue." Restore it: "…were not examined. Added to #277's body as a measured instance; no new issue."

2. **[claim, extent]** `research/bcfishpass_parity.md:89-91` (and `moves.R:173`, `findings.md:73`). The two causes are right, but tying the second to "349 segments on 75 lines" understates where it moves mapping codes. Moved crossings also change downstream-barrier flags on **shared segments of lines that are not resegmented**. On those segments the habitat flags and `access_<sp>` are unchanged:
   - KOTL BT 23 and WCT 16 segments go `REMEDIATED` → `MODELLED` (`remediated_dnstr_ind` t → f). Example: 356377341, 356543322 1060–4733 m.
   - HARR BT 13 segments: `has_barriers_anthropogenic_dnstr` differs.
   - LSKE 1 segment each in BT, CH, CO, SK and ST: `has_barriers_anthropogenic_dnstr` differs.

   All other mapping-code changes on shared segments either come with a habitat-flag change (the gate) or sit on a resegmented line (ADMS BT 11, KOTL BT 13, KOTL WCT 13). Nothing found needs a third cause. Suggested wording: "the gate, and the two builds breaking lines in different places (349 segments on 75 lines in 12 of the 17 groups, `resegmented_closure.csv`), which also changes downstream-barrier flags on segments upstream of a moved break (KOTL, HARR, LSKE)". Whether HARR's and LSKE's flag flips come from the same tie was not checked.

3. **[fragile, low]** `moves.R:24-25`. The new guard refuses an unset `LNK_COMPARE_NEW`, but a name that is set and wrong still fails only at `read.csv` (`:176`), after `pair_moves.csv`, `resegmented*.csv` and `override_diff.csv` have been rewritten. That is round 3's mixed-output state again, reached by a typo. Add `file.exists(file.path("data-raw/logs/study_area_run", compare_new))` to the same `stop()`.

## moves.R code

- `reseg_in()`: the parameterised `IN (%1$s)` is used twice through `%1$s`, which is correct. Callers pass `wsgs` (round 2's empty guard is upstream) and the closure (17 groups, never empty).
- Closure summary: `table(x)[sort(unique(x))]` and `tapply(...)[sort(unique(x))]` index by name, so the order is consistent whatever the locale. The 0-row branch returns a typed empty frame. `sum(lines)` counts lines per group, and it equals the distinct-blk count here (75 = 75), so "75 lines" is not double-counted.
- `closure` is read from `fresh_parity362` only, so a group in 246 alone would be missed. Both schemas hold the same 17, so this is not a defect.
- No other defects.
