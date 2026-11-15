# Review round 4 (#463): documentation claims in `git diff 6f0eea81..HEAD`

Read only. No file in the repo was edited and no build or proof script was run. Numbers were
recomputed with `Rscript` from the committed CSVs in `data-raw/logs/grad_parent_463/`.

## Findings

- **[wrong]** data-raw/logs/grad_parent_463/README.md:233-235 (the Review table's round 3 row,
  "inside the previous fix: yes"). Round 3 found nothing inside round 2's fixes: it says
  "Round 2's fixes check out" (review-round3.md, the paragraph after Findings). Its two findings
  are proof.R:125-127, described as "R1's `want_tok()` defect in the next block", and
  proof.R:160-162 (counts compared with no check that any exist). Round 2's fixes were the
  apply's re-read (R/lnk_gradient_parent.R:366-377) and proof.R's `accessible` arm (proof.R:263).
  Round 3's row should read "no" (or "the same mechanism in adjacent code"). Round 2's "yes" is
  right: review-round2.md:42-57 calls its first finding "round 1's mechanism on the other input
  of the same join".

- **[wrong]** data-raw/logs/grad_parent_463/README.md:245 says "`proof.R` reads the newest closed
  row." proof.R does not skip open rows. `newest()` (proof.R:95-101) takes the newest row by
  `date_start` whether it is open or closed, and :109 fails the proof if that row is open. The
  claim holds here only because the open rows are older than the closed ones. Suggested wording:
  "reads the newest row, which must be closed".

- **[unsupported]** CLAUDE.md:19 says "2,205 on `fresh_default_minimal`". The 2,205 km comes from
  the #415 proof's scratch schema, not `fresh_default_minimal`: `zz415_minimal`, BULK, CH,
  `km_rearing` 2205.244 (data-raw/logs/minimal_breaks_415/connectivity.csv:10), at link
  `6bf9ca06` (research/minimal_network.md:3). Nothing in the evidence measures BULK CH rearing in
  `fresh_default_minimal`. research/minimal_network.md:299 and findings.md:272 correctly say "on
  the minimal network (above)" or "there".

- **[overstated]** CLAUDE.md:22 says "FWA is one object per group". In `artifact_ids.csv`, only
  `whse_basemapping.fwa_stream_networks_sp` has a different version id and ETag in each group
  (BULK 1776306169024, COTR …170155, MORK …179021, SETN …181948). The other FWA tables are one
  object shared by all four groups, each with the same id in every group: `fwa_lakes_poly`,
  `fwa_rivers_poly`, `fwa_wetlands_poly`, `fwa_obstructions_sp`, `channel_width` and
  `discharge`. So a join on the table name alone misreads only the stream network as changed.
  planning/active/progress.md:69 carries the same phrase.

- **[unsupported]** CLAUDE.md:21 says "(7 min)" for the WAL replay. The only committed timing is
  planning/active/progress.md:55-56 and :63-65: Docker and `fresh-db` restarted at 06:35 UTC
  "recovering from WAL", and Postgres "came up at 06:37". That is about 2 min from the restart
  that is recorded. The 7.9 GB figure appears only in progress.md (no log of it is committed).

- **[unsupported]** README.md:26-29 (`artifact_ids.csv`), README.md:75
  (`near_river_462_distances.csv`), and CLAUDE.md:22 ("join … on table and object URL") cite two
  CSVs that no committed script writes. `proof.R` writes neither of them (its outputs are
  `builds`, `segments`, `gradient`, `access`, `habitat`, `habitat_classes`, `near_river_462` and
  `verdict`), `run.sh` writes neither, and `grep` finds no producer in the repo.
  - The CSV values do check: 36 of 48 rows are versioned and match; 12 have no identity; 94
    distances differ (20 + 10 + 58 + 6); the maximum is 541.6 m; `n_cross_1000m` is 0 in every
    group.
  - What cannot be checked is the method. Was the join made on URL (`artifact_ids.csv` has no URL
    column)? What population is "differ" counted over? Does a segment whose pair row is absent on
    one side count as differing or as crossing 1,000 m? The two sides hold equal row counts
    (`n_own_row` = `n_parent_row`), but nothing shows they are the same segments.
  - Research convention: "Never a number without its producer."

- **[overstated]** Several places describe the #462 cost: README.md:71-74,
  research/minimal_network.md:300, CLAUDE.md:20 (in part) and NEWS.md:38. They say it counts
  accessible CH segments failing the rear width whose parent is within 1,000 m and whose own
  distance is not, and that the count is 0. proof.R's `n_cost` adds a condition the prose omits:
  `AND NOT coalesce(h.rearing, false)`, so only segments not rearing in `default_parent` are
  counted (proof.R:295-301, header :43-44). As worded, the claim is stronger than
  `near_river_462.csv` measures.
  - The stronger statement does follow if `near_river_462_distances.csv`'s "none crosses 1,000
    m" holds for these segments, but that file has no producer (above).
  - CLAUDE.md:20's "94 CH 1050/1150 segments": the distances file counts across all 1050/1150
    segments (BULK `n_1050_1150` 2,791), not CH-accessible ones (BULK `n_ch_wetland_flow` 1,399
    in `near_river_462.csv`). "CH" names the pair, not a CH subset of segments.

## Checked

- 0.81.0 at the build commit: `git show 6f0eea81:DESCRIPTION` reads Version 0.81.0.
- Between the builds and HEAD, the only change in R/, inst/ or DESCRIPTION is
  `inst/extdata/vocabulary.csv`, a definition-text change; its spec is unchanged.
  - Note (not a claim in the diff): because of it, proof.R's builds check (`git diff sha HEAD --
    R inst DESCRIPTION`, proof.R:131) would now refuse if re-run at HEAD.
  - The pass in `verdict.csv` was at `4f5e08db`, where `proof.R` and `run.sh` are unchanged from
    `6f0eea81`.
- 8 builds exited 0, 05:12-06:02 UTC, taking 3.00 to 12.92 min: `status.tsv`.
- `proof.R` passed at 06:41:29 UTC: `verdict.csv`.
- All 8 builds are at `6f0eea81`, clean (`link_dirty` and `fresh_dirty` FALSE), on one
  `fresh_sha`, with tokens `cut-full-top acc-v5 grad-seg/grad-parent q-fwapg`. Each parent note
  names the newest full and minimal runs: `builds.csv` against `verify_before/verify.tsv`.
- Segments: BULK 42,458; SETN 80,538; MORK 51,930; COTR 28,473. Control, parent and full are
  identical, and all join: `segments.csv`, `status.tsv`.
- Every parent gradient equals `gradient_minimal`, and every control gradient equals
  `fresh_default`'s (all counts 0): `gradient.csv`.
- Gradient changed on 3,316 to 3,777 km per group (BULK 3,777 of 14,642; COTR 3,501 of 8,268):
  `gradient.csv`.
- `streams_access` shows 0 differences in every column in all 4 groups, and every segment has a
  row: `access.csv`.
- No habitat difference is unexplained. Classes are `own_gradient` and `connectivity` only, and
  there is no `accessible` difference: `habitat_classes.csv`.
- Rearing over the four groups: CH 6,902.8 → 7,175.0 (+3.94 %), ST 3,935.5 → 4,065.0 (+3.29 %),
  CO 5,139.0 → 5,216.9 (+1.52 %), BT 10,287.2 → 10,396.7 (+1.07 %): recomputed from
  `habitat.csv`.
- Spawning over the four groups: CM +0.33, PK +0.20, CO +0.13, CH +0.02, BT −0.05, ST −0.14,
  SK −0.28 %, all within ±0.33 %: recomputed.
- Gained and lost: BT spawning +74.1 / −77.5 km; CH rearing +317.3 / −45.0 km: recomputed.
- Wetland rearing: BT and CO −0.36 km each, in SETN only: `habitat.csv`.
- Accessible km, lake rearing and SK rearing show 0 change: `habitat.csv`.
- BULK CH rearing 2,101 → 2,208: `habitat.csv` (2100.975 → 2208.1).
- Minimal network 2,101 → 2,205: research/minimal_network.md:31 and
  minimal_breaks_415/connectivity.csv.
- #462 cost is 0 (0 km) in each group: `near_river_462.csv`.
- 94 distances differ, by at most 541.6 m, with 0 crossing 1,000 m: the values in
  `near_river_462_distances.csv`; its method is unverified (above).
- 36 of 48 artifact rows are versioned and match; 12 (`cabd.dams`, PSCIS,
  `fwa_stream_networks_order_parent` × 4) carry no identity on either side: `artifact_ids.csv`.
- `verify_before`: every group has `n_no_row` 0, `n_rows` = `n_segments`, `n_no_segment` 0 and
  `n_length_off` 0, with run ids equal to the newest builds: `verify_before/verify.tsv`.
- Run decisions: five quiet minutes, 30 min statement bound, `LNK_LOAD=loadall`,
  `LNK_GUARD_DOWNSTREAM=warn`, serial, clean-tree check: `run.sh`.
- Round 3 enumerated 49 numbered checks and found its 2 findings in proof.R, with the R code
  clean. Round counts 3/3, 2/2, 2/2, and round 2 "inside" round 1's fix: review-round1/2/3.md.
- Apply message "gradient from … on N segments", N equal to the segment count in each group;
  no refusal in any log: `parent_*.log`.
- Call order: the judge runs after `lnk_vocabulary_resolve()` and before
  `.lnk_log_run_start()`. The apply runs after `lnk_pipeline_break()` and before
  `lnk_pipeline_classify()`, whatever the active species: R/lnk_pipeline_run.R:178-246.
- The judge's refusals, R/lnk_gradient_parent.R:277-344:
  - persist schema is neither full nor minimal: :282-291;
  - newest builds closed: :184;
  - clean: :299-300;
  - one fresh sha: :301-304;
  - same species: :305;
  - tokens, and the minimal build at the parent cut (`cut-min`): :308-321;
  - `streams_parent` run ids, schema, rows, segments and lengths: :322-339.
- The apply, R/lnk_gradient_parent.R:363-460:
  - newest builds re-read; refuses on a re-model: :369-377;
  - blue line and both measures within 1 mm: :413-418;
  - one to one, with equal counts: :431-437;
  - every full segment has a judged, length-matching row: :389, :438;
  - `DROP EXPRESSION` and `UPDATE` in one transaction: :443-456.
- Keys are validated at load, and `source: segment` takes no other key:
  R/lnk_config.R:420-434 and R/lnk_gradient_parent.R:30-72.
- `config_hash` covers the `extends` chain (`default_parent` and `default`), not
  `minimal_config`: R/lnk_log.R:52-90.
- `default_parent` is `extends: default`, with schema `fresh_default_parent`, `source: parent`,
  `minimal_config: default_minimal` and `schema_full: fresh_default`:
  inst/extdata/configs/default_parent/config.yaml.
- There are seven bundles (`inst/extdata/configs/`) and ten live tokens; seven configs take nine
  of them, and `grad-fwa` is built by none: inst/extdata/vocabulary.csv. RUNBOOK's
  "`grad-seg` every bundle but one" also checks.
- CH's near-river pair: `rear_near_river = wetland_flow` (configs/default/dimensions.csv, CH
  row), `rear_river_channel_width_min` 15, `distance_max` 1000, `rear_channel_width_min` 1.5
  (configs/default/parameters_habitat_thresholds.csv).
- `fresh-db` has no restart policy: ~/Projects/repo/fresh/docker/docker-compose.yml has no
  `restart:` key. This agrees with findings.md:268.
  - It contradicts the older CLAUDE.md line 802 ("`fresh-db` comes back (`unless-stopped`)"),
    which is outside this diff.
