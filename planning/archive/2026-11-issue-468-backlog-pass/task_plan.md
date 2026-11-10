# Task: Backlog pass: batch the open issues into moves with umbrellas (#468)

link has 117 open issues (2026-11-09), no umbrella issues and no `planning/backlog.md`. knowledge ran the same pass on its own 58 (NewGraphEnvironment/knowledge#169), which ended in eleven move umbrellas and a backlog file. Two of those moves, and two of knowledge's tracks, wait on link issues, and that dependency is visible only from knowledge's side.

## Decided at the gate

- 2026-11-09, the owner approved the plan as presented: it is `/backlog-sweep`'s go for the 13 moves, 20 batches, 15 singles and 21 closures in the report below. No regrouping, dropped closure or reorder was asked for.

## Context

link has 117 open issues besides this one, no umbrella issues and no `planning/backlog.md`.
knowledge ran the same pass (knowledge#169) and two of its moves and two tracks wait on link
issues that look no more urgent than any other from link's side. This pass runs
`/backlog-sweep` steps 0–4 as this plan's exploration (done; the report is below), so approval
here is the sweep's **go**: write `planning/backlog.md`, file one umbrella per move, close what
is agreed, and open the PR.

Read for the pass: every open body and its comments (three read-only readers, 39 issues each,
each premise checked against `origin/main` f8a45c29, NEWS, CLAUDE.md status, `git log`); the
reference graph (hubs: #402 named by 8 open issues, #377 by 7, #398 by 5, #369 by 5, #400 and
#444 by 4); the state of every peer issue a batch waits on (knowledge, fresh, fwapg, crate,
floodplains, and the infrastructure repository); knowledge's published `data/thresholds.csv`
is on its `origin/main` (91ae2f5d, run 20261104). Re-listed 2026-11-09: 118 open, no new issue
since step 1. link is **public**: the file and the umbrella bodies name no private repository;
the infrastructure repo's consumer of #465 and the skills repository's track umbrellas are
described in words.

No issue reports a recurrence since it was filed, so the recurrence rule promotes nothing.

## The report (step 4)

### Proposed closures (21) — every issue here was filed by you, so each closes only on your word

Done (shipped, acceptance met):
- #444 — parent attributes: every box and acceptance line ticked; PR #457 (0.79.0); knowledge#120 ticked line 1 on 2026-11-05. Follow-ups are #462, #463.
- #439 — hosts readied for the minimal run: that run and #454's ran across five hosts on fresh 0.52.0 with both verifiers passing. the worker's refused GitHub token moves to batch 20 (#269).
- #376 — persistent workers: acceptance 1–3 met; run 20261103's longest leg 9.8 % under its estimate.
- #375, #371, #369 — phase times, statement bound, consolidate-on-finish: each body says its criterion 2 reads as met at run 20261103_163715 (#369's item 3 waived in its body).
- #374 — early recompute: tail 15.6 min against 60.6, audit 2,191/2,191 in order; the digest match against `--recompute-at-end` was measured on 10 groups, not provincially — your call whether that suffices.
- #196 — per-source flag columns in `streams_access`: NEWS 0.40.3, commit 46b2042b.
- #185 — per-source `wgc_tables`: NEWS 0.39.0 "Closes #180 and #185"; never closed.
- #183 — sibling-host parity: absorbed by #246 (commit fb8e6428, `lnk_preflight_parity()`).
- #128 — resume check fails open: `run_provincial_parity.R` became `wsgs_run_host.R`, whose gate reads persist rows and has `--force`.
- #95 — parameterize `network_schema`: pipeline steps write `<schema>.streams`; `fresh.streams` survives only in comments.
- #84 — bcfishpass-config departures: fresh#186 shipped; #130's measurement leaves BULK SK the only outlier.
Superseded:
- #353 — config_hash as accounting → #466 ("#353's verify becomes a report").
- #293 — float sum order in one script → #356, which names the same line.
- #167 — tunnel drops: its own close condition (a tunnel-free compare) met by #175; the scripts it names are gone.
- #131 — crew.aws.batch + RDS: overtaken by `study_area_run.sh` on cloud hosts and workers (241 groups in 237 min).
- #126 — `consolidate_schema()` hardening: the file is gone; `schema_consolidate.R` streams COPY and never restores or drops a source.
Premise disproved:
- #295 — describe private evidence inputs generically: knowledge is public (since 2026-11-01); the URL read it was rewritten to lives in #346.
- #388 — a bundle list in `_targets.R`: no run reads `_targets.R` (last touched 2026-09-25; provincial runs go through `study_area_run.sh`). #389 does not need it.
Its own close clause:
- #268 — legacy-provenance escape in the verifier: "if the honest answer is no, close this"; three provincial `default` runs since have replaced the run it was for.

Kept but a close is possible on your word (placed in batches below): #316 (≤156 km of BT gain measured; batch 11), #179 and #110 (close if the legacy `wsgs_*` path is retired; batch 10), #130 (accepted divergence; single), #2 and #20 (literature now lives in knowledge's stores and `literature_evidence.csv`; singles).

### Moves and batches (ranked)

| move | batches | issues | state |
|---|---|---:|---|
| 1 | 1: the parent gradient and the grad tokens | 4 | open: start here |
| 2 | 2, 3: which records count; what each lift rests on | 7 | open |
| 3 | 4: docs, and a check that gates on warnings | 4 | open |
| 4 | 5: `default`'s presence table as a copy plus an overlay | 4 | open |
| 5 | 6, 7: the export contract; one-group runs that read downstream | 6 | open: after move 2 (#423 carries code 2 as #400 defines it) |
| 6 | 8, 9: what a run stamps and checks before launch; how primitives load | 9 | open |
| 7 | 10: drivers: an explicit config, a labelled standalone run, the legacy path | 6 | open |
| 8 | 11: the rules builder and `dimensions.csv` | 7 | open |
| 9 | 12, 13: mapping codes as rules; the persist and run API | 8 | open: after move 8 (#189's residence columns feed #197) |
| 10 | 14, 15: snapping; habitat upstream of each crossing | 6 | open |
| 11 | 16: what blocks access at a barrier | 4 | open: after move 10 (#341 reads #321's per-crossing totals) |
| 12 | 17, 18, 19: thresholds from knowledge's table; MAD everywhere; the PARS vignette | 7 | **waiting** on knowledge#139's decision of which method sets link's flow numbers |
| 13 | 20: the next fresh pin | 4 | **waiting** on fresh 0.54.0's release |

Batches (members · touches · gate · why here; "knowledge:" names what waits on it):

1. **Parent gradient and grad tokens** — #460, #420, #462, #463 · `inst/extdata/vocabulary.csv`, `research/output_vocabulary.md`, `R/lnk_pipeline_classify.R`, `R/lnk_pipeline_run.R`, `R/lnk_streams_parent.R`, `data-raw/streams_parent_build.R` · gate: #462's option (carry the parent's near-river distance, or report the ~1,042 km as transfer cost); #420 cut to the 0.66.0-era tokens (its grad item is #460) · one vocabulary edit and one dispatcher build of the full network under `grad-parent`. knowledge: #460 is the last task of knowledge#120 (the Atlas-line setup's archive refuses `grad-fwa`); #462 and #463 let link draw knowledge#120's parent-gradient pick.
2. **Which records count** — #400, #398, #425 · one species-code helper in `R/lnk_pipeline_break.R`, `R/lnk_pipeline_access.R`, `R/lnk_pipeline_prepare.R`, `R/lnk_presence_check.R`, `R/lnk_presence_measures.R`, `R/lnk_habitat_validate.R` · gate: #400's date and pooling rule; #425's two-way codes (BT/DV, DV/BT, RB/CT) · one `acc` row, one release; outputs move at the next provincial re-model. knowledge: #400 holds knowledge#178 (move 9: tuning on link's access, knowledge#131 — which records lift a barrier).
3. **What each lift rests on** — #434, #426, #427, #236 · `R/lnk_barrier_overrides.R`, `R/lnk_persist_init.R`, `R/lnk_pipeline_persist.R`, `default/parameters_fresh.csv`, `data-raw/study_area_verify.sql`, RUNBOOK §5 · gate: `>=` or `>` at 1990-01-01 per bundle; #427's threshold for salmon, GR and KO; #236 cut to multi-rule and group-scoped overrides or closed · same `acc` row as batch 2. knowledge: #434 holds knowledge#178 (move 9, knowledge#131's leave-one-out).
4. **Docs and a check that gates on warnings** — #456, #279, #275, #385 · `README.md`, `CLAUDE.md`, `research/study_area_run.md`, `data-raw/study_area_buckets.R`, the non-ASCII and Rd fixes in five `R/` files, `.github/workflows/R-CMD-check.yaml` · gate: none · cheap, and every later move then gates on warnings.
5. **Presence table as a copy plus an overlay** — #402, #431, #436, #292 · `default/overrides/wsg_species_presence*.csv`, `default/config.yaml`, `R/lnk_overlay.R`, `R/lnk_pipeline_prepare.R` (exclusion keys), `R/lnk_presence.R`, the sync script · gate: #436's option (overlay adds rows, a link-owned exclusions file, or upstream); UTRE CH and QUES ST; whether rainbow trout's return gets its own issue · one `acc` row (`acc-v6`). knowledge: #402's record rules are what knowledge#132 (in move 9) reads; rainbow trout's return, held in #402's pending KO and RB rows since #432 paused it, is what knowledge#148 (in knowledge#177, move 8) waits on.
6. **The export contract** — #423, #333, #334, #465 · `R/lnk_scenario_export.R`, `inst/extdata/schemas/habitat_fwa_v1_segment.yaml`, `R/lnk_catalog.R`, `data-raw/habitat_publish.R`, crate · gate: #423's column shape; #334's PUBLISH refusals and the bucket's versioning and public read; #466 (provenance track) edits the same manifest, so it lands first or inside this move · one crate release, one republish. A cloud loader in the infrastructure repository waits on #465's per-group barriers.
7. **One-group runs that read downstream** — #464, #461 · `R/lnk_wsg_downstream_check.R`, `data-raw/wsg_run_one.R`, `data-raw/wsg_recompute_one.R` · gate: none · #464 refuses an unloaded downstream path; #461 times the same function.
8. **What a run stamps and checks before launch** — #451, #446, #266, #458, #450 · `R/lnk_log.R`, `R/lnk_stamp.R`, `data-raw/study_area_run.sh` (bcfishobs gate), `data-raw/study_area_verify.sql`, `data-raw/pretest_*`, RUNBOOK §8d · gate: retire or refill `bcfishobs_sha`; #450's range rule; one bcfp-build selection rule (#266 with #446) · one release before the next provincial run.
9. **How primitives load** — #459, #276, #273, #270 · `data-raw/snapshot_bcfp.sh`, `study_area_run.sh` `preflight_hosts`, `R/lnk_preflight_vintage.R`, `R/lnk_artifact.R`, a new fwapg load wrapper · gate: ETag change or age per table · one primitives reload on a host proves it.
10. **Drivers** — #278, #281, #166, #181, #179, #110 · about 15 `data-raw/` drivers' argument handling, `data-raw/README.md`, `state_clean.sh`, `wsgs_dispatch.sh`, `wsgs_run_host.R` · gate: retire the legacy `wsgs_*` path (closes #179, #110, shrinks #176) · one pass over `data-raw/`.
11. **Rules builder and `dimensions.csv`** — #75, #86, #129, #189, #212, #316, #327 · `R/lnk_rules_build.R`, `data-raw/build_rules.R`, `configs/*/dimensions.csv`, `configs/dictionary_dimensions.csv`, `R/lnk_config_verify.R`, a workflow to fresh · gate: #212 cut to GR only (KO and RB are paused); #316 and #327 adopt or decline on measurement; #86 cut to row counts · one rules regeneration and diff; a `default` re-model if #316 or #327 is adopted.
12. **Mapping codes as rules** — #197, #153, #191, #351 · `R/lnk_pipeline_mapping_code.R`, `R/lnk_mapping_code.R`, `R/lnk_access.R` (merge CASE), new tests · gate: `""` for absent species is the design (#153) · one parity run shows unchanged output.
13. **The persist and run API** — #177, #176, #159, #204 · `R/lnk_pipeline_persist.R`, `R/lnk_pipeline_run.R`, `R/lnk_compare_wsg.R`, `R/lnk_persist_init.R`, NAMESPACE · gate: shims or hard renames · one release with the deprecations.
14. **Snapping** — #313, #314, #383 · `R/lnk_points_snap.R`, `R/lnk_pipeline_pscis_build.R`, `R/lnk_barriers_unify.R` · gate: wrap or retire in favour of `frs_point_snap()`; the tie rule waits on fwapg#41 (fwapg#45 is the locate twin) · one re-snap, a re-model of both configs.
15. **Habitat upstream of each crossing** — #321, #232, #356 · `R/lnk_aggregate.R` on `fresh::frs_aggregate()`, the threshold query scripts, a crossings parity script · gate: none · one live parity against bcfishpass's crossings.
16. **What blocks access at a barrier** — #201, #83, #341, #386 · `R/lnk_barriers_unify.R`, `R/lnk_barriers_views.R`, `R/lnk_barriers_emit.R`, `R/lnk_pipeline_access.R`, a `parameters_barrier_rules.csv` · gate: a deliberate departure from bcfishpass (dams per species, evidence over dams); #386 owner-only or province-wide controls · one `acc` row, one provincial re-model.
17. **Thresholds from knowledge's published table** — #346, #343, #322 · `configs/default_tuned/parameters_habitat_thresholds.csv`, `data-raw/habitat_variants_*.R`, `data-raw/habitat_validate.R`, `research/habitat_thresholds.md` · gate: knowledge#139's flow method; the table version pinned · retires link's per-threshold ladders. knowledge: knowledge#139's baselines track decides with link before #346 reads `data/thresholds.csv`; knowledge#140 files grayling's proposed `default` beside #343.
18. **MAD everywhere on wet's flows** — #387, #389 · `R/lnk_preflight_discharge.R`, `R/lnk_log.R`, a new `configs/default_mad/`, `vocabulary.csv` · gate: same flow decision · one five-group build on the dispatcher.
19. **The PARS vignette** — #390, #342 · `data-raw/wsg_vignette_data.R`, `vignettes/`, `data-raw/readme_figure.R` · gate: none · #342 shows batch 17's values.
20. **The next fresh pin** — #452, #269, #288, #222 · `R/lnk_persist_init.R`, `R/lnk_habitat_validate.R`, `DESCRIPTION`, `scripts/update_hosts.sh`, `R/lnk_db_conn.R`, `tests/testthat/test-lnk_wsg_resolve.R` · gate: tag pins or an `Imports:` floor; the worker's refused token · one pin bump and host re-prep.

Singles (15): #203 (global `id_segment`: re-models every schema; fresh#231 and fresh#218 hold the other half), #115 (derived gradient classes; a `cut` token), #366 (waits on fwapg#36), #169 (waits on a snapshot rebuild in the infrastructure repository; pulls against #204), #132 (waits on fresh#189), #133 (waits on fresh#44), #213 (link-vs-link compare; after #212), #224 (a bcfishpass question, no link change), #130 (parked BULK SK; close as accepted?), #332 and #335 (desktop and web products; after move 5), #52, #21 (research; logic's stream-temperature work is the input), #20, #2 (literature; knowledge holds the stores).

Tracks (not moves): speed (`track:speed`; its umbrella is in the skills repository): #377, #418, #410, #411, next #418. Provenance (`track:provenance`; same): #466. Minimal-run (knowledge#120, `track:minimal-run`): #418.

### Ranked top three
1. Move 1 — #460 is one vocabulary row and is the last task of knowledge#120; #462 and #463 let link draw knowledge#120's pick.
2. Move 2 — #400 and #434 are two of the three things knowledge#178 (move 9) waits on (the third is fresh#257).
3. Move 3 — cheap, and puts every later move behind a check that fails on warnings.

### Placed count
Frozen set: 118 open issues. 76 batched, 15 single, 5 in tracks, 21 closed, and #468 itself (named on the `**Verified:**` line). Public repo: the file and the umbrella bodies are scanned before writing.

### Umbrella titles and bodies (as step 7 will file them)

Each body: an **If we do it / If we never do** line, then "Move N of link's backlog
(`planning/backlog.md`); run `/planning-init <this issue>`; one phase per batch, one PR.", then
per batch: **Why here**, **Touches**, **Decided at the gate** (the gate above, as open questions),
and a members table `issue | title`. Titles and the opening lines:

1. **Backlog move 1: The parent gradient on the full network, and the grad tokens** — If we do it: link classifies on each full segment's minimal parent's gradient under `grad-parent`, and the Atlas-line setup has a token, so knowledge#120's picks can be drawn and archived. If we never do: knowledge's minimal-network tuning stays a comparison link cannot deploy, and one of its setups stays untokened.
2. **Backlog move 2: Which fish records count, and what each lift rests on** — If we do it: one written rule says which records make code 2 and which lift a barrier, aliases count as their species, and each lifted barrier is published with the records behind it. If we never do: code 2 and the lifts follow defaults no one chose, and knowledge's access tuning re-implements the overrides.
3. **Backlog move 3: Docs, and a check that fails on warnings** — If we do it: the README says fish habitat definitions, the research index is linked, the scope docs agree, and CI fails on a warning. If we never do: warnings accumulate unseen and two documents keep defining the scope.
4. **Backlog move 4: default's presence table as bcfishpass's copy plus an overlay** — If we do it: every departure from bcfishpass's presence table is an overlay row with its reason, link can exclude a record it finds wrong, and the presence groups live in the bundle. If we never do: the table stays a hand-edited fork, and a wrong record stays counted until bcfishpass drops it.
5. **Backlog move 5: The habitat export's contract, and one-group runs that read downstream** — If we do it: the export carries code 2, its column contract lives in crate, publishing refuses unprovenanced builds, and a one-group run reads its downstream groups' barriers or refuses. If we never do: a one-group run on a partial database ignores every dam downstream, and consumers can pin builds nobody can reproduce.
6. **Backlog move 6: What a run stamps and checks before launch, and how primitives load** — If we do it: each stamp describes something the run read, the bcfp reference pin is chosen by one rule, the gate finds its own history, and primitive loads fall back and record what they loaded. If we never do: every launch needs a clean bcfishobs clone for a number nothing reads, and stale primitives pass the gate.
7. **Backlog move 7: Drivers: an explicit config, a labelled standalone run, and the legacy path retired** — If we do it: no driver defaults to `bcfishpass`, a standalone run carries a run id, and `data-raw/` holds one runner. If we never do: the next run can go out on the parity config by default, as North Thompson's did.
8. **Backlog move 8: The rules builder and dimensions.csv as the source of truth** — If we do it: the dictionary validates and documents the columns, residence comes from `dimensions.csv`, fresh's copy of the rules stays current, and the two open rearing questions are answered. If we never do: residence stays hard-coded and fresh's sample rules keep drifting.
9. **Backlog move 9: Mapping codes as rules, and the persist and run API** — If we do it: mapping-code tokens come from a rules file, the persist functions form one family, and a failed run cleans up its working schema. If we never do: each new token is a code change and the API keeps its old seams.
10. **Backlog move 10: Crossings: snapping, and habitat upstream of each crossing** — If we do it: points snap by one rule off placeholder lines, and each crossing's upstream habitat is summed over its whole network and checked against bcfishpass. If we never do: a crossing's upstream habitat misses every tributary.
11. **Backlog move 11: What blocks access at a barrier** — If we do it: barrier rules are config, dams can be species-dependent, and copies of one barrier agree. If we never do: what blocks is fixed in code and scenarios cannot be compared.
12. **Backlog move 12: Thresholds from knowledge's published table, MAD everywhere, and the PARS vignette (waiting)** — If we do it: `default_tuned` reads knowledge's versioned thresholds, a MAD-everywhere bundle is proven, and the vignette shows the difference. If we never do: link keeps a second calibration harness beside the evidence it reads.
13. **Backlog move 13: The next fresh pin (waiting)** — If we do it: the persisted near-river table keeps fresh's key, hosts install the pinned fresh, and both connection helpers read the same variables. If we never do: the validator errors on the first fresh 0.54.0 install.


## Phase 1: Freeze
- [x] Re-list open issues, write the frozen set (`backlog_frozen.txt` in the git dir); place any issue filed since this plan.

## Phase 2: Write `planning/backlog.md`
- [x] Header (`**Verified:**` naming #468, the measurements), Moves table (umbrella cells as placeholders), tracks line, Order table, 20 batch sections (each with its knowledge line in words), Singles, Closed and transferred.
- [x] Coverage check against the frozen set passes.

## Phase 3: Scan
- [x] Draft the 13 umbrella bodies to `umbrella_<n>.md` in the git dir; `public_leak_scan` clean on them and the file (rewrite and re-show any body it flags).

## Phase 4: File umbrellas
- [x] File the 13 umbrellas via `--body-file`; write their numbers into the Moves table and batch sections.
- [x] Every open move ticks cleanly on a copy (`backlog_moves.sh`); `next` names move 1.

## Phase 5: Close
- [x] Close the agreed issues, each with a comment giving its reason and what would have changed.

## Phase 6: Land
- [x] Commit the file and archive the PWF; the PR follows with `/gh-pr-push`.

## Owed at the end (reported, done after merge)

None in link. knowledge's backlog line pointing at link#468 is refreshed at knowledge's next pass, by its peer search (#468, "Keeping the two backlogs in step").

## Validation

- [x] Tests pass (no code changes; the tick check on a copy, coverage and the public scan are the tests, all clean)
- [ ] `/code-check` not run: the diff is `planning/` only (no code, script or convention); it was reviewed by the Plan review instead, whose corrections are in commit aadaad42
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion

- Coverage: every frozen issue appears in the file (step 5 check).
- Tick: every open move ticks cleanly on a copy; `backlog_moves.sh next` names move 1.
- Scan: `public_leak_scan` reports nothing for the file and each umbrella body.
- Closures: `gh issue list --state open` no longer lists the 21 closed; each has its comment.
