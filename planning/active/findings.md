# Findings — Weekly CSV sync skips four copied bcfishpass files; Keogh and Adams dam fixes missing (#429)

## Issue context

**If done:** every bundle file copied from bcfishpass is checked by the weekly sync, and the Keogh and Adams dam passability fixes reach both bundles. **If never:** four copied files drift silently, and a dam fixed upstream stays a barrier in link, which moves `bcfishpass` parity for reasons nobody sees.

## Problem

`data-raw/sync_bcfishpass_csvs.R` checks 7 files against `s3://fresh-bc/bcfishpass/csvs/` (the dump of bcfishpass's ng-prod build, `v0.7.15-51-g3bd2824` at 2026-10-28). It selects files whose provenance `source` is `https://github.com/smnorris/bcfishpass`, so files declared otherwise are never compared. Compared byte for byte on 2026-10-31 against the same dump:

| File | Bundles | Differs by |
|---|---|---|
| `cabd_passability_status_updates.csv` | `bcfishpass`, `default` | 2 rows dated 2026-09-29: the Keogh River and Adams dams set passable (`smnorris/bcfishpass@620dbe4`, `a0c1a36c`) |
| `wsg_species_presence.csv` | `bcfishpass` | 2 cells: UTRE CH and QUES ST present upstream, absent here (the bundle also carries its own `ko` column) |
| `wcrp_watersheds.csv` | `bcfishpass`, `default` | 6 lines (BONP, SHUL, …) |
| `cabd_blkey_xref.csv` | `bcfishpass` | trailing newline only (#347, ours) |

`observation_exclusions.csv` is also outside the sync and matches upstream today. The dry run reports "no drift" while these differ.

## Proposed

- Bring the four files under the sync, with provenance `source` set so the selector finds them. Two of them carry link-side edits (the presence table's `ko` column, `cabd_blkey_xref.csv`'s newline), so either the sync learns to compare them modulo those edits, or the edits move out of the copied file.
- Pull the two passability rows and the two presence cells now, in the same PR.
- `observation_exclusions.csv`: decide whether it is a synced copy.

## Acceptance

- The dry run reports drift on any copied bundle file that differs from the dump.
- `bcfishpass` parity re-checked where the Keogh and Adams dams sit (Adams in ADMS; Keogh on northern Vancouver Island), since `.lnk_crossings_union()` reads the updated passability code (CLAUDE.md, 2026-10-23 status).


## Measured at plan time (2026-10-31)

- Every CSV in `bcfishpass` and `default` `overrides/` compared byte for byte with `s3://fresh-bc/bcfishpass/csvs/` (dump `v0.7.15-51-g3bd2824`, completed 2026-10-28T04:44:44Z). Differ: `cabd_blkey_xref` (both bundles; our trailing newline, #347), `cabd_passability_status_updates` (both; 2 rows), `wcrp_watersheds` (both; BONP, SHUL, USHU), `wsg_species_presence` (both). Same, but outside the sync: `cabd_additions`, `cabd_exclusions`, `dfo_known_sockeye_lakes`, `observation_exclusions`, plus the 7 already-synced files. `user_modelled_crossing_fixes_20240825.csv` is not in the dump (403) and has no reader.
- Presence, cell level with `ko` set aside: bcfishpass bundle differs at UTRE CH and QUES ST; default at those two and LARL GR (`322389a3`, deliberate). Default's UTRE CH and QUES ST are already rows in #402's tracker (`absent_recorded`).
- Presence cells are in the `acc` token spec (`R/lnk_vocabulary.R`), so a presence change needs a new `acc` row; the passability and wcrp rows are vintage (no token).
- All package readers take presence from `loaded$wsg_species_presence`; only `data-raw/audit_configs.R`, `data-raw/regen_provenance.R` and `data-raw/wsg_species_presence_check.R` name the file.
- `wcrp_watersheds.csv` and `dfo_known_sockeye_lakes.csv` are not in either bundle's `files:`; `wcrp_watersheds.csv` has no R reader.
- The sync writes each changed file into both bundles unconditionally, and a failed fetch prints WARNING and skips (reads clean).
- `cabd_blkey_xref.csv` has 3 lines, so base `read.csv()`'s header read hits the incomplete final line (the warning #347 removed by adding a newline). Other synced copies also lack a final newline but are long enough not to warn.

## The dam rows

- Neither `298b0f7e-41d5-479a-95d7-af685224cf3f` (Keogh) nor `1c16395b-0411-4bad-bfc2-3445b1e94bcc` (Adams) is in `cabd.dams` in local fwapg (2,592 rows) or in the reference DB (bcfishpass `v0.7.15-51-g3bd2824c`, completed 2026-10-27 20:47).
- Keogh Dam in CABD is `242fa0e4-82ff-4ff6-9fa1-a2d892d4b41f`, passability 1, and `bcfishpass.crossings` holds it as `BARRIER` in NIMP.
- CABD API: `298b0f7e` unknown; `1c16395b` is a dam, passability 6 ("NA - Decommissioned/ Removed"), last modified 2026-10-02.
- So the two update rows match no dam in either build: pulling them moves no crossing and no parity.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `PG_*_SHARE` not in the Bash tool's shell | Query the reference DB through `lnk_db_conn()` in Rscript |
