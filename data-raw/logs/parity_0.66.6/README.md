# bcfishpass parity at v0.66.6 (#362)

The 17-group closure of ADMS, BULK, BABL and ELKR, rebuilt under the `bcfishpass` config into
scratch `fresh_parity362` and scored against the same reference as the 2026-10-17 baseline
(`../provincial_246/`, schema `fresh_parity246`). The write-up is `research/bcfishpass_parity.md`.

## Stamp

| | |
|---|---|
| run_uid | `20261020_171738-477072be` (label `parity-4-bcfishpass-362`), dispatcher only |
| model leg | 2026-10-20 17:17:47 → 18:10:08 UTC; recompute `-j8`; run exit 0 at 18:15 UTC |
| link | 0.66.6, `6e5cc837`, `link_dirty` f on all 17 rows |
| fresh | 0.39.0, `e247ca19` (same as baseline) |
| fwapg checkout | `6d48dabf` (baseline `f9718cb7`: an `FWA_WatershedAtMeasure` migration and pcic, which link does not call; the FWA data is the same load) |
| bcfishobs | `08630cf4` (same); `bcfishobs.observations` loaded 2026-10-17 00:47 UTC, before both runs |
| primitives | loaded 2026-10-17 00:46 UTC, before both runs |
| bcfp reference | local `fresh.streams_vw_bcfp`, loaded 2026-10-17 00:55 UTC from bcfishpass `v0.7.15-50-g620dbe4`, model_run_id 143, completed 2026-10-14 03:00 UTC (`../bcfp_baselines.csv`; the run ID from `turn_bt.txt`) |

## Files

| file | what it is |
|---|---|
| `run.log`, `run.started`, `run.exit` | the driver's stdout; its own logs are `../study_area_run/20261020_171738_*` |
| `verify.log` | `study_area_verify.sql` with `-v schema=fresh_parity362 -v expected_n=17`: PASS |
| `expected.txt` | the expected moves, written before scoring |
| `parity_crosssection.log`, `.exit`, `parity_annotated.csv` | the score: 48/50, PASS |
| `moves.R`, `moves.log` | the comparison with 2026-10-17 |
| `pair_moves.csv` | every scored pair, before and after |
| `segment_diff.csv` | segments whose access, spawning or rearing changed, by cause, km |
| `resegmented.csv` | segments in one build only: breaks at modelled crossings that moved (#277) |
| `override_diff.csv` | barrier-override positions added or lost, across all holding groups |
| `mapping_code_moves.csv` | the driver's 17-group mapping_code compare, before and after |
| `turn_bt.txt` | why TURN BT was not scored |
