# bcfishpass parity at v0.68.0 (#361)

The 17-group closure of ADMS, BULK, BABL and ELKR, rebuilt under the `bcfishpass` config into
scratch `fresh_parity361` and compared with the v0.66.6 build (`../parity_0.66.6/`, schema
`fresh_parity362`). The write-up is `research/bcfishpass_parity.md`.

## Stamp

| | |
|---|---|
| run_uid | `20261023_215312-16fb3aae` (label `parity-4-bcfishpass-361`), dispatcher only, built from a worktree at `1d00c04c` |
| model leg | 2026-10-23 21:53 UTC → recompute `-j8` → exit 0 (`run.log`; the driver's own files are `../study_area_run/20261023_215312_*`) |
| link | 0.68.0, `1d00c04c`, `link_dirty` f on all 17 rows (`run_verify.log`) |
| fresh | 0.42.0, `e9793047` |
| primitives | refreshed by the provincial run, 2026-10-23 07:44 UTC, so inputs are NOT held equal to the v0.66.6 build |
| bcfp reference | local `fresh.streams_vw_bcfp`, reloaded 2026-10-23 00:52 UTC from bcfishpass `v0.7.15-50-g620dbe4` (`../bcfp_baselines.csv`, row `snapshot-20261023`) |

A first run (`20261023_203809-1222132d`) was discarded: 16 of its 17 log rows were `link_dirty`,
because records were edited in the repo it modelled from (`run_dirty_tree.log`,
`run_verify_dirty_tree.log`). The schema was dropped and rebuilt from the worktree.

## Result

**48/50, PASS, as at v0.66.6** (`parity_crosssection.log`, `parity_annotated.csv`). BULK SK spawning
and rearing stay over and parked (#130). Accessible km is within 0.07 % on all 17 pairs.

Three pairs moved, all CO rearing, all link-side (`pair_moves.csv`, `segment_diff.csv`):

| pair | v0.66.6 | v0.68.0 | link change | reference change | predicted (`expected.txt`) |
|---|---|---|---|---|---|
| ADMS CO rearing | 352.6 | 352.3 | −0.3 (−0.21 by segment) | 0 | −0.22 |
| BULK CO rearing | 2215.6 | 2214.3 | −1.3 (−1.38 by segment) | +0.3 | −1.45 |
| BABL CO rearing | 1281.6 | 1280.2 | −1.4 (−1.46 lost, +0.23 gained, by segment) | 0 | under 0.1 (missed) |

All three are #364's CO gradient test on through-wetland lines under the `bcfishpass` bundle: of the
segments both builds share whose CO rearing changed, 52 are FWA edge 1050 (2.1 km) and 5 are main-stem
1000 lines (1.2 km) whose rearing cluster lost its connection when the wetland lines dropped. #364
measured ADMS and BULK only, and `expected.txt` extrapolated "under 0.1" to BABL without a
measurement; BABL has as many affected wetland lines as BULK. No other pair moved by 0.1 km or more,
the #367 pick moved nothing at this resolution, and no barrier override was added or lost
(`override_diff.csv` is empty). The two builds break 58 segments differently in the scored groups
(`resegmented.csv`).

## Files

| file | what it is |
|---|---|
| `run.log`, `run.started` | the driver's stdout for the kept run |
| `run_verify.log` | `study_area_verify.sql` with `-v schema=fresh_parity361 -v expected_n=17`: PASS |
| `expected.txt` | the expected moves, written before scoring (committed in `568b369a`) |
| `parity_crosssection.log`, `parity_annotated.csv` | the score: 48/50 |
| `moves.R`, `moves.log` | the comparison with v0.66.6 |
| `pair_moves.csv` | every scored pair, before and after, with the reference's change beside link's |
| `segment_diff.csv` | segments both builds share whose access, spawning or rearing changed, km |
| `resegmented*.csv` | segments in one build only, and habitat km on their lines |
| `override_diff.csv` | barrier-override positions added or lost (none) |
| `mapping_code_moves.csv` | the driver's mapping_code compare, before and after |
| `run_dirty_tree.log`, `run_verify_dirty_tree.log` | the discarded first run |
