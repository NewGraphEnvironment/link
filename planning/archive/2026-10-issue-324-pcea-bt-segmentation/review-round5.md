# Code-check round 5 (#324)

Reviewed `git show 34c3ad1` plus the sites quoting its figures (taxonomy, `mechanism.R`, research doc,
log README, CLAUDE.md status, issue #324 body, ledger). Probes: recomputed every mechanism split per
rollup row from `*_bt_pieces.csv` (scratchpad `slice.R`), ran `lnk_parity_annotate()` on the
`parity_crosssection_after.txt` rows, re-read `load_habitat_linear_bt.sql`, fresh's width SQL, and a
PCEA query on `fresh.streams_vw_bcfp`.

What holds: first-match ordering (no earlier entry reaches PCEA/FINA/PARS BT; annotator output tags all
seven target rows with the intended entry, LKEL falls to WITHIN_TOLERANCE); every diff_range covers its
rows (PCEA +1.87, FINA −0.52, PARS −0.54, spawning 0.79–0.93, connection −2.18); NULL-width claim
(PCEA 3,306 order-1/parent≥5 segments, 3,236 NULL width, 0 rear); width exception in BT/CH/CO/ST/WCT
only; NA-safe bypass is correct; `segmentation_net`/`_gross` arithmetic; the 25–39 % spawning share.

## Mechanism (a): one more axis

**Which quantity a figure measures vs. which row it is attached to.** `habitat_diff_segments.R` /
`mechanism.R` measure the `rearing` *flag* total, which includes lake connection lines; the rollup's
`rearing` row (since #319) excludes them, and `rearing_stream` is a further polygon slice. The figures
are labelled "flag km" in the research doc, README and issue, so they are right there — but the
taxonomy attaches them to `rearing` / `rearing_stream` rows, where they are not the row's composition.
It reaches the two entries below and the ledger's categorical table. (A second, smaller instance of
the same "cited thing is not the thing that ran" shape: a code-path citation, finding 4.)

## Findings

- **[claim]** `research/bcfp_divergence_taxonomy.yml:156` (`bt-gradient-segmentation-over`) — the
  mechanism explains the PCEA `rearing` / `rearing_stream` rows as "net +29.9 km, less bcfishpass's
  order-1 width exception (−9.6 km), plus 1.8 km access", i.e. the flag net +22.1. The row it tags is
  +1.87 % = 1,655.8 − 1,625.5 = **+30.3 km** (`parity_crosssection_after.txt`), which leaves connection
  lines out. 8.37 of the 9.59 km width exception is on the two 1450 lines in a lake (`b_lake_conn`
  TRUE), i.e. in `rearing_lake_connection`, which `pcea-bt-connection-width-exception` already
  annotates. Recomputed from `pcea_bt_pieces.csv` with each side's own `*_lake_conn`: the `rearing` row
  is segmentation +29.74, width exception **−1.22**, access +1.80 = +30.33; `rearing_stream` has the
  exception at −1.00. So the entry double-counts 8.37 km across two rows and its sum does not equal its
  row. The ledger's categorical row ("mechanism text names the −9.6 width exception",
  `review-enumeration.md:66`) carries the same error.

- **[claim]** `research/bcfp_divergence_taxonomy.yml:179-187` (`pars-bt-rearing-width-exception`) —
  targets `rearing` and `rearing_stream`, but its figures (−24.8 km, segmentation +10.0) are the
  `rearing` row's. On `rearing_stream` the exception is −22.77 km (2.01 km of the 24.78 sits on
  lake / wetland polygon lines, edges 1200 / 1050) and segmentation ≈ +9.2. Sign and verdict hold; the
  numbers quoted for the stream row do not.

- **[claim]** `research/bcfp_segmentation_parity.md` ("Segmentation's net sign varies by group …
  negative in FINA (−13.10), where cutting outweighs joining") and taxonomy `-under` — implies the sign
  is set by cutting vs joining, so PARS (positive) would be a joining-wins group. It is not: PARS
  connectivity is −9.27 (cutting wins, as in FINA); its positive segmentation net comes from rear-
  gradient flips (+19.28). Same generalise-from-one-group shape as round 4's PARS finding.

- **[claim]** `research/bcfp_segmentation_parity.md` (spawning: "fresh on width ≥ it
  (`frs_habitat_predicates.R`, `size_sql()`)") and ledger row "rearing width test is `>=` on both
  sides … fresh `size_sql()`" — `size_sql()` is the no-rules branch. The bcfishpass bundle ships
  `rules.yaml`, so its predicate comes from `.frs_rules_to_sql()` (`R/utils.R`, `s.channel_width
  BETWEEN %s AND %s`; same at fresh v0.33.0, which built PCEA). The operator conclusion (inclusive)
  holds; the cited code is not what ran.

- **[claim]** `data-raw/logs/rearing_diff_324/README.md` vs `research/bcfp_segmentation_parity.md` and
  the `segmentation_*` columns — the README calls `connectivity_other` "unexplained connectivity
  (≤ 4.01 km)", while `segmentation_net` / `segmentation_gross` (`mechanism.R`, `fam %in%
  c("rear_gradient","connectivity")`, connectivity including `connectivity_other`) count it as
  segmentation, and the research doc says "nothing is left unattributed". "Segmentation alone moves
  74–87 km" therefore includes up to 4.01 km (PCEA) whose tie to a gradient split was not established.
  Either say it is attributed to segmentation through cross-stream clusters (and probe that), or stop
  calling it unexplained / exclude it from the segmentation columns.

- **[claim / sweep miss]** `data-raw/logs/rearing_diff_324/README.md:5` — "Taxonomy:
  `bt-gradient-segmentation-over` / `-under`, and `pcea-bt-connection-width-exception`" omits the two
  entries round 4 added (`pars-bt-rearing-width-exception`, `bt-spawning-segmentation-and-width`); the
  PARS rearing and all spawning rows are now tagged by entries the index does not name.
