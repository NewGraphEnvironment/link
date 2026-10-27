# Code review, round 3: branch 326-break-streams-only-where-a-present-speci (#326)

Diff: `/var/folders/.../cc_link/diff3.patch` (a34d5357..a81d059e, logs and planning excluded). This round asked for the mechanism behind rounds 1–2 and an enumeration of everywhere it reaches.

## Checklist read

- **code-check.md** (330 KB): the prose of all 14 H3s under `## Mechanisms`, with table rows skipped. The other 23 H3s I read as index lines only. None of them names a tool or shape this diff uses.
- **code-check-r.md** (178 KB): 5 of 111 headings read in full; 106 read as index lines only. The 5:
  - "Postgres row order is never fixed…"
  - "A `function(...)` mock hides arguments…"
  - "`$` on a list partial-matches"
  - "An `information_schema` lookup by the literal table name…"
  - "A database driver's value is not a base R type"
- **code-check-spatial.md** (156 KB): 2 of 93 headings read in full ("FWA `upstream_route_measure` misses the next segment's start", "FWA main flow is not edge type 1000 alone"); 91 read as index lines only.
- **code-check-shell.md** (125 KB): index only, 67 headings. The diff contains no shell.

## Mechanism

**Segmentation used to grow with the barrier set. It now shrinks, so it depends on two sets agreeing, and nothing checks that they do.**

- Before #326, every barrier position was a break. Any difference between the break-time set (a) and the access set (c) could only add breaks, which is harmless.
- After #326, the break set is (a) **reduced**. Each position in (a) takes away the breaks above it. So:
  - **D1.** A position that (a) holds and (c) does not hold or lifts deletes a break at a real (c) frontier above it.
  - **D2.** A position that (c) holds and (a) lifts or lacks is not broken at all, unless an independent source breaks it (falls, user-definite, subsurface).
- The code asserts the two are equal: "the same recipe as the persisted `barriers_<sp>_access` view". But (a) and (c) are built from **different copies of the same inputs, at different scopes**:
  - (a) works per group from working tables: this group's overrides, gradient over whole lines, and falls / definite / subsurface for the AOI.
  - (c) is the union of every group's persisted rows, and every group's override rows.
  - Several inputs are filtered or mapped independently on each side: the AOI filters, the class→species map, and the controls.
- The prior findings are instances of this. R1 #3 / R2 is the lift scope. R1 #4 is classify (b) seeing a third scope. R2's two bugs came from trying to equalise scope by reading a store whose contents depend on run order. `breaks_diff.R` reading another config's `working_<wsg>` is the same "one name, several builds" shape on the diagnostic side.
- **The invariant that has to hold:** for every species whose access is computed, every effective (c) barrier on the group's streams is either broken, or shadowed by an effective (c) barrier below it. Equivalently, (a) minus (c), taken effectively, must not prune anything.

## Enumeration

"Equal" means the same rows reach (a) and (c) for this group. "Harmless" means the difference only adds breaks, or is a (c) barrier off this group's streams.

| Barrier row / lift | (a) break-time, `prep_minimal` | (b) classify gate | (c) access view | Can (a) prune a (c) frontier, or miss a (c) barrier on the group's streams? | Verdict |
|---|---|---|---|---|---|
| Gradient, per class | working raw, whole lines; species classes from cfg `classes` ≥ amax | raw, AOI-filtered segments | every group's persisted raw; species from `.lnk_classes_bcfp` CASE in unify | Shipped bundles: no. Every class ≥ 0.15 is in `.lnk_classes_bcfp`, and bins are exclusive (`.frs_break_find_multiclass`). A bundle bin ≥ min amax outside that set (e.g. `"1750"`, `"3500"`) is in (a) but blocks nobody in (c): **D1** | Equal for shipped bundles; **latent, see F1** |
| Gradient on a shared line held by another group | the group's own copy (same FWA positions) | AOI only | union of copies | (c) ⊇ (a). Extra (c) rows only shadow frontiers | Equal / harmless |
| Gradient pruned by a control row (`barrier_ind = false`, AOI-filtered) | removed from G's raw | removed | H's unpruned copy survives in the union | G does not break at Y, but (c) holds Y (D2). Before #326 G did not break at Y either | Pre-existing; CLAUDE.md "2 rows today". Not caused by #326 |
| Gradient below the outlet on another blue line | absent | absent | present | Only shadows (c) frontiers | Harmless (extra breaks) |
| Gradient out of the AOI on the group's own lines | present (prunes) | absent | present | (a) and (c) agree; (b) does not see the pruner | Named residual (R1, classify scope) |
| Falls | CSV code = AOI **and** segment group = AOI | segment group = AOI | CSV code = AOI (any segment), plus other groups' | (a) ⊆ (c). A falls whose segment is in another group is not on this group's streams | Harmless |
| Subsurface flow | present when `break_order` opts in | same | unify probes whether the table exists; `setup(overwrite = TRUE)` drops the schema first | Equal | Equal |
| User-definite | AOI CSV, FWA join with no group filter, never lifted | segment group = AOI | same rows persisted, override-exempt | Equal (b is R1's scope) | Equal |
| NULL-ltree rows / points in the ≤ 9 mm FWA gap | dropped | dropped by the join | kept but inert (`fwa_downstream` on NULL) | Neither prunes | Equal |
| Observation lift | this group's overrides; observations counted province-wide | exact rounded-measure match (fresh) | union of every group's overrides | Other groups' rows lift where G does not: **D1** | Named residual (R2, cross-group lift) |
| Lift at another bcfishobs vintage (partial re-model, `--recompute-only`) | not read | — | read | Same as above | Named (R1 #3, under R2) |
| Habitat lift | whole CSV, no AOI filter | same table | same CSV in every group | Equal | Accepted (pre-existing) |
| Control blocking a lift (`barrier_ind = true`, AOI-filtered) | this group's controls | — | another group's row may lift where this group's control blocked it | **D1** | Named (R2) |
| Lift match rule | `abs(raw − rounded) < 1` | exact `round = round` | `abs < 1` | (b) lifts ⊆ (a) lifts, so (b) is stricter only at a lifted position, the same as before #326 | Pre-existing |
| Species set | `cfg$species` ∩ `lnk_presence()` (expanded) | `lnk_pipeline_species()` (literal `"t"`) | access for `active_species` (literal) and present per `lnk_presence` | Access ⊆ (a). Absent species get no access value (CH / ST on FINA: their unbroken frontiers are irrelevant) | Harmless |
| Topology predicate | `fwa_upstream(Y, X, false, 1)` | ltree-only `fwa_upstream` + `b.drm <= s.drm` | `fwa_downstream(seg, Y, true, 1)` | I compared the two SQL bodies clause by clause (same-blk measure, tributary `subltree`, side-channel, bottom-segment). Wherever `fwa_upstream(Y, X)` holds, `fwa_downstream(S_X, Y)` holds for the segment S_X containing X, given the break chain below. Equivalents and the 1 m tolerance make the reduction prune less | Equal / harmless |

**Reproducibility.** After a81d059e, (a) reads only this build's working tables (`gradient_barriers_raw`, `falls`, `barriers_definite`, `barriers_subsurfaceflow`, `barrier_overrides`), the loaded presence table, and FWA. `barrier_overrides` is built from the fixed input `bcfishobs.observations`, the habitat CSV and the controls. The `frs_barriers_minimal` DELETE and the `DISTINCT … UNION` are set operations, so they do not depend on row order. Nothing persisted is read, so (a) is clean on this axis.

**End-to-end check (read-only, scratch schema `zz_review_r3_a81d`, since dropped).**
- Population: on FINA's persisted segments (`fresh`, built at 1b69ad7c, which has the same own-group lift as HEAD), every effective BT `barriers_bt_access` position that has no effective BT barrier below it (`fwa_upstream`, 1 m), across the whole `fresh.barriers` table.
- Result: 3,879 frontiers. **0 are more than 2 m from a segment boundary.**
- With a 1 m window, one stays unbroken: blk 359529138 at 10,178.57 (rounds to 10,179). It is in `barriers_bt_min` and `gradient_barriers_minimal`. `frs_break_apply` skipped it because another source breaks the line at 10,180, within 1 m, so it sits inside segment [10,176, 10,180). That skip predates #326.
- CH and ST show 1,313 and 1,786 unbroken frontiers. Both are absent from FINA (`wsg_species_presence`: BT, DV, GR, RB), so they get no access value and are irrelevant.
- `fresh.barrier_overrides` here holds only FINA's and PARS's rows, so this measurement cannot see R2. It confirms the shipped path, not the cross-group residual.

## Findings

- **[severity: fragile] `R/lnk_barriers_unify.R:133` against `R/lnk_pipeline_prepare.R:126,650`. The class→species map is derived twice.**
  - Unify builds `blocks_species` from the hardcoded `.lnk_classes_bcfp`, and any `gradient_class` outside it falls to `ELSE ARRAY[]` (line 160).
  - (a) builds each species' set from the resolved cfg `classes` (`classes >= sp_amax`).
  - Suppose a bundle's `pipeline.gradient_classes` adds a bin at or above the lowest `access_gradient_max` that is not in the bcfishpass set: say `"1750": 0.175`, or a `"3500"` cap. `.frs_break_find_multiclass` labels each island with exactly one bin, so those islands carry only the new class.
    - (c) treats them as passable for every species. That part is a pre-existing (c) bug, and (b) disagrees, because it parses `gradient_1750` and blocks CH.
    - (a) puts them in CH's set, where they prune CH's (c) frontiers above. Before #326 that only added breaks. Now a 15 % frontier above a 17.5 % island goes unbroken, and the segment straddling it is labelled accessible above it (D1).
  - No shipped bundle does this today: every class ≥ 0.15 in `bcfishpass`, `default*` is in `.lnk_classes_bcfp`.
  - But `bcfishpass/config.yaml:77` and `default/config.yaml:88` invite the override, and say "Setting this changes only break positions", which is no longer true.
  - Fix: derive unify's CASE from the same resolved `classes` (`.lnk_resolve_classes(NULL, cfg)`), or refuse at prepare time a class ≥ min amax that is not in `.lnk_classes_bcfp`. Then fix the two comments.

No new defect in the shipped configurations. Every other difference in the table is equal, harmless (it only adds breaks, or the (c) barrier is off the group's streams), or one of the two named residuals (R1 classify scope, R2 cross-group lift). The control-pruned-copy D2 and the 1 m `frs_break_apply` skip both predate #326 and do not change with it.

## Note

Both named residuals have the same remedy class. They will not show up in any single-group measurement until other groups' override rows are persisted. On this machine `fresh.barrier_overrides` holds 38 rows (FINA and PARS only). So Phase 4's "count such positions per re-modelled group" needs a database where the neighbours' overrides exist (the dispatcher's `fresh_default`), or it will report 0 by construction.
