# Code-check round 3: branch 479 (#386, #236, #341) and round 2's fix

## Checklist read

- code-check.md: every H3 under `## Mechanisms` read as prose (table rows skipped). Cited below: "A guard that fails toward pass", "One fact derived twice", "A fix lands in one of two callers that share a harness", "Zero-length, empty, and unset are three different things", "Written data outlives the fix".
- code-check-r.md: "Cross-function consistency for label/string normalization", "CSV whitespace: `trim_ws` and `strip.white` do not do what the name suggests", "Postgres row order is never fixed unless the query fixes it, so a pick, a float sum and a presence check can each depend on it", "`sprintf("%g", x)` writes `Inf` and `NA` into SQL as bare words…", "An `information_schema` lookup by the literal table name misses what Postgres resolves", "Tests that silently do not run", "`match()` treats NA as a matchable VALUE…", "`paste()` with a zero-length argument returns length ONE, not zero", "`nzchar(NA)` is TRUE — non-empty checks silently pass NA", "Under `R CMD check`, tests run from a temp dir against the INSTALLED package".
- code-check-shell.md: "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0" (verify SQL).
- code-check-spatial.md: "FWA `upstream_route_measure` misses the next segment's start", "A relation between FWA watershed codes is not a place" (owner pick, line deps).

What I ran, all in my own worktree (`git worktree add --detach … HEAD`, removed after) against local fwapg, writing only the test's own scratch schema:
- `tests/testthat/test-lnk_wsg_downstream_check.R` under `NOT_CRAN=true`: 67 expectations, 0 failed, 0 errors, 0 skipped.
- The resolver set against the pipeline-species set, for both bundles: they agree (241 and 217 groups).
- Owned gradient rows in the smallest groups of `fresh_default` (NBNK 423 of 423, UJER 8,524 of 8,528 owned): no modelled group would hold zero rows under owner-only persistence, so `.lnk_wsg_unheld()`'s "any rows" test is not refused by a legitimately empty group.
- The outlet closure against the round-2 line deps for two real run sets (results under finding 1).
- `read.csv` on a lifts file with one blank date and `yes` in `observation_control_apply`, and `SELECT current_date >= ''` in Postgres (findings 3 and 4).

## Mechanism

**One fact, changed where it is written and worked out again by each reader.** The branch changes three facts. Each consumer that had its own copy of the old fact keeps reading it the old way. The earlier rounds' findings are all this shape:

- **What a blank or unexpected cell in a rule table means.** Round 1 found a blank `observation_species` read as `IN ('')`, and a rule-name grammar that one validator accepted and another refused. In both, `.lnk_lift_rules()` and `lnk_barrier_overrides()` each decided the meaning on their own.
- **Which groups' persisted rows a group's walk needs.** Before #386 a group held its own copy of every gradient barrier on the lines it touches, so the outlet closure (dams) was enough for readiness. Round 2 found the model-time guard still reading the closure.
- **Which crossings a rule selects.** Round 1 found the scope of a `pscis_assessment` row. Its LEFT JOIN reads NULL for every non-PSCIS crossing, and nothing in that row's own reader knew it.

Every place each fact reaches in this diff, and whether it is handled:

**A. Who holds a gradient position** (the writer is `.lnk_sql_gradient_held()`: the owner when the owner is a modelled scanner, otherwise the lowest-coded modelled scanner)
1. `lnk_barriers_unify()`: the writer. Handled.
2. `lnk_pipeline_persist()` keeps an override or evidence row beside a held natural barrier: by line within 1 m, not through the holder rule. It is consistent with the writer. Where two natural barriers lie within 1 m of each other across a group boundary, both groups persist the override. That is harmless: the walk reads overrides as a set, and the verify check passes it. Handled.
3. `lnk_wsg_downstream_check()` (round 2): line rule, intersected with the modelled set, "holds any rows". Handled on a host with full FWA. It is blind on a database holding only some groups' FWA (finding 2).
4. The run resolver, `lnk_wsg_resolve(expand = TRUE)` and `study_area_wsgs.R`, is still the outlet closure. It now disagrees with the guard, and `wsg_recompute_one.R`'s post-condition has no override. **Not handled** (finding 1).
5. The recompute scheduler and audit (`recompute_deps.R`, line rule). Handled: the line rule still covers the holder, because the holder scans the line.
6. `recompute_readers_check.R` asks the guard in warn mode and recomputes only on `pass`, so a reader with an unheld dependency is named. Handled through round 2.
7. The export and `lnk_downstream_files()` / `lnk_downstream_load()`: the `dependencies` map uses the line rule. Handled.
8. The `study_area_verify.sql` one-holder check: judged groups only, by design. Handled.
9. The holder fallback is computed from the host's FWA. On two hosts whose FWA loads differ, it can pick two holders for a position owned by an unmodelled group. The result is duplicates, never a loss, because the lowest modelled scanner always picks itself. The verify check would name them. Not seen with full-FWA hosts; noted only.

**B. What a blank or unexpected value in a lift rule means**
1. A blank `observation_species` in `lnk_barrier_overrides()`: handled in round 1.
2. The rule-name grammar: handled in round 1 (duplicated in both places).
3. A blank `observation_date_min` from `parameters_barrier_lifts.csv`: **not handled** (finding 3).
4. `observation_control_apply` written `yes`/`no`, as its dictionary type `yes_no` says: **not handled** (finding 4).
5. `.lnk_presence_check()`'s `lift_readers` reads a blank or NA `observation_species` as reading no species, where the lift reads it as the rule's own species. **Not handled.** It feeds only the review tracker's text, not a build, so it is listed here and not as a finding.
6. A blank `observation_buffer_m`, or a blank `observation_threshold` (refused). Handled: `as.numeric("")` gives NA, then 20; the threshold is validated.

**C. Which crossings are human-made barriers** (`crossings.barrier_rule_id`)
1. The four `.lnk_sql_barrier_selected()` sites (unify, and the emit sets: anthropogenic, PSCIS, dams). Handled. No other `barrier_status IN ('BARRIER','POTENTIAL')` remains in `R/`, `data-raw/*.R` or `data-raw/*.sql`. The classify `streams_breaks` crossing labels still read `barrier_status`, but those labels never block access (they are not `blocked`), which matches "human-made barriers block no species".
2. A `pscis_assessment` row scoped beyond PSCIS: handled in round 1. A PSCIS crossing with no assessment row matches `is_null` by the documented rule.
3. `barriers.passability` carries `barrier_status` for a crossing a rule selects. It is only carried, never filtered on. Handled.

## Findings

- **[severity: bug]** `data-raw/wsg_recompute_one.R:230` with `R/lnk_wsg_downstream_check.R:565` (round 2's `deps`/`unheld`) and `R/lnk_wsg_resolve.R:132`. A run's group set is still the outlet closure (`lnk_wsg_resolve(expand = TRUE)` → `fresh::frs_wsg_drainage()`, used by `study_area_wsgs.R` and the parity closures). Round 2's guard now also requires every modelled group touching a line on each group's downstream paths. `wsg_recompute_one.R`'s post-condition calls the guard with `on_fail = "error"` and no override. So any partial run into a schema that does not already hold those groups fails each affected group's recompute: a new scratch schema, as in the documented parity re-score of a closure into `fresh_parity*`. The recompute has already rewritten `streams_access` and `streams_mapping_code` by then, and the run exits non-zero. Measured on local FWA under `bcfishpass`:
  - BULK's closure is 4 groups (LSKE, KLUM, KISP, BULK). 9 line dependencies fall outside it: LKEL, LNAR, MORR, MSKE, NASR, UNAR, USKE, WORC, ZYMO.
  - The ADMS/BULK/BABL/ELKR parity closure is 17 groups. 43 dependencies fall outside it, most of the Fraser among them.

  The accepted tradeoff says "warn/override modes exist". They do at model time (`LNK_GUARD_DOWNSTREAM=warn` / `_NOTE`), not at this post-condition, so nothing lets such a run finish. The resolver and the guard are two derivations of "what a group reads". Either the resolver expands by the line rule for a schema that lacks the dependencies, or the recompute post-condition takes the same recorded override the model leg does.
  - **Rule:** code-check.md "One fact derived twice"

- **[severity: fragile]** `R/lnk_wsg_downstream_check.R` `.lnk_wsg_line_deps()` (round 2). The dependencies come from `whse_basemapping.fwa_stream_networks_sp` on the host running the check. Take a database holding only some groups' FWA, such as the per-group cloud loader that #461/#465 single-group runs use. There, a tributary group owning a stretch of the focal group's downstream line is invisible whenever its FWA is not loaded. The check then passes with that group's barriers absent from the schema: the round-2 defect again, one axis over. `.lnk_wsg_fwa_unloaded()` guards only the outlet-closure groups (`down`), so nothing reports that the line deps were derived from incomplete FWA. The guard should refuse or warn when a group on its lines cannot be seen: compare the lines' segments with a complete source, or require that every modelled group be loaded before trusting an empty answer.
  - **Rule:** code-check.md "A guard that fails toward pass"

- **[severity: bug]** `R/lnk_barrier_overrides.R:199-200` with `R/lnk_lift_rules.R:104-136`. A further lift rule in `parameters_barrier_lifts.csv` with a blank `observation_date_min` is read by `read.csv` as `""` (a character column with other values), not NA. `lnk_barrier_overrides()` then tests `is.na("")` (FALSE) and builds `o.observation_date >= ''`. Postgres refuses that: `invalid input syntax for type date: ""`, checked here. It happens in prepare, after the run's log row has opened.
  - `.lnk_lift_rules()` checks the date only under `observation_record_date: lift_floor`, through `.lnk_date_col()`, which reads `""` as no floor. So under `lift_floor` a blank date passes validation whenever the listed species' floor is also empty (BT in `default`).
  - Under any other setting (the `bcfishpass` bundle) nothing checks it. Nor is a non-date string checked; that string is also pasted into the SQL unescaped.

  The dictionary documents blank as `1900-01-01`. The two readers disagree on "blank", exactly as round 1's `observation_species` did. Normalise the rule's date once in `.lnk_lift_rules()`, whatever the setting, and hand the lift a `Date` or NA.
  - **Rule:** code-check.md "Zero-length, empty, and unset are three different things"

- **[severity: fragile]** `R/lnk_barrier_overrides.R:218-219` with `inst/extdata/configs/dictionary_parameters_barrier_lifts.csv` (`observation_control_apply`, type `yes_no`). The lift reads the flag as `isTRUE(as.logical(x))`. `as.logical("yes")` is NA, so a rule written `yes`, as the dictionary's `yes_no` type says (and as `dimensions.csv`'s `yes_no` columns are written), silently becomes FALSE. The control table's veto is then never applied to that rule's lifts. `.lnk_lift_rules()` does not validate the column. `parameters_fresh.csv` happens to use TRUE/FALSE, so the shipped rows work. A new lifts file is where an author follows the dictionary. Accept or refuse explicitly: map yes/no and TRUE/FALSE, and refuse anything else.
  - **Rule:** code-check-r.md "Cross-function consistency for label/string normalization"
