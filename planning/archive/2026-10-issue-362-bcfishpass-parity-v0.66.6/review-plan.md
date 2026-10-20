# Plan review (#362), Plan agent, 2026-10-20

No blockers. Findings and dispositions:

| # | Kind | Finding | Disposition |
|---|---|---|---|
| 1 | Assumption | Cited evidence for "no scored pair moves through a lift" is `groups_blocked.csv`, which lists only whole-group blocks under `default`. Province-wide counting (`R/lnk_pipeline_prepare.R:318,353-384,575-582`) can only add lifts, never lose them; read-only it found no other-group record upstream of any focal group's unlifted natural barrier (upper bound, 0 rows), and no natural barrier on the Bulkley / Morice / Skeena mainstems, so MORR's records lift nothing for BULK. | Added a direct override-position diff across all holders to `moves.R`; the parity file states what was measured. |
| 2 | Gap | `study_area_verify.sql` defaults to schema `fresh`; needs `-v schema=fresh_parity362`; `expected_n` from the `done` lines. | Corrected command used. |
| 3 | Gap | The driver's 17-group mapping_code compare is free and covers the groups where new lifts happen. Confounded by 91a968ab for mapping codes. | Joined in `moves.R` (`mapping_code_moves.csv`), caveat stated. |
| 4 | Ordering | Any tracked-file change outside `data-raw/logs` mid-run sets `link_dirty`, which verify raises on. | No planning / research edits or commits until `run.exit`. |
| 5 | Assumption | Cost "~7 h" was wrong: the 2026-10-17 model leg ran 09:36-10:30 UTC (`fresh_parity246.log`), the file mtimes are a checkout. | Verified by query; corrected in task_plan. |
| 6 | Assumption | fwapg SHA moved (f9718cb -> 6d48dab: `FWA_WatershedAtMeasure` migration + pcic; link calls neither). Link changes since a17e9177: comment, mapping_code (91a968ab), CSV newline, log tables (#354). bcfishobs not reloaded. | bcfishobs load stamp 2026-10-17 00:47 UTC verified; stated in the stamp. |
| 7 | Acceptance | Write the expected result before scoring: accessible and spawning 0.0 everywhere; rearing BT about -0.3 BULK, -0.3 BABL, -0.6 ELKR. The 0.1 km threshold sits at the CSV's rounding; use the segment diff as authority. | Recorded in findings before scoring. |
| 8 | Scope | Do not copy the driver's logs into `parity_0.66.6/`; reference `data-raw/logs/study_area_run/20261020_171738_*`. `bcfp_model_run_id` NULL tunnel-free is correct; 143 from `turn_bt.txt`. | Adopted. |
