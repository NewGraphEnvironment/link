# Code-check round 1 — #305 staged diff

Reviewer: subagent, 2026-10-06. Read-only; probes run against local fwapg in read-only
transactions (`SET default_transaction_read_only = on`).

## Verified (no finding)

- `fwa_stream_networks_discharge.mad_m3s` is `double precision` and `linear_feature_id` has a
  unique index, so `.lnk_discharge_join()` with the fill off writes the same type and values
  `frs_col_join()` did. The scope is `watershed_group_code IN aoi`, and the working table holds
  only the aoi, so nothing is lost there either.
- `.lnk_discharge_sql(w, fill = TRUE)` parses and runs: ADMS 0.5 s (1 `fill_upstream`), UBTN
  56 s (496 `fill_tributary_max`), MMUS 29 s, LSIK 0.5 s.
- The 4-arg `fwa_upstream(a, b)` argument order is right: it is TRUE when b is upstream of a.
- The log column is added via `ADD COLUMN IF NOT EXISTS`, and the INSERT's column and value
  order agree.
- `built.csv` round-trips logical to `"TRUE"`/`"FALSE"`, and the score's `%in% "TRUE"`
  handles both.

## Findings

- **[bug] data-raw/discharge_fill_count.R:250-258 (`reach.csv`)**: `stats::aggregate()` drops
  rows whose grouping value is NA. `gap_class` is NA for every `fill_tributary_max` line,
  because `nul$gap` is NA unless the tier is upstream or downstream, and only `tier == "none"`
  is reset to `""`. So every tributary-tier line is silently missing from `reach.csv`.
  - The committed log shows it. It has no `fill_tributary_max` row at all, while UBTN alone
    has 496 tributary-filled lines.
  - The absent rows sum to 3,412 km of the 4,152 km the research cites, and row_null to
    2,085 of 2,091 km. About 746 km is missing from a published measurement.
  - The research line "the rest through the tributary tier" is therefore inferred from the
    difference, not counted.
  - Fix: `nul$gap_class[is.na(nul$gap_class)] <- ""`, or set it for the tributary tier, then
    re-run.
  - This is the `code-check-r.md` rule "`stats::aggregate()` has three separate silent
    behaviours".

- **[fragile] R/lnk_habitat_validate.R:447-448 (`.lnk_hv_discharge_src`)**: the fill is
  materialised whenever `cfg` fills, even when no aoi group is on `mad`. That is the normal
  case for `default_tuned` today: every group is `cw` and `discharge_fill: true`. Two effects:
  - A cw-only validation now reads the discharge table. That contradicts the stated
    constraint at `.lnk_hv_obs()` ("a cw-only run should not depend on the discharge table"),
    and the existence guard `.lnk_hv_check_mad()` runs only when a group is `mad`. A cw-only
    run against a DB without the table now fails with a raw "relation does not exist" where
    it used to pass.
  - Each such call pays the full fill, up to about 56 s for UBTN, for a value that is then
    NA'd out. The scoring harness calls the validator per variant × buffer, plus the
    absences call, so the cost multiplies.
  - Fix: add `|| !any(models == "mad")` to the early return. Pass `models`, or restrict
    `aoi` to the mad groups for the `lines` scope.
