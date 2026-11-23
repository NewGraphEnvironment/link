# The fresh pin from 0.55.1 to 0.56.0 (#507)

**Verified:** 2026-11-23 · **Issues:** #507 (#504) · **Produced by:** `run.sh`, `digest.R`, `compare.R` in this directory; `pretest_reach_fresh.R`; `pretest_run.sh --pick-only`

## What was asked

Does moving link's fresh pin from v0.55.1 to v0.56.0 change any persisted output, and does the pre-run gate's map cover fresh's changes?

## Answer

- **The gate's map covers it.** At v0.56.0, link's modelling path reaches the same 19 fresh files as at v0.55.1 (`reach.md`). All seven files fresh changed between the tags are reached and already mapped. The gate's pick, run at `565e4478` with fresh 0.56.0 alone in a scratch library, takes 11 groups with no unmapped file (`pick_20261123_183614/`).
- **The digests** (`compare.csv`, `builds.csv`): ADMS and BULK under `default` and ADMS under `bcfishpass`, each built once at main (`b89d3150`, link 0.89.0) on fresh 0.55.1 and once at this branch (`ad2381c1`) on fresh 0.56.0. `compare.R` stops unless every build exited 0 and every table-group digest and output token is identical. **Status at the PR's opening: the builds were still running.** The PR body says what they found.

## How

`run.sh <before|after> <link tree> <R library> <fresh sha>` builds into scratch schemas `fresh_pin507_<step>` and `fresh_pin507_bcfp_<step>` on m1's local fwapg, through `wsg_run_one.R` under `load_all`. fresh comes from a scratch library holding it alone (`R CMD INSTALL -l` from a worktree of each tag), so the shared library, which holds 0.55.1, was not touched. `FRESH_GIT_SHA` carries the tag's commit into the stamps.

The first launch waited its full 60 minutes for a quiet database and then built far slower than #481's minutes. Another session's modelling statements were running, one of them 3.8 hours old. That launch was stopped and its orphaned backend cancelled. The relaunch skips the wait (`QUIET_MAX_MIN=0`). So the minutes in `builds.csv` carry that load and say nothing about fresh's speed. The digests are unaffected.
