# Plan review — #283 (Plan agent, 2026-09-26)

Returned as reply text (the Plan agent has no Write tool); recorded here with the
disposition of each finding. Claims marked *verified* were re-probed before acting.

| ID | Finding | Disposition |
|---|---|---|
| B1 | `schema = cfg$pipeline$schema` default scores the wrong bundle: `default` declares `fresh`, which bcfishpass builds (65 `bcfishpass` log rows) | *verified*; `schema` now required; `<schema>.log` config_name must match `cfg$name` where logged |
| G1 | Miss reasons from the thresholds CSV + #284 `pred_set` cannot match `rules.yaml` (stream rear rule has no `in_waterbody: false`; lake/wetland rules skip thresholds; 1050/1150 `thresholds: false`; bcfishpass BT `rear: []` is open on any edge) | *verified* (predicates printed for both bundles); reasons now re-evaluate `fresh::frs_habitat_predicates()` with gradient / width relaxed |
| G2 | Unattached observations counted as inaccessible (8 in `fresh_default`) | `n_unattached`, reason `no_segment` |
| G3 | Lake / wetland rearing unscored (16,651 BT segments `lake_rearing` and not `rearing`); A/B match drops D/E waterbody matches | `rearing_any` added; A/B documented as stream matches |
| G4 | `lnk_points_snap()` writes a permanent table and returns no WSG; FISS absence rule unstated; 3 WSGs only | driver snaps in a temp table; absence = sampled site where the species was not caught; stated not decision-grade |
| A1 | Scoring `default_tuned` against the observations that set BT 0.1349 is in-sample | documented in roxygen + research; `observations` arg takes any table for hold-outs |
| A2 | Access circularity checked; codes 0/1/2 only in persisted WSGs | noted |
| A3 | spawning/rearing gated on `streams_habitat.accessible`, not `streams_access` | documented (`share_spawning` not a strict subset of `share_accessible`) |
| A4 | Baseline diff conflates config with build vintage (50/51 shared WSGs unlogged in `fresh_default`) | `run_logged` column; driver stamps per-WSG log state; diff not read as a pure config effect |
| A5 | `n_in_uhc` differs by bundle (`apply_habitat_overlay: no` in bcfishpass) | `overlay_applied` column |
| A6 | Assert identical observation sets across bundles | driver asserts per WSG x species |
| AC1 | Sanity check against #284 must use the pooled 5,104 over 55 WSGs | driver runs `fresh_default` on all 55 |
| AC2 | Baseline compares bundles, not thresholds | scope decided by the user (read-only); stated in PR |
| — | `buffer_m` semantics (mainstem only, WSG-bounded, lake connectors) | documented |
| — | unqualified temp-table DROP | `pg_temp.` prefix |
