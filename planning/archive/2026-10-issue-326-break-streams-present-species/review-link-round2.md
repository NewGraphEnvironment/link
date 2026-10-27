# Code review, round 2: branch 326-break-streams-only-where-a-present-speci (#326)

Diff: `/var/folders/.../cc_link/diff2.patch` (a34d5357..0511104a, logs and planning excluded). I looked hardest at the round-1 fixes (`fixes_r1.patch`).

## Checklist read

- **code-check.md** (330 KB): the prose of all 14 H3s under `## Mechanisms`, with table rows skipped. The other 23 H3s (Rules that stand alone, Security, Spreadsheets and PDFs) I read as index lines only. None of them names a tool or shape this diff uses.
- **code-check-r.md** (178 KB): 6 of 111 headings read in full; 105 read as index lines only. The 6:
  - "A `data-raw/` script must load the source tree"
  - "A database driver's value is not a base R type"
  - "`identical()` on two reader results"
  - "Postgres row order is never fixed…"
  - "`sprintf("%g", x)` writes `Inf`…"
  - "An `information_schema` lookup by the literal table name…"
- **code-check-spatial.md** (156 KB): 1 of 93 headings read in full ("FWA `upstream_route_measure` misses the next segment's start"); 92 read as index lines only.
- **code-check-shell.md** (125 KB): index only, 67 headings. The diff contains no shell.

## Findings

- **[severity: bug] `R/lnk_pipeline_prepare.R:673-699` (the round-1 fix). The persisted lift reads this group's own rows from its previous build, which the persist step then deletes. So the claim "an extra lift only keeps an extra break" is false.**
  - **What lifting does.** Lifting position Y takes Y out of `barriers_<sp>`.
    - If Y was on the minimal set, `frs_barriers_minimal()` no longer keeps it, so the gradient-minimal source no longer breaks at Y.
    - The positions above Y break instead. That is the "extra break" the comment describes.
    - The comment leaves out the other half: **the break at Y itself is lost.** For a gradient barrier, no other source breaks there. Falls, definite and opt-in subsurface still break through their independent sources.
  - **When that is safe.** The union is safe only when every extra lift is also a lift in the view the persist step will produce. Two kinds of persisted row are not.
  - **This group's own rows.** Nothing in `NOT EXISTS (SELECT 1 FROM <persist>.barrier_overrides p …)` filters on `watershed_group_code`.
    - So the reduction also lifts by this group's rows from its previous build.
    - `lnk_pipeline_persist()` (`R/lnk_pipeline_persist.R:129-134`) then runs `DELETE … WHERE watershed_group_code = aoi` and inserts this run's rows. From then on the view no longer lifts Y.
    - Result: Y is a barrier in `barriers_<sp>_access`, but the stream is not broken at Y. The segment that straddles Y starts below Y, so classify and `streams_access` both label the reach above Y accessible.
    - This is round 1's defect again, one axis over. The recompute cannot repair it, because it does not re-segment.
    - Where an old row lifts what the current build does not:
      - a bcfishobs reload that drops or re-matches records (`--refresh-primitives`, or the weekly vintage);
      - a `barriers_definite_control` row added by the weekly sync;
      - a changed observation threshold or pooling row;
      - another config's earlier build in the same schema. `default`'s YAML schema is `fresh` too, and its BT lifts pool DV, so a `default` run without `LNK_SCHEMA` leaves BT lifts that a later `bcfishpass` build of the group would inherit.
    - **Fix:** add `AND p.watershed_group_code <> <aoi>` to `persist_lift_sql`. The working table is this group's authoritative set; the persisted copy of it is about to be replaced. Add a test that asserts the filter. One more reason to filter: a stale own row could also be a lift the current build has dropped.

- **[severity: bug] same lines. A group's segmentation now depends on what the persist schema held when the group was prepared. Builds therefore differ by host and by run order, and nothing records the difference.**
  - The other groups' rows the fix reads are whatever the persist schema holds at that moment.
    - On the dispatcher, that is the previous provincial build's rows for every group not yet re-modelled. Some of those are replaced later in the same run.
    - On a cloud host or worker, it is only the groups that host has already modelled.
    - It also depends on whether a `consolidate` (#369, mid-run) or a parallel `-j` job's DELETE+INSERT has landed.
  - So the same group, inputs and code can produce different break sets, and so different segment counts, `id_segment`s and digests, depending on where and when it ran.
  - This breaks two things this repo relies on:
    - CLAUDE.md's correctness bar ("identical inputs → byte-identical"; "Any variation … is a defect");
    - #361's split-host result ("nothing the order can reach differs").
  - `<schema>.log` / `log_input` record none of it, so a later digest mismatch cannot be traced back to this.
  - Where the previous-build rows are replaced later in the run, the first finding's missing-break failure applies as well.
  - **Even when the rows are current, the fix only works if the other group's rows land first.** Round 1's case (a control row in H, which lifts on G's copy) is closed only when G persisted before H was prepared.
  - **Options (an operator call, since it changes stored segmentation):**
    1. **(recommended)** Keep the per-group lift deterministic: drop the persisted read and name round 1's control residual next to CLAUDE.md's "2 rows today" note. This was round 1's second remedy.
    2. Remove the cause in the working lift: apply `barriers_definite_control` to the same positions in every group that holds a shared barrier, so each group's working overrides already match the view's.
    3. Keep the read, with the own-group filter above, and record which persisted rows were read (count and digest) in `log`, so a host or order difference can be seen.

## Checked and clean (no finding)

- **`cfg$pipeline$schema` is the persist schema at prepare time on every model path.**
  - `lnk_pipeline_run()` persists through `.lnk_table_names(cfg)` (`R/utils.R:206`), so the persist and the lift read one value.
  - `wsg_run_one.R:56`, `wsgs_run_host.R:83`, `wsg_recompute_one.R:52` and `cypher_prep.sh` / `worker_prep.sh` all set it from `LNK_SCHEMA` / `--schema` before the run.
  - `habitat_variants_build.R:312` sets the base schema; variants only re-classify (`:804`).
  - The only callers of `lnk_pipeline_prepare()` that do not override it are one-off scripts under `data-raw/logs/` and `exp_gradient_extra_breaks.R`, which sets its own schema.
  - `wsg_recompute_one.R` does not call prepare.
- **Persisted columns.** `cols_barrier_overrides` (`R/lnk_persist_init.R:168`) has `blue_line_key`, `downstream_route_measure`, `species_code` and `watershed_group_code`, with an index on `(blue_line_key, downstream_route_measure)`. The persist step writes them from the working table plus the AOI.
- **`data-raw/breaks_diff.R` fingerprint guard.**
  - It passes on its positive case. I ran it read-only against `working_fina` and `fresh` FINA: both are `28650 / 460862538`, `identical()` is TRUE, and `n` is `integer64` on both sides.
  - Its `information_schema` lookups use lowercase literal names, which resolve correctly.
  - The script uses no link code, so the load-the-source-tree rule does not apply.
  - A float `sum` rounded to whole metres could flip on a value at `.5`. That is negligible.
- **Regenerated provenance.**
  - `shasum -a 256` of `rules.yaml` and `dimensions.csv` matches `config.yaml` (`e9b9ea7…`, `a48aadd…`).
  - `lnk_config_verify(lnk_config("bcfishpass"))` reports no drift and no shape drift on 14 files.
  - `test-lnk_config.R`: 162 pass, 0 fail.
- **Tests, run in a copy with `skip_if_no_db()` forced to skip, so nothing was written to the shared DB:**

  | File | Pass | Fail | Error |
  |---|---|---|---|
  | `test-lnk_pipeline_prepare.R` | 217 | 0 | 0 (3 skipped) |
  | `test-lnk_pipeline_classify.R` | 44 | 0 | 0 |
  | `test-lnk_rules_build.R` | 351 | 0 | 0 |
  | `test-lnk_preflight_fresh.R` | 41 | 0 | 0 |
  | `test-dictionaries.R` | 99 | 0 | 0 |

  The new test's `fresh\.barrier_overrides p` assertions would go red with the lift removed.
- **`.lnk_order_child_bounds`.**
  - fresh's `.frs_build_ranges()` returns `rear$channel_width = c(min, max)` and `rear$gradient = c(0, max)`, so `[[1]]` and `[[2]]` are right.
  - A missing `rear_channel_width_min` leaves `channel_width` NULL, which errors as intended.
  - Measured on local FINA: 0 positions lifted only by other groups' persisted rows today, so neither finding has moved a number yet.

## Note (not a code finding)

The PARS pre-flight now running (`wsg_run_one.R PARS bcfishpass`, started 19:28 PDT from `$TMPDIR/link_326_wt`) logs `link_sha` `1b69ad7c`, which is before the round-1 fixes. Its break set does not include the persisted lift. If it becomes Phase 4 evidence, cite it at that SHA.
