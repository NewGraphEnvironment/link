# link#162 — lnk_compare_wsg + provincial parity annotated CSV

## Outcome

Lifted two scattered `data-raw/` scripts into a single exported `lnk_compare_wsg()` with both linear-rollup and per-segment mapping_code lenses, added `lnk_parity_annotate()` against a YAML divergence taxonomy, modernized the multi-host orchestrator to 5-host (M4 + M1 + N cyphers via tofu workspaces) with inline LPT, and hardened the spin-up + smoke + dispatch + burn-down flow so failures fail loud and fail fast. Ships as v0.36.0.

First live 5-host provincial run (2026-05-12 → 13) covered 114 of 217 WSGs — 56 surviving UNEXPLAINED rows form the investigation queue, and 93 cypher WSGs were lost to a `fresh.streams` DDL drift caught **after** the run completed. The hardening shipped on this branch (DDL drift detection in `lnk_persist_init`, smoke fail-fast contract, cypher-side log pull-back, truth-in-headline error count) means the same failure mode would surface in 3 minutes via the smoke instead of 80 minutes via the full run. Acceptance bar (zero UNEXPLAINED ≥ 2%) deferred to the next provincial run.

Closed by: PR #__TBD__ (commit 531e881).

## Phase ledger

| Phase | Commit | Summary |
|---|---|---|
| 1 | `846d11a` + `da39e7a` | scaffold + rollup-only `lnk_compare_wsg()` |
| 2 | `23c6c47` | mapping_code branch (float-key rounding + NaN-guard fixes) |
| 3 | `051ecab` | data-raw wrapper collapse (−745 lines) |
| 4 | `2ab4aab` | taxonomy YAML + `lnk_parity_annotate()` |
| 5 | `a3e7dfc` | 5-host orchestrator + inline LPT + auto-annotation |
| 6 | `7a3bda0` | smoke modernization + dedup + bucket-aware consolidation |
| 7 (live + fix) | `6955603` + `0e26f50` | bcfp-not-modeled WSGs warn-not-error |
| 7 (hardening) | `531e881` | DDL drift detection + smoke fail-fast + log visibility |
| 8 (release) | (this commit) | NEWS + DESCRIPTION 0.36.0 + runbook update |

## Follow-ups (NOT in this PR)

- **#163** — Adaptive `host_speeds` learning from observed wall times (LPT refinement)
- Investigation of the 56 UNEXPLAINED rows from the 2026-05-12 run (use `research/bcfp_divergence_investigation.md` recipes; update taxonomy YAML + re-annotate, no rerun needed for 114-WSG slice)
- Next provincial run to recover the 93 missing cypher WSGs and validate the Phase 7 hardening end-to-end against the acceptance bar

## Key durable references

- `R/lnk_compare_wsg.R` + `R/lnk_parity_annotate.R` — library entry points
- `research/bcfp_divergence_taxonomy.yml` — taxonomy SoT
- `research/bcfp_divergence_investigation.md` — diagnostic recipes
- `research/provincial_parity_2026_05_12.md` — first live run results + lessons
- `research/provincial_run_runbook.md` — 5-host operational recipe
- `data-raw/README.md#provincial-dispatch` — CLI flag reference
- `findings.md` (this dir) — operational lessons from the 2026-05-12 → 13 run
