## Outcome

Each config bundle now carries its own `parameters_habitat_thresholds.csv` under `files:`, resolved by `lnk_pipeline_classify()` / `lnk_pipeline_connect()` from `cfg`, with a messaged fallback to fresh's copy for custom bundles that declare none. The four existing bundles got byte-identical copies with provenance; `bcfishpass`'s is a frozen parity input that csv-sync does not touch. Runs log the values in `<persist>.log_parameters_habitat_thresholds` (new dictionary, per-table snapshot gate). The thin `default_tuned` bundle (`extends: default`, schema `fresh_default_tuned`) is where #284's calibrated values will land.

The main lesson is that **`extends:` had never been exercised by a shipped bundle, and five parts of it were broken**. Inherited provenance resolved against the child directory, so every run was flagged `config_drift`. `config_hash` named inherited files by absolute path and sorted names by `LC_COLLATE`, so it differed from host to host. It also ignored the parent's `config.yaml`. A depth-3 chain did not load, and a relative `extends:` resolved against the working directory. Code-check round 3 named the underlying mechanism: nothing owns a config's resolved input set, and each consumer re-derives it. It then enumerated every consumer (14 threshold-path consumers, 10 file-set deciders, 9 path resolutions), and those enumerations are what ended the review loop. Along the way the trace also showed that on link's rules path the CSV's MAD and edge-type columns are carried but never applied, and that `rear_lake_ha_min` only takes effect through a `rules.yaml` rebuild. Both facts are recorded in the dictionary and in RUNBOOK §7.

## Measurement

- **Classify output is unchanged on fixed segmentation.** Holding segmentation fixed and re-running classify + connect, the branch is byte-identical to main on ADMS (4 species) and BULK (6 species). Main re-classifying its own schema reproduces its own digests, so classify is deterministic.
- **Thresholds move only what they should.** In a thin bundle, CH `rear_gradient_max` 0.0549 → 0.0321 moves CH rearing on ADMS from 1,470 to 1,280 segments and changes nothing else. Reverting restores the output exactly.
- **Hashes.** `bcfishpass`, `default_rearbreaks` and `default_extrabreaks` hashes were unchanged by the extends refactor itself. Every bundle's hash still changes in this release, because of the new file under `files:` and the radix sort.
- **Wrong turn, kept on purpose.** The first main-vs-branch test compared full-run digests. The `streams` digest differed, and that looked like a regression. A second run of **main** differed from the first (39,423 vs 39,422 segments; CH spawning 1,062 vs 1,060), so full runs are nondeterministic on main. The cause is the PSCIS→modelled crossing pick, which ties when two modelled candidates share a `linear_feature_id` (`R/lnk_pipeline_pscis_build.R:264-279`). This changed the verification method to re-classifying on fixed segmentation. The issue is drafted but not filed pending body review.
- **Environment moved mid-run.** fresh was reinstalled 0.33.0 → 0.34.0 at 23:25 local, by something outside this session. Each comparison stayed within one fresh version.
- **Suites.** Test failures are identical to main's baseline: 3, all from the down `:63333` tunnel. `R CMD check` passes 1,939 tests on the branch vs 1,867 on main, with no new WARNING or NOTE.

## Evidence

`data-raw/logs/habitat_thresholds_282/*` (method scripts, per-run digests, README with stamps). Code-check rounds: `review-round*.md` in this directory.

Closed by: PR for branch `282-per-bundle-habitat-thresholds-csv-in-co` (Fixes #282)
