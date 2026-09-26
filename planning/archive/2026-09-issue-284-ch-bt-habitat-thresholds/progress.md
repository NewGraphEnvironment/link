# Progress — Research: calibrate CH and BT gradient and channel-width thresholds from observations (#284)

## Session 2026-09-25

- Plan-mode exploration — phases approved by user
- Gate decisions: research-only branch (steps 1,2,3,6); steps 4–5 wait on #282/#283; step 2 uses FISS site data behind bcfishobs, not NGE crew sheets; analysis in data-raw + research doc, no exports
- Created branch `284-research-calibrate-ch-and-bt-gradient-a` off main
- Scaffolded PWF baseline from issue #284 with approved phases
- Next: start Phase 1

## Parked 2026-09-25 — user moved to #282 first

Phase 1 not started (no script written). Measured before parking:
- `whse_basemapping.fwa_stream_networks_channel_width`: 4.91 M rows, 2.20 M with a width;
  columns `linear_feature_id, channel_width_source, channel_width` — province-wide join key for (a).
- CH+BT obs by top-level wscode: 100 Fraser 6,673 · 300 (Columbia) 4,050 · 200 (Peace/Mackenzie) 3,837 ·
  920 1,299 · 400 Skeena 1,101 · 900 884 · 930 730 · 600 614 · 910 483 · 500 Nass 394 — usable as the region split.
- `default/overrides/observation_exclusions.csv` (1,181 rows) keyed on `observation_key`;
  exclude where `data_error` or `release_exclude` is t — mirror `R/lnk_pipeline_prepare.R:307-321`.
- fresh installed 0.33.0 (`7f12d99`), local checkout v0.34.0: CH/BT threshold rows identical in the CSV read.
- A Plan-agent review of this task_plan was spawned before parking; its findings were not yet in.
- Resume: #282 lands `default_tuned` + per-bundle thresholds, which also unblocks steps 4–5 here.

## Session 2026-09-26 — resumed

- #282 merged (v0.51.0). Re-ran plan gate: evidence now / score after #283; `default_tuned`
  owns a copy of `parameters_fresh.csv`.
- New branch `284-research-calibrate-ch-and-bt-gradient-an` off `origin/main`, carrying the
  three planning commits from the parked `-a` branch by cherry-pick. That leaves the unpushed
  MCGR run-log commit (`796c182`, on local `main` and the parked branch) out of this PR.
- Folded `review-plan.md` B1–B3 and G1–G11 into task_plan; re-probed B1 and B3 (both hold).
- Found `knowledge` owns FISS data-submission snapshots (UNTH, LNTH, COTR, PINE, UPCE),
  which replaces the bcdata/`fshclctn_id` route that B3 showed does not link.
- Phases 1–2: `query_habitat_thresholds_obs.R` / `_fiss.R` → `data-raw/logs/habitat_thresholds_284/`.
  Literature (Phase 3) by a background agent → `planning/active/literature.md`.
- Phase 4: one cell in `default_tuned` (BT `rear_gradient_max` 0.1049 → 0.1249); the
  `parameters_fresh.csv` copy was not made because the evidence keeps both of its values.
- Phase 5: `research/habitat_thresholds.md` + new `research/README.md` index.
- `/code-check`: 4 rounds (`review-round1..4.md`). R1 flipped CH rear 0.0649 → keep and BT
  0.1349 → 0.1249 (accessible-only use, a post-hoc change disclosed in the doc). R2 corrected
  the bridge mechanism (checked against fresh `.frs_cluster_both()`). R3 found the coverage
  error (a third of the CH locations are lower Fraser / coastal Skeena). R4's enumeration was clean.
- Agent spend: 1 literature + 4 review rounds = 5, at the §6 bound.
- Drafts (not filed, awaiting approval): `draft_knowledge_issue.md` and
  `draft_issue_riverpoly_null_width.md`.
- Commits are grouped by phase; the checkbox flips land with Phase 5, because review ran
  over the combined diff.
