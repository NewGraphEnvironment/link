# The fresh pin from 0.52.0 to 0.55.1 (#481)

**Verified:** 2026-11-23 · **Issues:** #481 (#452, #288, #222) · **Produced by:** `run.sh`, `digest.R`, `compare.R`, `verify.R` in this directory

## What was asked

Does moving link's fresh pin from v0.52.0 to v0.55.1, with the persisted near-river table gaining fresh 0.54.0's `linear_feature_id`, change any persisted output? And does the stored column hold what fresh wrote, both on a new build and on a table migrated from an old one?

## Answer

No output moves but the new column. ADMS and BULK under `default` and ADMS under `bcfishpass`, each built once at link `be06e2b4` (main, link 0.86.0) on fresh 0.52.0 and once at this branch (`f40c1d49`) on fresh 0.55.1, digest identical in every persisted table and group, 36 table-group pairs (`compare.csv`), over every column but the new one. Every other table is identical over all its columns, and the output tokens did not move (`cut-full-top-2 acc-v6 grad-seg q-fwapg` on both).

- **The column** (`verify.txt`, 1): every one of the 2,896 ADMS and 4,399 BULK near-river rows of the after-build carries its streams row's `linear_feature_id`, none NULL.
- **The migration** (2): `lnk_persist_init()` on a copy of the 0.52.0 build's `streams` and `streams_near_river` (no column) filled all 7,295 rows with exactly what fresh 0.55.1 wrote.
- **The validator** (3): on the after-build, ADMS, CH, CO and BT, `lnk_habitat_validate()` gives identical results with the near-river predicate keyed on the parent line (`near_river_lfid = TRUE`, what it passes) and without it, over 94 observations, 27 on near-river segments. Both runs went through the predicate builder with the table.

## How

`run.sh <before|after> <link tree> <R library> <fresh sha>` builds the three groups into scratch schemas (`fresh_pin481_<step>`, `fresh_pin481_bcfp_<step>`) on m1's local fwapg, by `wsg_run_one.R` under `load_all`, after five quiet minutes on the database. fresh comes from a scratch library holding it alone (`R CMD INSTALL -l` from a worktree of each tag), so the shared library, which held fresh 0.53.0, was never touched; `FRESH_GIT_SHA` carries the tag's commit into the stamps, since such an install writes no `RemoteSha`. The downstream guard was off with a note, the same in both steps. `digest.R` digests every base table but the logs per group, each row as its columns in name order, once over every column and once without the new one; `compare.R` stops on any difference. The four scratch schemas were dropped after.

Minutes (`builds.csv`; the host's load average was 6 to 10 throughout): ADMS 2.73 then 2.13, BULK 8.60 then 7.97, ADMS under `bcfishpass` 1.68 then 3.12. No pattern; one run each.

`reach.md` is the pre-run gate's call graph at fresh v0.55.1: 19 fresh files, `frs_db_conn.R` new among them now that `lnk_db_conn()` delegates to it (#288).

## Along the way

- m1's fwapg had been unreachable since about 2026-11-21 20:46 PDT: the colima VM ran but its guest network was gone. Restarted (`colima stop && colima start`) on the operator's word, 2026-11-23 01:30 UTC.
- The Phase 5 proof (#222): with `PGHOST` pointed at an unreachable host from inside R, main's closure tests error twice and the branch's pass all 25. An exported `PGHOST` did not reach R on m1, because `~/.Renviron` sets it and wins; the first attempt at the proof read nothing for that reason.
