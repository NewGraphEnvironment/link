## Outcome

Backlog move 6 (#474) landed as one PR and release (link 0.81.0) closing eleven issues across two batches. What a run stamps and checks before launch: `bcfishobs_sha` retired for the observations' loaded version in `log_input` (#451); one rule for the bcfishpass reference build, carrying its completion time in `log.bcfp_date_completed` (#446, #266); RUNBOOK says a build is the `log` rows of one `run_uid` (#458); the pre-run gate held to an ancestor found through `extends:`, or to every input, with minutes from a committed `data-raw/logs/build_minutes.csv` (#450); `update_hosts.sh` installing the DESCRIPTION-pinned fresh (#269). How primitives load: `snapshot_bcfp.sh` retries, row checks and WFS/pyarrow fallbacks (#484, #459); a skip guard on the upstream build's date and a cross-host compare of loaded primitives before any write (#276); the vintage gate judging object tables by live ETag (#273); a wrapper that records what fwapg's `load.sh` fetched (#270, not yet run against a real load). What was learned beyond the plan: flooded no longer reads `bcfishpass.log`, so #266 reduced to link's own rule; nothing clears `log_recompute` either, so #458's asymmetry was #454's hand-seeded log; DataBC's GeoServer pages only on a sort; a WFS-fallback table equals bc2pg's by value but not by content md5; RPostgres sets the session zone to UTC. Mechanics are in RUNBOOK §6b, §6c and §8d; the durable facts in CLAUDE.md's 2026-11-13 status.

## Measurement

- **Gate without history** (m1, 2026-11-12): `default` against an empty schema picked on every input, the same 11 groups (SETN, BULK, QUES, LFRA, TOAD, HARR, UPCE, OKAN, TAKL, HORS, SAJR) as #454's gate from a hand-seeded 242-row log; `default_minimal` found `default`'s 241 builds in `fresh_default` with no flags. The first ancestor pick chose a 2-group test schema over 241 groups (an `integer64` count ordered on raw bits), fixed.
- **Fallbacks** (m1): the WFS needs a sort to page (HTTP 400 otherwise); normalised, all four PSCIS views match bc2pg's columns, and on 2026-11-13 the assessment view matched a same-day bc2pg load in every row by value, but not by content md5 (decimal spelling); an attempt to match the spelling fixed measurements and not ids, and was reverted. The pyarrow fallback first differed in 352,766 rows (`distance_to_stream`'s last digits: GDAL writes 15 significant digits), then 0 once it did the same.
- **Proof reload** (m1, 2026-11-13, 7 min): PSCIS on attempt 1 with exact counts; ledger row `v0.7.15-51-g3bd2824` built 2026-11-11, the same version as m1's 2026-11-02 row (built 2026-10-28), which the old version-only guard would have skipped; vintage judged the two object tables by ETag; m1 against m4 now refuses on the modelled crossings (`1794344402364` against `1793134826715`).
- **Checks:** `devtools::test()` 5,639 pass, 2 fail and `R CMD check` 3 fail, all on the bcfp reference tunnel being down; `/code-check branch` three rounds, 10 findings fixed (two inside round 1's fix), ended on round 3's enumeration of ~60 places.

## Evidence

`data-raw/logs/gate_history_450/`, `data-raw/logs/snapshot_fallbacks_459/` (its README indexes the reload log and the m1/m4 input rows).

## Owed

- Re-snapshot every host's primitives before the next provincial run (already owed from #465).
- The pre-run gate runs again: `R/`, `data-raw/pretest_*` and `study_area_run.sh` changed.
- #270's wrapper on the next real FWA reload.
- Rotate the worker host's GitHub token (#269's residue from #439).
- Append the next provincial run to `build_minutes.csv`.

Closed by: commit 02027b1d (Release v0.81.0) / PR (to be opened by /gh-pr-push)
