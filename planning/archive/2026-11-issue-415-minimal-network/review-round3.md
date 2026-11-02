## Checklist read

- **code-check.md:** the prose of all 14 H3s under `## Mechanisms`, table rows skipped, with long paragraph lines cut at 420 to 600 characters by my reader (so the tail of some paragraphs was not read). From `## Rules that stand alone`, index lines only.
- **code-check-shell.md:** "A value validated with one numeric grammar and consumed with another", "Over Tailscale SSH to a Mac" in full. The rest index lines only.
- **code-check-r.md:** "An `information_schema` lookup by the literal table name", "Postgres row order" (first part). The rest index lines only.
- **code-check-spatial.md:** "FWA `upstream_route_measure`". The rest index lines only (no spatial tool in this diff).

Nothing here was built. Code ran only in two temporary worktrees (removed), for `lnk_vocabulary_resolve()` and compiled predicates. The DB was read only by catalog queries.

## Mechanism

Two mechanisms produced the earlier rounds' defects and both are still the right lens:

1. **Prose stating a behaviour nobody executed against the code, usually with a universal in it.** "Independent of the records", "only lose km", "every source", "stream rule only". Each reads true of the case its author had in mind (ADMS, a salmon-only frontier, a clean run) and false of the population the sentence quantifies over.
2. **A script's stop reading a stand-in for the state it means.** `log` for "the recompute ran", `least()` for "differs", a filed group for "applies here", a loop that ended for "the database went quiet". It passes on any state where the stand-in holds and the state does not.

The enumeration below finds one remaining universal of kind 1 (finding 3) and two stand-ins of kind 2 (findings 1 and 2).

## Enumeration A

Every claim in the added prose, walked by sentence. "Code" means read; "smoke" means `smoke415c` / `smoke415d` ADMS CSVs (15,716 full, 11,920 minimal segments).

### NEWS.md top entry

| # | Claim | Verdict | Checked against |
|---|---|---|---|
| 1 | "far fewer cuts" | pass | smoke: minimal 1,646 non-FWA cuts (census 8,434 less 6,788 FWA starts); full 15,716 segments vs 11,920. One group only, and the entry says the proof groups are not run |
| 2 | cuts only at gradient barriers where a modelled species' access changes, falls, user-definite | pass | `break_order`; `prep_minimal`; census has no third source |
| 3 | no fish record or crossing cuts a stream at its own position | pass | `frs_break_apply` called only in `lnk_pipeline_break.R:130` over `break_order`; `cut-min` lists none of them |
| 4 | meant for tuning thresholds | intent | |
| 5 | records reach cuts through observation lifts; lifted = no longer that species' cut; another species' barrier or a falls may still cut; positions above can become cuts | pass | `prepare.R:752` per-species `NOT EXISTS`, reduced after; falls unreduced source |
| 6 | `default`, `default_tuned`, `bcfishpass` do not change | pass | only `R/` change is the refusal; no file of theirs in the diff |
| 7 | named `cut-min` with default's other three tokens | pass | resolved at HEAD: `cut-min acc-v5 grad-seg q-fwapg`; smoke `builds.csv` |
| 8 | keyed `cut-<source set>[-<qualifier>...]`, written in the RUNBOOK | pass | RUNBOOK:889 |
| 9 | `break_order: ~` refused in an extending bundle; would have deleted the list and fallen back to defaults | pass | `lnk_config.R:240`; `.lnk_break_order()` default; the test |
| 10 | "Nothing has been modelled on it yet" | pass, loose | no output kept; ADMS smokes built and dropped, and the proof README says so |
| 11 | scripts compare group by group; not run on proof groups | pass | `proof.R` loop; README |
| 12 | parent id and gradient is a follow-up | intent | task_plan |

### `cut-min` definition (vocabulary.csv)

| # | Claim | Verdict | Checked against |
|---|---|---|---|
| 13 | "in this order" gradient, falls, definite | pass | spec string, loop over `break_order` |
| 14 | classes 15, 20, 25, 30 | pass | spec; each species takes classes at or above its access gradient (0.15 to 0.25), so 30 is used |
| 15 | kept only where a modelled species' access changes | pass | reduction per species. Includes a promoted species that gets no access code, as `cut-full-top`'s wording does |
| 16 | which the acc token decides | pass | acc spec covers species, gradients, lifts, presence |
| 17 | no cuts at observations, end points, crossings | pass | as 3 |
| 18 | lifts sentence | pass | as 5 |
| 19 | bundle declares definite, control, UHC | pass | spec `barrier_inputs`; `cfg$files` identical to default's (test) |
| 20 | cuts also move with data, recorded in the log | pass | same sentence as `cut-full-top` |

### `default_minimal/config.yaml`

| # | Claim | Verdict | Checked against |
|---|---|---|---|
| 21 | description's cut list and lifts sentence | pass | as 2, 5 |
| 22 | inherits everything else | pass | test |
| 23 | overlay applies only to a segment wholly inside a range, reaches fewer km | pass | `lnk_habitat_gate.R:113-114`; fresh `frs_habitat_overlay.R:273-274`; smoke applied 114.9 vs 122.0 km CO |
| 24 | code 2 reads from each segment's start; segment holding a species' top record reads 2 to the next cut | pass | RUNBOOK §2c, smoke `access_km`. A top within 1 m of a start is the known exception (§2c), rare on this network |
| 25 | crossing field reads below the start; crossing counts only from the next cut above | pass | walk `b <= start + 1`; smoke `has_barriers_anthropogenic` 401.6 km full only, 0 minimal only |
| 26 | `dam_dnstr_ind`, `remediated_dnstr_ind` move either way | pass | `lnk_pipeline_access.R:381-448`; smoke 0.65 / 19.36 and 1.97 / 10.47 km |
| 27 | comment: list replaces wholesale | pass | `.lnk_config_merge` |
| 28 | comment: tables still built, nothing but the cuts reads them | pass | grep of `observations_breaks`, `habitat_endpoints`, `crossings_breaks` in `R/` and `data-raw/`: only `lnk_pipeline_break.R` (and a script's own `working.` tables) |
| 29 | comment: `~` refused at manifest load | pass | test |

### `default_minimal/README.md`

| # | Claim | Verdict | Checked against |
|---|---|---|---|
| 30 | thin, overrides two keys | pass | test |
| 31 | `$chain` lists both | pass | test |
| 32 | tokens default's except cut | pass | test |
| 33 | `subsurfaceflow` off | pass | `break_order` |
| 34 | gradient is drop over own length, so each cut moves it | pass | `grad-seg`; smoke `gradient.csv` |
| 35 | observation cut sits at a record; others unrelated to form | pass | |
| 36 | "with no record cutting the segment it is scored on" | pass | qualified by the next paragraph |
| 37 | "not independent"; lifts; a record far upstream can move a cut below it | pass | as 5 |
| 38 | overlay bullet | pass | as 23 |
| 39 | code 2 bullet | pass | as 24 |
| 40 | "Species access codes 0 and 1 stay at cuts, because each species' minimal reduction cuts every access frontier" | **FAIL** | finding 3 |
| 41 | crossing bullet | pass | as 25, 26 |
| 42 | `streams_access` and `barriers` persist as for `default` | pass | same run path; smoke |
| 43 | the two run commands | pass | `wsg_run_one.R` reads `LNK_SCHEMA`; ADMS guard passes (smoke exit 0) |
| 44 | needs `--schema=` as for every bundle but `bcfishpass` | pass | `study_area_run.sh:460` |
| 45 | pre-flight refuses with no gate record | pass | `study_area_run.sh:1199-1206` |
| 46 | `pretest_pick.R` refuses no `log`; `--minutes-schema` reads under the run's config | pass | `pretest_pick.R:65-69`, `pretest_history_sql` |
| 47 | `--pretest-note` records an override and needs the schema first | pass | `pretest_override.sql` creates the table, no schema |

### `data-raw/logs/minimal_breaks_415/README.md`

| # | Claim | Verdict | Checked against |
|---|---|---|---|
| 48 | #432 moved which species cut | pass | NEWS 0.76.0, `prep_minimal` reads `cfg$species` |
| 49 | smoke ADMS at `e333ec97`, fresh 0.52.0 against the `v0.48.0` pin | pass, ages | `smoke415c/proof/builds.csv`; DESCRIPTION. See the note under Findings: `proof.R` has since changed |
| 50 | run.sh and recompute passed; every CSV written; schemas dropped | pass | status.tsv, 13 CSVs, no `zz415%` schema now |
| 51 | swapped schemas stopped on commit-and-token, superset, census | pass | progress.md records the swap; the arms read correctly |
| 52 | `builds.csv` records version; stops when builds differ; no pin compare | pass | `proof.R:96-106` |
| 53 | proof reads channel width only | pass | `src` is `<schema>.streams`; stop at :313 |
| 54 | schemas, order, serial, default first so working holds minimal | pass | `run.sh:94-97`; census `same` in smoke after recompute |
| 55 | run.sh refuses tracked changes; proof names one clean sha, tokens, one acc and flow | pass | `run.sh:32`, `proof.R:96-106`. Does not tie the proof's own read to that sha: finding 1 |
| 56 | recompute pass rule; check runs after the work commits | pass | `wsg_recompute_one.R:212` is the last call in `recompute_wsg()`, after `.mc_persist` |
| 57 | scratch holds no groups below | pass | |
| 58 | `status.tsv` records `yes` or `postcondition` | pass, arm unrun | read; every smoke exited 0 |
| 59 | table rows: each file's question and stops | pass | see B. Rows checked against code one by one, `access_km` codes -9, 0, 1, 2 against `lnk_pipeline_access.R:27` |
| 60 | connectivity: predicate ORs every rear rule; polygon split | pass | printed BT rear predicate: lakes + `fwa_manmade_waterbodies_poly` + wetlands, as `in_poly` reads |
| 61 | placement follows `knw_link_place()` | pass | `.knw_place_sql`: `BETWEEN m - 1 AND m + window`, default 5, else containing |
| 62 | why 1.01 m; later cut within 1 m skipped | pass | fresh `frs_break.R` lines 34-35 (`> 1` from each end); RUNBOOK:301-303 |
| 63 | `has_barriers_*` lose km apart from pieces of about 2 m or less | pass | reasoned: the crossing cuts the full network unless within 1 m; smoke 0 minimal only |
| 64 | `dam_dnstr_ind`, `remediated_dnstr_ind` next feature | pass | as 26 |
| 65 | `has_barriers_<sp>` should move little; another group's barrier not cut, access_open would show | pass | smoke 0 / 0. Contradicts row 40, which is the finding |
| 66 | mapping codes inherit; knowledge reads none | pass | grep of knowledge `R/ data-raw/ inst/ tests/` for the four field names: no hit |
| 67 | `subsurfaceflow` off | pass | |

### RUNBOOK and research additions

| # | Claim | Verdict | Checked against |
|---|---|---|---|
| 68 | §2c: no record cuts its streams; inherited key has no effect | pass | `observation_breaks` table is built and read by nothing; spec leaves the key out |
| 69 | §6b source set and qualifier tables | pass | the two `cut-full-*` specs, `cut-min` spec |
| 70 | a set with no observation source takes no `top` or `all` | pass | `.lnk_vocabulary_spec_cut()` |
| 71 | same cut under another acc is another network | pass | next paragraph, #326 |
| 72 | §7: thin bundle, replaces, refused | pass | as above |
| 73 | research: six bundles, eight live tokens | pass | 6 bundle dirs; 8 rows with no `retired`: `cut-full-top`, `cut-full-ssf-all`, `cut-min`, `grad-seg`, `q-fwapg`, `q-wet-fill`, `acc-bcfp-4`, `acc-v5` |
| 74 | research table cells | pass | `acc-v5` now on all three `default*`; round 2's stale cells gone |
| 75 | research key paragraph | pass | as 69 |

### CLAUDE.md top Status block

| # | Claim | Verdict | Checked against |
|---|---|---|---|
| 76 | cuts and tokens (0.77.0) | pass | DESCRIPTION |
| 77 | no R modelling code changed; only `.lnk_config_merge()` refusal | pass | `git diff` of `R/`: one file, one hunk |
| 78 | two-PR split, mechanics pointer in §6b | pass | task_plan:36; RUNBOOK:754, :889 |
| 79 | owed items; files named exist | pass | `research/species_paused.md`, `pick_groups.sql` |
| 80 | knowledge#120, knowledge#131 | pass | both open, titles match |
| 81 | gate cannot pick; routes | pass, accepted | open decision per the brief |
| 82 | not independent; falls and definite unreduced | pass | as 5 |
| 83 | issue's framing quoted | pass | #415 body line 1 |
| 84 | overlay under-applies, first draft had it backwards | pass | as 23; #415 body line 19 said "over-extends" |
| 85 | full segment not always inside one minimal; 1.01 m; largest overlap | pass | `proof.R` parent query |
| 86 | `streams` has no `ADD COLUMN` path; export list is a contract | pass | `.lnk_log_align_columns()` called only for log and artifact tables; `lnk_scenario_export.R:14` |
| 87 | knowledge archives by four tokens | pass | knowledge `R/archive.R:62-65` |
| 88 | child list replaces | pass | |
| 89 | both-way fields; `has_barriers_*` lose km apart from slivers | pass | as 26, 63 |
| 90 | three unused tables, "opt-out" comment | pass | as 28; `lnk_pipeline_break.R` comment exists |

## Enumeration B

Every stop, from a grep of `stop(`, `stopifnot`, `defects`, `exit`, `return 1`, `fail=1`.

### `proof.R`

| Line | Means to detect | Can a state pass that should fail? |
|---|---|---|
| 43 | no groups given | no |
| 44 | malformed group code | no |
| 82 | no build | no |
| 89 | no recompute | no |
| 96-106 `builds_ok` (sha, `recompute_link_sha`, NA sha) | builds and recomputes of one commit | Not within the builds. **Yes for what the proof itself reads**: finding 1 |
| dirty flags `%in% FALSE` | clean tree | Only an untracked `R/` file, which `load_all()` loads and the predicate leaves out by design; repo-wide |
| `token_ok`, single `acc`, single `flow` | right networks | no (NA token makes `builds_ok` NA, and `if` errors, loudly) |
| fresh version single | one fresh | A dev fresh at one version string between builds; `fresh_sha` not read. No route in this workflow. Not reported |
| `!anyNA(date_end)` | a closed build | no |
| `recompute_start >= date_end` | recompute read this build | no; a re-model after the recompute fails it |
| `recompute_end` set or `BLOCKED` in notes | recompute succeeded or failed only on the post-condition | no by reading: `.lnk_log_recompute_fail` appends to `notes` and leaves `date_end` NULL. The BLOCKED arm has not run; ADMS exits 0 |
| 164 coverage | pieces cover both sides | no; two compensating gaps still move `km_pieces` off both |
| 198 species setequal | species on one network only | no |
| 313 mad | group on `mad` | no; positive control TRUE for BT under `model = "mad"`. 188 of 188 groups are `cw` today |
| 455 superset | minimal cut absent from full | no; empty side reaches 164 first |
| 456 access | species reads differently | no for pieces at or above 1.01 m. Slivers are counted and printed, by design |
| 457 missing access row | row lost to the join | no |
| 458 census `none` | a cut with no named source | no; a stray source within 1.01 m of a named one is indistinguishable and harmless |
| 458 `working_schema_not_this_build` | working schema is another build | no; count and summed starts |
| 459 stop | | Header says stops come "after every CSV is written"; 82, 89, 164, 198, 313 stop earlier. They fail loud, so not reported |

### `run.sh`

| Line | Means to detect | Can a state pass that should fail? |
|---|---|---|
| 18, 20, 25, 36 | usage, repo, out dir, sha | no |
| 32-34 | tracked changes | A failing `git status` prints nothing and reads clean; `proof.R`'s dirty flags and sha are the backstop. Not reported |
| 38, 45 | database reachable | no |
| 42-51 | database quiet for the bound | **Yes**: finding 2. Sampled once a minute, so a session between samples passes too; that is the gate's stated grain |
| 67 | checkout present | no |
| 75 | model or recompute exit 0 | A `SKIP` at exit 0 (`wsg_run_one.R:68`) passes here, then `proof.R:82` or the sha check stops. Not reported |
| 77-79 | exit 1 with `BLOCKED (link#227)` | no by reading: the log is overwritten per step, and the check is `recompute_wsg()`'s last call. Arm not run |
| 88, 90, 95-101, 103-105 | any step failed | no; carries on and exits 1 at the end |

## Findings

- **[severity: fragile]** data-raw/logs/minimal_breaks_415/proof.R:68-70, :96-106, :309 — the commit check ties the builds to each other and never to what the proof reads. `cfg`, `loaded` and `params` come from the proof's own checkout, and `overlay.csv` (`user_habitat_classification`) and `connectivity.csv` (thresholds, rules, and `frs_habitat_predicates()` from the installed fresh) are computed from them. So a state that should fail passes: builds at commit A, then a commit, a pulled weekly CSV sync, a threshold edit or a fresh install before `proof.R`. Every builds check still reads one clean commit, and the two CSVs compare the persisted flags with another bundle's rules and report the difference as connectivity or overlay km. `run.sh` and `proof.R` are separate commands, and the README's "Edit nothing in the checkout while it runs" names the run. Stop unless `git rev-parse HEAD` equals the builds' `link_sha` with a clean tree (or compare `.lnk_config_hash(cfg)` with the logged `config_hash`), and `packageVersion("fresh")` equals `fresh_version`. Beside round 2's `builds_ok` fix, not a defect in it: the same stand-in one step along.
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** data-raw/logs/minimal_breaks_415/run.sh:42, :49 — inside the fix for round 1 finding 7 (the quiet gate falling through). A non-integer `LNK415_QUIET_MIN` (`5m`, `abc`) makes `[ "$quiet" -lt "$QUIET_MIN" ]` an error, which is false in both tests, so the loop never runs, the refusal never fires, and it prints "gate passed (quiet minutes 0, waited 0 min)", the same line `0` prints. Measured on a copy of those lines: `5m` and `abc` pass with `integer expected` on stderr, `2` against a busy stub exits. Builds then run beside whatever is on the database, on timings the README records. Validate once where it is read: `case "$QUIET_MIN" in ''|*[!0-9]*) exit 2;; esac`.
  - **Rule:** code-check-shell.md "A value validated with one numeric grammar and consumed with another"

- **[severity: fragile]** inst/extdata/configs/default_minimal/README.md:21 — "Species access codes 0 and 1 stay at cuts, because each species' minimal reduction cuts every access frontier" is a universal the code names an exception to. `.lnk_pipeline_prep_minimal()` lifts by this group's own `barrier_overrides`, while the access view reads the province-wide table; its comment (R/lnk_pipeline_prepare.R:708-716) says "where another group lifts its copy of a shared barrier and this group does not (group-filtered controls), that position still prunes the frontier above it here". The proof README:49 also says "A barrier of another group is not cut here, which `access_open.csv` would show", so the two documents disagree on one network. CLAUDE.md records 2 such rows today and #326's 27 segment-species 1.07 to 1.43 m from a break. Not counted on this network; only ADMS has been read, at 0 pieces. The sentence matters because a reader of a non-zero `access_open.csv` would take it for a bug in the build rather than this family. Say "stay at cuts, apart from a shared barrier another group lifts and the metre-rounded cases, which `proof.R`'s access check measures". Not inside an earlier fix; same class as round 1's "only lose km".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

Not findings, for the record:

- `README.md`'s smoke line names `e333ec97`, and `proof.R` has changed since (`git diff e333ec97 HEAD` touches 13 lines, including the recompute commit check). `smoke415d` at `1ad2e6f9` ran HEAD's `run.sh` and `proof.R` and passed with the new columns populated, so the sentence is true of its commit and can be moved to the newer one when this round's fixes land.
- Neither `BLOCKED` arm (`run.sh:77`, `builds_ok`) has run on real data, because ADMS has no dam on its path. Read as correct; the first dam-blocked group in the real proof runs them.
