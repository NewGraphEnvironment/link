## Outcome

Backlog move 13 (#481) landed as link 0.87.0: fresh pinned at v0.55.1 (floor 0.55.1, was 0.52.0). #452: `streams_near_river` carries `linear_feature_id`, fresh 0.54.0's key. `lnk_persist_init()` adds the column to an old table once and fills it from `streams` in one transaction. When cfg reads a pair, the validator passes `near_river_lfid = TRUE` after refusing a missing column or a NULL. #288: `lnk_db_conn()` delegates to `fresh::frs_db_conn()`, the owner's choice. A fully explicit call unsets `PG_*_SHARE` for its duration, so fresh neither prints its deprecation notice nor uses it up. #222: the live closure tests use the connection their gate found. The owner decided #288 and #452 at the resume. The parked plan's Phase 5 gate keyed on `public.wsg_outlet`, a table retired in fresh 0.33.0, and was corrected to `whse_basemapping.fwa_downstream()`.

The resume found m1's fwapg unreachable: the colima VM's guest network had died about 2026-11-21 20:46 PDT. A restart, on the owner's word, brought it back. m1's shared library also held fresh 0.53.0, not the pinned 0.52.0, so both arms of the proof ran from scratch libraries. `/code-check branch` took three rounds. Round 1 found three issues, each a stand-in taken for its property:
- the validator's key check ran whenever the table existed, not when a rule read it;
- muffling fresh's message still spent its once-per-session flag;
- a top-level `on.exit()` never fired.

All three were fixed and proven by restoring each defect. Rounds 2 and 3 were clean.

## Measurement

ADMS and BULK under `default` and ADMS under `bcfishpass` were built at main (`be06e2b4`) on fresh 0.52.0 and at this branch (`f40c1d49`) on fresh 0.55.1. Their 36 table-group digests are identical over every column but the new one, and the output tokens did not move.
- The new column equals `streams.linear_feature_id` on all 7,295 near-river rows (ADMS 2,896, BULK 4,399).
- Migrating a 0.52.0 copy fills every row with what fresh 0.55.1 wrote.
- `lnk_habitat_validate()` on ADMS gives identical results with `near_river_lfid` TRUE and FALSE: 94 observations, 27 of them on near-river segments.
- Build minutes did not move beyond noise: ADMS 2.73 then 2.13, BULK 8.60 then 7.97, ADMS bcfishpass 1.68 then 3.12.
- The pre-run gate's call graph reaches 19 fresh files at v0.55.1. `frs_db_conn.R` joined it and moved from `none` to `any`.
- Phase 5: with `PGHOST` unreachable inside R, main's closure tests error twice and the branch's pass all 25.

The first attempt at this read nothing: an exported `PGHOST` loses to `~/.Renviron` on m1.

## Evidence

`data-raw/logs/fresh_pin_481/` (its README indexes it).

## Owed

- Install fresh 0.55.1 into each host's shared library (`pak` from the pin), and re-prep every host (`--auto-install` at the next launch; m1's worker).
- Under Open decision 2 (a): migrate `streams_near_river` in `fresh_default`, `fresh` and `fresh_default_minimal` on each host, once, at a quiet time.
- The pre-run gate runs again before the next provincial run (`R/`, the fresh pin and `pretest_inputs.csv` changed).
- The variants harness's bases (`score*` schemas, `data-raw/logs/habitat_score_284/` digests) are rebuilt with `--step=base` before the next variants run.

Closed by: the PR for branch `481-backlog-move-13-the-next-fresh-pin` (release 0.87.0).
