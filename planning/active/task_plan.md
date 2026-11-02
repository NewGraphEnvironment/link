# Task: A minimal network for tuning, with parent attributes on the full network (#415)

`lnk_pipeline_break()` cuts streams at observations, gradient barriers, falls, definite barriers, habitat end points and crossings. Each cut shortens a segment, and a segment's gradient is averaged over its length, so the cuts change the gradient a habitat rule reads:

- **Observations make the gradient depend on the outcome.** On link 0.66.0's build (every observation a break), 86 % of electrofishing visits that caught a modelled species sat on a segment starting at the visit, against 10 % of visits that caught nothing (median segment 113 m against 305 m). `observation_breaks: top_per_species` (#396) cuts fewer, but a species' highest record on a stream is still a catch.
- **Crossings and habitat end points** don't depend on fish, but they cut segments at places unrelated to the stream's form.
- A downstream tuning of chinook rearing moved its gradient limit when the gradient source alone changed, so the tuning is sensitive to this.

Connectivity needs those cuts; habitat measurement doesn't.


## Context

Every cut shortens a segment, and a segment's gradient is the elevation drop over its own
length (fresh's `frs_col_generate()`, recomputed on every piece), so the observation,
habitat-endpoint and crossing cuts move the gradient a habitat rule reads, and observation
cuts make it depend on where fish were caught. #415 adds a *minimal network*, cut only at
`gradient_minimal`, `falls` and `barriers_definite`, built from the same commit and inputs
as `default`, with its own `cut` token; later, each full-network segment gets the id and
gradient of the minimal segment it lies in.

Agreed sequencing (CLAUDE.md status, 2026-11-01): the other session builds #432 (KO and RB
paused, off means off). This branch builds #415's minimal bundle and cut token in parallel
with it; the proof builds run after #432 merges, with #433's keep-or-drop measurement
folded in; then the pre-run gate on the minimal schema and a minimal-breaks provincial run
from m4.

## Decided at the gate (operator, 2026-11-01)

- **Bundle `default_minimal`, schema `fresh_default_minimal`**: a thin bundle, `extends:
  default`, overriding only `pipeline: schema` and `pipeline: break_order`.
- **Token `cut-min`.** The cut axis is keyed `cut-<source set>[-<observation qualifier>]`
  (`cut-full-top`, `cut-full-ssf-all`, now `cut-min`); the pattern leaves room for coarser
  networks later, `bar` (falls and definite barriers only, no access-gradient cuts) and a
  no-cut FWA network. The keying sentence goes in RUNBOOK §6b; no reserved rows are added.
- **Two PRs.** This branch: bundle, token, tests, docs, and the proof script ready to run,
  smoke-tested on one small group. A second branch after #432 merges: the proof builds on
  BULK plus two or three chinook-rearing and crossing-heavy groups, `research/`, and the
  parent-attribute issue drafted from what the proof shows.
- **Parent attributes by post-hoc join into their own table** (`<full schema>.streams_parent`:
  `id_segment, watershed_group_code, id_segment_minimal, gradient_minimal, length_minimal`,
  plus the minimal build's `config_hash` / run), largest measure overlap per
  `blue_line_key`, slivers under 1 cm dropped. The full network and its token stay as they
  are. Reading the parent's gradient on the full network is a `grad` token of its own
  (knowledge archives setups by it). Not built in this PR; recorded here as the design the
  follow-up starts from, with the proof's prototype join as its measurement.

## What the consumer needs (knowledge repo, read 2026-11-01)

- **knowledge#120** (chinook rearing tuned on minimal segments) scores one key on six setups
  from one evidence build: `published` (full, own gradient), `minimal` (own gradient),
  `minimal, other access classes`, `full, parent gradient`, `Atlas line` (`grad_fwa`),
  `fixed window` (later). It needs both networks from one build and, on the full network,
  each segment's minimal parent id and gradient, so `minimal` and `full, parent gradient`
  read the same gradient at every visit. Its mechanics check on link's test groups: every
  visit lands on a segment on both networks, ids join, the walk starts where it should on
  longer segments, the parent-gradient setup reads its parent's value.
- **The gradient trail is the `grad` axis.** knowledge archives a run by link's four
  tokens (`knw_archive_setup()`, `tune/<key>/<cut>.<acc>.<grad>.<flow>/`, `grade_record.R`),
  and its setups differ only in which gradient a rule reads. So the parent reading needs
  its own `grad` token (a `grad-min` shape: "each segment reads its minimal parent's
  gradient"), and the Atlas-line reading knowledge already runs as a sensitivity would take
  one too. Not minted in this PR; recorded in the parent-attribute design. (Plan review:
  knowledge's grade record already carries `curve_grad`, so the reading is distinguishable
  in the record today, not in the archive path, where two setups on one build collide.)
- **knowledge#131** gates each species' population on `streams_access.access_<sp> > 0` on
  the minimal network (overrides included) with leave-one-out through link#434's lifted
  barrier table; today it drops visits with a pre-override natural barrier below through
  `knw_link_barrier_dnstr()`, which reads `<schema>.barriers` (`barrier_source`,
  `blocks_species`) with `fwa_downstream()`. So the minimal schema must carry
  `streams_access` and `barriers` as the full one does; the full pipeline gives both.
  knowledge reads no `streams_mapping_code`.
- **Placement assumes observation cuts.** `knw_link_place()` takes the segment whose start
  lies within `[measure - 1, measure + 5]` m of the visit, else the segment containing the
  point. On the minimal network the window finds nothing at most visits and the fallback
  takes over. The proof counts placement by branch on both networks and the km of segment
  above and below each visit, so knowledge#120's "the walk starts where it should" has a
  number before its code runs.
- **knowledge#132** reviews the access gradient classes; the `minimal, other access
  classes` setup is a second minimal network under another `acc` token, which the
  `cut-min` keying already allows (same cut token, different acc).

## What exploration settled (no code change needed for the network itself)

- `lnk_pipeline_break()` already supports omitting sources: `R/lnk_pipeline_break.R:114-136`
  loops over `cfg$pipeline$break_order`; a partial order is tested
  (`test-lnk_pipeline_break.R:251,292`). Nothing in prepare, access, classify or persist
  reads `observations_breaks`, `habitat_endpoints` or `crossings_breaks`.
- `extends:` merges `pipeline` one level deep (`R/lnk_config.R:212-249`), so a child
  `break_order:` list replaces the parent's wholesale (`~` would delete the key and fall
  back to all six). Not tested today; this PR adds the test.
- The cut spec (`R/lnk_vocabulary.R:127-145`) drops `observation_breaks=` when
  `observations` is absent. Expected spec:
  `break_order=gradient_minimal,falls,barriers_definite;gradient_classes=1500:0.15,2000:0.2,2500:0.25,3000:0.3;barrier_inputs=user_barriers_definite,user_barriers_definite_control,user_habitat_classification`.
  The other axes resolve to `acc-v4 grad-seg q-fwapg`. The resolver prints the real spec
  when it refuses; paste that, not this derivation.
- **The issue's overlay premise is backwards.** `frs_habitat_overlay()` and
  `lnk_habitat_gate()` keep a flag only where the segment lies wholly inside an overlay
  range, so without endpoint cuts the overlay applies to *fewer* segments. The proof
  measures under-application (km of overlay range on segments that straddle an end).
- **Strict containment fails near records.** Observations cut first in the full build and a
  later cut within 1 m of an existing end is skipped (`frs_break_apply`, RUNBOOK §2), so a
  minimal cut can be absent from the full network. The superset check must allow a 1 m
  tolerance and the parent join must use largest overlap.
- Species 0/1 access boundaries stay at cuts (each species' minimal reduction cuts every
  access frontier). Code 2 reads `observations_province` from each segment's start, so the
  segment holding a species' top record reads 2 to the next cut. `dam_dnstr_ind` and
  `remediated_dnstr_ind` shift up to the next cut.
- `streams` has no `ADD COLUMN` path (only log tables align, `R/lnk_log.R:539-550`),
  `schema_consolidate.R` copies only shared columns, and the export's column list is a fixed
  contract (`inst/extdata/schemas/habitat_fwa_v1_segment.yaml`). Hence the own-table design.
- `study_area_run.sh` refuses any non-bcfishpass config without `--schema=` (lines 460-466);
  `pretest_inputs.csv` already maps `configs/{config}/config.yaml` and `README.md`.
- Tests that enumerate bundle directories pick the new one up (`test-dictionaries.R`,
  `test-lnk_config.R:397`, `test-lnk_log.R:308`); `test-lnk_vocabulary.R:94-107` lists
  bundles by name and needs the new expectation.
- Installed fresh is 0.52.0 against the `v0.48.0` pin; `link` installed is 0.74.0 (we run
  by `load_all`). Neither blocks this PR.

## Phase 1: the `default_minimal` bundle
- [ ] `inst/extdata/configs/default_minimal/config.yaml`: `name`, `description` (what it
  is for, what it cuts at, the overlay and code 2 consequences), `extends: default`,
  `pipeline: schema: fresh_default_minimal`, `pipeline: break_order:` the three sources with
  the comment that the list replaces the parent's. No `files:` (everything inherited).
- [ ] `inst/extdata/configs/default_minimal/README.md` on the `default_tuned` pattern: thin
  bundle, inherited files, what differs, how to run it (`--config=default_minimal
  --schema=fresh_default_minimal`, `LNK_SCHEMA` for `wsg_run_one.R`).
- [ ] `test-lnk_config.R`: `default_minimal` extends `default`, `break_order` is exactly the
  three sources (a child list replaces the parent's), every other `pipeline` key and every
  file is inherited, schema is `fresh_default_minimal`; `lnk_config_verify()` clean.
- [ ] `test-lnk_pipeline_break.R` (or the vocabulary test): `.lnk_break_order()` on the
  bundle returns the three, and a child `break_order: ~` is refused or documented
  (decide from what `lnk_config()` does; refuse is preferred, one check in the merge).

## Phase 2: the `cut-min` token
- [ ] Run `lnk_vocabulary_resolve(lnk_config("default_minimal"))`, take the spec the
  refusal prints, add the `cut-min` row to `inst/extdata/vocabulary.csv` (definition in
  prose: cut at gradient barriers only where a modelled species' access changes, falls,
  user-definite barriers; no observation, habitat end point or crossing cuts; the bundle
  declares the three barrier inputs), `introduced` = `0.76.0`, the version Phase 4 bumps
  `DESCRIPTION` to (no test ties the two; the Validation check below does).
- [ ] `test-lnk_vocabulary.R:94-107`: `default_minimal` resolves to `cut-min acc-v4 grad-seg
  q-fwapg`; the append-only test passes locally against `origin/main`.
- [ ] RUNBOOK §6b: the cut keying written as the abstract pattern, not the one name:
  `cut-<source set>[-<qualifier>...]`, with a short table of source sets (`full`: every
  source; `min`: access-gradient positions, falls, definite barriers; and the shapes the
  pattern leaves room for, a barriers-only set and a no-cut FWA set, named only when
  built) and of qualifiers (`top`, `all`, `ssf`, each saying which key it reads). `cut-min`
  joins the axis table's examples; §7's bundle list names `default_minimal`. The research
  file's naming paragraph gets the same pattern.
- [ ] `research/output_vocabulary.md`: the config table gains `default_minimal`; the
  verified date moves.

## Phase 3: the proof script, ready to run (after Phase 2: a build refuses a config with no live token)
- [ ] `data-raw/logs/minimal_breaks_415/README.md`: question, groups to build (BULK plus
  two or three chinook-rearing and crossing-heavy groups, picked by a query in the README
  when the proof runs), the two scratch schemas (`zz415_default`, `zz415_minimal`), the
  order (downstream-first per schema, serial because both share `working_<wsg>`), and the
  checks below. States that the real run waits for #432 and folds in #433.
- [ ] `run.sh` adapted from `observation_breaks_396/run.sh`: both bundles from one commit
  into the two scratch schemas with `LNK_SCHEMA`, then `wsg_recompute_one.R`, `status.tsv`
  with minutes and row counts per group and schema.
- [ ] `proof.R` adapted from `observation_breaks_396/pre_post_diff.R` (overlap pieces per
  `blue_line_key`, 1 cm slivers dropped, coverage both ways), writing one CSV per check:
  superset (every minimal cut matches a full cut within 1 m; each full segment's
  largest-overlap parent, and the km that straddle by more than 1 m), access code 2 km per
  species both builds, species 0/1 access identical on every piece (asserted), crossing
  fields (`dam_dnstr_ind`, `remediated_dnstr_ind`, `has_barriers_*_dnstr`) km moved,
  overlay under-application km, connectivity-pass drops (rearing km lost to the
  spawning-within-10 km rule) both builds, gradient agreement (minimal segment gradient
  against the length-weighted full gradient over its pieces; report the distribution of the
  difference), a `breaks_diff.R`-style census showing the minimal schema's breaks all
  carry a named source, and a placement check: the bcfishobs records of the groups placed
  by `knw_link_place()`'s rule on both networks (start-window branch against containing
  segment, offset from the start, segment length), counted per branch and per network.
  Plan review: 396's script reads `zz396_cuts.obs_<wsg>` (built by its `build_obs.R`) for
  its `at_top` measures; `proof.R` drops those measures rather than carry the builder, and
  its 0/1 assertion excludes slivers (`len < 1.01`), because a minimal cut skipped in the
  full build by the 1 m rule leaves a sub-metre piece whose access differs by construction.
- [ ] Access on the minimal network (the issue's third checkbox): the proof reports
  `access_<sp>` km by code (-9, 0, 1, 2) per species on the minimal schema beside the full
  one, and for each crossing-based field (`dam_dnstr_ind`, `remediated_dnstr_ind`,
  `has_barriers_*_dnstr`) states in the README what it means on a segment that was not cut
  at the crossing. Whether to flag or drop those fields on the minimal network is the
  follow-up's call, written there as a question. `subsurfaceflow` stays off, as `default`
  leaves it; the bundle inherits that and the README says so.
- [ ] The parent-table prototype inside `proof.R`: the largest-overlap join from each full
  segment to its minimal parent, written as a CSV per group (`id_segment, wsg,
  id_segment_minimal, gradient_minimal, length_minimal, overlap_m, straddle_m`), so the
  follow-up issue's table design is measured, not guessed.
- [ ] Smoke run on one small group (ADMS) at this commit into the two scratch schemas with
  `LNK_GUARD_DOWNSTREAM=warn` (as 396's `run.sh` sets it; the scratch schema holds no
  downstream group), the recompute's pass rule written before the run as 396 did ("failed
  only on the downstream-dam post-condition" passes), schemas dropped after. Pass line: no
  violation outside slivers, every minimal cut matched within 1 m, every CSV written. The
  smoke output is not evidence and is not committed beyond the README's note that it ran.

## Phase 4: release bookkeeping and the issue
- [ ] `DESCRIPTION` to `0.76.0` (the token row names it), `NEWS.md` entry.
- [ ] CLAUDE.md status entry (what landed, what is owed, facts not worth re-deriving: the
  overlay direction, the 1 m containment caveat, the own-table design).
- [ ] Edit the #415 body: the overlay bullet reads "under-applies", the four proposed
  checkboxes note the two-PR split and link this PR, the parent-attribute design is written
  in, and `cut-min` is named. No new issue filed here.

## Owed at the end (reported, done after merge)
- [ ] Second branch after #432 merges: the proof builds, `research/minimal_network.md`
  (or a section of `bcfp_segmentation_parity.md`), #433's measurement folded in, and the
  parent-attribute issue drafted from the proof (the `streams_parent` table, its `grad`
  token, and whether the Atlas-line reading gets one), with knowledge#120's mechanics
  check named as its acceptance.
- [ ] Pre-run gate (#372) on `fresh_default_minimal` before the minimal provincial run.

## Validation
- [ ] `devtools::test()` clean, `lintr::lint_package()` clean, `devtools::document()`,
  `pkgdown::check_pkgdown()`.
- [ ] `/code-check branch` before the PR.
- [ ] `lnk_vocabulary_resolve(lnk_config("default_minimal"))` prints the four tokens;
  `lnk_vocabulary_resolve(lnk_config("default"))` unchanged.
- [ ] The vocabulary append-only test run locally in this checkout, and the `cut-min` row's
  `introduced` equals `packageVersion("link")` (one line in R; no test ties them).
- [ ] The smoke run completes on ADMS and `proof.R` writes every CSV.
- [ ] PWF checkboxes match landed work; `/planning-archive` on completion.

Parked (operator, 2026-11-01): approval covered the baseline only, written and pushed. The run-to-PR
mandate starts at the `### Resume` block in `progress.md`.
