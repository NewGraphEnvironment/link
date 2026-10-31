# Code-check round 3 (#401): branch 47bb3dfa...c54c2058

## Checklist read

- **code-check.md:** read in full the prose of all 14 H3s under `## Mechanisms` (from the extracted `mech.txt`, table rows skipped), plus "Documentation Staleness". Not read in full: the other 28 headings (stand-alone rules, Security, Spreadsheets and PDFs), none of which names a tool or shape this diff uses.
- **code-check-r.md:** read in full "`on.exit()` at a script's top level never fires", "Postgres row order is never fixed unless the query fixes it, …", "A database driver's value is not a base R type — and it fails twice". Checked from the index line alone against the diff (shapes present, rule not triggered): "`$` on a list partial-matches", "`paste()` with a zero-length argument", "`match()` treats NA as a matchable VALUE", "A `function(...)` mock hides arguments", "`load_all()` refuses an installed dependency below the `Imports:` floor", "Tests that silently do not run", "Under `R CMD check`, tests run from a temp dir". Not read: the remaining ~117 headings.
- **code-check-shell.md:** checked by index line against `run.sh` ("`grep -c` prints the count AND exits 1", "psql does not interpolate `:'var'`", "A failed `cd` lets every later command run"; run.sh guards its `cd` with `|| exit 1`). Not read in full: all ~95 headings.
- **code-check-spatial.md:** read in full "FWA `upstream_route_measure` misses the next segment's start" (pre_post_diff.R / parity_pieces.sql measure overlaps; both drop pieces under 1 cm, so fine). Not read: the other ~110 headings.

## Mechanism

Rounds 1 and 2 share one shape: **the change moved where a cost and a table's lifetime are decided, and artifacts written against the old place were checked by the files that happened to change together, not against the decision.** Round 1: the pre-run gate maps the *file that runs the walk* to a cost input, but the walk's cost now depends on *which table it is handed*, chosen elsewhere. Round 2: the drop moved from the shared phase (`lnk_pipeline_prepare()`, which every caller ran) into one caller (`lnk_pipeline_run()`'s `on.exit()`), and the prose describing the new place claimed more than `try(..., silent = TRUE)` in an `on.exit()` delivers. Both are "A fix lands in one of two callers that share a harness" (cleanup moved out of the harness) plus "Documentation Staleness" for the claims written around it.

## Findings

- **[severity: fragile]** `R/lnk_pipeline_prepare.R:29-47` (exported `lnk_pipeline_prepare()`, `man/lnk_pipeline_prepare.Rd`) — the province table's cleanup moved out of the shared phase into one caller. Since this branch (`R/lnk_pipeline_prepare.R:606`) `lnk_pipeline_prepare()` returns with `<schema>.observations_province` (every group's records, ~200 MB) still in the working schema, and only `lnk_pipeline_run()` drops it. The exported function's "Writes to" list, its contract for any other caller, does not name the table (nor `<schema>.observations`), so a direct caller of the exported phase has no way to know it now owns a ~200 MB table. The six historical data-raw callers are accepted; the exported contract is a separate artifact that did not follow.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness"

- **[severity: fragile]** `RUNBOOK.md:246-248` ("a kept working schema holds it only after a killed run (no `on.exit()` runs then)") and `R/lnk_pipeline_run.R:197-200` ("Dropped when the run returns or errors (not when R is killed)") — the drop is `try(DBI::dbExecute(conn, drop_obs_province), silent = TRUE)`. When the run errors because the connection itself is gone (server restart, network loss, a terminated backend), the drop fails silently and the table stays, though R was not killed. "only after a killed run" is the round-2 overstatement surviving in one more sentence: the set of runs that leave the table is "killed, or ended with a connection that cannot run the DROP", not "killed". Effect is the same accepted cost (one ~200 MB table until the group's next run), so this is a wording fix, not a code fix.
  - **Rule:** code-check.md "A guard that fails toward pass"

No bug found in the walk, the gate, the config check, the vocabulary digest, the tests or the pre-run query. Checked: `obs_upstr` lookup with absent ids and an empty walk result (`character(0)` filled; integer `id_segment` on both sides, so `as.character()` cannot diverge); `.lnk_observation_upstream()` validated before any write (the vocabulary resolve calls it first); the gate reproduces bcfishpass's `spp INNER JOIN ids` (`load_streams_upstr_observations.sql` at the local `bcfishpass` checkout, `620dbe43`), and `<schema>.observations` equals the group's slice of the province table (`build_obs.R` asserts it); `on.exit()` after `cleanup_working = TRUE` drops into a dropped schema, which Postgres answers with a NOTICE, not an error; `data-raw/pretest/obs_upstream.sql` ran read-only here in 36 s, 246 rows, LFRA 126,143 first, its `DISTINCT ON` ending on `linear_feature_id`; the published figures (31/14 group-species, 25.98 km, 114 pieces; 8/1, 0.05 km; LNTH BT 3.6 %, UPCE at most 0.7 %; parity 0.00 km and UPCE BT −0.05 → 0) all re-derive from `pre_post_diff.csv` and `parity_bcfp.csv`. The measured POST commit `ff6e7ea2` differs from HEAD in `R/` only by a comment and the preflight comment.

## Enumeration

Artifacts that encode where the observation walk's cost lives or where `observations_province` lives, found by `git grep -n "observations_province"`, `git grep -ln "lnk_pipeline_prepare("`, `git grep -n "lnk_pipeline_access(\|lnk_access(\|observations *="`, `grep` of `data-raw/pretest_inputs.csv`, and `git grep "0\.47\.0"`:

| artifact | encodes | followed? |
|---|---|---|
| `R/lnk_pipeline_prepare.R` drop after the lifts | table lifetime | followed (removed, comment says why) |
| `R/lnk_pipeline_run.R` `on.exit()` drop | table lifetime | followed (added after setup, runs after the log handler; test pins it on the error path and as the last DROP) |
| exported `lnk_pipeline_prepare()` roxygen "Writes to" | what the phase leaves behind | **not followed** (finding 1) |
| `R/lnk_pipeline_prepare.R` internal roxygen of `.lnk_pipeline_prep_observations` | lifetime | followed ("lnk_pipeline_run() drops it") |
| RUNBOOK §2c / §5, `R/lnk_pipeline_run.R` comment | when the drop runs | followed, with an overstatement (finding 2) |
| `research/access_columns.md` | lifetime ("lives through break, classify and connect") | followed |
| `data-raw/wsg_run_one.R` (`cleanup_working = FALSE`) | kept working schema | followed (run drops it) |
| `data-raw/habitat_variants_build.R` (base via `lnk_pipeline_run()`, focal schemas kept; variant passes read no observations) | lifetime | followed |
| `R/lnk_compare_wsg.R` (through `lnk_pipeline_run()`) | lifetime | followed |
| `R/lnk_access.R` / `wsg_recompute_one.R` recompute (`observations = NULL`, keeps prior 2) | where code 2 is computed | followed (unchanged by design; CLAUDE.md "Owed" says so) |
| `data-raw/overrides_scope_time_349.R`, `observation_breaks_396/build_obs.R` | read/rename the table after prep | unaffected (they drop their schema / rename it themselves) |
| six accepted historical prepare callers (`exp_gradient_extra_breaks.R`, `habitat_thresholds_282/307`, `params_method_286`, `wetland_floor_311`, `discharge_wet_331`) | lifetime | not followed, accepted |
| `data-raw/pretest_inputs.csv` `R/lnk_pipeline_access.R` → `obs_upstream`; fresh `R/frs_network_features.R` → `obs_upstream`; `data-raw/pretest/obs_upstream.sql` | walk cost | followed |
| `data-raw/pretest_inputs.csv` `config.yaml` rows (`any`, `segments`, `observations`, `dams`) | cost of the new `observation_upstream` knob | followed: the knob only adds or removes the existence walk over the group's own records (`observations` x `segments`); the province walk runs under both values |
| `data-raw/pretest_inputs.csv` `R/lnk_pipeline_run.R` → `any` | which table the walk is handed (now `observations_province`) | not followed, latent: a future edit to that argument alone would pick no `obs_upstream` group. Pre-existing convention (run.R chose `<schema>.observations` before, also `any`), and masked in this branch because `R/lnk_pipeline_access.R` changed too; not raised as a finding |
| RUNBOOK §8d pre-run gate input list | inputs | followed (`obs_upstream` named) |
| `R/lnk_preflight_fresh.R` (formals + `min_version` from DESCRIPTION) | fresh capability | followed: formals cannot see `"distinct"`, but `version_ok` reads the 0.48.0 floor, so a 0.47.0 host fails the preflight |
| `DESCRIPTION` `Imports` floor and `Remotes` pin | fresh 0.48.0 | followed |
| `inst/extdata/vocabulary.csv`, `.lnk_vocabulary_spec_acc()`, RUNBOOK §6b, `research/output_vocabulary.md` | the acc rule set now depends on a bundle key | followed (digest hashes the resolved value; acc-v2 / acc-bcfp-2 retired) |
| `R/lnk_log.R` `.lnk_log_inputs()` | provenance of what code 2 read | followed: `bcfishobs.observations` is fingerprinted whole-table, so province records are covered |
| `R/lnk_persist_init.R` (`has_observation_key_upstr` not persisted) | meaning of the walk's second column | followed (meaning changed under the gate, nothing persisted or read) |
| CLAUDE.md #396 fact "Code 2 reads only the group's own records" | where code 2 reads | followed (marked superseded) |
| `R/lnk_pipeline_break.R`, `R/lnk_pipeline_access.R` roxygen, both `config.yaml` comments | where code 2 reads | followed |
