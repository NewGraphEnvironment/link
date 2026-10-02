# Progress — Thread fresh params_method (per-WSG cw/mad) through lnk_pipeline_classify (#286)

## Session 2026-10-01

- Plan-mode exploration — phases approved by user (method CSV per bundle; mad_m3s working-only; provenance via config_hash only)
- Created branch `286-thread-fresh-params-method-per-wsg-cw-ma` off main
- Scaffolded PWF baseline from issue #286 with approved phases
- Next: start Phase 1
- Phase 1: fresh pin -> v0.36.2 (floor 0.35.0); `lnk_preflight_fresh(required_formals=)` asserts `frs_habitat_classify(params_method)`; vignette script off `frs_db_conn()` (fresh 0.36.0 precedence flip). Code-check round 1 clean; it flagged stale text (validator/test comments citing v0.33.0, CLAUDE.md `frs_db_conn` line, a skip message), fixed in the same commit
- Phase 2: method CSV in the four base bundles (frozen, not csv-synced: B1 from the plan review and code-check round 2, found by both independently), resolver + config_hash fallback, dictionary + tests, discharge in `log_input` primitives, stale `*_mad_*` docs fixed, verify-clean loop over every bundle. Code-check rounds 2 (B1) and 3 (clean)
- Phase 3: `mad_m3s` joined onto working streams; `lnk_pipeline_classify(method_csv=)` passes `params_method`; the stream-order rearing bypass is skipped for a `mad` AOI (G3); tests for capture, fallback, override, the `NA` code, the bypass pair, the join args and the persist shape
- Phase 4: live on local fwapg, scratch schemas `zz286_*`, config `default`. ADMS and BULK `streams_habitat` digests identical across branch / main+fresh 0.36.2 / main+fresh 0.33.0 (and ADMS without the `mad_m3s` column). mad on ADMS: invariants hold, BT/RB lose all stream habitat and keep waterbody-rule rearing. mad on BULK (no discharge): 0 km stream habitat for every species, no error. Evidence `data-raw/logs/params_method_286/`
- Phase 5: RUNBOOK §7 "Channel width or discharge, per watershed group" (incl. cypher re-prep), CLAUDE.md pointer; follow-up issue body drafted in findings, not filed
