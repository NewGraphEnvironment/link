# The fresh pin from 0.55.1 to 0.56.0 (#507)

**Verified:** 2026-11-23 · **Issues:** #507 (#504) · **Produced by:** `run.sh`, `digest.R`, `compare.R` in this directory; `pretest_reach_fresh.R`; `pretest_run.sh --pick-only`

## What was asked

Does moving link's fresh pin from v0.55.1 to v0.56.0 change any persisted output, and does the pre-run gate's map cover fresh's changes?

## Answer

- **The gate's map covers it.** At v0.56.0, link's modelling path reaches the same 19 fresh files as at v0.55.1 (`reach.md`). All seven files fresh changed between the tags are reached and already mapped. The gate's pick, run at `565e4478` with fresh 0.56.0 alone in a scratch library, takes 11 groups with no unmapped file (`pick_20261123_183614/`).
- **The digests** (`compare.csv`, `builds.csv`): ADMS and BULK under `default` and ADMS under `bcfishpass`, each built once at main (`b89d3150`, link 0.89.0) on fresh 0.55.1 and once at this branch (`ad2381c1`) on fresh 0.56.0. `compare.R` stops unless every build exited 0 and every table-group digest and output token is identical. **Not yet run to completion: owed before merge.** Both attempts stalled on the first build (ADMS, `default`, fresh 0.55.1) in fresh's `frs_near_river_walk` statement: 22 minutes and counting, where #481's whole build took 2.7. That was the #487 shape, under another session's identical statement, then 4.2 hours old, at load average 25. Both were stopped, and their backends cancelled. Run it on a quiet database (`QUIET_MAX_MIN` left at its 60-minute default) with the command below.

## How

`run.sh <before|after> <link tree> <R library> <fresh sha>` builds into scratch schemas `fresh_pin507_<step>` and `fresh_pin507_bcfp_<step>` on m1's local fwapg, through `wsg_run_one.R` under `load_all`. fresh comes from a scratch library holding it alone (`R CMD INSTALL -l` from a worktree of each tag), so the shared library, which holds 0.55.1, was not touched. `FRESH_GIT_SHA` carries the tag's commit into the stamps.

The first launch waited its full 60 minutes for a quiet database and then built far slower than #481's minutes. Another session's modelling statements were running, one of them 3.8 hours old. That launch was stopped and its orphaned backend cancelled. The relaunch skips the wait (`QUIET_MAX_MIN=0`). So the minutes in `builds.csv` carry that load and say nothing about fresh's speed. The digests are unaffected.

## To finish the proof

From the repo root on m1. The trees and libraries are rebuilt if `/tmp` was cleared: worktrees of link `b89d3150` and `ad2381c1`, and of fresh `v0.55.1` and `v0.56.0`, with each fresh installed alone by `R CMD INSTALL -l`.

```bash
D=data-raw/logs/fresh_pin_507; bash $D/run.sh before /tmp/link507/link_before /tmp/link507/lib_0551 29e7aa13c50af8a7e35f664aadaadecfda1bdee1 && bash $D/run.sh after /tmp/link507/link_after /tmp/link507/lib_0560 7566f85013d94d4a59a045bd5a857acf975f27b9 && for s in before after; do Rscript $D/digest.R fresh_pin507_$s $D/digest_$s.csv && Rscript $D/digest.R fresh_pin507_bcfp_$s $D/digest_bcfp_$s.csv; done && Rscript $D/compare.R
```

Then drop the four `fresh_pin507_*` schemas and replace NEWS's `__DIGESTS__` with the count `compare.R` prints.
