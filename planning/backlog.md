# link backlog: move order

**Verified:** 2026-11-09 against 118 open issues · **Produced by:** a read of every open issue body
(`gh issue list --state open`) and its comments; each premise checked against `origin/main` (f8a45c29), NEWS,
the `CLAUDE.md` status sections and `git log`; the open-issue reference graph (#402 is named by 8 open issues,
#377 by 7, #398 and #369 by 5, #400 and #444 by 4); the state of every peer issue a batch waits on (knowledge,
fresh, fwapg, crate, floodplains, and the infrastructure repository) · the pass's own issue, #468, whose
`planning/archive/` holds the read (one digest per issue)

How to use this file: `/backlog-sweep` writes it. Take the first move in **Moves** that is not
ticked and not **waiting**; `/planning-init <umbrella>` plans it, one phase per batch, one PR.
`/gh-pr-merge` step 9c ticks the move on merge; `/compact-prep` names the next. A `NONE` from
`backlog_moves.sh next` that names batch sections means those batches have no move yet: run
`/backlog-sweep` again, the backlog is not finished.

## Moves

| move | umbrella | batches | state |
|---|---|---|---|
| - [ ] 1 | UMB-1 | 1: the parent gradient and the grad tokens (4 issues) | open: start here |
| - [ ] 2 | UMB-2 | 2, 3: which records count, what each lift rests on (7 issues) | open |
| - [ ] 3 | UMB-3 | 4: docs, and a check that fails on warnings (4 issues) | open |
| - [ ] 4 | UMB-4 | 5: `default`'s presence table as a copy plus an overlay (4 issues) | open |
| - [ ] 5 | UMB-5 | 6, 7: the export contract, one-group runs that read downstream (6 issues) | open: after move 2, whose rule for code 2 the export's new column carries |
| - [ ] 6 | UMB-6 | 8, 9: what a run stamps and checks before launch, how primitives load (9 issues) | open |
| - [ ] 7 | UMB-7 | 10: drivers (6 issues) | open |
| - [ ] 8 | UMB-8 | 11: the rules builder and `dimensions.csv` (7 issues) | open |
| - [ ] 9 | UMB-9 | 12, 13: mapping codes as rules, the persist and run API (8 issues) | open: after move 8, whose residence columns the mapping-code rules read |
| - [ ] 10 | UMB-10 | 14, 15: snapping, habitat upstream of each crossing (6 issues) | open |
| - [ ] 11 | UMB-11 | 16: what blocks access at a barrier (4 issues) | open: after move 10, whose per-crossing totals the barrier scenarios are compared on |
| - [ ] 12 | UMB-12 | 17, 18, 19: thresholds from knowledge's table, MAD everywhere, the PARS vignette (7 issues) | **waiting** on knowledge#139's decision of which method sets link's flow numbers |
| - [ ] 13 | UMB-13 | 20: the next fresh pin (4 issues) | **waiting** on fresh 0.54.0's release |

Tracks are separate efforts, not moves: speed (`track:speed`; its umbrella is in the skills repository: #377,
#410, #411, #418, next #418), provenance (`track:provenance`; umbrella likewise: #466) and minimal-run
(knowledge#120, `track:minimal-run`: #418).

What knowledge waits on, placed (#468's table): #460, #462 and #463 in batch 1; #400 in batch 2; #434 in
batch 3; #402 and rainbow trout's return in batch 5; #346 and #343 in batch 17. #444 is closed: its table is
built and knowledge#120 reads it.

## Order

| # | tracking | batch | issues | gate | why here |
|---|---|---|---:|---|---|
| 1 | UMB-1 | parent gradient and grad tokens: #460, #420, #462, #463 | 4 | #462's option; #420 cut to the older builds' tokens | one vocabulary edit and one full-network build under `grad-parent` |
| 2 | UMB-2 | which records count: #400, #398, #425 | 3 | #400's date and pooling rule; #425's two-way codes | one species-code rule read by the filter, the walk and the checks; one `acc` row |
| 3 | UMB-2 | what each lift rests on: #434, #426, #427, #236 | 4 | `>=` or `>` at 1990-01-01; #427's threshold; #236 cut or closed | all edit `R/lnk_barrier_overrides.R`; the same `acc` row as batch 2 |
| 4 | UMB-3 | docs and a check that fails on warnings: #456, #279, #275, #385 | 4 | none | cheap, and every later move is checked on warnings |
| 5 | UMB-4 | presence table as a copy plus an overlay: #402, #431, #436, #292 | 4 | #436's option; UTRE CH and QUES ST; rainbow trout's return | one presence file, one overlay mechanism, one `acc` row |
| 6 | UMB-5 | the export contract: #423, #333, #334, #465 | 4 | #423's column shape; #334's refusals and the bucket; #466 first or inside | all edit `R/lnk_scenario_export.R`; one crate release and one republish |
| 7 | UMB-5 | one-group runs that read downstream: #464, #461 | 2 | none | both edit `R/lnk_wsg_downstream_check.R` |
| 8 | UMB-6 | what a run stamps and checks before launch: #451, #446, #266, #458, #450 | 5 | retire or refill `bcfishobs_sha`; one bcfishpass build rule; #450's range | `R/lnk_log.R` and the driver's pre-flight; one release before the next provincial run |
| 9 | UMB-6 | how primitives load: #459, #276, #273, #270 | 4 | ETag change or age per table | `snapshot_bcfp.sh` and the vintage gate; one primitives reload proves it |
| 10 | UMB-7 | drivers: #278, #281, #166, #181, #179, #110 | 6 | retire the legacy `wsgs_*` path | one pass over `data-raw/` argument handling |
| 11 | UMB-8 | rules builder and `dimensions.csv`: #75, #86, #129, #189, #212, #316, #327 | 7 | #212 to GR only; #316 and #327 adopt or decline; #86 cut | one rules regeneration and diff |
| 12 | UMB-9 | mapping codes as rules: #197, #153, #191, #351 | 4 | `""` for absent species | one parity run shows the output unchanged |
| 13 | UMB-9 | the persist and run API: #177, #176, #159, #204 | 4 | shims or hard renames | one release carries the deprecations |
| 14 | UMB-10 | snapping: #313, #314, #383 | 3 | wrap or retire; the tie rule | one re-snap, then a re-model of both configs |
| 15 | UMB-10 | habitat upstream of each crossing: #321, #232, #356 | 3 | none | one live parity against bcfishpass's crossings |
| 16 | UMB-11 | what blocks access at a barrier: #201, #83, #341, #386 | 4 | a deliberate departure from bcfishpass; #386's rule | one `acc` row and one provincial re-model |
| 17 | UMB-12 | thresholds from knowledge's table: #346, #343, #322 | 3 | knowledge#139's flow method; the table version | `default_tuned`'s thresholds file, read from one published table |
| 18 | UMB-12 | MAD everywhere on wet's flows: #387, #389 | 2 | the same flow decision | one five-group build |
| 19 | UMB-12 | the PARS vignette: #390, #342 | 2 | none | #342 shows batch 17's values |
| 20 | UMB-13 | the next fresh pin: #452, #269, #288, #222 | 4 | tag pins or an `Imports:` floor | one pin bump and one host re-prep |

### 1. The parent gradient and the grad tokens

- [ ] Carried by move 1, UMB-1

#460 (a `grad-fwa` vocabulary row for the Freshwater Atlas segment's own gradient, which no build writes),
#420 (tokens for builds older than the vocabulary; its Atlas-line item is #460 now), #462 (under `grad-parent`
the near-river exception's distance does not transfer from the minimal network: about 1,042 km of rearing)
and #463 (classify habitat and run the connectivity pass on `streams_parent.gradient_minimal`, refusing a
stale parent table). Touches `inst/extdata/vocabulary.csv`, `research/output_vocabulary.md`,
`R/lnk_pipeline_classify.R`, `R/lnk_pipeline_run.R`, `R/lnk_streams_parent.R`,
`data-raw/streams_parent_build.R`, RUNBOOK §6b. Gate: #462's option (carry the parent's near-river distance,
or report the gap as transfer cost); whether #420's older-build tokens are still wanted. One full-network
build under `grad-parent` on the dispatcher proves it.

knowledge waits on it: #460 is the last task of knowledge#120 (the Atlas-line setup's archive refuses a
`grad-fwa` token link's vocabulary does not hold), and #462 and #463 are what lets link draw knowledge#120's
parent-gradient pick.

### 2. Which records count

- [ ] Carried by move 2, UMB-2

#400 (one written rule for which records make code 2 and the observation breaks: date cut and pooling; the
count is decided, one record), #398 (cutthroat alias records reach the observation tables but never make CT
read "observed upstream", because the walk tests exact codes) and #425 (count the steelhead and char alias
codes SST, WST, ADV, ABT and the two-way codes as their species). Touches one species-code helper read by
`R/lnk_pipeline_break.R`, `R/lnk_pipeline_access.R`, `R/lnk_pipeline_prepare.R`,
`R/lnk_presence_check.R`, `R/lnk_presence_measures.R` and `R/lnk_habitat_validate.R`. Gate: #400's date and
pooling rule; #425's two-way codes (BT/DV, DV/BT, RB/CT). One `acc` row and a release; outputs move at the
next provincial re-model.

knowledge waits on it: #400 decides which records lift a barrier and make code 2, which knowledge#178 (move
9, tuning on link's access with leave-one-out, knowledge#131) reads.

### 3. What each lift rests on

- [ ] Carried by move 2, UMB-2

#434 (each build publishes the barriers each observation override lifted, with the records and the rule
behind each, checked against `access_<sp>`), #426 (lifts count records dated exactly 1990-01-01, which
bcfishpass leaves out; RUNBOOK's "no date floor" line is wrong), #427 (lift a natural barrier on fewer than
five salmon records in `default`, or a distance or date rule) and #236 (DV as BT access evidence: what
remains is multi-rule and group-scoped overrides; the dictionary and region-scoped pooling shipped). Touches
`R/lnk_barrier_overrides.R`, `R/lnk_persist_init.R`, `R/lnk_pipeline_persist.R`,
`inst/extdata/configs/default/parameters_fresh.csv`, `data-raw/study_area_verify.sql`, RUNBOOK §5. Gate:
`>=` or `>` per bundle; #427's threshold for salmon, GR and KO; #236 cut to the overrides or closed. The same
`acc` row as batch 2.

knowledge waits on it: #434 is what knowledge#178 (move 9) reads so that knowledge#131's leave-one-out gates
on link's own lifts rather than re-implementing `lnk_barrier_overrides()`.

### 4. Docs, and a check that fails on warnings

- [ ] Carried by move 3, UMB-3

#456 (the README says fish habitat definitions, not rules, as the website and the registry do), #279 (link
`research/README.md` from `CLAUDE.md` once; the index and cutover line already exist), #275 (two study-area
scope documents: the generated one still carries a scope section and `research/study_area_run.md` points at
it) and #385 (clear the `R CMD check` warnings: non-ASCII characters in five `R/` files, missing Rd links, the
undocumented `presence` arguments; then drop `error-on`). Touches `README.md`, `CLAUDE.md`,
`research/study_area_run.md`, `data-raw/study_area_buckets.R`, the five `R/` files' roxygen,
`.github/workflows/R-CMD-check.yaml`. No gate.

### 5. `default`'s presence table as a copy plus an overlay

- [ ] Carried by move 4, UMB-4

#402 (the presence check and its tracker: 154 rows pending, 141 of them KO and RB held since #432 paused
those species), #431 (`default`'s `wsg_species_presence.csv` as bcfishpass's synced copy, with link's
departures and #402's decisions as overlay rows with reasons), #436 (exclude a fish record bcfishpass has not
listed: three data errors from #402's review) and #292 (move `lnk_presence()`'s hard-coded presence groups
into the bundle, under `config_hash`). Touches
`inst/extdata/configs/default/overrides/wsg_species_presence*.csv`, `default/config.yaml`,
`R/lnk_overlay.R`, `R/lnk_pipeline_prepare.R` (the exclusion keys), `R/lnk_presence.R`, the sync script,
`inst/extdata/vocabulary.csv`. Gate: #436's option (an overlay that adds rows, a link-owned exclusions file,
or upstream); UTRE CH and QUES ST; whether rainbow trout's return to `default` gets its own issue. One `acc`
row.

knowledge waits on it: #402's record rules are what knowledge#132 (in move 9, where link's access gradients
come from) reviews; rainbow trout's return, held in #402's pending RB rows, is what knowledge#148 (in
knowledge#177, move 8) waits on to bring rainbow trout rearing back through a promotion.

### 6. The export contract

- [ ] Carried by move 5, UMB-5

#423 (the habitat export carries whether the species is recorded upstream, access code 2), #333 (register
the export's column contract in crate as `nge/habitat/fwa/v1/segment`), #334 (gates before a floodplain item
pins a build: refuse a missing `run_uid` or a dirty tree, bucket versioning, public read, a per-group streams
digest) and #465 (export each group's persisted barriers and input snapshots, so a one-group run reads its
downstream groups). Touches `R/lnk_scenario_export.R`, `inst/extdata/schemas/habitat_fwa_v1_segment.yaml`,
`R/lnk_catalog.R`, `data-raw/habitat_publish.R`, crate. Gate: #423's column shape; #334's refusals and the
bucket decision; #466 (provenance track) rewrites the same manifest, so it lands first or inside this move.
One crate release and one republish. A cloud loader in the infrastructure repository waits on #465.

### 7. One-group runs that read downstream

- [ ] Carried by move 5, UMB-5

#464 (`lnk_wsg_downstream_check()` passes when the downstream groups are not loaded; refuse and name them)
and #461 (the same check takes 371 s of a 975 s one-group run; time its steps and make the dominant one fast
without changing pass, fail or override). Touches `R/lnk_wsg_downstream_check.R`, `data-raw/wsg_run_one.R`,
`data-raw/wsg_recompute_one.R`, tests. No gate.

### 8. What a run stamps and checks before launch

- [ ] Carried by move 6, UMB-6

#451 (the run stamps a local bcfishobs checkout's commit that no run reads, and refuses to launch when it is
dirty), #446 (the bcfishpass reference pin reads a CSV-sync ledger row as the loaded view), #266 (link and
flooded select the bcfishpass reference build by different rules), #458 (`<schema>.log` keeps earlier runs'
rows; say in RUNBOOK that readers key on `run_uid`) and #450 (the pre-run gate finds its history through
`extends:` and a committed record of build minutes). Touches `R/lnk_log.R`, `R/lnk_stamp.R`,
`data-raw/study_area_run.sh` (the bcfishobs gate), `data-raw/study_area_remote.sh`,
`data-raw/study_area_verify.sql`, `data-raw/pretest_*`, RUNBOOK §8d. Gate: retire or refill
`bcfishobs_sha`; one selection rule for the bcfishpass build (#266 with #446); #450's range rule. One
release before the next provincial run.

### 9. How primitives load

- [ ] Carried by move 6, UMB-6

#459 (`snapshot_bcfp.sh`: the two-argument `--config` form for GDAL 3.8, and fallbacks for the Parquet and
bcdata paths), #276 (the snapshot skip guard keys on a code SHA and is scoped per host; hosts should reach
one freshness decision), #273 (the vintage gate asks how old our copy is, not whether the source changed) and
#270 (capture fwapg `load.sh`'s trace as `loader` rows in `provenance.source_artifact`). Touches
`data-raw/snapshot_bcfp.sh`, `data-raw/study_area_run.sh` (`preflight_hosts`), `R/lnk_preflight_vintage.R`,
`R/lnk_artifact.R`, `R/lnk_baseline_current.R`, a new fwapg load wrapper. Gate: ETag change or age per
table. Both batches edit the driver's pre-flight, so they run in order inside the move. One primitives reload
on a host proves it.

### 10. Drivers

- [ ] Carried by move 7, UMB-7

#278 (drivers default `--config` to `bcfishpass`: make it required and print the resolved decision set),
#281 (a standalone `wsg_run_one.R` writes NULL `run_uid` and `run_label`; decided with #278), #166 (the
data-raw scripts still not noun-first, and `data-raw/README.md`'s convention), #181 (table-level drops in
`state_clean.sh`), #179 (the legacy dispatcher's fallback puts every group on one host when groups do not
outnumber hosts) and #110 (the legacy runner's cache key captures no code or config version). Touches about
15 `data-raw/` drivers, `data-raw/README.md`, `state_clean.sh`, `wsgs_dispatch.sh`, `wsgs_run_host.R`,
RUNBOOK. Gate: retire the legacy `wsgs_*` path, which closes #179 and #110 and shrinks #176.

### 11. The rules builder and `dimensions.csv`

- [ ] Carried by move 8, UMB-8

#75 (the column dictionary documents and validates: a generated README, and `lnk_rules_build()` warns on an
unknown column), #86 (config audit: row counts are what remains), #129 (sync `parameters_habitat_rules.yaml`
to fresh on rules-build), #189 (residence and spawn-only from `dimensions.csv`, not code), #212 (bcfishpass-
style rows for GR in the `bcfishpass` bundle; KO and RB are paused), #316 (wetland construction lines reach no
rear rule in `default`: at most 156 km of BT rearing, measured) and #327 (order-1 streams off larger rivers on
a measured width in `default`). Touches `R/lnk_rules_build.R`, `data-raw/build_rules.R`,
`inst/extdata/configs/*/dimensions.csv`, `configs/dictionary_dimensions.csv`, `R/lnk_config_verify.R`, a
workflow to fresh. Gate: #212 to GR only or dropped; #316 and #327 adopt or decline on measurement; #86 cut to
row counts or closed. One rules regeneration and diff; a `default` re-model if #316 or #327 is adopted.

### 12. Mapping codes as rules

- [ ] Carried by move 9, UMB-9

#197 (mapping-code second tokens from a rules CSV, not hard-coded chains), #153 (presence definitions for
mapping codes: absent species read `""`), #191 (tests for `lnk_mapping_code()`, `lnk_pipeline_mapping_code()`
and the deprecation shims) and #351 (`lnk_access(merge = TRUE)` turns an absent species' -9 into 1, and
`lnk_mapping_code(presence = NULL)` errors). Touches `R/lnk_pipeline_mapping_code.R`, `R/lnk_mapping_code.R`,
`R/lnk_access.R` (the merge CASE), new tests. Gate: `""` for an absent species is the design. One parity run
shows the output unchanged.

### 13. The persist and run API

- [ ] Carried by move 9, UMB-9

#177 (`lnk_persist_{init, write}`: rename `lnk_pipeline_persist`), #176 (`lnk_compare_wsg()` to
`lnk_compare_run()`), #159 (`lnk_pipeline_run()` drops its working schema only on success; clean up on error)
and #204 (`lnk_persist_init()` checks only generated columns, so species-column drift passes). Touches
`R/lnk_pipeline_persist.R`, `R/lnk_pipeline_run.R`, `R/lnk_compare_wsg.R`, `R/lnk_persist_init.R`,
NAMESPACE, tests. Gate: deprecation shims or hard renames. One release carries the deprecations.

### 14. Snapping

- [ ] Carried by move 10, UMB-10

#313 (`lnk_points_snap()` can snap to placeholder `999` segments: `<@` rather than `!=`), #314 (wrap or retire
it in favour of `fresh::frs_point_snap()`) and #383 (fwapg's tie rule and stream-head fix across the
`FWA_LocateAlong` callers, with a sweep and live tests). Touches `R/lnk_points_snap.R`,
`R/lnk_pipeline_pscis_build.R`, `R/lnk_barriers_unify.R`, `data-raw/query_habitat_thresholds_obs.R`, tests.
Gate: wrap or retire; the tie rule waits on fwapg#41 (fwapg#45 is the locate twin). One re-snap, then a
re-model of both configs.

### 15. Habitat upstream of each crossing

- [ ] Carried by move 10, UMB-10

#321 (per-crossing upstream habitat per species on `fresh::frs_aggregate()`, checked against bcfishpass),
#232 (link-built crossings against bcfishpass's complete crossings table) and #356 (float length sums depend
on row order in the threshold scripts and `lnk_aggregate()`). Touches `R/lnk_aggregate.R`,
`data-raw/query_habitat_thresholds_obs.R`, `data-raw/query_habitat_thresholds_mad.R`, a crossings parity
script, `research/bcfishpass_parity.md`. No gate. One live parity against bcfishpass's crossings.

### 16. What blocks access at a barrier

- [ ] Carried by move 11, UMB-11

#201 (carry barrier ingredients and classify access late, per species, with an evidence-based dam
override), #83 (species-dependent dam handling), #341 (barrier rules as config, compared as scenarios on
#321's per-crossing totals) and #386 (copies of one barrier held by several groups can disagree under
group-filtered controls). Touches `R/lnk_barriers_unify.R`, `R/lnk_barriers_views.R`,
`R/lnk_barriers_emit.R`, `R/lnk_pipeline_access.R`, `R/lnk_pipeline_prepare.R`, a new
`parameters_barrier_rules.csv`, `data-raw/study_area_verify.sql`. Gate: a deliberate departure from
bcfishpass (dams per species, evidence over dams); #386 owner-only persistence or province-wide controls. One
`acc` row and one provincial re-model.

### 17. Thresholds from knowledge's published table

- [ ] Carried by move 12, UMB-12

#346 (`default_tuned` takes its thresholds from knowledge's published, versioned table and link retires its
per-threshold ladders), #343 (GR, RB and KO MAD minima on wet's discharge) and #322 (WCT thresholds from
observations). knowledge's `data/thresholds.csv` is published (run 20261104) with rows for all four. Touches
`inst/extdata/configs/default_tuned/parameters_habitat_thresholds.csv`, `data-raw/habitat_variants_*.R`,
`data-raw/habitat_validate.R`, `research/habitat_thresholds.md`. Gate: which method sets link's flow numbers;
the table version pinned.

knowledge waits on it, and it waits on knowledge: knowledge#139's baselines track decides with link which
method sets link's flow numbers before #346 reads `data/thresholds.csv`, and knowledge#140 files grayling's
proposed `default` beside #343.

### 18. MAD everywhere on wet's flows

- [ ] Carried by move 12, UMB-12

#387 (report the stream lines whose model reads a flow the bundle's discharge source does not have) and #389
(a `default_mad` bundle: MAD in every group on wet's flows, proven on five groups). Touches
`R/lnk_preflight_discharge.R`, `R/lnk_log.R` (a log column), a new `inst/extdata/configs/default_mad/`,
`inst/extdata/vocabulary.csv`. Gate: the same flow decision as batch 17. One five-group build on the
dispatcher.

### 19. The PARS vignette

- [ ] Carried by move 12, UMB-12

#390 (the vignette's data cannot be rebuilt once the two configs segment differently: take geometry from one
schema and join the other by measure overlap) and #342 (`default` against `default_tuned` for bull trout in
the Parsnip, side by side). Touches `data-raw/wsg_vignette_data.R`, `vignettes/`, `inst/vignette-data/`,
`data-raw/readme_figure.R`. No gate; #342 shows batch 17's values.

### 20. The next fresh pin

- [ ] Carried by move 13, UMB-13

#452 (`cols_streams_near_river` gains `linear_feature_id` with fresh 0.54.0, and the validator passes
`near_river_lfid`), #269 (`update_hosts.sh` installs fresh from main while `DESCRIPTION` pins a tag), #288
(`lnk_db_conn()` reads `PG_*_SHARE` first, fresh reads `PG*` first) and #222 (the live `lnk_wsg_resolve`
tests route to another database than their skip gate; the failure is gone, the mismatch is not). Touches
`R/lnk_persist_init.R`, `R/lnk_pipeline_persist.R`, `R/lnk_habitat_validate.R`, `DESCRIPTION`,
`scripts/update_hosts.sh`, `R/lnk_db_conn.R`, `tests/testthat/test-lnk_wsg_resolve.R`. Gate: tag pins or an
`Imports:` floor; the worker's refused GitHub token. One pin bump and one host re-prep.

## Singles

- #203: a globally unique `id_segment` re-models every persist schema and changes the export key; fresh#231 and fresh#218 hold fresh's half.
- #115: gradient classes derived from `access_gradient_max` would move cuts (a `cut` token), within the bcfishpass class set #326 enforces.
- #366: the downstream checks reviewed against fwapg's walk measurement; waits on fwapg#36.
- #169: simplify `lnk_persist_init()` once a clean snapshot lands in the infrastructure repository; it pulls against #204 in batch 13.
- #132: thread `known_habitat` through classify; waits on fresh#189.
- #133: non-FWA column names; waits on fresh#44.
- #213: a link-against-link mapping-code compare; after batch 11 settles #212.
- #224: why bcfishpass flags reservoir-inflow sub-basins dam-free; a question about bcfishpass, no link change.
- #130: BULK SK's upstream-spawning over-credit, parked as the only outlier; close as an accepted divergence or measure more groups.
- #332: a desktop GeoPackage of the export; after move 5, with its QGIS consumer.
- #335: a webmap of published habitat; after #334's public read (move 5).
- #52: channel-class break positions against gradient thresholds; research.
- #21: growing-season degree days as an intrinsic variable; research, its temperature input is outside link.
- #20: literature and observation evidence for each departure from bcfishpass; knowledge now holds the literature evidence table.
- #2: a fish passage literature store; knowledge now holds the literature stores.

## Closed and transferred

- #444: done; PR #457 (0.79.0) built `streams_parent` on all 241 groups, every acceptance line ticked (knowledge#120 ticked the first on 2026-11-05). Follow-ups #462, #463.
- #439: done; the minimal run and the `default` run it readied hosts for ran on fresh 0.52.0 with both verifiers passing. The worker's refused token moves to batch 20.
- #376: done; persistent workers shipped (PR #380), acceptance 2 met at run 20261103 (longest leg 9.8 % under its estimate).
- #375: done; phase times shipped (PR #378), criterion 2 met at run 20261103.
- #374: done; early recompute shipped (PR #382), tail 15.6 min against 60.6 and every pair in order at run 20261103.
- #371: done; the statement bound shipped (PR #373), no group timed out at run 20261103.
- #369: done; consolidate-on-finish shipped (PR #379), every host burned within 0.5 min of its consolidate at run 20261103.
- #196: done in 0.40.3 (NEWS; commit 46b2042b).
- #185: done in 0.39.0 (NEWS: "Closes #180 and #185").
- #183: done; absorbed by #246 (`lnk_preflight_parity()`, commit fb8e6428).
- #128: done; the runner it names became `wsgs_run_host.R`, whose resume gate reads persist rows and has `--force`.
- #95: done in effect; every pipeline step writes `<schema>.streams`.
- #84: done; fresh#186 shipped and the remaining gaps closed except BULK SK (#130).
- #353: superseded by #466, which makes the verify a report.
- #293: superseded by #356, which names the same line.
- #167: superseded; its own close condition, a tunnel-free compare, was met by #175.
- #131: superseded by the cloud-host and worker runs of `study_area_run.sh`.
- #126: superseded; `consolidate_schema()` is gone and `schema_consolidate.R` never restores or drops a source.
- #295: premise disproved; knowledge is public, and the read by URL lives in #346.
- #388: premise disproved; no run reads `data-raw/_targets.R`.
- #268: its own close clause; three provincial `default` runs since replaced the run it was for.
