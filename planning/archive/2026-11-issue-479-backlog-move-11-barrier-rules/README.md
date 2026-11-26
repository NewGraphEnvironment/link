## Outcome

Backlog move 11 landed three of its five issues as link 0.93.0; #201 and #83 (which barriers block which species) split out. **#386:** every barrier-control row applies by position, and a gradient barrier, its lifts and evidence are held only by the group owning its segment (with a fallback holder where the owner is never modelled). Before, 1,224 positions on the 259 lines touching more than one group were held by up to 13 groups, and LSAL's Salmon River control was defeated by its neighbours' copies. **#236:** several observation-lift rules per species (`parameters_barrier_lifts.csv`), evidence keyed by rule. **#341:** which crossings are human-made barriers is `parameters_barrier_rules.csv`, evaluated into `crossings.barrier_rule_id`; `lnk_thresholds()`, `lnk_score()` and `lnk_source()` removed. Code-check took three rounds and an enumeration: round 2 found that owner-only persistence left a closure run into a schema missing a tributary owner reading its barriers as open, so `lnk_wsg_downstream_check()` now refuses that; round 3 found that fix blind on partial-FWA databases and without an override at the recompute's post-condition. Write-up: `research/barrier_rules.md`.

## Measurement

- Province-wide on `fresh_default` (0.78.2): 1,864 non-owner copies, 72 of them below segments of their holder (what a lone run would lose); 7 of 238 control rows filed under a non-owner, all inert falls rows.
- Eleven groups (TABR, LSAL, SALR, ADMS, ELKR, BULK, UPCE, PCEA, LPCE, FINA, PARS) built BEFORE / AFTER-386 / FINAL under both bundles: only copies removed (118 gradient rows each bundle; 81 and 114 overrides); no segment, access or habitat value moved, no lift lost; FINAL equals AFTER-386 in every persisted table, the rule marker on exactly the status set.
- The candidate second BT lift rule adds 2 lifts in the eleven groups (ADMS); follow-up #520.
- Two measured barrier-rule sets on ADMS and BULK: in place of the status, 779 of BULK's 1,564 PSCIS crossings leave the barrier set; a rule change needs the crossings phase and the recompute, not a full re-model.
- Two default proof builds stalled in fresh's near-river walk under other sessions' load (#487 shape); a 20-minute statement bound with one retry got them through.

## Evidence

`data-raw/logs/barrier_copies_386/`, `data-raw/logs/lift_rules_236/`, `data-raw/logs/barrier_rules_341/`

## Owed

- Every group re-models at the next provincial run (`acc-v8`, `acc-bcfp-6`), after the pre-run gate runs again (`R/`, `inst/extdata/`, `pretest_inputs.csv` changed).
- `lnk_persist_init()` once per host on each persist schema at a quiet time, for the evidence table's column and key, before any consolidate into it.
- The scheduler's move to the owner rule, after a provincial run leaves every group at 0.93.0 or later (speed track).
- The #201 + #83 issue filed from the draft below once the owner has read its body.
- #341's body edited to what remains open (which rules `default` adopts, unassessed crossings, POTENTIAL, sources beyond PSCIS, the side-by-side export); #236's optional group-scoped rule named where it is left.
- A full bcfishpass parity re-score on the 17-group closure, at the provincial run.

Closed by: PR (opened next) for #479, release v0.93.0
