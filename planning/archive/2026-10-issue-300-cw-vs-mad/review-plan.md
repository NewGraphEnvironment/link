# Plan review (Plan agent, 2026-10-02) — triage

Full findings were returned as reply text (Plan agents cannot write); condensed here with triage.

| ID | Finding | Triage |
|---|---|---|
| B1 | score crashes on 0 ladder steps | already handled: early `quit()` after the model section when no row has a column |
| B2 | score finds base by empty column | already handled (score uses empty `step_from`, re-validates model-only rows) |
| B3 | threshold check breaks on model-only row | already handled (0-cell branch); plan wording "only a method table" wrong — bundle carries a byte copy of the base thresholds. Plan text corrected |
| B4 | scratch `--out` lacks bundles/built.csv | already handled: regression copies `bundles/` + `built.csv`; `stamp_score.txt` excluded from the comparison |
| B5 | no build-side regression | **fix**: `--step=bundles` (bundles only, no DB write); regenerate #284/#302 bundles under `--base=default` and diff byte for byte |
| G1 | thin core order classes (GR core orders 1-3 ≈ 30 km vs 1,826 km band) | **fix, pre-registered before any run**: merge a class whose core holds < 10 locations into its neighbour until each holds ≥ 10; report band km priced on merged classes |
| G2 | missing discharge / width mixed into bands | **fix (reported only)**: `model_reason.csv` splits cw-only by mad NULL / below mad min / in range, mad-only by width NULL / below width min / in range |
| G3 | UHC check skipped for model-only | already handled |
| G4 | new outputs not in delete list; base not in stamp | already handled |
| G5 | pooling key, stage filters, order 0 | key already species × flag × stage × role × class; order 0 → `unknown` class (fix) |
| G6 | pre-flight on a WSG with all species; empty aoi | **fix**: pre-flight PARS (BT, GR, RB, KO roles) and score it; skip a model-only variant with no focal WSG |
| G7 | forbid stepping from a model-only variant | **fix** in both scripts |
| G8 | `--base` duplicates `equals_bundle`; pooling hard-codes "default" | keep the flag (explicit, guarded both sides; build/score mismatch also caught by built.csv sha); pooling reads the base (fix) |
| G9 | obs_stage/equals_bundle unconstrained on model-only rows | **fix**: require both empty; `variants_300.csv` obs_stage blanked |
| O1 | rule changes before any run | yes — G1/G2/G5 go into the research section before the build |
| O2 | do not touch the tree during the detached build (planning/ and research/ count as dirty) | adopted: no edits while it runs |
| O3 | negatives before commit | done for build; score negatives before the harness commit |
| A1-A3 | base digest under default_tuned; clustering thins GR core; stage `any` for spawning bands | A1/A2 seen at pre-flight; A3 one sentence in the Reading |
| S2 | #302's cw km were under `default` (BT 0.1049) | noted for Phase 6 |
| Acc 1 | band identity: variant − base km = added − removed | Phase 6 check |
