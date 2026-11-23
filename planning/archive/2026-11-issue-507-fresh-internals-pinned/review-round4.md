## Checklist read
- code-check.md "A guard that fails toward pass" (index line); code-check-r.md index headings only, none applicable.

## Clean
No issues found. Non-function or primitive at an internal's name now yields a "have: not a closure" row; it reaches the `ok` fold and message through `length(mismatched_internal_formals)`, unchanged. Absent internals still `next` before `get()` and report only via missing_internal; the absent-fresh branch is untouched. All four pinned internals (.frs_run_connectivity, .frs_habitat_models, .frs_near_river_specs, .frs_sql_num) are plain closures in fresh 0.56.0 (frs_habitat.R:1242, utils.R:1904, frs_habitat_predicates.R:383, utils.R:183). Test not run; read only.
