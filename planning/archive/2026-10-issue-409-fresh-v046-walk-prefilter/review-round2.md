# Code-check round 2: link#409 (fresh v0.46.0 pin)

## Checklist read

- `index_code-check.md`, `index_code-check-r.md`, `index_code-check-shell.md`, `index_code-check-spatial.md`: in full.
- `code-check.md`: the prose of every H3 under `## Mechanisms`, 14 of 14, with the `|` table rows skipped. "Rules that stand alone", Security and Spreadsheets: index lines only.
- `code-check-r.md`: 6 sections in full: `stats::aggregate()` has three silent behaviours; `read.delim()` quotes by default; Postgres row order is never fixed; A `function(...)` mock hides arguments; `$` on a list partial-matches; `system2(stdout = TRUE)` warns. The other 105 headings: index line only.
- `code-check-shell.md`: 4 sections in full: psql does not interpolate / `\quit N`; `for x in $(cmd | grep … || true)`; A heredoc containing its own delimiter; Empty arrays under `set -u`. The other 63 headings: index line only.
- `code-check-spatial.md`: index only. The only spatial work in the diff is `md5(ST_AsEWKB(geom))` in `compare.R`, and its byte-for-byte comparison of two builds is the strict case.

## Findings

- **[fragile (doc claim)] CLAUDE.md:21, NEWS.md:6, RUNBOOK.md:597-599, data-raw/logs/prefilter_409/README.md:102-108, research/recompute_cost.md:94-98.** These blame the PSCIS and dam walks' rise (1.0 to 1.3 s in SALR, LKEL and CHWK, up to 4.2 s in SETN) on fresh building, indexing and analyzing its temp table each call. For example, NEWS says "Each scoped call pays to build its temp table before it walks, about 1 s …". They then name the lever: "one scope per group would remove most of it" (CLAUDE.md) and "reusing one scope across a group's calls would remove the rest" (research).
  - **Nothing in the record measures the scope.** `rerun.R`'s `timed_nf` times the whole `frs_network_features()` call. The `walks_*.tsv` files have no DDL column. So the rise is measured, but its cause is not.
  - **The one measurement that does exist is an order of magnitude smaller.** fresh's own timing of the temp table (`~/Projects/repo/fresh/data-raw/logs/network_features_272/`, `ddl_seconds`) is 0.07 to 0.15 s in SALR, LKEL and CHWK and 0.7 s in LSKE. That is on m4's local database, not the dispatcher, so it does not settle the question. It does show the attribution is a hypothesis.
  - **Other candidates are untested.** The prefilter's per-call ancestor array (`ARRAY(SELECT DISTINCT subpath(...) … generate_series)` over every segment) also grows with group size. So do the plan changes on small feature sets, whose walks took 0.15 to 0.5 s under 0.44.0. Reusing a scope would not touch either.
  - **Why it matters:** #394 / #411 and the "next lever" will be sized on this sentence. Round 1 corrected the numbers and kept the cause, so the defect moved one axis over.
  - **Fix:** state the rise as measured and the mechanism as unmeasured, or time `.frs_walk_scope` separately (wrap it like `frs_network_features` in `rerun.R`) before naming it.

- **[fragile (doc claim)] CLAUDE.md:21** says "the natural walks gain 4.7× to 17× against #261's 6.3× to 24.6×". That range covers four of the five groups. SETN's natural walks gained 1.8× (`summary_walks.csv`: 1,316 → 745 s summed). README:102 and research:93 both carry "(SETN 1.8×)". CLAUDE.md drops it, so the range reads as all five measured groups. This is the same kind of range-drops-a-member defect round 1 fixed for the per-call cost.

- **[fragile (doc claim)] data-raw/logs/prefilter_409/README.md:42** says "ADMS (its SK and KO reach fresh#242's connected-waterbody pass)". KO is not present in ADMS: `wsg_species_presence.csv` has a blank `ko` for ADMS, and `model/model_digests.csv` shows `streams_habitat_ko` with 0 rows on both sides. So for ADMS, the model-time check of #242's `connected_waterbody` path covered SK only. KO went through that path in NATR (33,906 rows, identical). The sentence states coverage the build did not have.

- **[fragile (doc claim)] README.md:76, CLAUDE.md:22, research/recompute_cost.md:89** state "189 positions in m4's `barriers_ch_access`, 188 across groups". No script or output in `data-raw/logs/prefilter_409/` produces that count. Only the `ties_*` files cover the anthropogenic and remediation sets, and grep finds no other source in the branch or `planning/active/`. These lines explain why 9 walks changed order, and each states a number with no producer. Add the query and its output beside `ties_*`. It also counts m4's copy, not the dispatcher database the 9 walks ran on.

- **[fragile] data-raw/logs/prefilter_409/rerun_all.sh:57** writes `> "$OUT/rerun_${w}_${label}.log"`, so a resumed run (`RESUME=`) truncates the refused attempt's log.
  - **It has already lost evidence.** `recompute/rerun_LSKE_a2.log` now holds the successful 02:02 run. README:55's "LSKE a2 first refused on autovacuum's lock on `streams_access`" has no surviving evidence in the record. `status.txt` keeps only "exit 1 3 s".
  - **It will lose more.** `rerun_SETN_a2.log` is the only record of SETN's refusal ("another backend holds 16 lock(s)"). The pending relaunch resumes at SETN a2 and will overwrite it, if its `OUT` is this directory or is copied over it.
  - **Fix:** append a timestamp to the log name or use `>>`, or move the refusal log aside before the resume.

## Checked and clean

- **Round 1's seven fixes, re-derived from the outputs.**
  - Per-call rise: SALR +1.03/+1.33, LKEL +1.13/+1.17, CHWK +1.10/+1.11, LSKE +2.04/+2.38, SETN +3.47/+4.19 s.
  - "Every PSCIS and dam walk" holds in all five groups. The anthropogenic walk is slower in four of five, and CHWK's is 4.39 → 1.85 s.
  - Model-time scope is narrowed to the five table kinds. `compare.R`'s `tables_of()` matches, and `frs_habitat_classify.R`'s v0.44.0..v0.46.0 diff is the `.frs_wsg_in()` progress count only.
  - SETN a2 refused once (`status.txt`, waited 4,320 s).
  - The `rerun.R` start-only check matches the code (`busy > 1L`, locks at start only).
  - The remediation scope is 134 groups, with 138 tables kept (`ties_remediations.txt`).
  - `pick_only.md` is tracked.
- **Every timing figure.** The table's totals and walks, 23.6 → 5.4 min (77 %), 48.3 → 20.2 (58 %), 4.7× (LKEL) / 17.3× (CHWK) natural, 5 to 11 calls per group, `setup_and_update` 2.7 to 9.5 s, and LKEL mapping code 4.4 / 7.3 s under 0.46.0.
- **Outputs.**
  - All 18 `digest_*.tsv` files have every row `same` TRUE, with 4 to 10 tables each.
  - 48 of 48 walks have `same_features`.
  - Model time: 25 of 25 non-empty group-tables identical, 20 empty. Provenance has six rows, one link SHA, `link_dirty` FALSE, and fresh 0.44.0 / 0.46.0 as stamped.
- **The two new tests, by mutation in a throwaway worktree at HEAD.** Both pass on HEAD with `NOT_CRAN=true`: 9 of 9 and 15 of 15, no skips.
  - Deleting `aoi = aoi` from the per-source walk in `lnk_pipeline_access()` fails "every downstream walk is scoped to the AOI…".
  - Lowering the Imports floor to 0.45.0 fails "the fresh floor is the version the Remotes pin installs".
  - The worktree was removed.
- **Every caller passes `aoi`.** `lnk_access()`, in both modes, and `lnk_pipeline_run()` pass `aoi` to `lnk_pipeline_access()`. That function holds the only three `frs_network_features()` calls in `R/`, and the observation walk is upstream.
- **`remediated_dnstr_ind` is preserved by `lnk_access(merge = TRUE)`.** So it is a model-time value, and the per-working-schema tie check is the right population.
- **Scripts.**
  - `rerun_all.sh`: a failed `psql` in `others()` reads as not-quiet, and the loop stops at `WAIT_MIN`. It fails closed.
  - `ties_remediations.sh`: `mapfile` from a process substitution is followed by an explicit empty guard, and `ON_ERROR_STOP=1`.
  - `compare.R`: refuses unless the provenance is right.
  - `summary.R`: `read.delim` reads unquoted fields with no `"`, and the `aggregate` inputs have no NA.
- **Other claims checked.**
  - `git diff 1d00c04c HEAD` is empty for the five recompute files named.
  - The reach.md sets are identical.
  - The pretest map rows' change voids the gate record by the gate's own rule, as CLAUDE.md says.
