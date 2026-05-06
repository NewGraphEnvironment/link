# Progress — lnk_pipeline_access: compute dam_dnstr_ind / remediated_dnstr_ind from primitives (#135)

## Session 2026-05-05 (evening)

- Filed as #135 follow-up to #124 (link 0.30.0).
- Plan-mode exploration:
  - Confirmed `barriers_<source>_id` columns are in shared ID space (all populated from `crossings.aggregated_crossings_id`) — `frs_network_features` already returns arrays in compatible IDs across sources.
  - Diagnosed `remediated_dnstr_ind` regression in [smnorris/bcfishpass#690](https://github.com/smnorris/bcfishpass/pull/690) (2025-09-24, "db v070" refactor). Contradictory `AND` clause where `IN` was intended.
  - Verified via DB: 4.2M rows in `bcfishpass.streams_access` have `remediated_dnstr_ind = FALSE`.
  - Confirmed `NewGraphEnvironment/bcfishpass` is our fork — can patch independently.
- Plan approved by user: compute both indicators correctly in link, file upstream PR to our fork.
- Created branch `135-lnk-pipeline-access-compute-dam-dnstr-in` off main.
- Scaffolded PWF baseline.
- Next: start Phase 1 (`R/lnk_pipeline_access.R` edits).
