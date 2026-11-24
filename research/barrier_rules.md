# What blocks access at a barrier: copies, lift rules and barrier rules

**Verified:** 2026-11-24 against link 0.93.0 on m1's local fwapg · **Issues:** #479 (backlog move 11), #386, #236, #341; split out: #201 and #83 · **Produced by:** `data-raw/logs/barrier_copies_386/`, `data-raw/logs/lift_rules_236/`, `data-raw/logs/barrier_rules_341/`

What a barrier does to access is decided in three places. A gradient barrier, its lifts and their evidence are held by one group; a species' barrier is lifted where any of its observation-lift rules is met; and which crossings are human-made barriers is a rules table. Which barriers block which species (a dam for some species and not others) is not built: it is #201 and #83.

## Copies of one barrier

A group finds gradient barriers along the whole of every line it has a segment of (`streams_blk`, edge type 6010 aside), because `fresh::frs_break_find()` reads each line whole. Until 0.93.0 every group scanning a line persisted every position on it.

On `fresh_default` at 0.78.2 (241 groups, `before_fresh_default/`):

- 259 lines touch more than one group, and every gradient position on them was held by every built group scanning them: 1,224 positions, 3,087 rows, up to 13 holders (the Fraser main stem). 1,864 rows were held by a group that does not own the segment.
- No two copies differed in subtype or species list. One position was missing from its owner: LSAL's control row on the Salmon River (67492, `GRADIENT`, `barrier_ind` false, "an odd point that looks like a data error") pruned LSAL's copy, while SALR and TABR kept theirs and lifted them for eight species. The position still blocked GR and KO in the access view, whatever the control said. That is the defect #386 describes.
- 7 of `default`'s 238 control rows are filed under a group that does not own their position. All 7 are `FALLS` rows with `barrier_ind` false, and no natural barrier sits within 1 m of any, because fresh's `falls.csv` already leaves those falls out. They did nothing before the change and do nothing after.
- Falls (3,294 with `barrier_ind` true) and user-definite rows (227) are filed by their files' groups, which own every one.

bcfishpass applies its control table by position, with no group filter, and files each gradient barrier under the group of the segment it sits on (`model/01_access/sql/barriers_gradient.sql` at `smnorris/bcfishpass@3bd2824`).

**The rule from 0.93.0** (owner's decision): controls apply by position whatever group a row is filed under, and a group persists a gradient barrier only at a position it owns, with overrides and evidence only beside a natural barrier it holds. The owner is the group of the segment the position sits on, picked as the pipeline picks a segment. Where the owner would never hold a position (no modelled species there, or it does not scan the line), the lowest-coded modelled scanner holds it. No position on `fresh_default` needs that fallback.

**What moved, on 11 groups built before and after** (TABR, LSAL, SALR, ADMS, ELKR, BULK, UPCE, PCEA, LPCE, FINA, PARS; `diff_bcfishpass/`, `diff_default/`):

- `bcfishpass`: 118 gradient rows removed (105 at positions owned by a group outside the set, 11 non-owner copies whose owner holds the same row, 2 at control positions) and 81 override rows (63, 4 and 14). No segment cut differently, no access or habitat value moved after the recompute, and no lift lost.
- `default`: the same 118 gradient rows and 114 override rows (90 non-owner copies, 8 owned outside the set, 16 at control positions); no segment, access or habitat value moved, no lift lost.

The LSAL position moved nothing on these builds because every species modelled in LSAL, SALR and TABR was already lifted there. The change is what a control row means; what it opens elsewhere is measured at the next provincial run.

**A one-group run** into a schema without its dependencies no longer holds the copies it used to. Of `fresh_default`'s 1,864 non-owner copies, 72 lay below segments of the group holding them, so a lone run reads those positions as open. The rest are on no downstream path of their holder. Each owner touches the line, so the line rule lists it among the group's dependencies, and loading those dependencies' rows (`lnk_downstream_load()`) from a build at 0.93.0 or later restores every one. A closure run has the same gap, because the outlet closure leaves out a tributary group that owns a stretch of the focal group's line (FINA's copies were owned by INGR, MESI, OSPK and UOMI). `lnk_wsg_downstream_check()` refuses both: it names every modelled group touching a line on the group's downstream paths that holds no barrier rows in the schema.

The owner rule of `data-raw/recompute_deps.R` is complete for a schema built wholly at 0.93.0 or later. The scheduler stays on the line rule until a provincial run has rebuilt every group.

## Several lift rules per species

`.lnk_lift_rules()` reads each species' `parameters_fresh.csv` row as rule `own` and a bundle's `parameters_barrier_lifts.csv` as further rules. A barrier is lifted where any rule is met, and the records of two rules never add together. Under `observation_record_date: lift_floor`, which `default` sets, one rule cannot mix date floors, so "BT on two salmon records since 1990" beside "BT on one BT record of any date" needs two rules.

No shipped bundle declares a further rule. A scratch copy of `default` declaring the candidate (BT also lifts on two or more salmon or steelhead records since 1990) runs through prepare and persist on ADMS: rule `own` lifts 34 BT positions, rule `salmon` 3, of which 2 no other rule lifts (`lift_rules_236/prove_ADMS_*.csv`). On the eleven proof groups the candidate adds 2 BT lifts, both in ADMS (`lift_rules_236/candidate_default.csv`): where salmon reach a BT barrier there, BT records already lift it, or the salmon records are fewer than two. Whether `default` adopts it is a follow-up issue, which would measure it province-wide.

## Which crossings are human-made barriers

`parameters_barrier_rules.csv` is evaluated once per group into `crossings.barrier_rule_id`. `default` and `bcfishpass` ship one row, the source's own status, which reproduces the barrier set exactly: on the proof builds the marker sits on the status set in every group, and every persisted table equals the build before the rules (`barrier_copies_386/final_equal_*.csv`).

A rule moves the barrier-below marks, the mapping code's second token and the per-crossing totals' below-barrier km, never access. Two measured rule sets against the province's result on #321's parity groups, ADMS and BULK, under `bcfishpass` (`barrier_rules_341/`):

- **added**: the province's result, or outlet drop above 0.6 m, or slope times length above 120 (the `high` thresholds `lnk_thresholds()` shipped until 0.93.0);
- **in place**: for a PSCIS crossing the measured rules, keeping the province's result only where both measurements are null; every other crossing keeps its status.

Measured against those two thresholds, most crossings PSCIS calls a barrier or potential barrier are neither. In place, BULK's PSCIS crossings go from barrier to not on 779 of 1,564 and the other way on 1; ADMS 27 and 3 of 69. Added, only 1 (BULK) and 3 (ADMS) become barriers. Neither measurement exists for 566 of BULK's assessments and 20 of ADMS's. In place moves BULK's below-barrier totals for 185 to 290 crossings per species and the anthropogenic mark on 3,602 of its 42,988 segments; added moves 2 crossings per species and 10 segments. Modelled crossings and dams are unchanged in both sets. The province's result reads more than outlet drop and slope, so which measured rules `default` adopts, and from what source, stays open on #341.

**Does a rule change need a re-model?** Not a full one. The per-crossing totals take one `lnk_aggregate()` call per group (ADMS 11 to 13 s, BULK 20 to 24 s), and the marks one `lnk_access()` pass (6 to 8 s, 28 to 30 s; `timing.csv`). But `crossings` is not persisted, and the persisted `barriers` hold only the crossings today's rules select, so a rule that widens the set needs crossings the persisted table does not hold (3 ADMS and 1 BULK crossings under the added set; `unmeasured_*.csv`). Such a change re-runs the crossings phase for each group, then the recompute.
