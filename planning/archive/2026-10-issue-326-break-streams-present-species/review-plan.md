# Plan review — #326 (2026-10-26, Plan agent, unnamed background spawn; findings returned as reply text and written here by the session)

Reviewed the gate-approved plan against the issue, `research/bcfp_segmentation_parity.md`, link main (v0.68.6), fresh origin/main (0.42.0) and the bcfishpass reference checkout. Both blockers were verified against the code by the session before folding: `barrier_overrides.species_code` is written from `parameters_fresh` (`R/lnk_barrier_overrides.R:140,198,239`, uppercase) while `lnk_presence()` returns lowercase; bcfishpass's order-1 exception sits inside `s.gradient <= t.rear_gradient_max` (`model/02_habitat_linear/sql/load_habitat_linear_bt.sql:88-96`) and fresh's `frs_order_child()` has no gradient test. Every finding below is folded into `task_plan.md`.

## Blockers

- **B1. Species-code case in the override anti-join reproduces #223's failure.** `lnk_presence()` returns lowercase names (`R/lnk_presence.R:94-109`); `barrier_overrides.species_code` is uppercase (`R/lnk_barrier_overrides.R:140,198,239`); the access view anti-joins with the uppercase literal (`R/lnk_barriers_views.R:170,214`). A lowercase literal matches nothing, every lift is ignored, and the reduction runs on the pre-lift set. Iterate `cfg$species` and test `tolower(sp) %in% present`; the mocked test asserts the literal `o.species_code = 'BT'`.
- **B2. `frs_order_child()` has no gradient test; a width test alone does not reproduce bcfishpass's exception.** The exception sits inside `s.gradient <= t.rear_gradient_max AND (...)` in every bcfishpass rearing block. With a width test only, a steep order-1 line with a measured width below the minimum rears in link and never in bcfishpass, and the PARS acceptance cannot see it (`data-raw/logs/rearing_diff_324/mechanism.R:43-44` classes `bypass` as `bcfp_only` only). Phase 0 needs a gradient bound, a fresh test for "steep order-1 never admitted", and a pre-flight line "0 link-only km on order-1 / parent ≥ 5 lines".

## Gaps

- **G1.** `gradient_barriers_raw` is not group-scoped (`streams_blk` is a BLK list, `prepare.R:394-399`; `frs_break_find` has no group filter), so a main-stem barrier below the outlet does prune this group's frontier; the cross-group residual is only a blocking barrier on a different blue line joining below the outlet, or a falls / subsurface / definite barrier outside the AOI (those are AOI-filtered: `:178-179`, `:536`, `:186`). Out-of-AOI positions survive into `barriers_<sp>_min`; harmless to `frs_break_apply` but a break census must restrict to the group's streams and label them.
- **G2.** The view and the break-time recipe otherwise match. Habitat lifts are computed from the whole `user_habitat_classification` CSV with no AOI filter (`prepare.R:235-240`; `lnk_barrier_overrides.R:237-255`) where bcfishpass filters to the group — pre-existing, now also decides which positions prune. Named, not changed.
- **G3.** Drop the "round measures to match barrier_overrides" step: raw is `ROUND(…, 2)`, overrides `round(drm)`, the `abs(…) < 1` anti-join covers it, and the view anti-joins on the raw measure. No double count is possible (`frs_break_apply` DISTINCTs after `round(…, 0)` and skips within 1 m of a segment end, as bcfishpass `break_streams` does). Raw rows with NULL ltrees neither prune nor are pruned: filter `wscode_ltree IS NOT NULL`.
- **G4.** `barriers_definite` before the reduction is correct: bcfishpass inserts `barriers_filtered UNION ALL barriers_user_definite` and then runs the non-minimal delete on the whole table. The research doc's "after" refers to the lift. The independent `falls` / `barriers_definite` / `subsurfaceflow` sources add breaks at every non-minimal position of their kinds, not only lifted ones.
- **G5.** Width minimum: the bcfishpass BT rear rule is `- []`, so it comes from thresholds (`params[[sp]]$rear_channel_width_min`); a rule carrying its own `channel_width` range should win; `lnk_rules_build` attaches the bypass to both stream and river rules and classify takes the first. Resolve carrying rule → thresholds → error (the existing classify mock has no width and would pass NULL silently). `bypass_keys` whitelist (`frs_params.R:457-460`) must gain the sub-key with a logical-scalar check. `channel_width_max` is a misleading name for the species' minimum.
- **G6.** `.lnk_fresh_required()` must regain `frs_barriers_minimal` (`R/lnk_preflight_fresh.R:113-119`) or the callsite drift guard trips.
- **G7.** Tests: "once per present species" is vacuous unless configured ⊋ present and a salmon-expansion case exists; every existing `prep_minimal` fixture lacks `wsg_species_presence` and will error in `lnk_presence()`; assert call ordering and that the union names `_min` tables only; the FINA-frontier check is live-DB (`parity_crosssection.R:188-207`), not testthat; "five rear rules" is nine rule objects across five species.
- **G8.** `lnk_presence()` vs `lnk_pipeline_species()`: with the shipped CSVs the only live difference is expansion (LKEL: SK breaks and never classifies — harmless, identical row to CH's). Under `default`, RB builds a set whose frontiers differ from BT's, so `default` breaks at RB-only frontiers too; expect it to fall less than `bcfishpass`.

## Ordering

- **O1.** The m4 snapshot refresh must precede Phase 2's FINA pre-flight.
- **O2.** The fresh pin bump belongs with Phase 3, not Phase 0, so Phases 1–2 do not wait on a fresh release.
- **O3.** "State the run decisions before re-modelling": write it into the Phase 4 README before the first `wsg_run_one.R` call, not only under Owed.

## Assumptions

- **A1.** "Access must not move" holds per species only; never reduce the union.
- **A2.** `falls` in `break_order` is now redundant for parity; keeping it adds non-minimal fall breaks — say so where residuals are named.
- **A3.** `default`'s halving depends on RB / GR / KO; report the ratio.

## Scope / Acceptance

- **S1.** The issue's "Before landing" list is covered once O3 and G6 land.
- **S2.** Say which of the raw `barriers_<sp>` tables survive (the diagnostics note at `lnk_barriers_views.R:165-167`).
- **S3.** The "≥ 99.9 % of bcfishpass's positions" line is restricted to the group's streams; the census labels out-of-AOI positions.
