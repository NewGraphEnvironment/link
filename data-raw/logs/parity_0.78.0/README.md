# bcfishpass parity at v0.78.0 (#440)

The 17-group closure of ADMS, BULK, BABL and ELKR, rebuilt under the `bcfishpass` config into scratch
`fresh_parity441` on m1 and compared with the v0.68.0 build (`../parity_0.68.0/`, schema `fresh_parity361`). The
write-up is `research/bcfishpass_parity.md`.

## Stamp

| | |
|---|---|
| run_uid | `20261102_083253-52f261f8` (label `parity-4-bcfishpass-441`), dispatcher only, from a worktree at `34c4c598` |
| model leg | 2026-11-02 08:32 UTC → recompute `-j8` → done 09:22, critical path 50.0 min (`run.log`; the driver's own files are `../study_area_run/20261102_083253_*`) |
| link | 0.78.0, `34c4c598` (PR #443's head) |
| fresh | 0.52.0, `245c8d8d`, installed on m1 by `remotes::install_github()` (m1's GitHub token is refused, so pak could not) |
| primitives | m1's 2026-10-23 load, the one `fresh_parity361` was built on; `--preflight-note` recorded it |
| bcfp reference | m1's `fresh.streams_vw_bcfp`, pinned at `v0.7.15-51-g3bd2824` (`run.log`); `fresh_parity361` was scored at `-50-g620dbe4`. No scored value moved. |
| gate | `--pretest-note`: the gate for this code runs on `default_minimal` before the provincial run |

## Result

**48/50, PASS, as at v0.68.0** (`parity_crosssection.log`, `parity_annotated.csv`). `run_verify.log`: PASS. The
reference moved on 0 of 50 pairs and no barrier override was added or lost (`override_diff.csv`), so every move in
`pair_moves.csv` is code; what moved is in the write-up. `expected.txt` was committed before scoring, and three of its
four bounds were wrong: accessible and spawning moved more than it allowed, and BULK CO rearing moved away from the reference.

## Files

| file | what it is |
|---|---|
| `expected.txt` | expected moves, written before scoring |
| `run.log`, `run_verify.log` | the driver's stdout (addresses redacted) and `study_area_verify.sql` |
| `parity_crosssection.log`, `parity_annotated.csv` | the score |
| `moves.R`, `moves.log` | the comparison with v0.68.0, adapted from `../parity_0.68.0/moves.R`; the line list became a temp table, because #326 re-breaks 17,527 lines and a `VALUES` list overflowed Postgres's stack. Columns and labels say `old` (`fresh_parity361`) and `new` (`fresh_parity441`). |
| `pair_moves.csv` | every scored pair, before and after, with the reference's change |
| `segment_diff.csv`, `resegmented.csv.gz`, `resegmented_*.csv` | segments both builds share whose habitat changed; segments in one build only (gzipped) |
| `override_diff.csv` | barrier-override positions added or lost (none) |
| `mapping_code_moves.csv` | the driver's mapping-code compare, before and after |
