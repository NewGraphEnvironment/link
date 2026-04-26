# Progress — v0.10.0 spawn edge_types tightening

## Session 2026-04-24

- Created branch `10-spawn-edge-types-explicit` off `main` (post v0.9.0 merge)
- PWF baseline: `task_plan.md`, `findings.md`, `progress.md` written
- Plan revised from "add new `spawn_edge_types_explicit` column" to
  "switch default config to existing `edge_types = "explicit"` mode" —
  much simpler, achieves the same end state, infrastructure already exists
- Verified bcfishpass config already uses `explicit`; default config uses
  `categories`. Switching the default's `data-raw/build_rules.R` call is
  the entire code change.
- Next: Phase 2 — flip `data-raw/build_rules.R` to `edge_types = "explicit"`
  for both default YAMLs, regenerate, verify diff.

### Phases 2-6 done in one atomic commit
- `data-raw/build_rules.R`: both default calls now pass
  `edge_types = "explicit"` (top-level `parameters_habitat_rules.yaml` and
  `configs/default/rules.yaml`)
- Regenerated both default YAMLs. bcfishpass yaml regenerated too (only
  date stamp changed since it was already on `explicit`)
- Verified: 1050/1150/2100 absent from all spawn rules and from
  rear-stream predicate rules. 1050/1150 retained in the dedicated
  wetland-rear rule (the one with `thresholds: false`) per design.
- Added 2 regression tests in `test-lnk_rules_build.R`:
  - default rules.yaml has no 1050/1150/2100 in spawn or rear-stream
    predicates (loops over all species)
  - BT (representative `rear_wetland=yes` species) still has the
    dedicated wetland-rear rule with `[1050, 1150]`
- Full suite: 360 PASS, 0 FAIL, 1 pre-existing WARN
  (`test-lnk_pipeline_break.R:214` mocked-bindings — unrelated)
- Next: Phase 7 — ADMS preflight on m1.

### Phase 7-12 done in one session
- ADMS preflight (M1, fresh 0.21.0, local Docker fwapg + tunnel
  bcfishpass): BT 397→368 km, CH 296→279, CO 340→318, SK 98→94,
  RB 331→311. All decreases 4-7%. Rearing flag preserved for
  `rear_wetland=yes` species. Sane.
- Full 5-WSG run: 18m 25s, 11 targets completed (2 skipped from preflight).
  Rollup digest TBD. Key finding: spawning Δ between bundles is now 0 km
  on every parity species × WSG. Rearing departures persist (intermittent
  streams + wetland_rearing additions).
- Refreshed all per-WSG tables in `research/default_vs_bcfishpass.md`
  (§Results — ADMS, BULK, BABL, ELKR, DEAD).
- Rewrote observation §2 to reflect spawning alignment (rearing-only
  inflation now); §3 updated with v0.10.0 narrative; §6 caveat note
  added (BABL SK source-bucket analysis is pre-v0.10.0).
- `/code-check` clean round 1.
- NEWS 0.10.0 + DESCRIPTION bump committed in branch state.
- Next: stage + commit research/NEWS/DESCRIPTION; open PR.
