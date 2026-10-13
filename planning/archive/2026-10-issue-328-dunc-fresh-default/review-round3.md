# Code-check round 3 (#328) — branch diff 2edc4105...HEAD

## Mechanism

Every earlier finding is one shape: **a property of one thing written down as a property of a neighbouring thing, because an upstream text put them side by side, and never read back from the artifact that owns the property.**
- LARL got KOTL's commit because the plan notes grouped "KOTL, LARL, SLOC".
- #282 and #307 were listed as flag-moving because their titles are about thresholds, not because anyone diffed the thresholds.
- The density list dropped CHWK because it was copied from an earlier tally.
- "The data is the same" was written about all FWA inputs when only six tables had been compared.

The source is always prose: the issue body, the plan-mode notes in `findings.md`, a PR title, an earlier status line. The check that settles each claim is to read the owning artifact (the log row, `git diff` of the CSV, the DB count, the code at the tagged version).

The same mechanism reaches one more claim nobody has checked yet. **The reporter's "Also observed" says DUNC "ran in the 2026-04-30 provincial parity run". The branch then adopted that run as the build date of DUNC's `fresh` rows, in three places.**

## Findings

- **[medium] `data-raw/logs/dunc_default_328/README.md:27`, the #328 issue body ("Answer (2026-10-12)" paragraph), and `planning/active/findings.md:41`.** Each says DUNC's `fresh` build dates from the 2026-04-30 parity run. That run cannot have produced the rows `fresh` holds now.
  - The 04-30 run's stamp reads link 0.20.0 / fresh 0.25.0 (`data-raw/logs/20260430_2155_provincial_parity.txt:4042-4050`).
  - At v0.20.0, `fresh.streams` was per-run scratch: `R/lnk_pipeline_prepare.R:452` runs `DROP TABLE IF EXISTS fresh.streams CASCADE` for every WSG, and habitat went to a single `fresh.streams_habitat`. v0.20.0 has no `lnk_pipeline_persist.R`.
  - The per-species `fresh.streams_habitat_<sp>` tables that DUNC is in today arrived in v0.26.0 (`d481f36`, #113, 2026-05-03).
  - DUNC was modelled again on 2026-05-13 by the trifecta provincial run, on the m1 bucket at link 0.36.0 / fresh 0.31.0 (`data-raw/logs/202605132248_trifecta_provincial_m1.txt:1946-1955`; also the m1 bucket of `202605131832_trifecta_provincial_orchestrator.txt`). At v0.36.0, `lnk_compare_wsg()` calls `lnk_persist_init()` and `lnk_pipeline_persist()`, which DELETE and INSERT the group's rows in `fresh.streams` / `streams_habitat_<sp>`.
  - So the 26,827-segment `fresh` build is from 2026-05-13, not 2026-04-30.
  - **The conclusion still holds**: 05-13 is before v0.40.0 (2026-05-19), #127 and #223, so "stale vintage, not a defect" stands. Only the date and run attribution are wrong.
  - **Fix:** say the build is from the 2026-05-13 trifecta run (link 0.36.0), or drop the date and keep "pre-v0.40.0, pre-#223".
  - The reporter's own sentence in "Also observed" can stay as their text. The Answer should not repeat it as fact.

- **[low] `planning/active/task_plan.md`, Phase 3, third box: "[x] Final report notes that floodplains `columbia.yml`'s `network_source` header (link 0.45.1) no longer holds for DUNC".** No final report has been made yet: the Validation boxes for `/code-check` and the archive are still open, and there is no PR. Under the PWF integrity rule, the box stays unchecked until the report is sent. The fact itself is correct: floodplains `config/regions/columbia.yml:21` cites link 0.45.1 for `fresh_default`.

## Checked, no defect (claim → source)

- CLAUDE.md: "KOTL, LARL and SLOC are August builds (link 0.45.1, fresh 0.33.0)". Matches `fresh_default.log`: all three are 2026-08-27, 0.45.1 / 0.33.0.
- CLAUDE.md: "only PINE, KOTL, LARL, SLOC (August) and DUNC have log rows". Exactly 5 rows; PINE is 2026-08-06.
- CLAUDE.md: "49 of the 56 under 1.5; CHWK 1.54; only PARS, PINE and the four Columbia groups dense, at 2.6+". Recomputed: KOTL 4.30, LARL 3.99, SLOC 3.60, PINE 2.86, DUNC 2.79, PARS 2.62, CHWK 1.54, HARR 1.497, everything else lower. 49 + 1 + 6 = 56.
- CLAUDE.md / issue: "59 and 39 of 98". `fresh.streams` 98, `streams_access` 59, `fresh.log` 39. No group has a log row but no `streams_access`, in either schema.
- README / issue: KOTL and SLOC `322389a` clean, hash `3cfde7b…`; LARL `8c8c29b`, dirty, hash `44e452e…`. Both commits are DESCRIPTION 0.45.1, pinned to fresh v0.33.0.
- README: "all six blocking dams below DUNC are in KOTL, already persisted". Re-ran `.lnk_dams_blocking_downstream()` and `lnk_wsg_downstream_check(on_fail = "warn")` with schema `fresh_default`: 6 dams, all KOTL (Brilliant, Corra Linn, Lower and Upper Bonnington, South Slocan Dam and Generating Station), status pass.
- README: "DUNC is a headwater group". No WSG outlet wscode descends from DUNC's `300.625474.096683`.
- README: species BT, WCT, RB; run times 15:31:35–15:33:45; 19 checks. All match `verify.txt` and the log row.
- README: "six FWA tables identical; DUNC also logs `fwa_obstructions_sp` and `fwa_stream_networks_discharge`; crossings 524,562 vs 529,244, observations 373,050 vs 372,690". Matches `log_input`, with DUNC listed first in both pairs. (PSCIS bytes also differ, rows equal. The README does not claim its list is exhaustive.)
- README / issue / task_plan: "#282 and #307 changed only MAD columns". Default's thresholds CSV against fresh v0.33.0's differ only in the BT, GR, KO and RB `*_mad_*` cells, and DUNC is `cw` in `parameters_habitat_method.csv`.
- "The rules that changed since August are #310, #311 (+ fresh#237, #240)". The default `rules.yaml` / `dimensions.csv` diff 322389a..8215d2d is only the #310 columns and rules plus the #311 W rule. The only override change is the xref, two ALBN rows. Pipeline R changes are #286 / #299 / #305 (MAD and discharge fill, inert for `default` on a `cw` group). fresh 0.34–0.39 NEWS lists nothing else that touches the `cw` classification.
- `fwapg_sha` "unrelated fwapg commits". `e6e1eb0..f9718cb` is SSNbler / PCIC / main-flow work and loader drafts. `log_input` fingerprints confirm the FWA data did not reload.
- The parity table matches `verify.txt`. "`working_dunc` kept like the others": `working_kotl`, `working_larl` and `working_sloc` exist.
