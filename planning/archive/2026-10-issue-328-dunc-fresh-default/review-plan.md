# Plan review — #328 (Plan agent, 2026-10-12, after the run finished; SELECTs only)

- **Blocker:** none.
- **Gap 1:** `fwapg_sha` is the HEAD of the local fwapg checkout (R/lnk_log.R:1197-1201, 1244-1255), not an FWA data version. It moved `e6e1eb0f` (KOTL/LARL/SLOC) → `f9718cb7` (DUNC) on unrelated commits. `log_input`'s `fwa_stream_networks_sp` fingerprint is identical for KOTL and DUNC (4,907,804 rows, 10,287,677,440 bytes). → compare `log_input` and say so in the issue.
- **Gap 2:** `lnk_rollup_wsg()` defaults to `schema = "fresh"`; pass `fresh_default`. Present default vs bcfp as context, not parity.
- **Gap 3:** cite the "Also observed" explanation (findings.md).
- **Acceptance 1:** order >= 2 km equals raw FWA (3,493 km), so the km check only shows length conserved. Add non-zero flag checks (BT 2,918 spawning / 4,528 rearing / 9,887 accessible segments).
- **Acceptance 2:** check `link_sha` against `8215d2d0` explicitly, not HEAD.
- **No LNK_SCHEMA leakage:** every persist/log path resolves through `.lnk_table_names(cfg)`; `fresh.barriers` DUNC 49,386 vs `fresh_default` 49,106, so `fresh` untouched.
- **Recompute:** not needed (access walks downstream; observations filtered to the run's group).
- **Assumption:** DUNC's access reads KOTL/LARL's persisted barriers and overrides built at link 0.45.1 (LARL dirty). The guard checks dams only. DUNC's access is mixed-vintage although its rules are current. `wsg_upstream` lists all 55 persisted groups, not dependencies.
- **Ordering:** `working_dunc` left by `cleanup_working = FALSE` (≈80 other `working_*` exist); decide and record. Copy the run log out of the scratchpad.

## Disposition

All folded in: verify.R gains the log_input comparison, raw-FWA km, non-zero flag counts and an explicit link_sha; parity labelled context; mixed-vintage barriers in README + issue; `working_dunc` kept, consistent with the other groups' working schemas.
