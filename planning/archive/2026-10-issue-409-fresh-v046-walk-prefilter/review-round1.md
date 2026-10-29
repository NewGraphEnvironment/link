# Code-check round 1: link#409 (fresh v0.46.0 pin)

## Checklist read

- `index_code-check.md`, `index_code-check-r.md`, `index_code-check-shell.md`, `index_code-check-spatial.md`: in full.
- `code-check.md`: the prose of every H3 under `## Mechanisms` (14 of 14), with the `|` table rows skipped. I did not read the "Rules that stand alone", Security or Spreadsheets sections beyond their index lines.
- `code-check-r.md`: read 17 sections in full: `on.exit()` at a script's top level; A `data-raw/` script must load the source tree; `stats::aggregate()` has three silent behaviours; `read.delim()` quotes by default; `system2(stdout = TRUE)` warns; Postgres row order; An `information_schema` lookup by literal name; A `function(...)` mock hides arguments; `load_all()` refuses a dependency below the floor; Two repos pinning the same remote; `identical(-0, 0)` and digest; A database driver's value; `::text` spelling; Rscript reads a script as it runs; testthat counts an uncaught error under `error`; A `skip_if_not()` skips only its own block; `package_version()` errors on a pre-release. The rest (about 100 headings): index line only.
- `code-check-shell.md`: read 11 sections in full: psql does not interpolate / `\quit N`; Empty arrays under `set -u`; `if ! cmd; then rc=$?`; `grep -c`; A failed `cd`; A heredoc containing its own delimiter; Heredoc precedence; Quoting; A `pgrep -f` waiter; `for x in $(cmd | grep … || true)`; Tailscale SSH exits 0. The rest (about 70 headings): index line only.
- `code-check-spatial.md`: index only. No heading names a tool used in this diff, which is psql and ltree SQL with no geometry work. The two FWA rows (`upstream_route_measure`, main flow) do not apply.

## Findings

- **[fragile (doc claim)] CLAUDE.md:16, NEWS.md:75, RUNBOOK.md:98-99, data-raw/logs/prefilter_409/README.md:220-222, research/recompute_cost.md:950-952.** These say each scoped call costs "about 1.1 to 1.4 s" and that the dam and PSCIS walks went to "1.3 to 1.6 s". That holds only in CHWK, LKEL and SALR. `recompute/summary_walks.csv` disagrees for the two larger groups:
  - LSKE: dams 0.43 → 2.81 s and PSCIS 0.54 → 2.58 s, so about 2.0 to 2.4 s of added cost per call.
  - SETN: dams 5.15 → 8.62 s and PSCIS 0.49 → 4.69 s, so about 3.5 to 4.2 s per call.

  The cost grows with the group's segment count, because the temp table holds the group's segments. That matters for the "small groups gain least" reasoning and for sizing the #394 / one-scope-per-group lever. At 11 calls per group it adds roughly 25 to 45 s on large groups, not 12 to 15 s. Restate the cost as rising with group size and give the measured range.

- **[fragile (doc claim)] NEWS.md:75, README.md:219, research/recompute_cost.md:951.** These say the anthropogenic walks "got slower" or "lose", and the research file gives "whose own work is 0.15 to 0.5 s". CHWK's `barriers_anthropogenic_unified` walk went 4.39 → 1.85 s, 2.37× faster (`summary_walks.csv`). Under 0.44.0 the anthropogenic walks took 0.99 to 10.3 s, not 0.15 to 0.5 s. Only the dam and PSCIS walks are uniformly slower in the three small groups. CLAUDE.md:16 already names only those two.

- **[fragile (doc claim)] README.md:165-166 ("then every persisted table digested per group"), NEWS.md:74 ("digest identical in every table"), research/recompute_cost.md:942 ("in every table"), CLAUDE.md:11 ("Outputs digest identical … model time").** `compare.R`'s `tables_of()` selects only `streams`, `barriers`, `streams_access`, `streams_mapping_code` and `streams_habitat_%`. The persist schema also holds `barrier_overrides` (`R/lnk_persist_init.R:556`) and `streams_near_river` (`:592`, written from fresh's classify, and `frs_habitat_classify.R` changed between the pins). Neither was digested. Either add them to `tables_of()` or narrow the claim to the tables compared. This scope is inherited from #367's `compare.R`.

- **[fragile (doc claim)] README.md:176-177** says "SETN a2 refused twice …" and that "`recompute/status.txt` has every attempt". `status.txt` records one SETN a2 refusal (04:36:52Z, after waiting 4320 s). `input_counters.tsv` agrees: it has four `before` blocks and only two `stopped` blocks, one for LSKE a2 and one for SETN a2. Either the second refusal is missing from the record, or "twice" is wrong.

- **[fragile (doc claim)] CLAUDE.md:19** says "A timing beside another session's walks is refused, not slowed". `rerun.R` checks locks and active clients only at its start, and it tolerates one other active client (`busy > 1L`). SETN a1 ran with another client active by its end (`steps_SETN_a1.tsv`: `others_end` 1), and README:213-214 says its 891 s "may be high". So a timing can be slowed; only one that starts beside a lock is refused.

- **[fragile (doc claim)] NEWS.md:74 and CLAUDE.md:17** say the tiebreak "cannot move `dam_dnstr_ind` or `remediated_dnstr_ind`". The anthropogenic check covers all 241 groups. The remediation check covers only the working schemas the dispatcher kept, about 134 of 241 groups, so "cannot move `remediated_dnstr_ind`" is unscoped beyond the evidence. Scope it to the 134 groups and to this build, as research/recompute_cost.md:917-918 does.

  A related count: README.md:198 says "134 groups whose working schemas it kept". `ties_remediations.txt` says the host kept 138 `working_<wsg>.crossings` tables, of which 134 contributed rows to the remediation set.

- **[fragile] data-raw/logs/prefilter_409/pick_only.md is untracked** (`git status`: `?? data-raw/logs/prefilter_409/pick_only.md`). README.md:171 and :239 cite it as the evidence that `pretest_run.sh --pick-only` exits 0 over fresh v0.42.0..v0.46.0. Unless it is committed, the PR ships a citation to a missing file.

## Checked and clean

- **Every number in the timing table.** Totals, walk sums and ratios for all five groups match `summary_steps.csv` and `summary_walks.csv`.
- **The summed totals.** 23.6 → 5.4 min (77 %) and 48.3 → 20.2 min (58 %).
- **The walk counts.** 48 of 48 walks return the same features. 9 walks differ in order (CHWK's eight, SALR's CH). Order is constant within each version, re-derived from the `walks_*.tsv` files.
- **The 18 recompute runs.** Every table in all 18 is digest-identical (4 to 10 tables). The input counters are unchanged.
- **Model provenance and digests.** 25 identical, 20 empty.
- **The "4.7× to 17×" range.** It is the sum of each group's natural walks: LKEL 4.70×, CHWK 17.3×.
- **The ties SQL.** It groups on fresh's ORDER BY keys (`wscode DESC, localcode DESC, measure DESC`). The remediation filter mirrors `lnk_barriers_emit()`.
- **The README's recompute-file list.** `git diff 1d00c04c HEAD` is empty for the five files it names. The only other recompute-adjacent diff is comment-only (`lnk_barriers_views.R`) or config-key validation (`lnk_config.R`).
- **The two new tests.** The mock records `direction` and `aoi`, which are real formals of `frs_network_features()`. `lnk_pipeline_access()` is the only caller of `frs_network_features()` in `R/`. The floor-equals-Remotes test reads the same `packageDescription()` source as `.lnk_fresh_floor()`.
