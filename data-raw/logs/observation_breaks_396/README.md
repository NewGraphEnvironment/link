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
- **Expected failures.** The recompute's last step, the downstream-dam post-condition, fails wherever a group below is not held: in both `default` schemas for UPCE and PARS (Peace Canyon and Site C sit in UPCE and below), BULK and LKEL (the Skeena groups below), ELKR (the Kootenay below), and in `fresh` as in #326. Its access, gate and mapping-code work commits before that check, so "failed only on the post-condition" is the pass rule, read from each log. A recompute is not retried, so its minutes are one run. Minutes come from `status.tsv`, not `log_recompute`.

## Files

| file | what it is |
|---|---|
| `build_obs.R` | builds `default`'s observation set per group and province-wide into `zz396_cuts`, with the pipeline's own prep helper |
| `cuts.sql`, `cuts.csv` | question 1 before building: positions today against tops, and which positions cut a segment (1 m rule) |
| `province.sql`, `province.csv` | the same ratio province-wide |
| `code2_class.sql`, `code2_class.csv` | a pre-build estimate of the main access change: pieces that go from code 1 to 2 at a species' top (not a bound; `pre_post_diff.R` measures it) |
| `redundancy.sql`, `redundancy.csv` | question 5 as the issue posed it: tops with the species also recorded up a tributary above (a moot premise, see the header) |
| `exact_set.sql`, `exact_set.csv` | a smaller break set that would keep code 2 nearly as `all` gives it: per species, the lowest record more than 1 m above its raw top; not built |
| `pre_post_diff.R`, `pre_post_diff.csv` | question 6: BEFORE against AFTER on measure-overlap pieces; every change must follow the direction its segment start moved |
| `bias.R`, `bias.csv`, `bias_fiss_note.txt` | question 3: segment length and gradient at sites with and without fish (aggregates only) |
| `readers_code2.md` | question 4: who reads code 2 against 1 |
| `run.sh`, `status.tsv`, `driver.log`, `<step>_<WSG>.log` | the builds |
