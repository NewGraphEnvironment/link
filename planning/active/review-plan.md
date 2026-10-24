# Plan review — #371 (Plan agent, 2026-10-24 ~01:20 UTC)

Read-only reviewer; its reply transcribed here in summary, with what was done about each.

| id | class | finding | verified? | action |
|---|---|---|---|---|
| B1 | Blocker | helper is internal; cyphers run `library(link)` | not reproduced: `wsg_run_one.R` already called `link:::` | handler wrapped in `tryCatch` so naming can never replace the error |
| G1 | Gap | `dbWithTransaction` re-throws, SQL frames gone (`lnk_mapping_code`) | **reproduced**: `<statement not found>` while the message held `Statement: …` | helper reads `.lnk_db_execute()`'s `Statement:` first; unit + live tests |
| G2 | Gap | `run_timeouts` sed anchored at line start (#347's mistake) | yes (by reading) | unanchored; mid-line fixture |
| G3 | Gap | SHOW line printed, never checked | yes | `LNK_STATEMENT_TIMEOUT_MIN` on both legs; `wsg_run_one.R` refuses a connection whose bound (pg_settings ms) differs |
| G4 | Gap | ssh leg never executed by a test | yes | not refactored: G3's runtime check fails the first cypher group if the export is lost or mangled; noted |
| G5 | Gap | printed re-model command unbounded | yes | prints `PGOPTIONS='-c statement_timeout=<N>min'`; test |
| G6 | Gap | downstream guard's queries outside the handler | yes | guard wrapped in the same calling handler |
| G7 | Gap | writer/reader format untested together | yes | test reads `wsg_run_one.R`'s format string and feeds `run_timeouts` |
| G8 | Gap | stall hook rides the operator's env | yes | banner prints `TEST HOOK:` when set; refuse = `stop()` (documented) |
| A1 | Assumption | 30 min from whole-group minutes; cyphers up to 2.9x | yes (its table) | RUNBOOK + header: raise it when a top group is hand-placed on a cypher; cost asymmetry stated |
| A2 | Assumption | ssh leg replaces the operator's PGOPTIONS, plan said appends | yes | plan, header, comments corrected (replacing is right) |
| A3 | Assumption | a leftover role setting could mask a missed leg | checked: `pg_db_role_setting` holds only search_path | none |
| A4 | Assumption | plan says first line; helper squishes 160 chars | yes | plan text corrected |
| AC1 | Acceptance | stall hook skips the transaction path | yes | live `dbWithTransaction` test |
| AC2 | Acceptance | unset `LNK_TEST_STALL_WSG` before the re-model | yes | done (`env -u`) |
| AC3 | Acceptance | spell out criterion 2's check | yes | Owed item reworded |
| S1 | Scope | also name operator cancels (`user request`) | — | not done; out of the issue's scope |
| S2 | Scope | NEWS entry | — | at `/gh-pr-merge` |
| S3 | Scope | structural count breaks on a comment | yes | comment lines filtered in the test |
