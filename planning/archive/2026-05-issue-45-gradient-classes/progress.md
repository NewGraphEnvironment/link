# Progress — Gradient classes: derive from parameters_fresh, optional override arg (#45)

## Session 2026-05-03

- Plan-mode exploration via Explore subagent — full surface-area mapping of both hardcodes, downstream label coupling, test scaffolding, integration points. Phases approved by user.
- Created branch `45-gradient-classes-derive-from-parameters` off main
- Scaffolded PWF baseline from issue #45 with approved phases
- Phase 1 complete — `classes` override threaded through `lnk_pipeline_prepare()` → `.lnk_pipeline_prep_gradient()` and `.lnk_pipeline_prep_minimal()`. `models` list replaced with per-species derivation from `loaded$parameters_fresh$access_gradient_max`. New helpers `.lnk_classes_bcfp` (default vector) + `.lnk_resolve_classes()` (caller → cfg → default fallback). 5 new tests + 2 existing tests updated. Code-check 2 rounds: round 1 caught 3 fragile issues (empty species → empty table fallback; defensive `sp_amax[1L]` for R 4.3+ length-1 `||` enforcement; identifier validation on species codes); round 2 clean. Commit `15327ea`.
- DB regression on ADMS surfaced a bug: `lnk_pipeline_species()` filtered species by WSG presence, dropping ST/WCT break positions on WSGs without ST/WCT presence flags → -0.62km BT spawn / -0.18km BT rear drift on ADMS. Fix: use `cfg$species %||% loaded$parameters_fresh$species_code` directly — break network is AOI-agnostic, presence filter applies at classify time. Bit-identical bcfp parity restored on ADMS + HARR (digests `f887d97...` and `18bc310...` match pre-#45 baselines). Commit `f606837`.
- Phase 2 complete — config knob `cfg$pipeline$gradient_classes` documented in `bcfishpass/config.yaml` and `default/config.yaml` as a commented-out optional with the bcfp-parity values shown explicitly. `.lnk_resolve_classes()` resolution chain (caller → cfg → default) was already in place from Phase 1; added a YAML→R round-trip test through `lnk_config()` for defensive coverage of the named-list shape `yaml::read_yaml()` produces. Commit `36d2f5e`.
- End-to-end override demo on ADMS: experimental `c("0500"=0.05, "1500"=0.15, "2000"=0.20, "2500"=0.25)` produced bit-identical rollup (0.05 doesn't enter any species filter; 0.30 redundant — 30%-class barriers always upstream of 25%-class on same flow path, dropped by minimal reduction). More aggressive `c("1500"=0.15, "2000"=0.20)` (drops 0.25) cleanly demonstrates: BT (@0.25) gets no class >= 0.25 → no barrier filter → BT habitat expands ~30% (+199km rearing, +173km rearing_stream, +81km spawning). CH/CO/SK at 0.15 unchanged. Schema isolation via `cfg$pipeline$schema = "fresh_exp_*"` works as designed.
- Phase 3 complete — bit-identical regression across 4 WSGs:
    - ADMS: `f887d97...` ✓
    - HARR: `18bc310...` ✓
    - BABL: `61bc7ad...` ✓
    - BULK: `699bd9e...` ✓
  Stamped log at `data-raw/logs/20260503_link45_regression.txt`.
- Phase 4: NEWS.md entry under 0.27.0, DESCRIPTION bumped 0.26.0 → 0.27.0. Full suite 728 PASS / 0 FAIL.
- Next: open PR with SRED tag, archive PWF, file follow-up issue for auto-derive default.
