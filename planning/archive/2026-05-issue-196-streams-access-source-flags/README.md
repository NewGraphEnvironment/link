# #196 — streams_access per-source flag persistence + cross-WSG mapping_code

**Outcome:** Shipped as **v0.40.3** (PR #199, merged `46b2042`, tagged `v0.40.3`). Fixed the three coupled root causes of the `NONE`-everywhere second token in `lnk_pipeline_mapping_code`: persist DDL gained the six per-source flag columns (`lnk_persist_init`), the mapping_code phase pre-persists barriers for cross-WSG dam visibility (`lnk_pipeline_run`), and the persist INSERT projection now includes the flag columns (`lnk_pipeline_persist` — the actual `NONE` bug). Added `RUNBOOK.md` (the durable barrier→access→mapping_code mental model + authoritative bcfp access-set mechanism).

**Spun out (not done here):**
- **#200** — mapping_code accessibility: reproduce bcfp `barriers_<sp>` (natural-only + override) so dam-downstream segments emit `;DAM`. The access set still carried dams (should be natural-only + observation/habitat-overridden). Now in flight on branch `200-mapping-code-accessibility-reproduce-bcf`.
- **#201** — `blocks_species` redesign (carry barrier ingredients, classify access late) + evidence-based dam-override. Depends on #200.

The investigation trace (Causes 1–4, the `_min`-swap dead end, the bcfp source read on 2026-05-23) is in `findings.md`; the scoped fix that became #200 is in `phase4d_plan_draft.md`. `HANDOFF.md` was the M4→M1 handoff.
