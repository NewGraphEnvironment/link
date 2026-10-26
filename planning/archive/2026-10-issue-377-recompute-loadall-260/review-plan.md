# Plan review (Plan agent, 2026-10-26) — findings and dispositions

| id | finding | disposition |
|---|---|---|
| B1 | The 105 → 110 min gap cannot be "not the prologue": anything before `t0` lands only there. It is an upper bound on all untimed per-job cost (≈10 s/job, ≤4.5 % of the phase). | Accepted. Report the gap as the in-run upper bound on everything untimed, prologue included. |
| G1 | Stage list missed R startup, connect + SETs, species/presence. | Already covered by `prologue.R` (r_start, connect, set, species); bash fork/cd/.rc are inside r_start or negligible. |
| G2 | The phase row also holds `recompute_order`, the concatenation and `fanout_judge.R` (one more load_all). | Accepted; named in the gap accounting. |
| A1 | 110 min is from `research/study_area_run.md`, not a `_phases.tsv` (none for that run). | Accepted; cite the research file, cross-check from log mtimes if possible. |
| A2 | In-run SALR/CHWK minutes are contended; #260 frames SALR 11 s, CHWK 226 s. | Accepted; report both denominators. |
| A3 | 8 simultaneous prologues ≠ -j8 (other slots run CPU-bound R). | Accepted in part: add a condition with 7 CPU-busy R processes beside the prologue. Not re-running a real recompute: it rewrites `fresh_default`'s shipped tables. |
| AC | AC2/AC3 are conditional: mark N/A, not ticked. Stale line refs in #260 (:24-28) and research (:25-27); now :26-30. | Accepted. |
| Scope | Keep the #376 tick separate from #260 evidence. | It is an issue-body edit, made as its own step. |
