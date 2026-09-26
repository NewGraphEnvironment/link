## Outcome

Calibrated the CH and BT gradient and channel-width thresholds for the `default_tuned`
bundle (#282), from observations, FISS site data and literature, using a decision rule fixed
before the distributions were seen. One value moves: BT `rear_gradient_max` 0.1049 → 0.1249.
Everything else was examined and kept, including `spawn_gradient_min` (CH spawning selects
the flattest bin) and `cluster_bridge_gradient`, so `default_tuned` still inherits
`parameters_fresh.csv`. The durable verdicts are in
[`research/habitat_thresholds.md`](../../../research/habitat_thresholds.md).

Step 5 (scoring against #283) is still open, and #284 stays open with it.

What was learned along the way:
- bcfishobs carries **no life stage for BT at all**.
- The FISS data-submission parse already exists in `knowledge`; its
  `average_gradient_percent` holds proportions.
- Observations *are* the pipeline's break points, so the upstream segment is the one to use.
- NULL-width river-polygon segments fail the river rule's `BETWEEN 0 AND 9999`.
- The rearing bridge only governs rearing that sits above spawning.

## Measurement

- **Use vs availability** (accessible segments, 55 `fresh_default` WSGs):
  - BT rearing P95 0.125 (n 2,443);
  - CH spawning P95 0.044 (n 226), with 0 of those observations in 5.0–5.5 % across 2,140 km available;
  - CH spawning selection 2.8 in the ≤ 0.25 % bin;
  - bridge loss 1.2 % of BT observations.
- **Modelled channel width vs FISS-measured** (n 18): median 0.97, p10–p90 0.69–1.56.
- **The wrong turns, kept on purpose:**
  - The first run took P95s over all observations. Review made them accessible-only, after
    the numbers had been seen. That withdrew a CH rearing 0.0649 candidate and moved BT from
    0.1349 to 0.1249, and it is disclosed in the doc as a post-hoc change.
  - The first DV proxy rule ("BT and not DV") was empty by construction.
  - The first draft described the bridge backwards, and called coverage "interior only" when
    a third of the CH locations are in the lower Fraser and coastal Skeena.
  - Four code-check rounds (`review-round*.md`). R3 and R4 were claim enumerations (88,
    then 97 claims).

## Evidence

`data-raw/logs/habitat_thresholds_284/*` (producers: `data-raw/query_habitat_thresholds_*.R`).
Literature: `literature.md` here. Issue drafts awaiting approval: `draft_*.md` here.

Closed by: PR (relates to #284; #284 stays open for step 5)
