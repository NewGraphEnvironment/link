# Review — #299 phase 1, round 1

## Clean
No issues found.

What was checked:
- fresh floor: `.frs_habitat_models(wsg_codes, params_method)` was introduced in fresh c56961c (#220) and is byte-identical at tag v0.35.0 (R/utils.R:875) and in the installed 0.36.2, so the DESCRIPTION floor (>= 0.35.0) has it with the same signature and argument order the wrapper uses.
- Classify behaviour for valid inputs: `aoi` is validated as a single non-empty string, so the old `params_method$model[match(aoi, ...)]` returned the model or NA, and the new resolver returns the model or "cw"; `identical(x, "mad")` is TRUE for exactly the same inputs. The resolver's new stops (bad model, duplicate code, missing columns) fire only on tables `fresh::frs_habitat_classify(params_method = ...)` already rejects earlier in the same function via the same helper, so no previously-succeeding run now fails. `unname()` keeps `identical()` from failing on the names attribute.
- "NA" group code: `.lnk_habitat_method_read` keeps `na.strings = character(0)`, so "NA" stays a string; fresh's `incomparables = NA` only excludes real NA, so "NA" resolves (test confirms).
- Preflight: `lnk_preflight_fresh()` already vapply()s `exists` over `required_internal`, so the length-2 vector is handled; the stopifnot has no length-1 constraint on it.
- Tests run (NOT_CRAN=true, load_all): test-lnk_config 158 pass, test-lnk_preflight_fresh 39, test-lnk_pipeline_classify 35, test-dictionaries 99, test-lnk_pipeline_connect 10, test-lnk_log 279, test-lnk_pipeline_run 22 — 0 fail, 0 skip.

Non-blocking note (not a defect in the diff): planning/active/findings.md:44 cites `R/lnk_pipeline_classify.R:167`; the diff removes two lines above it, so the call now sits at :165.
