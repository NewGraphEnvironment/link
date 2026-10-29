# Plan review (#394), Plan agent, delivered 2026-10-29 ~03:12 UTC

Condensed from the reviewer's reply, with the disposition of each finding.

| # | Category | Finding | Disposition |
|---|---|---|---|
| 1 | Blocker | A live session writes `fresh_default` (a habitat-gate `UPDATE ... streams_habitat_st`, `zz_lnk_access_prior_setn` from a recompute). measure.R through `lnk_access()` drops and recreates `zz_lnk_streams_<aoi>`, the live recompute's name. | Round stopped at 03:12. measure.R now calls `lnk_pipeline_access()` with its own `zz394_streams_<aoi>`, drops its tables on exit, and sets `lock_timeout`. My killed CHWK run left an orphan backend and `zz_lnk_streams_chwk`; the orphan finished on its own (`pg_terminate_backend` was refused by the auto-mode classifier) and I dropped the table. |
| 2 | Gap | Install fresh 0.47.0 into a private library, not the site library. | Done before the review arrived (`lib047`). |
| 3 | Gap | Busy check counts only active backends, at the start only. | Each walk now records the other backends at its end; each row records `other_backends_max`. Rows are taken `--allow-busy` because the other client is continuous. |
| 4 | Gap | Inputs can drift between variants run days apart. | Each row records `n_tup_ins + n_tup_upd + n_tup_del` for `barriers`, `barrier_overrides` and `streams` at start and end; the variants of a group run back to back. |
| 5 | Gap | One run per variant, cold cache first. | A-B-C-C-B-A per group. |
| 6 | Gap | Scratch model underspecified: working schema collides with live runs; a reused persist schema lets run 2 see run 1's barriers; pick groups that exercise the paths. | `model_digest.R`: own persist schema per variant (`zz394_<variant>`), own working schemas, `log = FALSE`, and counts of `dam_dnstr_ind`, `remediated_dnstr_ind` and access codes per group. ADMS (SK, CH, CO) and ELKR (BT, WCT, Elko Dam). |
| 7 | Acceptance | Lever 1 is verified live only through `lnk_access()`; the model-time role mix (remediations, observations, crossings) only by mocks. | The scratch model is built at the lever-1 commit too (`b047`), and must digest equal to `m047`. |
| 8 | Gap | Lever 2's key must be NULL-safe: `||` drops a row, `concat_ws` collides. 153 `fresh_default.barriers` rows have NULL `localcode_ltree`. | Key over record text `row(...)::text`; a restored-bug test with a NULL localcode. |
| 9 | Assumption | `watershed_group_code` must be in the key and its order (natural ids repeat across groups). | In the key; order is the record text, total. |
| 10 | Assumption | An empty `wscode_ltree` would be admitted by `<@ ''` but missed by `generate_series(1, nlevel)`. None exist. | Key subpaths start at length 0, so the empty code is included. |
| 11 | Assumption | Dedup uses one key snapshot for several walks; under concurrent writes species B inherits A's walk. | Documented: the same readiness invariant #374 relies on (nothing a group's walks read changes while it is recomputed). Without dedup each species already reads its own snapshot. |
| 12 | Acceptance | Lever 2 needs a net-gain criterion; pin the 10 % gate. | Gate: repeated walks' seconds summed over the four groups at `exists`, over all walk seconds there, at least 10 %. Keep only if, per group, `dedup` walks plus key time are below `exists` walks. |
| 13 | Wording | `dams` is read in full, not its first element. | Plan wording corrected. |
| 14 | Stale doc | `@return` says `conn` invisibly; the function returns a tibble. | Fixed in Phase 2's follow-up. |
| 15 | Note | `names(df)[2]` renames `has_features` to `barriers_<sp>_dnstr`. | Harmless (only the id column is read); left as is. |
| 16 | fresh 0.45 tie order | `anth[1]` could move where anthropogenic features are co-located; 0 such ties in `fresh_default.barriers`. | Digests cover it. |
| 17 | Scope | `lnk_access()`'s `zz_lnk_streams_<aoi>` duplicates fresh's per-walk temp table since 0.45. | Out of scope; noted as a follow-up. |
