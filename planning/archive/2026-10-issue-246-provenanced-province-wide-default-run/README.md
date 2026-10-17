## Outcome

`fresh_default` now holds one provenanced `default` build of all 241 watershed groups `default` can model (run_uid `20261017_004619-3f4c713b`, m1 plus three cloud hosts), so threshold calibration can be scored wherever a species occurs (#346 part 1). Both provenance verifiers pass at 241: one config_hash, one fwapg / bcfishobs / bcfp pin, every group's newest log row from this run. `bcfishpass` parity at the same code passes 48/50 on ADMS, BULK, BABL and ELKR. `fresh` is unchanged.

The run did not go cleanly, and the record keeps that.
- The driver's completeness check reads log text. It missed 18 finished groups whose `done` marker an R warning had pushed mid-line, and was about to burn the hosts holding their only copy (#347). The operator paused the driver with `kill -STOP`, which auto mode refused to do. The 18 were consolidated by hand and the driver resumed.
- KITR and UPET failed on two bugs, both fixed in `a17e9177` and re-run under the same run_uid. Had they stayed missing, the coverage gate would have skipped the recompute for every group (#348).
- Code-check found that the UPET fix still left RB with no mapping codes (`91a968ab`).
- Code-check also found that the run had silently replaced builds an earlier decision had kept: the August KOTL / LARL / SLOC and the 2026-10-12 DUNC builds. Their old copies survive in a machine-local dump. The operator confirmed no floodplains item needs them restored.

Learned:
- Count completion from the database, never from logs.
- One run_uid can legitimately span more than one link SHA when a run is repaired. Say so in the record rather than hide it.
- Prose numbers drift when copied from a printed value rather than re-derived: three review rounds were spent on that.

## Measurement

| what | measured | planned / believed |
|---|---|---|
| modelling per host | job1 171, job2 207, job3 277, m1 ~225 min | ~4.7 h each; equal packing put the slowest cloud host 52 min after m1 |
| recompute, 241 groups, `-j4` | 154 min; per group median 2.0, quartiles 1.1 / 3.2, longest 16.2 min | ~1 h, from FINA's single-group ~10 s (#205) |
| wall clock | 8 h 48 m, with ~30 min of pause and recovery | ~6 h |
| cloud hosts | 3 × ~6 h ≈ $4.50 | ~$3 |
| `fresh_default` | 7.3 → 31 GB (14 tables + 17 indexes), 11.39 M segments | ~21 GB of persist growth; a first figure of 48 GB double-counted indexes |
| database | 221 → 275 GB; volume grown to 600 GiB, 253 G free after | 26 G free before, so the resize was required |
| parity | accessible 17/17 within 1 %; habitat 31/33 within 5 %; BULK SK over (parked); 5 rows UNEXPLAINED at the taxonomy's 2 % | — |

Wrong turns kept in `findings.md`:
- A 0.68 min recompute median that was the driver's prior-run default, not a measurement.
- A bcfishpass precedence claim in a code comment.
- "UPET RB is accessible, the NA flag is fine", which round 6 disproved.
- "The dump is the pre-run schema", which round 7 disproved.

The durable version is `research/study_area_run.md`, "The province-wide `default` run".

## Evidence

- `data-raw/logs/provincial_246/`: wrapper logs, verifiers (`run_verify*`, `verify_extra.sql`), parity (`parity*`), the UPET recompute (`recompute_upet_*`).
- `data-raw/logs/study_area_run/20261017_004619_*`: the main run, including `_consolidate_recover18.log` and `_run_local_rerun2.log`.
- `data-raw/logs/study_area_run/20261017_093603_*`: the parity run.
- `data-raw/logs/study_area_run/20261016_215933_*`: the pilot.

Closed by: PR for #246 (follow-ups #347, #348; #276 and #346 bodies updated)
