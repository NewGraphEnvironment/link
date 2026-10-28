# observation_breaks_396 — break streams at an observation only at each species' top per line (#396)

## Run decision (written before any build)

- **What re-segments.** Under `default` (and `default_tuned`, which inherits it) streams break at fewer observation positions, so every persisted `default` group must re-model, all 241, then the post-consolidate recompute. That is the next provincial run at the release this lands in, done after merge, stacked on #326's owed re-model. The `bcfishpass` schema does not re-segment: its bundle leaves `observation_breaks` out, which means `all`.
- **What is built here.** m4's local docker fwapg only, for measurement; these schemas are dev state and are published nowhere.
  - `default` BEFORE at main (`43e34096`) into the scratch schema `zz396_default_pre`, and AFTER at the branch (`71ccc2ce`; later commits change comments and docs only, which moves `config_hash` but not the build) into `zz396_default_post`: LKEL (sparse, salmon and residents), BULK (heavily surveyed, salmon and residents), UPCE, PARS (resident only), ELKR (the largest reduction, BT and WCT). Each from its own worktree.
  - UPCE is added for question 3 only. The FISS sites that give visits without fish cover COTR, LNTH, PINE, UNTH and UPCE, none of the other four, and UPCE holds the most (7,024 site rows). It drains below PARS, so it is built before PARS in both schemas.
  - `bcfishpass` AFTER at the branch into `fresh` for BULK and PARS, last, so `working_<wsg>` holds the build `breaks_diff.R` reads. It overwrites #326 round 2's rows for those two, so "unchanged" is judged against the committed `segmentation_326/round2/{bulk,pars}_breaks.csv` and the README counts (BULK 42,989, PARS 43,776 segments).
  - Groups run downstream-first, then `wsg_recompute_one.R` (always merge) per group and schema. Each group's BEFORE and AFTER run back to back.
- **Load from another session.** At launch another session's six parallel R workers had been using this host and database for 1 h 50 min, one short query active at a time. They cannot be waited out on a known clock, so the BEFORE and AFTER of each step run in pairs, and `status.tsv` records the 1-minute load average at each step's start and end. Minutes are compared within a pair, not across the run.
- **Software.** Both worktrees on the installed fresh 0.43.0 (`RemoteSha 18d92ceb`).
- **Primitives.** `lnk_preflight_vintage()` passed on 2026-10-28 06:40 UTC, oldest load stamp 3.0 days (`whse_fish.pscis_assessment_svw`), so nothing was re-pulled.
- **Before state.** `zz396_default_pre` is built here rather than read from `fresh_default`, because an AFTER build into a schema replaces the group's rows (plan review). `fresh_default` and `zz326_default_pre` are left as they are.
- **Expected failures.** The recompute's last step, the downstream-dam post-condition, fails wherever a blocking dam below a group sits in a group the schema does not hold. Written before the run as UPCE, PARS, BULK, LKEL and ELKR; it failed for PARS (W.A.C. Bennett Dam, PCEA) and ELKR (eight Kootenay dams in KOTL and below) in both `default` schemas, and passed for the rest and for `fresh`. Its access, gate and mapping-code work commits before that check, so "failed only on the post-condition" is the pass rule, read from each log. A recompute is not retried, so its minutes are one run. Minutes come from `status.tsv`, not `log_recompute`.

## Files

| file | what it is |
|---|---|
| `build_obs.R` | builds `default`'s observation set per group and province-wide into `zz396_cuts`, with the pipeline's own prep helper |
| `cuts.sql`, `cuts.csv` | question 1 before building: positions today against tops, and which positions cut a segment (1 m rule) |
| `province.sql`, `province.csv` | the same ratio province-wide |
| `code2_class.sql`, `code2_class.csv` | an estimate (re-run after the builds with the raw-top test; only ELKR CT moved, because `working_elkr` now holds a `default` build) of the main access change: pieces that go from code 1 to 2 at a species' top (not a bound; `pre_post_diff.R` measures it) |
| `redundancy.sql`, `redundancy.csv` | question 5 as the issue posed it: tops with the species also recorded up a tributary above (a moot premise, see the header) |
| `exact_set.sql`, `exact_set.csv` | a smaller break set that would keep code 2 nearly as `all` gives it: per species, the lowest record more than 1 m above its raw top; not built |
| `pre_post_diff.R`, `pre_post_diff.csv` | question 6: BEFORE against AFTER on measure-overlap pieces; every change must follow the direction its segment start moved |
| `bias.R`, `bias.csv`, `bias_fiss_note.txt` | question 3: segment length and gradient at sites with and without fish (aggregates only) |
| `readers_code2.md` | question 4: who reads code 2 against 1 |
| `run.sh`, `status.tsv`, `driver.log`, `<step>_<WSG>.log` | the builds |
| `segments.csv` | question 1 and the `bcfishpass` check: segments and network km per group in each schema after the run |
| `minutes.csv` | question 2: paired model and recompute minutes from `status.tsv` (BULK BEFORE's stalled first attempt left out) |
| `run_elkr_repeat.sh`, `status_elkr_repeat.tsv`, `driver_elkr_repeat.log`, `repeat_*_ELKR.log` | ELKR's pair again, AFTER first |
| `elkr_digest.sql`, `elkr_digest_{before,after}.csv` | ELKR's persisted rows before and after the repeat: identical |
| `{bulk,pars}_breaks_bcfishpass.csv` | `breaks_diff.R` on the `bcfishpass` builds: identical to `segmentation_326/round2/` |
| `parity_crosssection.{csv,log}` | `bcfishpass` parity on BULK and PARS: 18 of 20 pairs (BULK SK parked), every value equal to round 2 |
| `validate/`, `validate_pre_post.csv` | `habitat_validate.R` on BEFORE and AFTER: same `n_obs`, `n_unattached` and `n_accessible` |

## What happened during the builds

- **BULK BEFORE stalled once and did not reproduce.** Its first attempt sat in fresh's near-river walk (`CREATE TEMP TABLE pg_temp.frs_near_river_walk AS …`) from 07:03:37 UTC, on freshly analyzed tables, with no other query active. It was cancelled at 07:48:13 (`pg_cancel_backend`, 44.6 min), and `run.sh`'s retry built the whole group in 5.1 min. That is the OKAN shape CLAUDE.md records from the 2026-10-23 run. Its minutes are left out of question 2 and the retry's are used. The retry overwrote the first attempt's log, so `default_pre_BULK.log` is the retry's.
